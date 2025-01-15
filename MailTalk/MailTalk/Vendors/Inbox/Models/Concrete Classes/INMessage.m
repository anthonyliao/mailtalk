//
//  INMessage.m
//  BigSur
//
//  Created by Ben Gotow on 4/30/14.
//  Copyright (c) 2014 Inbox. All rights reserved.
//

#import "INMessage.h"
#import "INThread.h"
#import "INFile.h"
#import "NSString+FormatConversion.h"
#import "INModelObject+Uniquing.h"
#import "INNamespace.h"
#import "INMarkMessageAsReadTask.h"

@implementation INMessage


+ (NSMutableDictionary *)resourceMapping
{
	NSMutableDictionary * mapping = [super resourceMapping];
	[mapping addEntriesFromDictionary:@{
 	 @"subject": @"subject",
 	 @"body": @"body",
	 @"snippet": @"snippet",
	 @"threadID": @"thread_id",
	 @"date": @"date",
	 @"from": @"from",
	 @"to": @"to",
	 @"cc": @"cc",
	 @"bcc": @"bcc",
     @"inReplyTo": @"in_reply_to",
	 @"unread": @"unread",
     @"modSeq": @"mod_seq",
     @"messageID": @"message_id"
	}];
	return mapping;
}

+ (NSString *)resourceAPIName
{
	return @"messages";
}

+ (NSArray *)databaseIndexProperties
{
	return [[super databaseIndexProperties] arrayByAddingObjectsFromArray: @[@"threadID", @"subject", @"date", @"messageID", @"inReplyTo", @"modSeq"]];
}

- (INThread*)thread
{
    if (!_threadID)
        return nil;
    return [INThread instanceWithID: [self threadID] inNamespaceID: [self namespaceID]];
}

- (NSMutableDictionary *)resourceDictionary
{
    NSMutableDictionary * dict = [super resourceDictionary];
    NSMutableArray * files = [NSMutableArray array];
    NSMutableArray * fileIDs = [NSMutableArray array];
    for (INFile * file in _files) {
        [files addObject: [file resourceDictionary]];
        [fileIDs addObject: [file ID]];
    }
    [dict setObject:files forKey:@"files"];
    [dict setObject:fileIDs forKey:@"file_ids"];

    return dict;
}

- (void)updateWithResourceDictionary:(NSDictionary *)dict
{
    [super updateWithResourceDictionary: dict];
    
    NSMutableArray * files = [NSMutableArray array];
    if (dict[@"files"]) {
        for (NSDictionary * fileDict in dict[@"files"]) {
            INFile * file = [INFile attachedInstanceMatchingID: fileDict[@"id"] createIfNecessary:YES didCreate: NULL];
            [file updateWithResourceDictionary: fileDict];
            [files addObject: file];
        }
    } else {
        for (NSDictionary * ID in dict[@"file_ids"]) {
            INFile * file = [INFile attachedInstanceMatchingID: ID createIfNecessary:YES didCreate: NULL];
            [files addObject: file];
        }
    }
    _files = [NSArray arrayWithArray: files];
}

- (void)markAsRead
{
    if (self.unread == NO)
        return;

    INMarkMessageAsReadTask * task = [[INMarkMessageAsReadTask alloc] initWithModel: self];
    [[INAPIManager shared] queueTask: task];
}


@end
