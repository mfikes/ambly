#include <Foundation/Foundation.h>
#include <JavaScriptCore/JavaScriptCore.h>

/**
 This class wraps a `JSGlobalContextRef` and listens a TCP server, accepting
 ClojureScript-REPL JavaScript expressions to evaluate, evaluating
 them in JSC, and returning the results.
 */
@interface ABYServer : NSObject<NSStreamDelegate>

/**
 Initializes this server.
 
 @param context the supplied context
 @param compilerOutputDirectory the compiler output directory
 */
-(id)initWithContext:(JSGlobalContextRef)context compilerOutputDirectory:(NSURL*)compilerOutputDirectory;

/**
 Starts server listening and wrapping a context.
 
 @return YES iff successful
 */
-(BOOL)startListening;

@end
