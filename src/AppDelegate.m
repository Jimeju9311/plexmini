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

// Info.plist already lists the landscape orientations, but iOS only offers an
// orientation it has a launch image for, so before those existed the app could get
// stuck in portrait. Answering here removes the dependency on that entirely: every
// orientation except upside-down, which is disorienting for a video player.
- (UIInterfaceOrientationMask)application:(UIApplication *)application
          supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskAllButUpsideDown;
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
