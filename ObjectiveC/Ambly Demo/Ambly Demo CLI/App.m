#import "App.h"

#import <JavaScriptCore/JavaScriptCore.h>
#import "ABYContextManager.h"
#import "ABYServer.h"

@interface App ()

@property (strong, nonatomic) ABYContextManager* contextManager;
@property (strong, nonatomic) ABYServer* replServer;

@end

void uncaughtExceptionHandler(NSException *exception) {
    NSLog(@"CRASH: %@", exception);
    NSLog(@"Stack Trace: %@", [exception callStackSymbols]);
}

@implementation App

- (BOOL)setup {
    
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
    
    // All of the setup below is for dev.
    // For release the app would load files from shipping bundle.
    
    // Set up the compiler output directory
    NSURL* compilerOutputDirectory = [self temporaryDirectory];
    [self createDirectoriesUpTo:compilerOutputDirectory];
    
    // Set up our context
    self.contextManager = [[ABYContextManager alloc] initWithContext:JSGlobalContextCreate(NULL)
                                             compilerOutputDirectory:compilerOutputDirectory];
    [self.contextManager setupGlobalContext];
    [self.contextManager setUpConsoleLog];
    [self.contextManager setUpTimerFunctionality];
    [self.contextManager setUpAmblyImportScript];
    [self.contextManager setUpAmblySetLastModified];
    
    self.replServer = [[ABYServer alloc] initWithContext:self.contextManager.context
                                 compilerOutputDirectory:compilerOutputDirectory];
    BOOL successful = [self.replServer startListening];
    if (!successful) {
        NSLog(@"Failed to start REPL server.");
    }
    
    return YES;
}

- (NSURL *)temporaryDirectory
{
    NSString *directoryName = [NSString stringWithFormat:@"%@_%@", @"Ambly", [[NSProcessInfo processInfo] globallyUniqueString]];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:directoryName]];
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
