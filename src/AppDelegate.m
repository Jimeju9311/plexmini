#import "AppDelegate.h"
#import "PlexClient.h"
#import "PlexListViewController.h"
#import "LinkViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    if ([PlexClient authToken]) {
        [self showLibraries];
    } else {
        LinkViewController *link = [[LinkViewController alloc] init];
        __weak typeof(self) weakSelf = self;
        link.onLinked = ^{
            [weakSelf showLibraries];
        };
        self.window.rootViewController = link;
    }

    [self.window makeKeyAndVisible];
    return YES;
}

- (void)showLibraries {
    PlexListViewController *root = [[PlexListViewController alloc] init];
    root.title = @"Plex";
    root.fetchPath = @"/library/sections";
    root.isTopLevel = YES;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBar.barStyle = UIBarStyleBlack;
    self.window.rootViewController = nav;
}

@end
