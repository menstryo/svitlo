#import <UIKit/UIKit.h>
#import "SVMainViewController.h"
#import "SVStore.h"

@interface SVAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, retain) UIWindow *window;
@end

@implementation SVAppDelegate
@synthesize window = _window;

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease];

    SVMainViewController *main = [[[SVMainViewController alloc] init] autorelease];
    UINavigationController *nav = [[[UINavigationController alloc] initWithRootViewController:main] autorelease];
    nav.navigationBar.tintColor = [UIColor colorWithRed:0.80 green:0.56 blue:0.06 alpha:1];

    self.window.rootViewController = nav;
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];

    app.applicationIconBadgeNumber = 0;

    // iOS 8+ needs explicit permission for local notifications
    Class settingsCls = NSClassFromString(@"UIUserNotificationSettings");
    if (settingsCls && [app respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        NSUInteger types = (1 << 1) | (1 << 2); // sound | alert
        id settings = [settingsCls performSelector:@selector(settingsForTypes:categories:)
                                        withObject:(id)(uintptr_t)types withObject:nil];
        [app performSelector:@selector(registerUserNotificationSettings:) withObject:settings];
    }

    if ([SVStore shared].regionId) [[SVStore shared] refresh:nil];
    return YES;
}

- (void)application:(UIApplication *)app didReceiveLocalNotification:(UILocalNotification *)n {
    if (app.applicationState == UIApplicationStateActive) {
        UIAlertView *a = [[[UIAlertView alloc] initWithTitle:@"Світло" message:n.alertBody delegate:nil
                                           cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease];
        [a show];
    }
}

- (void)dealloc {
    [_window release];
    [super dealloc];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SVAppDelegate class]));
    }
}
