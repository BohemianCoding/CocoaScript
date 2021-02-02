// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//  Created by Sam Deane on 19/03/2018.
//  All code (c) 2018 - present day, Elegant Chaos Limited.
//  For licensing terms, see http://elegantchaos.com/license/liberal/.
//
//  We're relying on some Block API knowledge here:
//  http://releases.llvm.org/3.8.1/tools/docs/Block-ABI-Apple.html
//  With thanks also to Mike Ash for some important nuggets contained
//  in: https://www.mikeash.com/pyblog/friday-qa-2011-05-06-a-tour-of-mablockclosure.html
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

#import "MOJSBlock.h"
#import <objc/message.h>

#import "MOJavaScriptObject.h"
#import "MOUtilities.h"
#import "MOUndefined.h"

/**
 Internal block structures.
 
 See http://releases.llvm.org/3.8.1/tools/docs/Block-ABI-Apple.html for more details.
 */

struct BlockDescriptor
{
    unsigned long reserved;
    unsigned long size;
    const char *signature;
    const char *layout;
};

struct Block
{
    void *isa;
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct BlockDescriptor *descriptor;
};

enum {
    BLOCK_DEALLOCATING =      (0x0001),
    BLOCK_REFCOUNT_MASK =     (0xfffe),
    BLOCK_NEEDS_FREE =        (1 << 24),
    BLOCK_HAS_COPY_DISPOSE =  (1 << 25),
    BLOCK_HAS_CTOR =          (1 << 26), // helpers have C++ code
    BLOCK_IS_GC =             (1 << 27),
    BLOCK_IS_GLOBAL =         (1 << 28),
    BLOCK_USE_STRET =         (1 << 29), // undefined if !BLOCK_HAS_SIGNATURE
    BLOCK_HAS_SIGNATURE  =    (1 << 30)
};

// MARK: - Invocation

/**
 The higher level invocation function extracts the arguments, converts
 them to JSValueRefs, and calls the JS function.
 
 We return the result as another JSValueRef.
 */

static JSValueRef jsInvoke(MOJavaScriptObject* function, NSMethodSignature* signature, va_list args) {
    
    NSUInteger count = [signature numberOfArguments] - 1;
    NSMutableArray *arguments = [[NSMutableArray alloc] init];
    
    for (NSUInteger i = 1; i <= count; ++i) {
        NSString* type = [NSString stringWithCString:[signature getArgumentTypeAtIndex:i] encoding:NSASCIIStringEncoding];
        if ([type isEqualToString:@"i"]) {
            int value = va_arg(args, int);
            [arguments addObject:[NSNumber numberWithInt:value]];
        } else if ([type isEqualToString:@"I"]) {
            uint value = va_arg(args, uint);
            [arguments addObject:[NSNumber numberWithUnsignedInt:value]];
        } else if ([type isEqualToString:@"q"]) {
            NSInteger value = va_arg(args, NSInteger);
            [arguments addObject:[NSNumber numberWithInteger:value]];
        } else if ([type isEqualToString:@"Q"]) {
            NSUInteger value = va_arg(args, NSUInteger);
            [arguments addObject:[NSNumber numberWithUnsignedInteger:value]];
        } else if ([type isEqualToString:@"d"]) {
            double value = va_arg(args, double);
            [arguments addObject:[NSNumber numberWithDouble:value]];
        } else if ([type isEqualToString:@"c"]) {
            char value = va_arg(args, int);
            [arguments addObject:[NSNumber numberWithChar:value]];
        } else if ([type isEqualToString:@"B"]) {
            bool value = va_arg(args, int) != 0;
            [arguments addObject:[NSNumber numberWithBool:value]];
        } else if ([type isEqualToString:@"{CGRect={CGPoint=dd}{CGSize=dd}}"]) {
            CGRect value = va_arg(args, CGRect);
            [arguments addObject:[NSValue valueWithRect:value]];
        } else if ([type isEqualToString:@"{CGPoint=dd}"]) {
            CGPoint value = va_arg(args, CGPoint);
            [arguments addObject:[NSValue valueWithPoint:value]];
        } else if ([type isEqualToString:@"{CGSize=dd}"]) {
            CGSize value = va_arg(args, CGSize);
            [arguments addObject:[NSValue valueWithSize:value]];
        } else if ([type isEqualToString:@"{_NSRange=QQ}"]) {
            NSRange value = va_arg(args, NSRange);
            [arguments addObject:[NSValue valueWithRange:value]];
        } else if ([type characterAtIndex:0] == '@') {
            id value = va_arg(args, id);
            if (value) {
                [arguments addObject:value];
            } else {
                [arguments addObject:[MOUndefined undefined]];
            }
        } else {
            NSLog(@"arg #%ld type %@", i, type);
            [arguments addObject:[MOUndefined undefined]];
        }
    }
    
    __block JSValueRef value = NULL;
    
    void (^execBlock)(void) = ^{
        JSContextRef ctx = [function JSContext];
        Mocha *runtime = [Mocha runtimeWithContext:ctx];
        
        value = [runtime callJSFunction:[function JSObject] withArgumentsInArray:arguments];
        
        if (value == NULL) {
            [NSException raise:@"CallbackError" format:@"Error while calling the callback"];
        }
    };
    
    // Mocha expects all JS functions to be executed on the main thread.
    // So when creating a block, the JS function still needs to be executed on
    // the main thread, regardless of where the block is executed.
    if ([NSThread isMainThread]) {
        execBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), execBlock);
    }
    
    return value;
}

