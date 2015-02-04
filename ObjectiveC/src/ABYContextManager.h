#import <Foundation/Foundation.h>

@class JSContext;

/**
 This class manages a `JSContext` instance, enriching the JavaScriptCore execution
 environment with a few extra things that are either needed or nice for ClojureScript
 execution.
 */
@interface ABYContextManager : NSObject

@property (strong, nonatomic, readonly) JSContext* context;

@end
