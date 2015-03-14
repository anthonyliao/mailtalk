//
//  INDeltaSyncEngine.m
//  MailTalk
//
//  Created by anthony on 11/24/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

#import "INDeltaSyncEngine.h"
#import "INAPIManager.h"
#import "INDatabaseManager.h"
#import "MailTalkAdapter.h"
#import "INNamespace.h"
#import "INMessage.h"
#import "INModelObject.h"
#import "INModelObject+Uniquing.h"
#import "MailCore.h"

#define SYNC_COMPLETE @"sync-complete"
#define SYNC_UID @"sync-uid"
#define SYNC_MOD_SEQ @"sync-mod-seq"
#define OLDEST_SYNC_DATE -60*60*24*90

static NSString *const GMAIL_FOLDER = @"[Gmail]/All Mail";

@implementation INDeltaSyncEngine {
    BOOL syncEnabled;
}

- (INDeltaSyncEngine *)init
{
    self = [super init];
    if (self) {
        syncEnabled = NO;
        [self enableSync:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enableSync:) name:INNamespacesChangedNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)providesCompleteCacheOf:(Class)klass
{
    if (klass == [INMessage class]) {
        return YES;
    }
    return NO;
}

- (void)enableSync:(NSNotification *)notification
{
    NSArray * namespaces = [[INAPIManager shared] namespaces];
    if ([namespaces count] > 0) {
        syncEnabled = YES;
    }
}

- (BOOL)isCompleteSync
{
    if (!syncEnabled) {
        return NO;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SYNC_COMPLETE]) {
        return YES;
    }
    return NO;
}

/* Clear all sync state, usually called during the logout process. */
- (void)resetSyncState
{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SYNC_UID];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SYNC_MOD_SEQ];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SYNC_COMPLETE];
    syncEnabled = NO;
}


