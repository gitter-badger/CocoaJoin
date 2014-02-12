//
//  CJoin.m
//  Copyright (c) 2014 Sergei Winitzki. All rights reserved.
//

#import "CJoin.h"

#import "NSPair.h"
#import "NSArray+OVRandom.h"
#import "NSNumber+lowercaseTypes.h"
#import "WeakRef.h"

#define LOGGING NO

static NSMutableSet *allCreatedJoins; // this set contains weakRef objects pointing to CJoin objects

@interface CJoin()
@property (assign, nonatomic) NSInteger joinID;
@property (strong, nonatomic) NSString *joinQueueName;
@property (strong, nonatomic) dispatch_queue_t joinQueue;
@property (strong, nonatomic) dispatch_queue_t reactionQueue;
@property (assign, nonatomic) ReactionPriority reactionPriority;
@property (strong, nonatomic) NSMutableDictionary *availableMoleculeNames; // molecule name => array of molecule values in instances of that molecule that are currently available in the soup. Access to this dictionary is restricted to the serial queue.
// these two are actually immutable, but declared as mutable since we now declare reactions one by one rather than all together. Should be made immutable.
@property (strong, nonatomic) NSMutableArray *declaredReactions; // NSSet of molecule names => reaction object
@property (strong, nonatomic) NSMutableSet *knownMoleculeNames; // NSSet of all known molecule names
@property (assign, nonatomic) BOOL decideOnMainThread;
- (void) injectFullMolecule:(CjR_A*)molecule;
- (id)getSyncReplyTo:(CjS_A *)syncMolecule;
@end


@interface CjR_A()
+ (instancetype)name:(NSString *)name join:(CJoin *)join;
@property (strong, nonatomic) NSString *moleculeName;
@property (strong, nonatomic) CJoin *ownerJoin;
- (void) putInternal;

@end

#define _cjMkRClassPrivate(t,attr) \
@interface CjR_##t() \
@property (attr, nonatomic) t value;\
@end

// all value types, including empty
_cjMkRClassPrivate(empty, strong)
_cjMkRClassPrivate(id, strong)
_cjMkRClassPrivate(int, assign)
_cjMkRClassPrivate(float, assign)

@implementation CjR_A
- (instancetype)makeCopy {
    CjR_A *result = [self.class name:self.moleculeName join:self.ownerJoin]; // these can be shared
    
    return result;
}
+ (instancetype)name:(NSString *)name join:(CJoin *)join {
    CjR_A *result = [[self alloc] init];
    result.moleculeName = name;
    result.ownerJoin = join;
    return result;
}
- (void)putInternal {
    [self.ownerJoin injectFullMolecule:self];
}
- (NSString *)description {
    return @"Abstract molecule(invalid)";
}
@end

@implementation CjR_empty
- (void)put {
    CjR_empty *copy = [self makeCopy];
    copy.value = [NSNull null];
    [copy putInternal];
}
- (NSString *)description {
    return [NSString stringWithFormat:@"%@(%@)", self.moleculeName, self.value];
}
@end

