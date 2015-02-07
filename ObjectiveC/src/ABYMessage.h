#import <Foundation/Foundation.h>

/**
 An `ABYMessage` is an immutable value container for message 
 payloads and terminators.
 */
@interface ABYMessage : NSObject

/**
 The message payload
 */
@property (nonatomic, strong, readonly) NSData* payload;

/**
 The message terminator. `0` is used for responses and `1` is used for async prints.
 */
@property (nonatomic, readonly) uint8_t terminator;

/**
 Inits this message with a payload and terminator
 @param payload the payload
 @param terminator the terminator
 */
-(id)initWithPayload:(NSData*)payload terminator:(uint8_t)terminator;

@end