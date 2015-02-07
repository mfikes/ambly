#import "ABYServer.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <CoreFoundation/CoreFoundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "ABYMessage.h"

@interface ABYServer()

@property (strong, nonatomic) JSContext* jsContext;

@property (strong, nonatomic) NSInputStream* inputStream;
@property (strong, nonatomic) NSOutputStream* outputStream;

@property (strong, nonatomic) NSMutableData* inputBuffer;
@property (atomic) NSUInteger inputBufferBytesScanned;

// Message currently being sent. (In flight iff messageBeingSent != nil)
@property (strong, atomic) ABYMessage* messageBeingSent;
@property (atomic) NSUInteger messagePayloadBytesSent;

// Subsequent messages to be transmitted in FIFO order
@property (strong, nonatomic) NSMutableArray* queuedMessages;

@end

@implementation ABYServer

- (BOOL)isReplConnected
{
    return self.outputStream != nil;
}

- (void)sendMessage:(ABYMessage*)message
{
    @synchronized (self) {
        if (self.messageBeingSent == nil) {
            self.messageBeingSent = message;
            self.messagePayloadBytesSent = 0;
            if (self.outputStream.hasSpaceAvailable) {
                [self sendPayload];
            }
        } else {
            // Something is in flight. Queue message.
            if (!self.queuedMessages) {
                self.queuedMessages = [[NSMutableArray alloc] init];
            }
            [self.queuedMessages addObject:message];
        }
    }
}

-(void)dequeAndSend
{
    @synchronized (self) {
        if (self.queuedMessages.count) {
            ABYMessage* message = self.queuedMessages[0];
            [self.queuedMessages removeObjectAtIndex:0];
            [self sendMessage:message];
        }
    }
}

- (void)setUpPrintCapability
{
    [self.jsContext evaluateScript:@"var out = {}"];
    self.jsContext[@"out"][@"write"] = ^(NSString *message) {
        if ([self isReplConnected]) {
            NSData* payload = [message dataUsingEncoding:NSUTF8StringEncoding];
            [self sendMessage:[[ABYMessage alloc] initWithPayload:payload terminator:1]];
        }
    };
}

- (void)evaluateJavaScriptAndSendResponse:(NSString*)javaScript
{
    // Temporarily install an exception handler
    id currentExceptionHandler = self.jsContext.exceptionHandler;
    self.jsContext.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        context.exception = exception;
    };
    
    // Evaluate the JavaScript
    JSValue* result = [self.jsContext evaluateScript:javaScript];
    
    // Construct response dictionary
    NSDictionary* rv = nil;
    if (self.jsContext.exception) {
        rv = @{@"status": @"exception",
               @"value": self.jsContext.exception.description,
               @"stacktrace": [self.jsContext.exception valueForProperty:@"stack"].description};
        self.jsContext.exception = nil;
    } else if (![result isUndefined] && ![result isNull]) {
        rv = @{@"status": @"success",
               @"value": result.description};
    } else {
        rv = @{@"status": @"success",
               @"value": [NSNull null]};
    }
    
    // Restore the previous excepiton handler
    self.jsContext.exceptionHandler = currentExceptionHandler;
    
    // Convert response dictionary to JSON
    NSError *error;
    NSData* payload = [NSJSONSerialization dataWithJSONObject:rv
                                                      options:0
                                                        error:&error];
    if (error) {
        payload = [NSJSONSerialization dataWithJSONObject:@{@"status": @"error",
                                                            @"value": @"Failed to serialize result."}
                                                  options:0
                                                    error:nil];
    }
    
    [self sendMessage:[[ABYMessage alloc] initWithPayload:payload terminator:0]];
    
}

- (void)sendPayload {
    NSInteger result = [self.outputStream write:self.messageBeingSent.payload.bytes + self.messagePayloadBytesSent
                                      maxLength:self.messageBeingSent.payload.length - self.messagePayloadBytesSent];
    if (result <= 0) {
        NSLog(@"Error writing bytes to REPL output stream");
    } else {
        self.messagePayloadBytesSent += result;
    }
    
    if (self.messagePayloadBytesSent == self.messageBeingSent.payload.length) {
        [self sendTerminator:self.messageBeingSent.terminator];
    }
}

- (void)sendTerminator:(uint8_t)value {
    uint8_t terminator[1] = {value};
    NSInteger bytesWritten = [self.outputStream write:terminator maxLength:1];
    if (bytesWritten != 1) {
        NSLog(@"Error writing terminator to REPL output stream");
    }
    self.messageBeingSent = nil;
    [self dequeAndSend];
}

