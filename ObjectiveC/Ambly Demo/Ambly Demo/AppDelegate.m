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
    
    // All of the setup below is for dev.
    // For release the app would load files from shipping bundle.
    
    // Set up the compiler output directory
    NSURL* compilerOutputDirectory = [[self privateDocumentsDirectory] URLByAppendingPathComponent:@"cljs-out"];
    
    // Ensure compiler output directory exists
    [self createDirectoriesUpTo:compilerOutputDirectory];
    
    // Start up the REPL server
    self.contextManager = [[ABYContextManager alloc] initWithCompilerOutputDirectory:compilerOutputDirectory];
    self.replServer = [[ABYServer alloc] init];
    [self.replServer startListening:50505 forContext:self.contextManager.context];

    // Start up the WebDAV server
    self.davServer = [[GCDWebDAVServer alloc] initWithUploadDirectory:compilerOutputDirectory.path];
//#if TARGET_IPHONE_SIMULATOR
//    NSString* bonjourName = [NSString stringWithFormat:@"Ambly WebDAV Server on %@ runnng on %@", [UIDevice currentDevice].name, [[NSProcessInfo processInfo] hostName]];
//#else
    NSString* bonjourName = [NSString stringWithFormat:@"Ambly WebDAV Server on %@", [UIDevice currentDevice].name];
//#endif
    [self.davServer startWithPort:8080 bonjourName:bonjourName];
    
    return YES;
}

- (NSURL *)privateDocumentsDirectory
{
    NSURL *libraryDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] lastObject];
    
    return [libraryDirectory URLByAppendingPathComponent:@"Private Documents"];
}

- (void)createDirectoriesUpTo:(NSURL*)directory
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:[directory path]]) {
        NSError *error = nil;
        
        if (![[NSFileManager defaultManager] createDirectoryAtPath:[directory path]
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error]) {
            NSLog(@"Can't create directory %@ [%@]", [directory path], error);
            abort();
        }
    }
}

@end
