// ILPDFViewController.m
//
// Copyright (c) 2016 Derek Blair
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "ILPDFKit.h"
#import "ILPDFFormContainer.h"
#import "ILPDFSignatureController.h"
#import "ILPDFFormSignatureField.h"

#import "OCRDocumentScanner3-Swift.h"

@interface ILPDFViewController(Private) <ILPDFSignatureControllerDelegate, NSURLSessionDataDelegate, NSURLSessionDelegate, NSURLSessionTaskDelegate>
- (void)loadPDFView;
- (void)setReviewMode;
@end

@implementation ILPDFViewController {
    ILPDFView *_pdfView;
    ILPDFSignatureController *signatureController;
    ILPDFFormSignatureField *signatureField;
    
    UIAlertController* loading;
    
    bool reviewPdfMode;
}

#pragma mark - UIViewController
- (void) setReviewMode {
    reviewPdfMode = true;
}
    
- (void) viewDidLoad {
    [super viewDidLoad];
    reviewPdfMode = false;
}
    
- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if(reviewPdfMode){
        UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(saveForm:)];
        self.navigationItem.rightBarButtonItems = [NSArray arrayWithObject:saveBtn];
    }else{
        UIBarButtonItem *saveBtn = [[UIBarButtonItem alloc] initWithTitle:@"Review" style:UIBarButtonItemStyleDone target:self action:@selector(reviewForm:)];
        self.navigationItem.rightBarButtonItems = [NSArray arrayWithObject:saveBtn];
    }
}
    
- (id)valueForFormName:(NSString *)name {
    for(ILPDFForm *form in self.document.forms) {
        if ([form.name isEqualToString:name]) {
            return form.value;
        }
    }
    return nil;
}
    
- (void) reviewForm:(id)sender{
    // Save static local version
    NSString *finalPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"temp.pdf"];
    NSData *data = [self.document savedStaticPDFData];
    NSError *error;
    [data writeToFile:finalPath options:NSDataWritingAtomic error:&error];
    if(error){
        NSLog(@"Failed to save pdf");
    }else{
        ILPDFViewController* reviewVc = [[ILPDFViewController alloc] init];
        ILPDFDocument* document = [[ILPDFDocument alloc] initWithPath:finalPath];
        reviewVc.document = document;
        [reviewVc setReviewMode];
        [reviewVc reload];
        reviewVc.xmlToSave = [self.document formXML];
        reviewVc.signToSave = _signToSave;
        [self.navigationController pushViewController:reviewVc animated:true];
    }
}

- (void) saveForm:(id)sender{
    
    self->loading = [UIAlertController alertControllerWithTitle:@"" message:@"Uploading..." preferredStyle:UIAlertControllerStyleAlert];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIActivityIndicatorView* ind = [[UIActivityIndicatorView alloc] initWithFrame:loading.view.bounds];
        ind.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth);
        ind.color = UIColor.blackColor;