-(void)processInputBuffer:(NSUInteger)terminatorIndex
{
    // Read the bytes in the input buffer, up to the first \0
    const char* bytes = self.inputBuffer.bytes;
    NSString* read = [NSString stringWithUTF8String:bytes];
    
    // Discard initial segment of the buffer up to and including the \0 character
    NSMutableData* newBuffer = [NSMutableData dataWithBytes:bytes + terminatorIndex + 1
                                                     length:self.inputBuffer.length - terminatorIndex - 1];
    self.inputBuffer = newBuffer;
    
    [self evaluateJavaScriptAndSendResponse:read];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    if (eventCode == NSStreamEventHasBytesAvailable) {
        if(!self.inputBuffer) {
            self.inputBuffer = [NSMutableData data];
            self.inputBufferBytesScanned = 0;
        }
        const size_t BUFFER_SIZE = 1024;
        uint8_t buf[BUFFER_SIZE];
        NSInteger len = 0;
        len = [(NSInputStream *)stream read:buf maxLength:BUFFER_SIZE];
        if (len == -1) {
            NSLog(@"Error reading from REPL input stream");
        } else if (len > 0) {
            [self.inputBuffer appendBytes:(const void *)buf length:len];
            
            BOOL found = NO;
            for (size_t i=0; i<len; i++) {
                if (buf[i] == 0) {
                    found = YES;
                    [self processInputBuffer:self.inputBufferBytesScanned + i];
                    break;
                }
            }
            if (found) {
                self.inputBufferBytesScanned = 0;
            } else {
                self.inputBufferBytesScanned += BUFFER_SIZE;
            }
        }
    } else if (eventCode == NSStreamEventHasSpaceAvailable) {
        if (self.messageBeingSent) {
            if (self.messagePayloadBytesSent < self.messageBeingSent.payload.length) {
                [self sendPayload];
            } else {
                [self sendTerminator:self.messageBeingSent.terminator];
            }
        }
    } else if (eventCode == NSStreamEventEndEncountered) {
        [ABYServer tearDownStream:self.inputStream];
        self.inputStream = nil;
        [ABYServer tearDownStream:self.outputStream];
        self.outputStream = nil;
        @synchronized (self) {
            self.queuedMessages = nil;
        }
    }
}

+(void)setUpStream:(NSStream*)stream server:(ABYServer*)server
{
    [stream setDelegate:server];
    [stream  scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [stream  open];
}

+(void)tearDownStream:(NSStream*)stream
{
    [stream close];
    [stream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [stream setDelegate:nil];
}

void handleConnect (
                    CFSocketRef s,
                    CFSocketCallBackType callbackType,
                    CFDataRef address,
                    const void *data,
                    void *info
                    )
{
    if( callbackType & kCFSocketAcceptCallBack)
    {        
        CFReadStreamRef clientInput = NULL;
        CFWriteStreamRef clientOutput = NULL;
        
        CFSocketNativeHandle nativeSocketHandle = *(CFSocketNativeHandle *)data;
        
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocketHandle, &clientInput, &clientOutput);
        
        ABYServer* server = (__bridge ABYServer*)info;
        
        NSInputStream* inputStream = (__bridge NSInputStream*)clientInput;
        NSOutputStream* outputStream = (__bridge NSOutputStream*)clientOutput;
        
        [ABYServer setUpStream:inputStream server:server];
        [ABYServer setUpStream:outputStream server:server];

        server.inputStream = inputStream;
        server.outputStream = outputStream;
    }
}

-(void)startListening:(short)port forContext:(JSContext*)jsContext {
    
    self.jsContext = jsContext;
    
    [self setUpPrintCapability];

    CFSocketContext socketCtxt = {0, (__bridge void *)self, NULL, NULL, NULL};
    
    CFSocketRef myipv4cfsock = CFSocketCreate(
                                              kCFAllocatorDefault,
                                              PF_INET,
                                              SOCK_STREAM,
                                              IPPROTO_TCP,
                                              kCFSocketAcceptCallBack, handleConnect, &socketCtxt);
    CFSocketRef myipv6cfsock = CFSocketCreate(
                                              kCFAllocatorDefault,
                                              PF_INET6,
                                              SOCK_STREAM,
                                              IPPROTO_TCP,
                                              kCFSocketAcceptCallBack, handleConnect, &socketCtxt);
    
    
    struct sockaddr_in sin;
    
    memset(&sin, 0, sizeof(sin));
    sin.sin_len = sizeof(sin);
    sin.sin_family = AF_INET; /* Address family */
    sin.sin_port = htons(port);
    sin.sin_addr.s_addr= INADDR_ANY;
    
    CFDataRef sincfd = CFDataCreate(
                                    kCFAllocatorDefault,
                                    (UInt8 *)&sin,
                                    sizeof(sin));
    
    CFSocketSetAddress(myipv4cfsock, sincfd);
    CFRelease(sincfd);
    
    struct sockaddr_in6 sin6;
    
    memset(&sin6, 0, sizeof(sin6));
    sin6.sin6_len = sizeof(sin6);
    sin6.sin6_family = AF_INET6; /* Address family */
    sin6.sin6_port = htons(port);
    sin6.sin6_addr = in6addr_any;
    
    CFDataRef sin6cfd = CFDataCreate(
                                     kCFAllocatorDefault,
                                     (UInt8 *)&sin6,
                                     sizeof(sin6));
    
    CFSocketSetAddress(myipv6cfsock, sin6cfd);
    CFRelease(sin6cfd);
    
    
    CFRunLoopSourceRef socketsource = CFSocketCreateRunLoopSource(
                                                                  kCFAllocatorDefault,
                                                                  myipv4cfsock,
                                                                  0);
    
    CFRunLoopAddSource(
                       CFRunLoopGetCurrent(),
                       socketsource,
                       kCFRunLoopDefaultMode);
    
    CFRunLoopSourceRef socketsource6 = CFSocketCreateRunLoopSource(
                                                                   kCFAllocatorDefault,
                                                                   myipv6cfsock,
                                                                   0);
    
    CFRunLoopAddSource(
                       CFRunLoopGetCurrent(),
                       socketsource6,
                       kCFRunLoopDefaultMode);
    
}

@end
