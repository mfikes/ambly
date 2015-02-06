#import <Foundation/Foundation.h>

/**
 An `ABYMessage` is an immutable value container for message 
 payloads and terminators.
 */
@interface ABYMessage : NSObject

@property (nonatomic, strong, readonly) NSData* payload;
@property (nonatomic, readonly) uint8_t terminator;

-(id)initWithPayload:(NSData*)payload terminator:(uint8_t)terminator;

@end