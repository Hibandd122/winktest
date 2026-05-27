#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define MAIN_VC "ClassManHinhChinhThat"
#define NET_CLASS "ClassNetworkThat"

#define kWinkVipEnabledKey @"WinkVipEnabled"
#define kWinkVipTargetURLPart @"vip_info_by_group.json"

static BOOL WinkVipIsEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWinkVipEnabledKey];
}

static void WinkVipSetEnabled(BOOL enabled) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kWinkVipEnabledKey];
    [defaults synchronize];
}

static NSData *WinkVipFakeJSONData(void) {
    NSDictionary *fakeData = @{
        @"account_type": @1,
        @"sub_type": @2,
        @"sub_type_name": @"\u7eed\u671f",
        @"valid_time": @32495508000000LL,
        @"invalid_time": @"32495529599000",
        @"is_vip": @YES,
        @"member_level": @2,
        @"member_level_name": @"Wink\u4f1a\u5458",
        @"have_valid_contract": @YES,
        @"contract_type": @1,
        @"is_lifetime_member": @NO,
        @"expire_title": @"",
        @"auto_renew": @YES
    };

    NSDictionary *responseObject = @{
        @"data": fakeData
    };

    return [NSJSONSerialization dataWithJSONObject:responseObject
                                           options:0
                                             error:nil];
}

%group WinkVipMainHooks

%hook WinkVipSwitchMainVC

- (void)viewDidLoad {
    %orig;

    UISwitch *vipSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    vipSwitch.on = WinkVipIsEnabled();
    [vipSwitch addTarget:self
                  action:@selector(winkVipSwitchChanged:)
        forControlEvents:UIControlEventValueChanged];

    UIBarButtonItem *switchItem = [[UIBarButtonItem alloc] initWithCustomView:vipSwitch];
    UINavigationItem *navigationItem = [(UIViewController *)self navigationItem];
    navigationItem.rightBarButtonItem = switchItem;
}

%new
- (void)winkVipSwitchChanged:(UISwitch *)sender {
    WinkVipSetEnabled(sender.isOn);
}

%end

%end

%group WinkVipNetworkHooks

%hook WinkVipSwitchNetworkClient

- (void)sendRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSString *urlString = request.URL.absoluteString ?: @"";

    if (WinkVipIsEnabled() && [urlString containsString:kWinkVipTargetURLPart]) {
        NSData *fakeData = WinkVipFakeJSONData();

        NSHTTPURLResponse *fakeResponse = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                                      statusCode:200
                                                                     HTTPVersion:@"HTTP/1.1"
                                                                    headerFields:@{
            @"Content-Type": @"application/json; charset=utf-8"
        }];

        if (completionHandler) {
            completionHandler(fakeData, fakeResponse, nil);
        }

        return;
    }

    %orig(request, completionHandler);
}

%end

%end

%ctor {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if ([defaults objectForKey:kWinkVipEnabledKey] == nil) {
        [defaults setBool:NO forKey:kWinkVipEnabledKey];
        [defaults synchronize];
    }

    Class mainClass = objc_getClass(MAIN_VC);
    if (mainClass) {
        %init(WinkVipMainHooks, WinkVipSwitchMainVC = mainClass);
    }

    Class networkClass = objc_getClass(NET_CLASS);
    if (networkClass) {
        %init(WinkVipNetworkHooks, WinkVipSwitchNetworkClient = networkClass);
    }
}
