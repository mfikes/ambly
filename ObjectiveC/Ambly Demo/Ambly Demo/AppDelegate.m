#import "AppDelegate.h"

#import "ABYServer.h"
#import "ABYContextManager.h"
#import "GCDWebDAVServer.h"

@interface AppDelegate ()

@property (strong, nonatomic) ABYContextManager* contextManager;
@property (strong, nonatomic) ABYServer* replServer;
@property (strong, nonatomic) GCDWebDAVServer* davServer;

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // Start up the REPL server
    self.contextManager = [[ABYContextManager alloc] init];
    self.replServer = [[ABYServer alloc] init];
    [self.replServer startListening:50505 forContext:self.contextManager.context];
    
    // Start up the WebDAV server
    NSString* documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    self.davServer = [[GCDWebDAVServer alloc] initWithUploadDirectory:documentsPath];
    [self.davServer start];
    NSLog(@"Visit %@ in your WebDAV client", self.davServer.serverURL);
    
    return YES;
}

@end
