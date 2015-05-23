#include "ABYServer.h"
#include "ABYUtils.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <CoreFoundation/CoreFoundation.h>
#include <UIKit/UIDevice.h>
#include "GCDWebDAVServer.h"

/**
 An `ABYMessage` is an immutable value container for message
 payloads and terminators.
 */
@interface ABYMessage : NSObject

/**
 The message payload
 */
@property (nonatomic, strong) NSData* payload;

/**
 The message terminator. `0` is used for responses and `1` is used for async prints.
 */
@property (nonatomic) uint8_t terminator;

/**
 Inits this message with a payload and terminator
 @param payload the payload
 @param terminator the terminator
 */
-(id)initWithPayload:(NSData*)payload terminator:(uint8_t)terminator;

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

@interface ABYServer()

// The context this server is wrapping
@property (nonatomic, assign, readonly) JSGlobalContextRef context;

// The WebDAV server
@property (strong, nonatomic) GCDWebDAVServer* davServer;

// The compiler output directory
@property (strong, nonatomic) NSURL* compilerOutputDirectory;

// The streams to the REPL. Non-nil iff connected.
@property (strong, nonatomic) NSInputStream* inputStream;
@property (strong, nonatomic) NSOutputStream* outputStream;

// Buffered data read from REPL
@property (strong, nonatomic) NSMutableData* inputBuffer;
@property (atomic) NSUInteger inputBufferBytesScanned;

// Message currently being sent. (In flight iff messageBeingSent != nil)
@property (strong, atomic) ABYMessage* messageBeingSent;
@property (atomic) NSUInteger messagePayloadBytesSent;

// Subsequent messages to be transmitted in FIFO order
@property (strong, nonatomic) NSMutableArray* queuedMessages;

@end

@implementation ABYServer

-(id)initWithContext:(JSGlobalContextRef)context compilerOutputDirectory:(NSURL*)compilerOutputDirectory
{
    if (self = [super init]) {
        _context = JSGlobalContextRetain(context);
        self.compilerOutputDirectory = compilerOutputDirectory;
    }
    return self;
}

-(void)dealloc
{
    [self tearDown];
    JSGlobalContextRelease(_context);
}

-(BOOL)isReplConnected
{
    return self.outputStream != nil;
}

