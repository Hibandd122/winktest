#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define kWinkVipEnabledKey @"WinkVipEnabled"
#define kWinkVipTargetURLPart @"vip_info_by_group.json"

// ========== TIỆN ÍCH ==========

static BOOL WinkVipIsEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWinkVipEnabledKey];
}

static void WinkVipSetEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWinkVipEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static NSData *WinkVipFakeJSONData(void) {
    NSDictionary *fakeData = @{
        @"account_type": @1,
        @"sub_type": @2,
        @"sub_type_name": @"续期",
        @"valid_time": @32495508000000LL,
        @"invalid_time": @"32495529599000",
        @"is_vip": @YES,
        @"member_level": @2,
        @"member_level_name": @"Wink会员",
        @"have_valid_contract": @YES,
        @"contract_type": @1,
        @"is_lifetime_member": @NO,
        @"expire_title": @"",
        @"auto_renew": @YES
    };
    NSDictionary *responseObject = @{@"data": fakeData};
    return [NSJSONSerialization dataWithJSONObject:responseObject options:0 error:nil];
}

// ========== TỰ ĐỘNG TÌM CLASS ==========

static UIViewController *WinkVipGetTopViewController(void) {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) { window = w; break; }
                }
            }
        }
    }
    if (!window) window = [UIApplication sharedApplication].keyWindow;
    
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:[UINavigationController class]])
        top = [(UINavigationController *)top visibleViewController];
    else if ([top isKindOfClass:[UITabBarController class]]) {
        top = [(UITabBarController *)top selectedViewController];
        if ([top isKindOfClass:[UINavigationController class]])
            top = [(UINavigationController *)top visibleViewController];
    }
    return top;
}

static Class WinkVipFindNetworkClass(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        unsigned int mCount = 0;
        Method *methods = class_copyMethodList(cls, &mCount);
        for (unsigned int j = 0; j < mCount; j++) {
            SEL sel = method_getName(methods[j]);
            NSString *selName = NSStringFromSelector(sel);
            // Tìm method có tên chứa "send" hoặc "request" và có block parameter
            if (([selName localizedCaseInsensitiveContainsString:@"send"] ||
                 [selName localizedCaseInsensitiveContainsString:@"request"]) &&
                [selName containsString:@":"]) {
                char *types = method_copyReturnType(methods[j]);
                // Đơn giản: kiểm tra xem method có nhận block không (có '@?' trong type encoding)
                const char *typeEnc = method_getTypeEncoding(methods[j]);
                if (strstr(typeEnc, "@?")) {
                    free(types);
                    free(methods);
                    free(classes);
                    return cls;
                }
                free(types);
            }
        }
        free(methods);
    }
    free(classes);
    return nil;
}

// ========== HOOK ĐỘNG VỚI LOGOS ==========

// Lớp trung gian để hook ViewController
@interface WinkVipMainVCHook : NSObject
- (void)viewDidLoad;
- (void)winkvip_switchChanged:(UISwitch *)sender;
@end

@implementation WinkVipMainVCHook

- (void)viewDidLoad {
    // Gọi original (đã được hook động)
    // Không thể gọi %orig ở đây vì đây là class giả, ta sẽ dùng method swizzling bên dưới
}

- (void)winkvip_switchChanged:(UISwitch *)sender {
    WinkVipSetEnabled(sender.isOn);
}

@end

%ctor {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kWinkVipEnabledKey: @NO}];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // 1. Hook ViewController chính
        UIViewController *topVC = WinkVipGetTopViewController();
        if (topVC) {
            Class mainClass = [topVC class];
            // Swizzle viewDidLoad
            __block void (*origViewDidLoad)(id, SEL) = NULL;
            IMP newIMP = imp_implementationWithBlock(^(id self) {
                if (origViewDidLoad) origViewDidLoad(self, @selector(viewDidLoad));
                
                UISwitch *vipSwitch = [[UISwitch alloc] init];
                vipSwitch.on = WinkVipIsEnabled();
                [vipSwitch addTarget:self action:@selector(winkvip_switchChanged:) forControlEvents:UIControlEventValueChanged];
                UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:vipSwitch];
                [self navigationItem].rightBarButtonItem = item;
            });
            
            Method m = class_getInstanceMethod(mainClass, @selector(viewDidLoad));
            origViewDidLoad = (void (*)(id, SEL))method_setImplementation(m, newIMP);
            
            // Thêm selector winkvip_switchChanged:
            class_addMethod(mainClass, @selector(winkvip_switchChanged:), imp_implementationWithBlock(^(id self, UISwitch *sender) {
                WinkVipSetEnabled(sender.isOn);
            }), "v@:@");
        }
        
        // 2. Hook class network
        Class netClass = WinkVipFindNetworkClass();
        if (netClass) {
            unsigned int mCount = 0;
            Method *methods = class_copyMethodList(netClass, &mCount);
            for (unsigned int i = 0; i < mCount; i++) {
                SEL sel = method_getName(methods[i]);
                NSString *selName = NSStringFromSelector(sel);
                const char *typeEnc = method_getTypeEncoding(methods[i]);
                if (strstr(typeEnc, "@?") && ([selName localizedCaseInsensitiveContainsString:@"send"] ||
                                               [selName localizedCaseInsensitiveContainsString:@"request"])) {
                    IMP orig = method_setImplementation(methods[i], imp_implementationWithBlock(^(id self, NSURLRequest *req, void (^completion)(NSData *, id, NSError *)) {
                        if (WinkVipIsEnabled() && [req.URL.absoluteString containsString:kWinkVipTargetURLPart]) {
                            NSData *fake = WinkVipFakeJSONData();
                            id resp = [[NSHTTPURLResponse alloc] initWithURL:req.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
                            if (completion) completion(fake, resp, nil);
                            return;
                        }
                        ((void (*)(id, SEL, NSURLRequest *, void (^)(NSData *, id, NSError *)))orig)(self, sel, req, completion);
                    }));
                    free(methods);
                    return;
                }
            }
            free(methods);
        }
    });
}
