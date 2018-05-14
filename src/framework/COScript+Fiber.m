//
//  COScript+Fiber.m
//  Cocoa Script
//
//  Created by Mathieu Dutour on 12/04/17.
//
//

#import "COScript+Fiber.h"
#import "COSFiber.h"

@implementation COScript (FiberAdditions)

- (void)addFiber:(COSFiber*)fiber {
    
    if (!_activeFibers) {
        _activeFibers = [NSMutableArray array];
    }
    
    [_activeFibers addObject:fiber];
}

- (void)cleanupFibers {
    if (!_activeFibers) {
        return;
    }
    
    for (COSFiber *fiber in [_activeFibers copy]) {
        [fiber cleanup];
    }

    [_activeFibers removeAllObjects];
    _activeFibers = nil;
}

- (void)removeFiber:(COSFiber*)fiber {
    
    if ([_activeFibers indexOfObject:fiber] == NSNotFound) {
        NSLog(@"Could not clean up fiber %@ because it is not in %@'s fiber stack.", fiber, self);
        return;
    }
    
    [_activeFibers removeObject:fiber];
}

- (id)createFiber {
    
    COSFiber *fiber = [COSFiber createWithCocoaScript:self];
    [self addFiber:fiber];
    
    return fiber;
}

@end

