#import "ABYServer.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <CoreFoundation/CoreFoundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

@interface ABYServer()

@property (strong, nonatomic) JSContext* jsContext;

@property (strong, nonatomic) NSInputStream* inputStream;
@property (strong, nonatomic) NSOutputStream* outputStream;

@property (strong, nonatomic) NSMutableData* inputBuffer;

// Data currently being transmitted. (In flight iff outJsonData != nil)
@property (atomic) NSUInteger bytesWritten;
@property (atomic) NSUInteger bytesToWrite;
@property (strong, atomic) NSData* outJsonData;
@property (atomic) uint8_t outTerminator;

// Subsequent data queued to be transmitted in FIFO order
@property (strong, nonatomic) NSMutableArray* outJsonDataQueue;
@property (strong, nonatomic) NSMutableArray* outTerminatorQueue;

@end

@implementation ABYServer


- (void)sendResponseData:(NSData*)data terminator:(uint8_t)terminator
{
    @synchronized (self) {
        if (self.outJsonData == nil) {
            self.outJsonData = data;
            self.outTerminator = terminator;
            self.bytesWritten = 0;
            self.bytesToWrite = self.outJsonData.length;
            if (self.outputStream.hasSpaceAvailable) {
                [self writeSomeData];
            }
        } else {
            // Something is in flight. Queue data.
            if (!self.outJsonDataQueue) {
                self.outJsonDataQueue = [[NSMutableArray alloc] init];
                self.outTerminatorQueue = [[NSMutableArray alloc] init];
            }
            [self.outJsonDataQueue addObject:data];
            [self.outTerminatorQueue addObject:@(terminator)];
        }
    }
}

-(void)dequeAndSend
{
    @synchronized (self) {
        if (self.outJsonDataQueue && self.outJsonDataQueue.count) {
            NSData* data = self.outJsonDataQueue[0];
            uint8_t terminator = ((NSNumber*)self.outTerminatorQueue[0]).intValue;
            if (self.outJsonDataQueue.count > 1) {
                NSMutableArray* newOutJsonDataQueue = [[NSMutableArray alloc] init];
                NSMutableArray* newOutTerminatorQueue = [[NSMutableArray alloc] init];
                for (int i=1; i<self.outJsonDataQueue.count; i++) {
                    [newOutJsonDataQueue addObject:self.outJsonDataQueue[i]];
                    [newOutTerminatorQueue addObject:self.outTerminatorQueue[i]];
                }
                self.outJsonDataQueue = newOutJsonDataQueue;
                self.outTerminatorQueue = newOutTerminatorQueue;
            } else {
                self.outJsonDataQueue = nil;
                self.outTerminatorQueue = nil;
            }
            [self sendResponseData:data terminator:terminator];
        }
    }
}

- (void)setUpPrintCapability
{
    [self.jsContext evaluateScript:@"var out = {}"];
    self.jsContext[@"out"][@"write"] = ^(NSString *message) {
        NSData* messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
        [self sendResponseData:messageData terminator:1];
    };
}

- (void)processInputBuffer
{
    // Read the bytes in the input buffer, up to the first \0
    const char* bytes = self.inputBuffer.bytes;
    NSString* read = [NSString stringWithUTF8String:bytes];
    
    // Temporarily install an exception handler
    id currentExceptionHandler = self.jsContext.exceptionHandler;
    self.jsContext.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        context.exception = exception;
    };
    
    // Evaluate the JavaScript
    JSValue* result = [self.jsContext evaluateScript:read];
    
    // Construct response dictionary
    NSDictionary* rv = nil;
    if (self.jsContext.exception) {
        rv = @{@"status": @"exception",
               @"value": [NSString stringWithFormat:@"%@\n%@",
                          self.jsContext.exception.description,
                          ([self.jsContext.exception valueForProperty:@"stack"]).description]};
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
    NSData* data = [NSJSONSerialization dataWithJSONObject:rv
                                                   options:0
                                                     error:&error];
    if (error) {
        data = [NSJSONSerialization dataWithJSONObject:@{@"status": @"error",
                                                         @"value": @"Failed to serialize result."}
                                               options:0
                                                 error:nil];
    }
    
    [self sendResponseData:data terminator:0];
    
    // Discard initial segment of the buffer prior to \0 character
    size_t i =0;
    while (bytes[i++] != 0) {}
    NSMutableData* newBuffer = [NSMutableData dataWithBytes:bytes+i length:self.inputBuffer.length - i];
    self.inputBuffer = newBuffer;
}

- (void)writeSomeData {
    NSInteger result = [self.outputStream write:self.outJsonData.bytes + self.bytesWritten
                                      maxLength:self.bytesToWrite - self.bytesWritten];
    if (result <= 0) {
        NSLog(@"Error writing bytes to REPL output stream");
    } else {
        self.bytesWritten += result;
    }
    
    if (self.bytesWritten == self.bytesToWrite) {
        [self writeTerminator:self.outTerminator];
    }
}

- (void)writeTerminator:(uint8_t)value {
    uint8_t terminator[1] = {value};
    NSInteger bytesWritten = [self.outputStream write:terminator maxLength:1];
    if (bytesWritten != 1) {
        NSLog(@"Error writing terminator to REPL output stream");
    }
    self.outJsonData = nil;
    [self dequeAndSend];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    if (eventCode == NSStreamEventHasBytesAvailable) {
        if(!self.inputBuffer) {
            self.inputBuffer = [NSMutableData data];
        }
        uint8_t buf[1024];
        NSInteger len = 0;
        len = [(NSInputStream *)stream read:buf maxLength:1024];
        if (len == -1) {
            NSLog(@"Error reading from REPL input stream");
        } else if (len > 0) {
            [self.inputBuffer appendBytes:(const void *)buf length:len];
            for (size_t i=0; i<len; i++) {
                if (buf[i] == 0) {
                    [self processInputBuffer];
                    break;
                }
            }
        }
    } else if (eventCode == NSStreamEventHasSpaceAvailable) {
        if (self.outJsonData) {
            if (self.bytesWritten < self.bytesToWrite) {
                [self writeSomeData];
            } else {
                [self writeTerminator:self.outTerminator];
            }
        }
    } else if (eventCode == NSStreamEventEndEncountered) {
        [stream close];
        [stream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        if (stream == self.inputStream) {
            self.inputStream = nil;
        } else {
            self.outputStream = nil;
        }
    }
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
        
        [inputStream setDelegate:server];
        [outputStream setDelegate:server];
        
        [inputStream  scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

        server.inputStream = inputStream;
        server.outputStream = outputStream;
        
        [inputStream  open];
        [outputStream open];
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
