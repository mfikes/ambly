#import "ABYServer.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <CoreFoundation/CoreFoundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

@interface ABYServer()

@property (strong, nonatomic) NSInputStream* inputStream;
@property (strong, nonatomic) NSOutputStream* outputStream;
@property (strong, nonatomic) JSContext* jsContext;

@property (strong, nonatomic) NSMutableData* inputBuffer;

@end

@implementation ABYServer

- (void)sleepUntilSpaceAvailable
{
    while (!self.outputStream.hasSpaceAvailable) {
        [NSThread sleepForTimeInterval:0.1];
    }
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
               @"value": self.jsContext.exception.description};
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
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rv
                                                       options:0
                                                         error:&error];
    if (error) {
        jsonData = [NSJSONSerialization dataWithJSONObject:@{@"status": @"error",
                                                             @"value": @"Failed to serialize result."}
                                                   options:0
                                                     error:nil];
    }
    
    // Send response to REPL
    NSUInteger bytesWritten = 0;
    NSUInteger bytesToWrite = jsonData.length;
    
    const uint8_t * outBytes = jsonData.bytes;
    while (bytesWritten < bytesToWrite) {
        [self sleepUntilSpaceAvailable];
        NSInteger result = [self.outputStream write:outBytes + bytesWritten
                                          maxLength:bytesToWrite - bytesWritten];
        if (result <= 0) {
            NSLog(@"Error writing to REPL output stream");
            break;
        } else {
            bytesWritten += result;
        }
    }
    
    uint8_t terminator[1] = {0};
 
    [self sleepUntilSpaceAvailable];
    bytesWritten = [self.outputStream write:terminator maxLength:1];
       
    // Discard initial segment of the buffer prior to \0 character
    size_t i =0;
    while (bytes[i++] != 0) {}
    NSMutableData* newBuffer = [NSMutableData dataWithBytes:bytes+i length:self.inputBuffer.length - i];
    self.inputBuffer = newBuffer;
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
        //[self.outputStream write:self.outputBuffer.bytes maxLength:10];
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
        [inputStream setDelegate:server];
        
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
