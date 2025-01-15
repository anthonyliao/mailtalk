//
//  INDeltaSyncEngine.h
//  MailTalk
//
//  Created by anthony on 11/24/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "INSyncEngine.h"

@class NSNotification;

@interface INDeltaSyncEngine : NSObject <INSyncEngine>

- (BOOL)providesCompleteCacheOf:(Class)klass;

- (void)enableSync:(NSNotification *)notification;

- (BOOL)isCompleteSync;

/* Clear all sync state, usually called during the logout process. */
- (void)resetSyncState;

- (void)remaining:(ResultBlock)resultBlock;

- (void)syncOlder:(ResultBlock)resultBlock;

- (void)syncNewer:(ResultBlock)resultBlock;

@end