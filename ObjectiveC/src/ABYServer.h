#import <Foundation/Foundation.h>

@interface ABYServer : NSObject<NSStreamDelegate>

-(void)startListening:(short)port;

@end
