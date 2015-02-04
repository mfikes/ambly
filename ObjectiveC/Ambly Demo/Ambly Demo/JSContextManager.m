#import "JSContextManager.h"

#include <libkern/OSAtomic.h>
#import <UIKit/UIKit.h>
#import <JavaScriptCore/JavaScriptCore.h>

@implementation JSContextManager

+ (void)setUpExceptionLogging:(JSContext*)context
{
    context.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        NSString* errorString = [NSString stringWithFormat:@"[%@:%@:%@] %@\n%@", exception[@"sourceURL"], exception[@"line"], exception[@"column"], exception, [exception[@"stack"] toObject]];
        NSLog(@"%@", errorString);
    };
}

+ (void)setUpConsoleLog:(JSContext*)context
{
    [context evaluateScript:@"var console = {}"];
    context[@"console"][@"log"] = ^(NSString *message) {
        NSLog(@"JS: %@", message);
    };
}

+ (void)setUpTimerFunctionality:(JSContext*)context
{
    static volatile int32_t counter = 0;
    
    NSString* callbackImpl = @"var callbackstore = {};\nvar setTimeout = function( fn, ms ) {\ncallbackstore[setTimeoutFn(ms)] = fn;\n}\nvar runTimeout = function( id ) {\nif( callbackstore[id] )\ncallbackstore[id]();\ncallbackstore[id] = nil;\n}\n";
    
    [context evaluateScript:callbackImpl];
    
    context[@"setTimeoutFn"] = ^( int ms ) {
        
        int32_t incremented = OSAtomicIncrement32(&counter);
        
        NSString *str = [NSString stringWithFormat:@"timer%d", incremented];
        
        JSValue *timeOutCallback = [JSContext currentContext][@"runTimeout"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [timeOutCallback callWithArguments: @[str]];
        });
        
        return str;
    };
}

+ (void)setUpRequire:(JSContext*)context
{
    context[@"require"] = ^(NSString *path) {
        // TODO deal with paths in various forms (relative, URLs?)
        [[JSContext currentContext] evaluateScript:[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]];
    };
}

+ (JSContext*)createJSContext
{
    JSContext* context = [[JSContext alloc] init];
    [self setUpExceptionLogging:context];
    [self setUpConsoleLog:context];
    [self setUpTimerFunctionality:context];
    [self setUpRequire:context];
    return context;
}

@end