- (void)remaining:(ResultBlock)resultBlock
{
    if (!syncEnabled) {
        NSLog(@"INDeltaSyncEngine: complete: not enabled");
        if (resultBlock) {
            resultBlock([NSNumber numberWithInteger:0], [NSError errorWithDomain:@"INDeltaSyncEngine" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Sync engine is not enabled yet. Unable to determine remaining messages to sync"}]);
        }
        return;
    }
    
    if ([self isCompleteSync]) {
        NSLog(@"INDeltaSyncEngine: complete: remaining: 0");
        if (resultBlock) {
            resultBlock([NSNumber numberWithInteger:0], nil);
        }
        return;
    }
    
    MCOIMAPSearchExpression * dateExpression = [MCOIMAPSearchExpression searchSinceReceivedDate:[NSDate dateWithTimeIntervalSinceNow:OLDEST_SYNC_DATE]];
    MCOIMAPSearchExpression * compoundExpression = nil;
    NSInteger uid = [[NSUserDefaults standardUserDefaults] integerForKey:SYNC_UID];
    if (uid != 0) {
        MCOIMAPSearchExpression * uidExpression = [MCOIMAPSearchExpression searchUIDs:[MCOIndexSet indexSetWithRange:MCORangeMake(1, uid-1)]];
        compoundExpression = [MCOIMAPSearchExpression searchAnd:dateExpression other:uidExpression];
    }
    
    MCOIMAPSearchOperation * searchOp = [[[[INAPIManager shared] MT] MC] searchExpressionOperationWithFolder:GMAIL_FOLDER expression:(compoundExpression != nil ? compoundExpression : dateExpression)];
    [searchOp start:^(NSError *error, MCOIndexSet *searchResult) {
        if (error == nil) {
            NSLog(@"INDeltaSyncEngine: complete: remaining: %u", [searchResult count]);
            resultBlock([NSNumber numberWithInteger:[searchResult count]], nil);
        } else {
            resultBlock([NSNumber numberWithInteger:0], error);
        }
    }];
}

- (void)syncOlder:(ResultBlock)resultBlock
{
    if (!syncEnabled) {
        NSLog(@"INDeltaSyncEngine: Sync engine is not enabled yet. INAPIManager needs to be authenticated.");
        if (resultBlock) {
            resultBlock([NSArray array], [NSError errorWithDomain:@"INDeltaSyncEngine" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Sync engine is not enabled yet. INAPIManager needs to be authenticated."}]);
        }
        return;
    }
    
    if ([self isCompleteSync]) {
        MCOIndexSet * uids = [MCOIndexSet indexSetWithRange:MCORangeMake(1, UINT64_MAX)];
        NSInteger modSeq = [[NSUserDefaults standardUserDefaults] integerForKey:SYNC_MOD_SEQ];
        MCOIMAPFetchMessagesOperation * syncOp = [[[[INAPIManager shared] MT] MC] syncMessagesWithFolder:GMAIL_FOLDER requestKind:MCOIMAPMessagesRequestKindUid uids:uids modSeq:modSeq];
        [syncOp start:^(NSError *error, NSArray *deltaMessages, MCOIndexSet *deletedMessages) {
            if (error == nil) {
                NSLog(@"INDeltaSyncEngine: complete: remaining:%lu", (unsigned long)[deltaMessages count]);
                resultBlock([NSNumber numberWithInteger:[deltaMessages count]], nil);
            } else {
                resultBlock([NSNumber numberWithInteger:0], error);
            }
        }];
        return;
    }
    
    INNamespace * namespace = (INNamespace *)[[[INAPIManager shared] namespaces] objectAtIndex:0];
    NSString * namespaceID = [namespace emailAddress];
    MCOIMAPFolderStatusOperation * folderStatusOp = [[[[INAPIManager shared] MT] MC] folderStatusOperation:GMAIL_FOLDER];
    [folderStatusOp start:^(NSError *error, MCOIMAPFolderStatus *status) {
        if (error != nil) {
            NSLog(@"INDeltaSyncEngine: folder status: failed error:%@", error);
            if (resultBlock) {
                resultBlock([NSArray array], error);
            }
            return;
        }
        
        uint64_t serverModSeq = [status highestModSeqValue];
        NSInteger uid = [[NSUserDefaults standardUserDefaults] integerForKey:SYNC_UID];
        if (uid == 0) {
            uid = NSIntegerMax;
        }
        [[[INAPIManager shared] MT] GET:namespaceID
                               function:@"messages"
                             parameters:@{@"uid":[NSNumber numberWithInteger:uid]}
                                success:^(id result, NSError *error) {
                                    NSLog(@"INDeltaSyncEngine: sync older: success: messages:%lu", [(NSArray *)result count]);
                                    NSArray * messages = (NSArray *)result;
                                    
                                    __block NSInteger oldestUID = uid;
                                    __block NSDate * oldestDate = [NSDate date];
                                    __block NSMutableArray * messagesToSave = [NSMutableArray array];
                                    dispatch_sync(dispatch_get_main_queue(), ^{
                                        for (NSDictionary * message in messages) {
                                            INMessage * model = [[INMessage class] instanceWithID:message[@"id"] inNamespaceID:namespaceID];
                                            [model updateWithResourceDictionary:message];
                                            oldestUID = MIN(oldestUID, [message[@"uid"] integerValue]);
                                            oldestDate = [oldestDate earlierDate:[model date]];
                                            [messagesToSave addObject:model];
                                        }
                                    });
                                    [[INDatabaseManager shared] persistModels:messagesToSave];
                                    
                                    [[NSUserDefaults standardUserDefaults] setInteger:oldestUID forKey:SYNC_UID];
                                    
                                    if ([messages count] == 0 || oldestUID == 1 || ([oldestDate compare:[[NSDate date] dateByAddingTimeInterval:OLDEST_SYNC_DATE]] == NSOrderedAscending)) {
                                        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SYNC_COMPLETE];
                                        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:SYNC_UID];
                                    }
                                    
                                    if ([[NSUserDefaults standardUserDefaults] integerForKey:SYNC_MOD_SEQ] == 0) {
                                        [[NSUserDefaults standardUserDefaults] setInteger:serverModSeq forKey:SYNC_MOD_SEQ];
                                    }
                                    NSLog(@"INDeltaSyncEngine: sync older: SYNC_MOD_SEQ:%llu, oldestUID:%li, oldestDate:%@, complete:%d", serverModSeq, (long)oldestUID, oldestDate, [[NSUserDefaults standardUserDefaults] boolForKey:SYNC_COMPLETE]);
                                    [[NSUserDefaults standardUserDefaults] synchronize];
                                    if (resultBlock) {
                                        resultBlock(messagesToSave, error);
                                    }
                                    
                                }
                                failure:^(BOOL success, NSError *error) {
                                    NSLog(@"INDeltaSyncEngine: sync older: failed error:%@", error);
                                    if (resultBlock) {
                                        resultBlock([NSArray array], error);
                                    }
                                }];
    }];
}

- (void)syncNewer:(ResultBlock)resultBlock
{
    if (!syncEnabled) {
        NSLog(@"Sync engine is not enabled yet. INAPIManager needs to be authenticated.");
        if (resultBlock) {
            resultBlock([NSArray array], [NSError errorWithDomain:@"INDeltaSyncEngine" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Sync engine is not enabled yet. INAPIManager needs to be authenticated."}]);
        }
        return;
    }
    NSInteger modSeq = [[NSUserDefaults standardUserDefaults] integerForKey:SYNC_MOD_SEQ];
    if (modSeq == 0) {
        [self syncOlder:resultBlock];
    } else {
        //Start sync from modSeq upwards
        INNamespace * namespace = (INNamespace *)[[[INAPIManager shared] namespaces] objectAtIndex:0];
        NSString * namespaceID = [namespace emailAddress];
        
        [[[INAPIManager shared] MT] GET:namespaceID
                               function:@"messages"
                             parameters:@{@"modSeq":[NSNumber numberWithInteger:modSeq]}
                                success:^(id result, NSError *error) {
                                    NSLog(@"INDeltaSyncEngine: sync newer: success: messages:%lu", [(NSArray *)result count]);
                                    NSArray * messages = (NSArray *)result;
                                    
                                    __block NSInteger highestModSeq = modSeq;
                                    __block NSMutableArray * messagesToSave = [NSMutableArray array];
                                    dispatch_sync(dispatch_get_main_queue(), ^{
                                        for (NSDictionary * message in messages) {
                                            INMessage * model = [[INMessage class] instanceWithID:message[@"id"] inNamespaceID:namespaceID];
                                            [model updateWithResourceDictionary:message];
                                            highestModSeq = MAX(highestModSeq, [model modSeq]);
                                            [messagesToSave addObject:model];
                                        }
                                    });
                                    [[INDatabaseManager shared] persistModels:messagesToSave];
                                    
                                    [[NSUserDefaults standardUserDefaults] setInteger:highestModSeq forKey:SYNC_MOD_SEQ];
                                    NSLog(@"INDeltaSyncEngine: sync newer: SYNC_MOD_SEQ:%lu", highestModSeq);
                                    [[NSUserDefaults standardUserDefaults] synchronize];
                                    if (resultBlock) {
                                        resultBlock(messagesToSave, error);
                                    }
                                }
                                failure:^(BOOL success, NSError *error) {
                                    NSLog(@"INDeltaSyncEngine: sync older: failed error:%@", error);
                                    if (resultBlock) {
                                        resultBlock([NSArray array], error);
                                    }
                                }];
    }
}

@end