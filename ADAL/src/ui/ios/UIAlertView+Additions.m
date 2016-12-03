#import <objc/runtime.h>
#import "ADWebAuthController.h"
#import "ADALFrameworkUtils.h"
#import "ADAppExtensionUtil.h"

@implementation UIAlertView (Additions)

static const char* HANDLER_KEY = "com.microsoft.adal.alertviewHandler";

static UIAlertView* alert;

+ (void)presentCredentialAlert:(void (^)(NSUInteger))handler
{
    if ([ADAppExtensionUtil isExecutingInAppExtension])
    {
        handler(0);
        return;
    }
    
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSBundle* bundle = [ADALFrameworkUtils frameworkBundle];
        
        if (!bundle)
        {
            bundle = [NSBundle mainBundle];
        }
        
        alert = [[UIAlertView alloc] initWithFrame:CGRectZero];
        alert.title = NSLocalizedStringFromTableInBundle(@"Enter your credentials", nil, bundle, nil);
        alert.alertViewStyle = UIAlertViewStyleLoginAndPasswordInput;
        
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", nil, bundle, nil)];
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Login", nil, bundle, nil)];
        [alert setCancelButtonIndex:0];
        
        [alert setDelegate:alert];
        [alert show];
    });
}

- (void)alertView:(UIAlertView*)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    id handler = objc_getAssociatedObject(alertView, HANDLER_KEY);
    
    if (handler)
    {
        // Execute associated handler
        ((void(^)())handler)(buttonIndex);
    }
}

+ (id)getAlertInstance
{
    return alert;
}

@end
