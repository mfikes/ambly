#include "ABYUtils.h"

JSValueRef BlockFunctionCallAsFunction(JSContextRef ctx, JSObjectRef function, JSObjectRef thisObject, size_t argc, const JSValueRef argv[], JSValueRef* exception) {
    JSValueRef (^block)(JSContextRef ctx, size_t argc, const JSValueRef argv[]) = (__bridge JSValueRef (^)(JSContextRef ctx, size_t argc, const JSValueRef argv[]))JSObjectGetPrivate(function);
    JSValueRef ret = block(ctx, argc, argv);
    return ret ? ret : JSValueMakeUndefined(ctx);
}

@implementation ABYUtils

+(NSString*)stringForValue:(JSValueRef)value inContext:(JSContextRef)context
{
    if (value == nil) {
      return @"null";
    } else if (JSValueGetType (context, value) == kJSTypeString) {
        JSStringRef JSString = JSValueToStringCopy(context, value, NULL);
        CFStringRef string = JSStringCopyCFString(kCFAllocatorDefault, JSString);
        JSStringRelease(JSString);
        
        return (__bridge_transfer NSString *)string;
    } else {
        JSStringRef error_str = JSStringCreateWithUTF8CString("Error");
        JSValueRef error_prop = JSObjectGetProperty(context, JSContextGetGlobalObject(context), error_str, NULL);
        JSObjectRef error_constructor_obj = JSValueToObject(context, error_prop, NULL);
        
        if (JSValueIsInstanceOfConstructor(context, value, error_constructor_obj, NULL)) {
            JSObjectRef error_obj = JSValueToObject(context, value, NULL);
            JSStringRef message_str = JSStringCreateWithUTF8CString("message");
            JSValueRef message_prop = JSObjectGetProperty(context, error_obj, message_str, NULL);
            NSString* message = [ABYUtils stringForValue:message_prop inContext:context];
            JSStringRef stack_str = JSStringCreateWithUTF8CString("stack");
            JSValueRef stack_prop = JSObjectGetProperty(context, error_obj, stack_str, NULL);
            NSString* stack = [ABYUtils stringForValue:stack_prop inContext:context];
            
            return [NSString stringWithFormat:@"%@\n%@", message, stack];
        } else {
            static JSObjectRef stringify_fn = NULL;
            
            if (!stringify_fn) {
                JSStringRef json_str = JSStringCreateWithUTF8CString("JSON");
                JSValueRef json_prop = JSObjectGetProperty(context, JSContextGetGlobalObject(context), json_str, NULL);
                JSObjectRef json_obj = JSValueToObject(context, json_prop, NULL);
                JSStringRelease(json_str);
                JSStringRef stringify_str = JSStringCreateWithUTF8CString("stringify");
                JSValueRef stringify_prop = JSObjectGetProperty(context, json_obj, stringify_str, NULL);
                JSStringRelease(stringify_str);
                stringify_fn = JSValueToObject(context, stringify_prop, NULL);
                JSValueProtect(context, stringify_fn);
            }
            
            JSStringRef space_str = JSStringCreateWithUTF8CString(" ");
            JSValueRef space = JSValueMakeString(context, space_str);
            JSStringRelease(space_str);
            
            size_t num_arguments = 3;
            JSValueRef arguments[num_arguments];
            arguments[0] = value;
            arguments[1] = JSValueMakeNull(context);
            arguments[2] = space;
            JSValueRef result = JSObjectCallAsFunction(context, stringify_fn, JSContextGetGlobalObject(context),
                                                       num_arguments, arguments, NULL);
            
            return [ABYUtils stringForValue:result inContext:context];;
        }
    }
}

+(void)setValue:(JSValueRef)value onObject:(JSObjectRef)object forProperty:(NSString*)property inContext:(JSContextRef)context
{
    JSStringRef propertyName = JSStringCreateWithCFString((__bridge CFStringRef)property);
    JSObjectSetProperty(context, object, propertyName, value, 0, NULL);
    JSStringRelease(propertyName);
}

+(JSValueRef)getValueOnObject:(JSObjectRef)object forProperty:(NSString*)property inContext:(JSContextRef)context
{
    JSStringRef propertyName = JSStringCreateWithCFString((__bridge CFStringRef)property);
    JSValueRef rv = JSObjectGetProperty(context, object, propertyName, NULL);
    JSStringRelease(propertyName);
    return rv;
}

+(JSValueRef)evaluateScript:(NSString*)script inContext:(JSContextRef)context
{
    JSStringRef scriptStringRef = JSStringCreateWithCFString((__bridge CFStringRef)script);
    JSValueRef jsError = NULL;
    JSValueRef rv = JSEvaluateScript(context, scriptStringRef, NULL, NULL, 0, &jsError);
    if (jsError) {
        NSLog(@"Ambly: An error occurred while evaluating JavaScript:\n%@",
              [ABYUtils stringForValue:jsError inContext:context]);
    }
    JSStringRelease(scriptStringRef);
    return rv;
}

+(JSObjectRef)createFunctionWithBlock:(JSValueRef (^)(JSContextRef ctx, size_t argc, const JSValueRef argv[]))block inContext:(JSContextRef)context
{
    static JSClassRef jsBlockFunctionClass;
    if(!jsBlockFunctionClass) {
        JSClassDefinition blockFunctionClassDef = kJSClassDefinitionEmpty;
        blockFunctionClassDef.attributes = kJSClassAttributeNoAutomaticPrototype;
        blockFunctionClassDef.callAsFunction = BlockFunctionCallAsFunction;
        blockFunctionClassDef.finalize = nil;
        jsBlockFunctionClass = JSClassCreate(&blockFunctionClassDef);
    }
    
    JSObjectRef jsObj = JSObjectMake(context, jsBlockFunctionClass, (void*)CFBridgingRetain(block));
    CFBridgingRelease((__bridge CFTypeRef)(block));
    return jsObj;
}

+(void)installGlobalFunctionWithBlock:(JSValueRef (^)(JSContextRef ctx, size_t argc, const JSValueRef argv[]))block name:(NSString*)name argList:(NSString*)argList inContext:(JSContextRef)context
{
    NSString* internalObjectName = [NSString stringWithFormat:@"___AMBLY_INTERNAL_%@", name];
    
    [ABYUtils setValue:[ABYUtils createFunctionWithBlock:block inContext:context]
              onObject:JSContextGetGlobalObject(context) forProperty:internalObjectName inContext:context];
    [ABYUtils evaluateScript:[NSString stringWithFormat:@"var %@ = function(%@) { return %@(%@); };", name, argList, internalObjectName, argList] inContext:context];
}

@end
