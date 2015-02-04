#import <Foundation/Foundation.h>

@class JSContext;

/**
 This class wraps a `JSContext` and listens a TCP server, accepting 
 ClojureScript-REPL JavaScript expressions to evaluate, evaluating
 them in JSC, and returning the results.
 */
@interface ABYServer : NSObject<NSStreamDelegate>

-(void)startListening:(short)port forContext:(JSContext*)jsContext;

@end
