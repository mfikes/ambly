#import <Foundation/Foundation.h>

@class JSContext;

@interface ABYServer : NSObject<NSStreamDelegate>

-(void)startListening:(short)port forContext:(JSContext*)jsContext;

@end