//        [loading.view addSubview:ind];
        [ind startAnimating];
        [self presentViewController:loading animated:YES completion:nil];
    });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *url = [NSString stringWithFormat:@"%@/%@", Setting.api_user_pdf_put, Store.hkid];
        
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
        [request setHTTPMethod:@"POST"];
        // define the boundary and newline values
        NSString *boundary = @"uwhQ9Ho7y873Ha";
        NSString *kNewLine = @"\r\n";
        
        NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary];
        [request setValue:contentType forHTTPHeaderField: @"Content-Type"];
        
        NSMutableData *body = [NSMutableData data];
        [body appendData:[[NSString stringWithFormat:@"--%@%@", boundary, kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"%@", @"pdf", @"form.pdf", kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Type: application/pdf"] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@%@", kNewLine, kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[self.document savedStaticPDFData]];
        [body appendData:[kNewLine dataUsingEncoding:NSUTF8StringEncoding]];
        
        [body appendData:[[NSString stringWithFormat:@"--%@%@", boundary, kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"%@", @"xml", @"form.xml", kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Type: text/xml"] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@%@", kNewLine, kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[_xmlToSave dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[kNewLine dataUsingEncoding:NSUTF8StringEncoding]];
        
        [body appendData:[[NSString stringWithFormat:@"--%@%@", boundary, kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"%@", @"hkidImage", @"hkid.jpg", kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Type: text/xml"] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@%@", kNewLine, kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:UIImageJPEGRepresentation(Store.hkidImage, 1.0)];
        [body appendData:[kNewLine dataUsingEncoding:NSUTF8StringEncoding]];
        
        [body appendData:[[NSString stringWithFormat:@"--%@%@", boundary, kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"%@", @"addressProofImage", @"addressproof.jpg", kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Type: text/xml"] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@%@", kNewLine, kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:UIImageJPEGRepresentation(Store.addressProofImage, 1.0)];
        [body appendData:[kNewLine dataUsingEncoding:NSUTF8StringEncoding]];
        
        [body appendData:[[NSString stringWithFormat:@"--%@%@", boundary, kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        
        [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"%@", @"sign", @"sign", kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"Content-Type: text/xml"] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"%@%@", kNewLine, kNewLine] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:UIImageJPEGRepresentation(_signToSave, 1.0)];
        [body appendData:[kNewLine dataUsingEncoding:NSUTF8StringEncoding]];
        
        [body appendData:[[NSString stringWithFormat:@"--%@--", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[kNewLine dataUsingEncoding:NSUTF8StringEncoding]];
        
        [request setHTTPBody:body];
        
        // TODO: Next three lines are only used for testing using synchronous conn.
//        NSData *returnData = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
//        NSString *returnString = [[NSString alloc] initWithData:returnData encoding:NSUTF8StringEncoding];
        
//        NSLog(@"Response : %@", returnString);
        //    [loading dismissViewControllerAnimated:true completion:nil];
        
        NSURLSessionConfiguration *defaultConfigObject = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSURLSession *session = [NSURLSession sessionWithConfiguration: defaultConfigObject delegate: self delegateQueue: [NSOperationQueue mainQueue]];
//        NSURLSession *session = [NSURLSession sharedSession];
        NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if(httpResponse.statusCode == 200){
                NSError *parseError = nil;
                NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
                NSLog(@"The response is - %@",responseDictionary);
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if([[responseDictionary valueForKey:@"code"]  isEqual: @"success"]){
                        [self.navigationController popToRootViewControllerAnimated:true];
                    }else{
                        NSLog(@"Upload fail! Try again!");
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self->loading dismissViewControllerAnimated:true completion:nil];
                    });
                });
            }
            else
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSLog(@"Error");
                     UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Error" message:@"Cannot connect to server!! Please check the network connectivity" preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction* alertAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleCancel handler:nil];
                    [alert addAction:alertAction];
                    [self->loading dismissViewControllerAnimated:YES completion: ^{
                        [self presentViewController:alert animated:YES completion:nil];
                    }];
                });
            }
            
        }];
        [dataTask resume];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    NSLog(@"%lld / %lld", totalBytesSent, totalBytesExpectedToSend);
    self->loading.message = [NSString stringWithFormat:@"Uploading... %lld%%", (totalBytesSent*100/totalBytesExpectedToSend)];
}
//- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
//    completionHandler(NSURLSessionResponseAllow);
//
////    progressBar.progress=0.0f;
//    _downloadSize=[response expectedContentLength];
//    _dataToDownload=[[NSMutableData alloc]init];
//}
//
//- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
//    [_dataToDownload appendData:data];
////    progressBar.progress=[ _dataToDownload length ]/_downloadSize;
//    NSLog(@"%@", [ _dataToDownload length ]/_downloadSize);
//}

- (void) saveXML {
    NSString* xmlStr = [self.document formXML];
}
    
- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showSignatureViewController:)
                                                 name:@"SignatureNotification"
                                               object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Alter or remove to define your own layout logic for the ILPDFView.
    _pdfView.frame = CGRectMake(0,self.topLayoutGuide.length,self.view.bounds.size.width,self.view.bounds.size.height-self.topLayoutGuide.length - self.bottomLayoutGuide.length);
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id <UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self loadPDFView];
}

- (void) viewWillDisappear:(BOOL)animated
{
    
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
}

#pragma mark - ILPDFViewController

#pragma mark - Setting the Document
- (void)setDocument:(ILPDFDocument *)document {
    _document = document;
    [self loadPDFView];
}

#pragma mark - Relaoding the Document
- (void)reload {
    [_document refresh];
    [self loadPDFView];
}
    
#pragma mark - set data
- (void)setData:(NSString*)name withHkid:(NSString*)hkid withDob:(NSString*)dob withAddress:(NSString*)address{
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:name forFormWithName:@"name"];
    [pdfForm setValue:hkid forFormWithName:@"hkid"];
    [pdfForm setValue:dob forFormWithName:@"dob"];
    [pdfForm setValue:address forFormWithName:@"address"];
}

- (void)setName:(NSString *)name {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:name forFormWithName:@"name"];
}

- (void)setHkid:(NSString *)hkid {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:hkid forFormWithName:@"hkid"];
}

- (void)setBirthday:(NSString *)dob {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:dob forFormWithName:@"dob"];
}
    
- (void)setAddress:(NSString *)address {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:address forFormWithName:@"address"];
}


- (void)setAddress1:(NSString*)address1 {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:address1 forFormWithName:@"address1"];
}

- (void)setAddress2:(NSString*)address2 {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:address2 forFormWithName:@"address2"];
}

