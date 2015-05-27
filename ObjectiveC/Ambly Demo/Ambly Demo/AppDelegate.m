#import "AppDelegate.h"

#import <JavaScriptCore/JavaScriptCore.h>
#import "ABYContextManager.h"
#import "ABYServer.h"

@interface AppDelegate ()

@property (strong, nonatomic) ABYContextManager* contextManager;
@property (strong, nonatomic) ABYServer* replServer;

@end

void uncaughtExceptionHandler(NSException *exception) {
    NSLog(@"CRASH: %@", exception);
    NSLog(@"Stack Trace: %@", [exception callStackSymbols]);
}

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
    
    // Shut down the idle timer so that you can easily experiment
    // with the demo app from a device that is not connected to a Mac
    // running Xcode. Since this demo app isn't being released we
    // can do this unconditionally.
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    // All of the setup below is for dev.
    // For release the app would load files from shipping bundle.
    
    // Set up the compiler output directory
    NSURL* compilerOutputDirectory = [[self privateDocumentsDirectory] URLByAppendingPathComponent:@"cljs-out"];
    [self createDirectoriesUpTo:compilerOutputDirectory];
    
    // Set up our context
    self.contextManager = [[ABYContextManager alloc] initWithContext:JSGlobalContextCreate(NULL)
                                             compilerOutputDirectory:compilerOutputDirectory];
    [self.contextManager setupGlobalContext];
    [self.contextManager setUpConsoleLog];
    [self.contextManager setUpTimerFunctionality];
    [self.contextManager setUpAmblyImportScript];
    
    self.replServer = [[ABYServer alloc] initWithContext:self.contextManager.context
                                 compilerOutputDirectory:compilerOutputDirectory];
    BOOL successful = [self.replServer startListening];
    if (!successful) {
        NSLog(@"Failed to start REPL server.");
    }

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