-(void)sendMessage:(ABYMessage*)message
{
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

-(void)dequeAndSend
{
    if (self.queuedMessages.count) {
        ABYMessage* message = self.queuedMessages[0];
        [self.queuedMessages removeObjectAtIndex:0];
        [self sendMessage:message];
    }
}

-(void)setUpPrintCapability
{
    __weak typeof(self) weakSelf = self;
    
    [ABYUtils installGlobalFunctionWithBlock:
     
     ^JSValueRef(JSContextRef ctx, size_t argc, const JSValueRef argv[]) {
         
         if (argc == 1 && JSValueGetType (ctx, argv[0]) == kJSTypeString)
         {
             JSStringRef messageStringRef = JSValueToStringCopy(ctx, argv[0], NULL);
             NSString* message = (__bridge_transfer NSString *)JSStringCopyCFString(kCFAllocatorDefault, messageStringRef);
             
             if ([weakSelf isReplConnected]) {
                 NSData* payload = [message dataUsingEncoding:NSUTF8StringEncoding];
                 [weakSelf sendMessage:[[ABYMessage alloc] initWithPayload:payload terminator:1]];
             } else {
                 NSLog(@"%@", message);
             }
             
             JSStringRelease(messageStringRef);
         }
         
         return JSValueMakeUndefined(ctx);
     }
                                        name: @"AMBLY_PRINT_FN"
                                     argList:@"message"
                                   inContext:_context];
    
    // If bootstrapping an app, the context may have already
    // been bootstrapped for ClojureScript. If so, set *print-fn*
    // now. Otherwise, the REPL Clojure side will set *print-fn*
    // after bootstrapping for ClojureScript over the TCP connection.
    [ABYUtils evaluateScript:@"if (typeof cljs !== 'undefined') { cljs.core.set_print_fn_BANG_.call(null,AMBLY_PRINT_FN); }" inContext:_context];
}

-(void)evaluateJavaScriptAndSendResponse:(NSString*)javaScript
{
    // Evaluate the JavaScript
    JSValueRef jsError = NULL;
    JSStringRef javaScriptStringRef = JSStringCreateWithCFString((__bridge CFStringRef)javaScript);
    JSValueRef result = JSEvaluateScript(_context, javaScriptStringRef, NULL, NULL, 0, &jsError);
    JSStringRelease(javaScriptStringRef);
 
    // Extract stacktrace if an exception ocurred
    NSString* stackDescription = nil;
    if (jsError) {
        JSStringRef propertyName = JSStringCreateWithCFString((__bridge CFStringRef)@"stack");
        JSValueRef stack = JSObjectGetProperty(_context, JSValueToObject(_context, jsError, NULL), propertyName, NULL);
        stackDescription = [ABYUtils stringForValue:stack inContext:_context];
        JSStringRelease(propertyName);
    }
    
    // Construct response dictionary
    NSDictionary* rv = nil;
    if (jsError) {
        rv = @{@"status": @"exception",
               @"value": [ABYUtils stringForValue:jsError inContext:_context],
               @"stacktrace":stackDescription};
    } else if (!JSValueIsUndefined(_context, result) && !JSValueIsNull(_context, result)) {
        rv = @{@"status": @"success",
               @"value": [ABYUtils stringForValue:result inContext:_context]};
    } else {
        rv = @{@"status": @"success",
               @"value": [NSNull null]};
    }
        
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

-(void)sendPayload
{
    NSInteger result = 0;
    if (self.messageBeingSent.payload.length) {
        result = [self.outputStream write:self.messageBeingSent.payload.bytes + self.messagePayloadBytesSent
                                maxLength:self.messageBeingSent.payload.length - self.messagePayloadBytesSent];
    }
    
    if (result < 0) {
        NSLog(@"Error writing bytes to REPL output stream");
    } else {
        self.messagePayloadBytesSent += result;
    }
    
    if (self.messagePayloadBytesSent == self.messageBeingSent.payload.length) {
        [self sendTerminator:self.messageBeingSent.terminator];
    }
}

- (void)sendTerminator:(uint8_t)value
{
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
                self.inputBufferBytesScanned += len;
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
        [self tearDown];
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

-(void)tearDown
{
    if (self.inputStream) {
        [ABYServer tearDownStream:self.inputStream];
        self.inputStream = nil;
    }
    
    if (self.outputStream) {
        [ABYServer tearDownStream:self.outputStream];
        self.outputStream = nil;
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
        
        CFReadStreamSetProperty(clientInput, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
        CFWriteStreamSetProperty(clientOutput, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
        
        ABYServer* server = (__bridge ABYServer*)info;
        [server tearDown];
        
        NSInputStream* inputStream = (__bridge NSInputStream*)clientInput;
        NSOutputStream* outputStream = (__bridge NSOutputStream*)clientOutput;
        
        [ABYServer setUpStream:inputStream server:server];
        [ABYServer setUpStream:outputStream server:server];

        server.inputStream = inputStream;
        server.outputStream = outputStream;
    }
}

-(BOOL)startListening {
    
    for (unsigned short attemptPort = 49152; attemptPort != 0; attemptPort += 2) {
        if ([self attemptStartListening:attemptPort]) {
            [self setUpPrintCapability];
            return YES;
        }
    }
    return NO;
}

-(BOOL)attemptStartListening:(unsigned short)port {
    
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
    
    CFSocketError sock4err = CFSocketSetAddress(myipv4cfsock, sincfd);
    CFRelease(sincfd);
    if (sock4err != kCFSocketSuccess) {
        return NO;
    }
    
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
    
    CFSocketError sock6err = CFSocketSetAddress(myipv6cfsock, sin6cfd);
    CFRelease(sin6cfd);
    if (sock6err != kCFSocketSuccess) {
        return NO;
    }
    
    
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
    
    
    BOOL startedWebDAV = [self startWebDavWithPort:port + 1];
    
    if (!startedWebDAV) {
        // Clean up TCP
        CFRunLoopRemoveSource(
                              CFRunLoopGetCurrent(),
                              socketsource6,
                              kCFRunLoopDefaultMode);
        
        CFRunLoopRemoveSource(
                              CFRunLoopGetCurrent(),
                              socketsource,
                              kCFRunLoopDefaultMode);
    }
    
    return startedWebDAV;
    
}

- (BOOL)startWebDavWithPort:(NSUInteger)port
{
    // Start up the WebDAV server
    self.davServer = [[GCDWebDAVServer alloc] initWithUploadDirectory:self.compilerOutputDirectory.path];
    
    NSString* appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    
#if TARGET_IPHONE_SIMULATOR
    
    NSString* hostName = [[NSProcessInfo processInfo] hostName];
    if ([hostName hasSuffix:@".local"]) {
        hostName = [hostName substringToIndex:hostName.length - 6];
    }
    
    NSString* bonjourName = [NSString stringWithFormat:@"Ambly %@ on %@ (%@)", appName, [UIDevice currentDevice].model, hostName];
#else
    NSString* bonjourName = [NSString stringWithFormat:@"Ambly %@ on %@", appName, [UIDevice currentDevice].name];
#endif
    
    bonjourName = [self cleanseBonjourName:bonjourName];
    
    [GCDWebDAVServer setLogLevel:3]; // Warning
    return [self.davServer startWithPort:port bonjourName:bonjourName];
}

- (NSString*)cleanseBonjourName:(NSString*)bonjourName
{
    // Bonjour names  cannot contain dots
    bonjourName = [bonjourName stringByReplacingOccurrencesOfString:@"." withString:@"-"];
    // Bonjour names cannot be longer than 63 characters in UTF-8
    
    int upperBound = 63;
    while (strlen(bonjourName.UTF8String) > 63) {
        NSRange stringRange = {0, upperBound};
        stringRange = [bonjourName rangeOfComposedCharacterSequencesForRange:stringRange];
        bonjourName = [bonjourName substringWithRange:stringRange];
        upperBound--;
    }
    return bonjourName;
}

@end