- (void)setAddress3:(NSString*)address3 {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:address3 forFormWithName:@"address3"];
}

- (void)setAddress4:(NSString*)address4 {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:address4 forFormWithName:@"address4"];
}

- (void)setAddress5:(NSString*)address5 {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:address5 forFormWithName:@"address5"];
}

- (void)setAgeLastBirthday:(NSString*)ageLastBirthday {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:ageLastBirthday forFormWithName:@"ageLastBirthday"];
}

- (void)setSex:(NSString*)sex {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:sex forFormWithName:@"sex"];
}

- (void)setSmokingStatus:(NSString*)smokingStatus {
    ILPDFFormContainer *pdfForm = _document.forms;
    NSString* value = @"Yes";
    if([smokingStatus isEqualToString:@"Non-smoker"]){
        value = @"No";
    }
    [pdfForm setValue:value forFormWithName:@"smokingStatus"];
}

- (void)setPolicyCurrency:(NSString*)policyCurrency {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:policyCurrency forFormWithName:@"policyCurrency"];
}

- (void)setTotalinitalAnnPre:(NSString*)totalinitalAnnPre {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:totalinitalAnnPre forFormWithName:@"totalinitalAnnPre"];
}

- (void)setTotalInitalMonPre:(NSString*)totalInitalMonPre {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:totalInitalMonPre forFormWithName:@"totalInitalMonPre"];
}

- (void)setPrepareBy:(NSString*)prepareBy {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:prepareBy forFormWithName:@"prepareBy"];
}

- (void)setDistrict:(NSString*)district {
    ILPDFFormContainer *pdfForm = _document.forms;
    [pdfForm setValue:district forFormWithName:@"district"];
}


#pragma mark - Private

- (void)loadPDFView {
    [_pdfView removeFromSuperview];
    _pdfView = [[ILPDFView alloc] initWithDocument:_document];
    [self.view addSubview:_pdfView];
}

#pragma mark - KVO

- (void) showSignatureViewController:(NSNotification *) notification {
    
    if ([notification.object isKindOfClass:[ILPDFFormSignatureField class]]) {
        signatureField = notification.object;
    }
    signatureController = [[ILPDFSignatureController alloc] initWithNibName:@"ILPDFSignatureController" bundle:nil];
    signatureController.expectedSignSize = signatureField.frame.size;
    signatureController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    signatureController.delegate = self;
    [self presentViewController:signatureController animated:YES completion:nil];
    
}

#pragma mark - Signature Controller Delegate

- (void) signedWithImage:(UIImage*) signatureImage {
    
    [signatureField removeButtonTitle];
    signatureField.signatureImage.image = signatureImage;
    _signToSave = signatureImage;
    [signatureField informDelegateAboutNewImage];
    signatureField = nil;
    
}

//替换非utf8字符
//注意：如果是三字节utf-8，第二字节错误，则先替换第一字节内容(认为此字节误码为三字节utf8的头)，然后判断剩下的两个字节是否非法；
- (NSData *)replaceNoUtf8:(NSData *)data
{
    char aa[] = {'A','A','A','A','A','A'};                      //utf8最多6个字符，当前方法未使用
    NSMutableData *md = [NSMutableData dataWithData:data];
    int loc = 0;
    while(loc < [md length])
    {
        char buffer;
        [md getBytes:&buffer range:NSMakeRange(loc, 1)];
        if((buffer & 0x80) == 0)
        {
            loc++;
            continue;
        }
        else if((buffer & 0xE0) == 0xC0)
        {
            loc++;
            [md getBytes:&buffer range:NSMakeRange(loc, 1)];
            if((buffer & 0xC0) == 0x80)
            {
                loc++;
                continue;
            }
            loc--;
            //非法字符，将这个字符（一个byte）替换为A
            [md replaceBytesInRange:NSMakeRange(loc, 1) withBytes:aa length:1];
            loc++;
            continue;
        }
        else if((buffer & 0xF0) == 0xE0)
        {
            loc++;
            [md getBytes:&buffer range:NSMakeRange(loc, 1)];
            if((buffer & 0xC0) == 0x80)
            {
                loc++;
                [md getBytes:&buffer range:NSMakeRange(loc, 1)];
                if((buffer & 0xC0) == 0x80)
                {
                    loc++;
                    continue;
                }
                loc--;
            }
            loc--;
            //非法字符，将这个字符（一个byte）替换为A
            [md replaceBytesInRange:NSMakeRange(loc, 1) withBytes:aa length:1];
            loc++;
            continue;
        }
        else
        {
            //非法字符，将这个字符（一个byte）替换为A
            [md replaceBytesInRange:NSMakeRange(loc, 1) withBytes:aa length:1];
            loc++;
            continue;
        }
    }
    
    return md;
}




@end
