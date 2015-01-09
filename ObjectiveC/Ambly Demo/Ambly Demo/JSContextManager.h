#import <Foundation/Foundation.h>

@class JSContext;

@interface JSContextManager : NSObject

+ (JSContext*)createJSContext;

@end
