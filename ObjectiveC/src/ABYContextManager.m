#import "ABYContextManager.h"

#include <libkern/OSAtomic.h>
#import <JavaScriptCore/JavaScriptCore.h>

@interface ABYContextManager()

// The context being managed
@property (strong, nonatomic) JSContext* context;

@end

@implementation ABYContextManager

-(id)init
{
    if (self = [super init]) {
        self.context = [[JSContext alloc] init];
        
        [self setUpExceptionLogging];
        [self setUpConsoleLog];
        [self setUpTimerFunctionality];
        [self setUpRequire];
    }
    return self;
}

/**
 Sets up exception logging for the wrapped context.
 */
- (void)setUpExceptionLogging
{
    self.context.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        NSString* errorString = [NSString stringWithFormat:@"[%@:%@:%@] %@\n%@", exception[@"sourceURL"], exception[@"line"], exception[@"column"], exception, [exception[@"stack"] toObject]];
        NSLog(@"%@", errorString);
    };
}

/**
 Sets up console logging for the wrapped context.
 */
- (void)setUpConsoleLog
{
    [self.context evaluateScript:@"var console = {}"];
    self.context[@"console"][@"log"] = ^(NSString *message) {
        NSLog(@"JS: %@", message);
    };
}

/**
 Sets up timer functionality for the wrapped context.
 */
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

/**
 Sets up `require` capability for the wrapped context.
 */
- (void)setUpRequire
{
    // TODO deal with paths in various forms (relative, URLs?)
    
    self.context[@"require"] = ^(NSString *path) {
        
        NSString* requiredPath = path;
        NSString* readPath = path;
        
#if 0
        NSString* outputDir = @"/Volumes/Mikes-iPod-touch.local";
        NSString* documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        
        if ([path hasPrefix:outputDir]) {
            readPath = [NSString stringWithFormat:@"%@%@", documentsPath, [path substringFromIndex:[outputDir length]]];
        }
#endif
        
        JSContext* currentContext = [JSContext currentContext];
        
        NSError* error = nil;
        NSString* sourceText = [NSString stringWithContentsOfFile:readPath encoding:NSUTF8StringEncoding error:&error];
        
        if (!error && sourceText) {
            [currentContext evaluateScript:sourceText withSourceURL:[NSURL fileURLWithPath:requiredPath]];
        }
        
        return [JSValue valueWithUndefinedInContext:currentContext];
    };
}

@end
