//
//  JSTalk.h
//  jstalk
//
//  Created by August Mueller on 1/15/09.
//  Copyright 2009 Flying Meat Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <JavaScriptCore/JavaScriptCore.h>

@class Mocha;
@class COScript;

@protocol COPrintController
- (void)scriptHadException:(NSException*)exception;
- (void)print:(id)s;
@end

@protocol CODebugController
- (void)output:(NSString*)format args:(va_list)args;
@end

@protocol COFlowDelegate
- (void)didClearEventStack:(COScript*)coscript;
@end

@interface COScript : NSObject {
    
    Mocha *_mochaRuntime;
    
    // used in COScript+Fiber
    NSMutableArray *_activeFibers;
    int _nextFiberId;
}

@property (weak) id<COPrintController> printController;
@property (retain) NSMutableDictionary *env;
@property (assign) BOOL shouldPreprocess;
@property (assign) BOOL shouldKeepAround;
@property (strong) NSString* processedSource;
@property (strong, nonatomic) NSDictionary* coreModuleMap;

- (instancetype)initWithCoreModules:(NSDictionary*)coreModules andName:(NSString*)name;
- (void)cleanup;
- (void)garbageCollect;
- (id)executeString:(NSString*) str;
- (id)executeString:(NSString*)str baseURL:(NSURL*)base;
- (void)pushObject:(id)obj withName:(NSString*)name;
- (void)pushJSValue:(JSValueRef)obj withName:(NSString*)name;
- (void)deleteObjectWithName:(NSString*)name;
- (void)print:(id)s;
- (JSValueRef)require:(NSString *)module;
- (BOOL)shouldKeepRunning;

- (JSGlobalContextRef)context;
- (id)callFunctionNamed:(NSString*)name withArguments:(NSArray*)args;
- (BOOL)hasFunctionNamed:(NSString*)name;

- (id)callJSFunction:(JSObjectRef)jsFunction withArgumentsInArray:(NSArray *)arguments;

+ (void)loadBridgeSupportFileAtURL:(NSURL*)url;
+ (void)listen;
+ (void)resetPlugins;
+ (void)loadPlugins;
+ (void)setShouldLoadJSTPlugins:(BOOL)b;
+ (id)application:(NSString*)app;
+ (id)app:(NSString*)app;
+ (COScript*)currentCOScript;

+ (id)setDebugController:(id<CODebugController>)debugController;
+ (id)setFlowDelegate:(id<COFlowDelegate>)flowDelegate;

- (void)fiberWasCleared;

@end

@interface NSObject (COScriptErrorControllerMethods)
- (void)coscript:(id)coscript hadError:(NSString*)error onLineNumber:(NSInteger)lineNumber atSourceURL:(id)url;
@end

@interface JSTalk : COScript // compatibility

@end
