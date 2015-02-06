#import "ABYMessage.h"

@interface ABYMessage()

@property (nonatomic, strong) NSData* payload;
@property (nonatomic) uint8_t terminator;

@end

@implementation ABYMessage

-(id)initWithPayload:(NSData*)payload terminator:(uint8_t)terminator
{
    if (self = [super init]) {
        self.payload = payload;
        self.terminator = terminator;
    }
    
    return self;
}

@end