#define _cjMkRImpl(t) \
@implementation CjR_##t \
- (void)put:(t)value { \
    CjR_##t *copy = [self makeCopy];\
    copy.value = value; \
    [copy putInternal]; \
} \
- (NSString *)description { \
    return [NSString stringWithFormat:@"%@(%@)", self.moleculeName, [CJoin wrap_##t:self.value]]; \
} \
@end

// all value classes, not including empty
_cjMkRImpl(int)
_cjMkRImpl(id)
_cjMkRImpl(float)


@interface CjS_A()
@property (strong, nonatomic) dispatch_semaphore_t syncSemaphore;
//@property (strong, nonatomic) CJoin *ownerJoin;
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) id value;
@property (strong, nonatomic) id resultValue;
- (void)replyInternal:(id)value;
- (id)putSyncInternal;
@end

@implementation CjS_A
- (void)replyInternal:(id)value {
    self.resultValue = value;
    dispatch_semaphore_signal(self.syncSemaphore);
}
- (id)putSyncInternal {
//    CjS_A *copy = [self makeCopy];
    self.syncSemaphore = dispatch_semaphore_create(0);
    return [self.ownerJoin getSyncReplyTo:self];
}
@end
#define _cjMkSEImpl(t) \
@implementation CjR_empty_##t \
- (t)put { \
    CjS_A *copy = [self makeCopy]; \
    copy.value = [NSNull null]; \
    return [CJoin unwrap_##t:[copy putSyncInternal]]; \
} \
- (void)reply:(t)value { \
    [self replyInternal:[CJoin wrap_##t:value]]; \
} \
- (empty)value { \
    return [NSNull null]; \
} \
- (NSString *)description { \
    return [NSString stringWithFormat:@"%@()", self.moleculeName]; \
} \
@end

#define _cjMkSPrivateAndImpl(in,out,attr) \
@interface CjR_##in##_##out() \
@property (attr, nonatomic) in value; \
@end \
@implementation CjR_##in##_##out \
- (out)put:(in)value { \
    CjR_##in##_##out *copy = [self makeCopy]; \
    copy.value = value; \
    return [CJoin unwrap_##out:[copy putSyncInternal]]; \
} \
- (void)reply:(out)value { \
    [self replyInternal:[CJoin wrap_##out:value]]; \
} \
- (NSString *)description { \
    return [NSString stringWithFormat:@"%@(%@)", self.moleculeName, [CJoin wrap_##in:self.value]]; \
} \
@end

@implementation CjR_empty_empty
- (void)put {
    CjR_empty_empty *copy = [self makeCopy];
    [copy putSyncInternal];
}
- (void)reply {
    [self replyInternal:[NSNull null]];
}
- (empty)value {
    return [NSNull null];
}
- (NSString *)description {
    return [NSString stringWithFormat:@"%@()", self.moleculeName];
}
@end

// all functions of type empty -> t except empty -> empty
_cjMkSEImpl(int)
_cjMkSEImpl(float)
_cjMkSEImpl(id)

// all function classes not including empty -> *

_cjMkSPrivateAndImpl(float, float, assign)
_cjMkSPrivateAndImpl(float, id, assign)
_cjMkSPrivateAndImpl(float, int, assign)
_cjMkSPrivateAndImpl(id, float, strong)
_cjMkSPrivateAndImpl(id, id, strong)
_cjMkSPrivateAndImpl(id, int, strong)
_cjMkSPrivateAndImpl(int, float, assign)
_cjMkSPrivateAndImpl(int, id, assign)
_cjMkSPrivateAndImpl(int, int, assign)


@interface CjReaction : NSObject
@end
@interface CjReaction()
@property (strong, nonatomic) NSArray *moleculeNames;
@property (copy, nonatomic) ReactionPayload reactionBlock;
@property (assign, nonatomic) BOOL runOnMainThread;
- (void) startReactionWithInput:(NSArray *)inputs;
@end


@implementation CjReaction
+ (instancetype) inputNames:(NSArray *)moleculeNames payload:(ReactionPayload)payload runOnMainThread:(BOOL)onMainThread {
    CjReaction *r = [[CjReaction alloc] init];
    r.moleculeNames = moleculeNames;
    r.reactionBlock = payload;
    r.runOnMainThread = onMainThread;
    return r;
}
- (void)startReactionWithInput:(NSArray *)inputs {
    self.reactionBlock(inputs);
}
@end


@implementation CJoin
+ (instancetype)joinOnMainThread:(BOOL)onMainThread reactionPriority:(ReactionPriority)priority {
    CJoin *join = [[CJoin alloc] init];
    join.decideOnMainThread = onMainThread;
    join.reactionPriority = priority;
    [join initializeJoin];
    [self registerNewJoin:join];
    return join;
}
- (void) initializeJoin {
    static NSInteger globalJoinCounter = 0;
    CJoin *join = self;
    
    
    
    join.joinID = (++globalJoinCounter);
    
    if (join.decideOnMainThread) {
        join.joinQueue = dispatch_get_main_queue();
        join.reactionQueue = join.joinQueue;
    } else {
        join.joinQueueName = [NSString stringWithFormat:@"CocoaJoin#%d", join.joinID];
        
        const char* queueLabel = [join.joinQueueName cStringUsingEncoding:NSASCIIStringEncoding];
        join.joinQueue = dispatch_queue_create(queueLabel, DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(join.joinQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        join.reactionQueue = dispatch_get_global_queue(join.reactionPriority, 0);
    }
    join.availableMoleculeNames = [NSMutableDictionary dictionary];
    join.knownMoleculeNames = [NSMutableSet set];
    join.declaredReactions = [NSMutableArray array];
}


- (id)getSyncReplyTo:(CjS_A *)syncMolecule {
   
    // set up the semaphore
    // create and inject a molecule of class CjSync into the soup
    // wait for the semaphore, then extract the result value from CjSync and return it (as id)
    [self injectFullMolecule:syncMolecule];
    // now either the reaction will be run right away and will finish synchronously on this thread, or it will be started asynchronously.
    // In either case, it is safe to wait for the semaphore now.
    dispatch_semaphore_wait(syncMolecule.syncSemaphore, DISPATCH_TIME_FOREVER);
    syncMolecule.syncSemaphore = nil;
    return syncMolecule.resultValue;
}
- (void)defineReactionWithInputs:(NSArray *)inputs payload:(ReactionPayload)payload runOnMainThread:(BOOL)onMainThread {
    NSMutableArray *inputNames = [NSMutableArray arrayWithCapacity:inputs.count];
    for (CjR_A *m in inputs) {
        [inputNames addObject:m.moleculeName];
    }
    CjReaction *reaction = [CjReaction inputNames:inputNames payload:payload runOnMainThread:onMainThread];
    [self defineReaction:reaction];
}
- (void) defineReaction:(CjReaction *)reaction {
    NSSet *moleculeSet = [NSSet setWithArray:reaction.moleculeNames];
    [self.knownMoleculeNames unionSet:moleculeSet];
    [self.declaredReactions addObject:reaction];
}

- (void) internalInjectFullMolecule:(CjR_A *)molecule {
    if (LOGGING) NSLog(@"%@ %@ join %d, injecting molecule '%@', mainThread=%d", self.class, NSStringFromSelector(_cmd), self.joinID, molecule, [[NSThread currentThread] isMainThread]);
    NSString *moleculeName = molecule.moleculeName;
        // add to available classes, but only if this is a class we recognize.
    if ([self.knownMoleculeNames containsObject:moleculeName]) {
        NSMutableArray *presentMoleculeValues = [self.availableMoleculeNames objectForKey:moleculeName];
        if (presentMoleculeValues == nil) {
            presentMoleculeValues = [NSMutableArray array]; // important to have a mutable array: we will update it as molecules are injected or consumed, and we will also shuffle it.
            [self.availableMoleculeNames setObject:presentMoleculeValues forKey:moleculeName];
        }
        [presentMoleculeValues addObject:molecule];
    } else {
        if (LOGGING) NSLog(@"%@ %@ join %d, molecule named %@ is unknown in this join definition", self.class, NSStringFromSelector(_cmd), self.joinID, moleculeName);
       
    }
    if (LOGGING) NSLog(@"%@ %@ join %d, after injecting molecule '%@' the join now contains:\n{ %@ }", self.class, NSStringFromSelector(_cmd), self.joinID, molecule, [self debugPrintSoupContents]);
    
    [self decideAndRunAllPossibleReactions];
}

- (void)injectFullMolecule:(CjR_A *)molecule {
    
    BOOL isMainThread = [[NSThread currentThread] isMainThread];
    if (isMainThread && self.decideOnMainThread) {
//        if (LOGGING) NSLog(@"%@ %@, join %d, inject molecule %@ on mainThread=%d", self.class, NSStringFromSelector(_cmd), self.joinID, moleculeName, isMainThread);
        [self internalInjectFullMolecule:molecule];
    } else {
        if (LOGGING) NSLog(@"%@ %@, join %d, scheduling the injection asynchronously, mainThread=%d", self.class, NSStringFromSelector(_cmd), self.joinID, isMainThread);
        dispatch_async(self.joinQueue, ^{
            [self internalInjectFullMolecule:molecule];
        });
    }
}

// pretty-print the current contents of the soup
- (NSString *)debugPrintSoupContents {
    NSMutableString *result = [NSMutableString string];
    for (NSString *moleculeName in self.availableMoleculeNames.allKeys) {
        NSArray *moleculeValues = self.availableMoleculeNames[moleculeName];
        for (id value in moleculeValues) {
            if ([result length] > 0) {
                [result appendString:@", "];
            }
            [result appendString:[(CjR_A*)value description]];
        }
    }
    return result;
}
- (void) decideAndRunAllPossibleReactions {
    // decide which reactions can be started, and start each of them asynchronously, until no new reactions can be started at this time.
    NSPair *foundReaction = nil;
    while ((foundReaction = [self findAnyReactionWithInput]) != nil) {
        [self dispatchReaction:foundReaction];
    }

}
/// internal function: returns a pair (Reaction, NSArray) if the reaction is now possible, with nsarray containing the available input molecules; otherwise returns nil.
- (NSPair *) findAnyReactionWithInput {
    for (CjReaction *foundReaction in [self.declaredReactions shuffledArray]) { // important to look for reactions in random order!
        NSArray *availableInput = [self moleculesAvailable:foundReaction.moleculeNames]; // this function returns an array of available molecules and removes them from the list of available molecules!
        if (availableInput != nil) {
            return [NSPair :foundReaction :availableInput];
        }
    }
    return nil;
}

/// internal function: return an array of molecules if all were available from the required classes, or nil if at least one molecule was not available. At the same time, the molecules are removed from availableMoleculeNames.
- (NSArray *) moleculesAvailable:(NSArray *)moleculeNames {
    NSMutableArray *molecules = [NSMutableArray arrayWithCapacity:moleculeNames.count];
    NSMutableArray *affectedMoleculeList = [NSMutableArray arrayWithCapacity:moleculeNames.count];
    for (NSString *moleculeClass in moleculeNames) {
        NSMutableArray *presentMolecules = [self.availableMoleculeNames objectForKey:moleculeClass];
        if ([presentMolecules count] > 0) {
            [presentMolecules shuffle];  // important to remove a randomly chosen object! so, first we shuffle,
            id chosenMolecule = [presentMolecules lastObject]; // then we select the last object.
            
            [molecules addObject:chosenMolecule];
            [affectedMoleculeList addObject:presentMolecules]; // affectedMoleculeList is the list of arrays from which we have selected last elements. Each of these arrays needs to be trimmed (the last element removed), but only if we finally succeed in finding all required molecules. Otherwise, nothing should be removed from any lists.
        } else {
            // did not find this molecule, but reaction requires it - nothing to do now.
            return nil;
        }
    }
    if (moleculeNames.count != molecules.count) return nil;
    // if we are here, we have found all input molecules required for the reaction!
    // now we need to remove them from the molecule arrays; note that affectedMoleculeInstances is a pointer to an array inside the dictionary self.availableMoleculeNames.
    for (NSMutableArray *affectedMoleculeInstances in affectedMoleculeList) {
        [affectedMoleculeInstances removeLastObject]; // now that the array was shuffled, we know that we need to remove the last object.
    }
    return [NSArray arrayWithArray:molecules];
}


/// internal function: dispatch the given reaction on the appropriate queue
- (void) dispatchReaction:(NSPair *)reactionWithInput {
    
    BOOL isMainThread = [[NSThread currentThread] isMainThread];
    if (LOGGING) NSLog(@"%@ %@ join %d mainThread=%d", self.class, NSStringFromSelector(_cmd), self.joinID, isMainThread);
    
    CjReaction *reaction = reactionWithInput.first;
    NSArray *inputMolecules = reactionWithInput.second;
    
    // error: the reaction received no input molecules?
    if (inputMolecules == nil) {
        if (LOGGING) NSLog(@"%@ %@ reaction %@ has no input molecules!", self.class, NSStringFromSelector(_cmd), reaction);
    }
    
    // need to avoid multiple async dispatch if we are on the main thread and we need to start a reaction on the main thread.
    if (reaction.runOnMainThread && isMainThread) {
        if (LOGGING) NSLog(@"%@ %@ join %d starting reaction %@, input %@, on main thread", self.class, NSStringFromSelector(_cmd), self.joinID, reaction, inputMolecules);
        
        [reaction startReactionWithInput:inputMolecules];
    } else {
        
        dispatch_queue_t queueForReaction = reaction.runOnMainThread ? dispatch_get_main_queue() : self.reactionQueue;
        // if the join is not running on main thread, but the reaction must be run on main thread, then we must use the main queue.
        if (reaction.runOnMainThread) {
            if (LOGGING) NSLog(@"%@ %@ join %d dispatching asynchronous reaction %@, input %@, mainThread=%d", self.class, NSStringFromSelector(_cmd), self.joinID, reaction, inputMolecules, isMainThread);
        }
        dispatch_async(queueForReaction, ^{
            
            if (LOGGING) NSLog(@"%@ %@ join %d starting asynchronous reaction %@, input %@, mainThread=%d", self.class, NSStringFromSelector(_cmd), self.joinID, reaction, inputMolecules, [[NSThread currentThread] isMainThread]);
            [reaction startReactionWithInput:inputMolecules];
        });
        
    }
    
    
}
+ (void) initializeGlobalSet {
    if (allCreatedJoins == nil) {
        allCreatedJoins = [NSMutableSet set];
    }
    
}

+ (void) registerNewJoin:(CJoin *)join {
    [self initializeGlobalSet];
    [allCreatedJoins addObject:[WeakRef value:join]];
    // what else? Inject some kind of new molecule for this join? not sure if this is necessary now. Maybe some of these joins will die later.
}
+ (void) cleanupGlobalArray {
    [self initializeGlobalSet];
    // remove any weakrefs that have become nil
    // need to synchronize somehow!
    NSMutableSet *newSet = [NSMutableSet setWithCapacity:allCreatedJoins.count];
    @synchronized(self){
        
        for (WeakRef *w in allCreatedJoins) {
            if (w.weakRef != nil) {
                [newSet addObject:w];
            }
        }
        allCreatedJoins = newSet;
    }
}
+ (void) stopAndThen:(void (^)(void))continuation {
    // TODO: implement
    // stop all joins, wait for them, then call continuation.
    // use the stopAndThen function on each join, wait for results
    // use a special globally created join for this!
}
- (void)stopAndThen:(void (^)(void))continuation {
    // TODO: implement
    // Wait until all reactions are finished; reply to all existing fast molecules, and remove all existing slow molecules; on any new inject, do not inject any new slow molecules but reply to any injected fast molecules.
    if (continuation != nil) continuation();
}

+ (id)wrap_empty:(empty)value {
    return value;
}
+ (id)wrap_id:(id)value {
    return value;
}
#define DEFINE_WRAP_TYPE(t) \
+ (id)wrap_##t:(t)value { \
    return [NSNumber t##Wrap:value]; \
}

DEFINE_WRAP_TYPE(BOOL)
DEFINE_WRAP_TYPE(char)
DEFINE_WRAP_TYPE(short)
DEFINE_WRAP_TYPE(int)
DEFINE_WRAP_TYPE(long)
DEFINE_WRAP_TYPE(longlong)
DEFINE_WRAP_TYPE(float)
DEFINE_WRAP_TYPE(double)

+ (empty)unwrap_empty:(id)value {
    return value;
}
+ (id)unwrap_id:(id)value {
    return value;
}
#define DEFINE_UNWRAP_TYPE(t) \
+ (t)unwrap_##t:(id)value { \
    return [(NSNumber *)value t##Value]; \
}
DEFINE_UNWRAP_TYPE(BOOL)
DEFINE_UNWRAP_TYPE(char)
DEFINE_UNWRAP_TYPE(short)
DEFINE_UNWRAP_TYPE(int)
DEFINE_UNWRAP_TYPE(long)
DEFINE_UNWRAP_TYPE(longlong)
DEFINE_UNWRAP_TYPE(float)
DEFINE_UNWRAP_TYPE(double)

@end