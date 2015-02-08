#import "AppDelegate.h"

#import "ABYServer.h"
#import "ABYContextManager.h"

@interface AppDelegate ()

@property (strong, nonatomic) ABYContextManager* contextManager;
@property (strong, nonatomic) ABYServer* server;

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.contextManager = [[ABYContextManager alloc] init];
    self.server = [[ABYServer alloc] init];
    [self.server startListening:50505 forContext:self.contextManager.context];
    return YES;
}

@end