/**
 Helpers to convert the return value to the correct type.
 */

static double return_double(JSContextRef ctx, JSValueRef value) { return JSValueToNumber(ctx, value, NULL); }
static int return_int(JSContextRef ctx, JSValueRef value) { return JSValueToNumber(ctx, value, NULL); }
static uint return_uint(JSContextRef ctx, JSValueRef value) { return JSValueToNumber(ctx, value, NULL); }
static NSInteger return_NSInteger(JSContextRef ctx, JSValueRef value) { return JSValueToNumber(ctx, value, NULL); }
static NSUInteger return_NSUInteger(JSContextRef ctx, JSValueRef value) { return JSValueToNumber(ctx, value, NULL); }
static char return_char(JSContextRef ctx, JSValueRef value) { return JSValueToNumber(ctx, value, NULL); }
static bool return_bool(JSContextRef ctx, JSValueRef value) { return JSValueToBoolean
(ctx, value); }
static id return_id(JSContextRef ctx, JSValueRef value) {
    Mocha *runtime = [Mocha runtimeWithContext:ctx];
    return [runtime objectForJSValue:value];
}
//static CGRect return_CGRect(Mocha* runtime, JSContextRef ctx, JSValueRef value) { return value.toRect; }
//static CGPoint return_CGPoint(Mocha* runtime, JSContextRef ctx, JSValueRef value) { return value.toPoint; }
//static CGSize return_CGSize(Mocha* runtime, JSContextRef ctx, JSValueRef value) { return value.toSize; }
//static NSRange return_NSRange(Mocha* runtime, JSContextRef ctx, JSValueRef value) { return value.toRange; }


/**
 We use a few different low level invocation functions - one for each return type - as a quick
 and easy way of getting the compiler to put the right sized return value onto the stack.
 
 This isn't scalable for generic structs, since there are an infinite variety of them and
 we can't declare a function for every one.
 
 In theory we ought to be able to use the signature plus knowledge of the ABI to figure out
 where the return value is supposed to go (registers, stack, or a bit of both) and how big it is.
 We could then execute a few assembler instructions to put it into the right place.
 
 This should allow us to have a single invocation function to handle all cases.
 
 */

/// Original implementation of the `void_invoke` method which takes variable arguments.
///
/// @param block The MOJSBlock wrapper that has additional information.
static void void_invoke_var(MOJSBlock* block, ...) {
    va_list args;
    va_start(args, block);
    NSMethodSignature* signature = block.signature;
    MOJavaScriptObject* function = block.function;
    jsInvoke(function, signature, args);
    va_end(args);
}

/// Wrapper around `void_invoke` with a set number of parameters instead of a variadic function.
///
/// Because the implementation of variadic functions is different on Intel and ARM CPUs (with the
/// former using registers plus stack for the arguments and the latter placing them directly on the
/// stack) paired with the inability of Clang to determine automatically that we are using a
/// variadic function for this block, we use a wrapper that passes the arguments it receives over
/// to the original variadic function.
///
/// **Note**: This is a workaround because finding a proper fix could potentially take a lot of
/// time. A better fix would be convincing the compiler that we're using variadic functions and
/// thus not to look for parameters in registers on ARM, but from our testing this is not achieved
/// by changing the type of the invoke method, possibly because it is not considered as part of the
/// Objective-C blocks ABI.
///
/// **See also**:
/// * https://github.com/sketch-hq/Sketch/issues/35324
///
/// @param block The MOJSBlock wrapper that has additional information.
/// @param argx The arguments passed into this function and on to the variadic function.
static void void_invoke(MOJSBlock* block, void *arg1, void *arg2, void *arg3, void *arg4, void *arg5, void *arg6, void *arg7, void *arg8, void *arg9, void *arg10, void *arg11, void *arg12) {
    void_invoke_var(block, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12);
}

