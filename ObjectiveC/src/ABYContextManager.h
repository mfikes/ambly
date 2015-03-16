#import <Foundation/Foundation.h>

@class JSContext;

/**
 This class manages a `JSContext` instance, providing various methods for enriching 
 the JavaScriptCore execution environment with a few extra things that are either 
 needed or nice for ClojureScript execution.
 */
@interface ABYContextManager : NSObject

/**
 The context being managed.
 */
@property (strong, nonatomic, readonly) JSContext* context;

/**
 Initializes with a compiler output directory, accepting an externally-created JSContext.
 
 @param context the JavaScriptCore context
 @param compilerOutputDirectory the compiler output directory
 */
-(id)initWithContext:(JSContext*)context compilerOutputDirectory:(NSURL*)compilerOutputDirectory;

/**
 Sets up global context in the managed context.
 Needed by foreign dependencies like React.
 */
- (void)setupGlobalContext;

/**
 Sets up exception logging for the managed context.
 */
- (void)setUpExceptionLogging;

/**
 Sets up console logging for the managed context.
 */
- (void)setUpConsoleLog;

/**
 Sets up timer functionality for the managed context.
 */
- (void)setUpTimerFunctionality;

/**
 Sets up `AMBLY_IMPORT_SCRIPT` capability for the managed context.
 */
- (void)setUpAmblyImportScript;

/**
 Bootstraps the JavaScript environment so that goog require is set up to work properly.
 Intended for use in dev when an app bundles up JavaScript files compiled using :optimizations :none.

 @param depsFilePath the path to the deps file (associated with :output-to)
 @param googBasePath the path to the goog base.js file
 */
-(void)bootstrapWithDepsFilePath:(NSString*)depsFilePath googBasePath:(NSString*)googBasePath;

@end
