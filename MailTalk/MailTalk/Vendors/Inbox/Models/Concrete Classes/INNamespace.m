//
//  INNamespace.m
//  BigSur
//
//  Created by Ben Gotow on 4/28/14.
//  Copyright (c) 2014 Inbox. All rights reserved.
//

#import "INNamespace.h"
#import "INTag.h"
#import "INContact.h"
#import "INThreadProvider.h"
#import "INMessageProvider.h"
#import "INThread.h"

@implementation INNamespace

+ (NSMutableDictionary *)resourceMapping
{
	NSMutableDictionary * mapping = [super resourceMapping];
	[mapping addEntriesFromDictionary:@{
	 @"emailAddress": @"email_address",
 	 @"provider": @"provider",
	 @"status": @"status",
	 @"scope": @"scope",
	 @"lastSync": @"last_sync"
	}];
	return mapping;
}

+ (NSString *)resourceAPIName
{
	return @"n";
}

- (NSString *)resourceAPIPath
{
	return [NSString stringWithFormat:@"/n/%@", self.ID];
}

- (INModelProvider *)newContactProvider
{
	return [[INModelProvider alloc] initWithClass:[INContact class] andNamespaceID:[self ID] andUnderlyingPredicate:nil];
}

- (INModelProvider *)newTagProvider
{
	return [[INModelProvider alloc] initWithClass:[INTag class] andNamespaceID:[self ID] andUnderlyingPredicate:nil];
}

- (INThreadProvider *)newThreadProvider
{
	return [[INThreadProvider alloc] initWithNamespaceID: [self ID]];
}

- (INMessageProvider *)newDraftsProvider
{
    return [[INMessageProvider alloc] initWithClass:[INDraft class] andNamespaceID:[self ID] andUnderlyingPredicate:nil];
}

- (INMessageProvider *)newMessageProvider
{
    return [[INMessageProvider alloc] initWithClass:[INMessage class] andNamespaceID:[self ID] andUnderlyingPredicate:nil];
}

@end
