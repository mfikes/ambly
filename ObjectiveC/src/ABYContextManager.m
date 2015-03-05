#import "ABYContextManager.h"

#include <libkern/OSAtomic.h>
#import <JavaScriptCore/JavaScriptCore.h>

@interface ABYContextManager()

// The context being managed
@property (strong, nonatomic) JSContext* context;

// The compiler output directory
@property (strong, nonatomic) NSURL* compilerOutputDirectory;

@end

@implementation ABYContextManager

-(id)initWithCompilerOutputDirectory:(NSURL*)compilerOutputDirectory
{
    if (self = [super init]) {
        self.context = [[JSContext alloc] init];
        self.compilerOutputDirectory = compilerOutputDirectory;
        
        [self setupGlobalContext];
        [self setUpExceptionLogging];
        [self setUpConsoleLog];
        [self setUpTimerFunctionality];
        [self setUpAmblyRequire];
    }
    return self;
}

-(id)initWithContext:(JSContext*)context compilerOutputDirectory:(NSURL*)compilerOutputDirectory
{
    if (self = [super init]) {
        self.context = context;
        self.compilerOutputDirectory = compilerOutputDirectory;
    }
    return self;
}

- (void)setupGlobalContext
{
    [self.context evaluateScript:@"var global = this"];
}

- (void)setUpExceptionLogging
{
    self.context.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        NSString* errorString = [NSString stringWithFormat:@"[%@:%@:%@] %@\n%@", exception[@"sourceURL"], exception[@"line"], exception[@"column"], exception, [exception[@"stack"] toObject]];
        NSLog(@"%@", errorString);
    };
}

- (void)setUpConsoleLog
{
    [self.context evaluateScript:@"var console = {}"];
    self.context[@"console"][@"log"] = ^(NSString *message) {
        NSLog(@"%@", message);
    };
}

- (void)setUpTimerFunctionality
{
    static volatile int32_t counter = 0;
    
    NSString* callbackImpl = @"var callbackstore = {};\nvar setTimeout = function( fn, ms ) {\ncallbackstore[setTimeoutFn(ms)] = fn;\n}\nvar runTimeout = function( id ) {\nif( callbackstore[id] )\ncallbackstore[id]();\ncallbackstore[id] = null;\n}\n";
    
    [self.context evaluateScript:callbackImpl];
    
    self.context[@"setTimeoutFn"] = ^( int ms ) {
        
        int32_t incremented = OSAtomicIncrement32(&counter);
        
        NSString *str = [NSString stringWithFormat:@"timer%d", incremented];
        
        JSValue *timeOutCallback = [JSContext currentContext][@"runTimeout"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [timeOutCallback callWithArguments: @[str]];
        });
        
        return str;
    };
}

- (void)setUpAmblyRequire
{
    __weak typeof(self) weakSelf = self;
    
    self.context[@"amblyRequire"] = ^(NSString *path) {
        
        NSString* readPath = [NSString stringWithFormat:@"%@/%@", weakSelf.compilerOutputDirectory.path, path];
        
        JSContext* currentContext = [JSContext currentContext];
        
        NSError* error = nil;
        NSString* sourceText = [NSString stringWithContentsOfFile:readPath encoding:NSUTF8StringEncoding error:&error];
        
        if (!error && sourceText) {
            [currentContext evaluateScript:sourceText withSourceURL:[NSURL fileURLWithPath:path]];
        }
        
        return [JSValue valueWithUndefinedInContext:currentContext];
    };
}

-(void)bootstrapWithDepsFilePath:(NSString*)depsFilePath googBasePath:(NSString*)googBasePath
{
    // This implementation mirrors the bootstrapping code that is in -setup
    
    // Setup CLOSURE_IMPORT_SCRIPT
    [self.context evaluateScript:@"CLOSURE_IMPORT_SCRIPT = function(src) { amblyRequire('goog/' + src); return true; }"];
    
    // Load goog base
    NSString *baseScriptString = [NSString stringWithContentsOfFile:googBasePath encoding:NSUTF8StringEncoding error:nil];
     NSAssert(baseScriptString != nil, @"The goog base JavaScript text could not be loaded");
    [self.context evaluateScript:baseScriptString];
    
    // Load the deps file
    NSString *depsScriptString = [NSString stringWithContentsOfFile:depsFilePath encoding:NSUTF8StringEncoding error:nil];
    NSAssert(depsScriptString != nil, @"The deps JavaScript text could not be loaded");
    [self.context evaluateScript:depsScriptString];
    
    [self.context evaluateScript:@"goog.isProvided_ = function(x) { return false; };"];
    
    [self.context evaluateScript:@"goog.require = function (name) { return CLOSURE_IMPORT_SCRIPT(goog.dependencies_.nameToPath[name]); };"];
    
    [self.context evaluateScript:@"goog.require('cljs.core');"];
    
    // TODO Is there a better way for the impl below that avoids making direct calls to
    // ClojureScript compiled artifacts? (Complex and perhaps also fragile).
    
     // redef goog.require to track loaded libs
    [self.context evaluateScript:@"cljs.core._STAR_loaded_libs_STAR_ = new cljs.core.PersistentHashSet(null, new cljs.core.PersistentArrayMap(null, 1, ['cljs.core',null], null), null);\n"
     "\n"
     "goog.require = (function (name,reload){\n"
     "   if(cljs.core.truth_((function (){var or__4112__auto__ = !(cljs.core.contains_QMARK_.call(null,cljs.core._STAR_loaded_libs_STAR_,name));\n"
     "       if(or__4112__auto__){\n"
     "           return or__4112__auto__;\n"
     "       } else {\n"
     "           return reload;\n"
     "       }\n"
     "   })())){\n"
     "       cljs.core._STAR_loaded_libs_STAR_ = cljs.core.conj.call(null,(function (){var or__4112__auto__ = cljs.core._STAR_loaded_libs_STAR_;\n"
     "           if(cljs.core.truth_(or__4112__auto__)){\n"
     "               return or__4112__auto__;\n"
     "           } else {\n"
     "               return cljs.core.PersistentHashSet.EMPTY;\n"
     "           }\n"
     "       })(),name);\n"
     "       \n"
     "       return CLOSURE_IMPORT_SCRIPT((goog.dependencies_.nameToPath[name]));\n"
     "   } else {\n"
     "       return null;\n"
     "   }\n"
     "});"];
}

@end