#define INVOKE_BLOCK_RETURNING(_type_) \
static _type_ _type_ ## _invoke_var(MOJSBlock* block, ...) { \
va_list args; \
va_start(args, block); \
JSValueRef jsResult = jsInvoke(block.function, block.signature, args); \
va_end(args); \
return return_ ## _type_([block.function JSContext], jsResult); \
} \
static _type_ _type_ ## _invoke(MOJSBlock* block, void *arg1, void *arg2, void *arg3, void *arg4, void *arg5, void *arg6, void *arg7, void *arg8, void *arg9, void *arg10, void *arg11, void *arg12) { \
return _type_ ## _invoke_var(block, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12); \
}

INVOKE_BLOCK_RETURNING(double);
INVOKE_BLOCK_RETURNING(int);
INVOKE_BLOCK_RETURNING(uint);
INVOKE_BLOCK_RETURNING(NSInteger);
INVOKE_BLOCK_RETURNING(NSUInteger);
INVOKE_BLOCK_RETURNING(char);
INVOKE_BLOCK_RETURNING(bool);
INVOKE_BLOCK_RETURNING(id);
//INVOKE_BLOCK_RETURNING(CGRect);
//INVOKE_BLOCK_RETURNING(CGPoint);
//INVOKE_BLOCK_RETURNING(CGSize);
//INVOKE_BLOCK_RETURNING(NSRange);

#define INVOKE_CASE(_char_, _type_) case _char_: _invoke = (IMP) _type_ ## _invoke; break

// MARK: - Object

@implementation MOJSBlock
{
    int _flags;
    int _reserved;
    IMP _invoke;
    struct BlockDescriptor *_descriptor;
}

+ (instancetype)blockWithSignature:(NSString*)signature function:(MOJavaScriptObject *)function {
    return [[self alloc] initWithSignature:signature.UTF8String function:function];
}


- (instancetype)initWithSignature:(const char*)signature function:(MOJavaScriptObject *)function {
    self = [super init];
    if (self) {
        _flags = BLOCK_HAS_SIGNATURE | BLOCK_IS_GLOBAL;
        _descriptor = calloc(1, sizeof(struct BlockDescriptor));
        _descriptor->size = class_getInstanceSize([self class]);
        _descriptor->signature = signature;
        _signature = [NSMethodSignature signatureWithObjCTypes:signature];
        
        const char* type = _signature.methodReturnType;
        switch (type[0]) {
            INVOKE_CASE('d', double);
            INVOKE_CASE('i', int);
            INVOKE_CASE('I', uint);
            INVOKE_CASE('q', NSInteger);
            INVOKE_CASE('Q', NSUInteger);
            INVOKE_CASE('c', char);
            INVOKE_CASE('B', bool);
            INVOKE_CASE('@', id);
                
//            case '{':
//                if (strcmp(type, "{CGRect={CGPoint=dd}{CGSize=dd}}") == 0) {
//                    _invoke = (IMP)CGRect_invoke;
//                    break;
//                } else if (strcmp(type, "{CGPoint=dd}") == 0) {
//                    _invoke = (IMP)CGPoint_invoke;
//                    break;
//                } else if (strcmp(type, "{CGSize=dd}") == 0) {
//                    _invoke = (IMP)CGSize_invoke;
//                    break;
//                } else if (strcmp(type, "{_NSRange=QQ}") == 0) {
//                    _invoke = (IMP)NSRange_invoke;
//                    break;
//                } else {
//                    NSLog(@"returning generic structures not handled yet");
//                }
//                break;
            default:
                _invoke = (IMP)void_invoke;
        }
        
        _function = function;
    }
    
    return self;
}

- (void)dealloc {
    free(_descriptor);
}

- (id)copyWithZone:(nullable NSZone*)zone {
    return self;
}

@end
