#import "AppDelegate.h"

#import "ABYServer.h"
#import "ABYContextManager.h"

@interface AppDelegate ()

@property (strong, nonatomic) ABYServer* abyServer;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    self.abyServer = [[ABYServer alloc] init];
    [self.abyServer startListening:9999 forContext:[ABYContextManager createJSContext]];
    return YES;
}

@end
