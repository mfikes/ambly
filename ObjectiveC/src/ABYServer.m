#import "ABYServer.h"

#include <CoreFoundation/CoreFoundation.h>
#include <sys/socket.h>
#include <netinet/in.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "JSContextManager.h"

@interface ABYServer()

@property (strong, nonatomic) NSInputStream* inputStream;
@property (strong, nonatomic) NSOutputStream* outputStream;
@property (strong, nonatomic) JSContext* jsContext;

@property (strong, nonatomic) NSMutableData* inputBuffer;

@end

@implementation ABYServer

- (void)processInputBuffer
{
    const char* bytes = self.inputBuffer.bytes;
    NSString* read = [NSString stringWithUTF8String:bytes];
    
    JSValue* result = [self.jsContext evaluateScript:read];
    NSDictionary* rv = nil;
    // TODO get any exception that occurred when evaluating
    if (![result isUndefined] && ![result isNull]) {
        rv = @{@"status": @"success",
               @"value": result.description};
    } else {
        rv = @{@"status": @"success",
               @"value": [NSNull null]};
    }
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rv
                                                       options:0
                                                         error:&error];
    // TODO check error
    
    [self.outputStream write:jsonData.bytes maxLength:jsonData.length];
    uint8_t terminator[1] = {0};
    [self.outputStream write:terminator maxLength:1];
    // TODO check length written and handle that case
    
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
        unsigned int len = 0;
        len = [(NSInputStream *)stream read:buf maxLength:1024];
        if(len) {
            [self.inputBuffer appendBytes:(const void *)buf length:len];
            for (size_t i=0; i<len; i++) {
                if (buf[i] == 0) {
                    [self processInputBuffer];
                    break;
                }
            }
        } else {
            NSLog(@"no buffer!");
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
        NSLog(@"Accepted a socket connection from remote host.");
        
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

-(void)startListening:(short)port {
    
    self.jsContext = [JSContextManager createJSContext];

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
