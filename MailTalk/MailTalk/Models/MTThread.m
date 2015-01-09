//
//  MTThread.m
//  mailtalkdemo
//
//  Created by anthony on 11/26/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTThread.h"
#import "MCOIMAPMessage.h"
#import "MCOMessageHeader.h"
#import "MCOAddress.h"
#import "MTTag.h"

@implementation MTThread {
    NSMutableArray * _messages;
}

- (id)init
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _messages = [[NSMutableArray alloc] init];
    
    return self;
}

- (NSString *)threadID
{
    if ([_messages count] == 0) {
        return nil;
    }
    
    MCOIMAPMessage * first = (MCOIMAPMessage *)[_messages firstObject];
    return [[NSString alloc] initWithFormat:@"%llu", [first gmailThreadID]];
}

- (void)addMessage:(MCOIMAPMessage *)message
{
    if ([_messages count] != 0) {
        MCOIMAPMessage * first = (MCOIMAPMessage *)[_messages firstObject];
        [first gmailLabels];
        NSAssert(([first gmailThreadID] == [message gmailThreadID]),
                 @"Error: attempt to add [gmailID:%llu, gmailThreadID:%llu] to existing [gmailThreadID:%llu], must be the same",
                 [message gmailMessageID],
                 [message gmailThreadID],
                 [first gmailThreadID]);
    }
    [_messages addObject:message];
}

- (NSDictionary *)resourceDictionary
{
    NSAssert([_messages count] != 0, @"Can not create a dictionary for thread with no messages");
    
    MCOIMAPMessage * first = (MCOIMAPMessage *)[_messages firstObject];
    NSString * gmailThreadID = [[NSString alloc] initWithFormat:@"%llu", [first gmailThreadID]];
    NSArray * messageIDs = [self getMessageIDs];
    NSString * lastTimestamp = [self getLastMessageTimestamp];
    NSArray * participants = [self getParticipants];
    NSArray * tags = [self getTags];
    NSString * subject = [[first header] subject] == nil ? @"" : [[first header] subject];
    NSString * highestModSeq = [self getHighestModSeq];
    NSAssert(gmailThreadID != nil, @"gmailThreadID can not be nil");
    NSAssert(messageIDs != nil, @"messageIDs can not be nil");
    NSAssert(lastTimestamp != nil, @"lastTimestamp can not be nil");
    NSAssert(participants != nil, @"participants can not be nil");
    NSAssert(tags != nil, @"tags can not be nil");
    NSAssert(subject != nil, @"subject can not be nil");
    NSAssert(highestModSeq != nil, @"highestModSeq can not be nil");
    NSDictionary * resourceDict = @{@"id" : gmailThreadID,
                                    @"subject" : subject,
                                    @"message_ids" : messageIDs,
                                    @"created_at" : [NSNull null],
                                    @"last_accessed_at" : [NSNull null],
                                    @"tags" : tags,
                                    @"snippet" : [NSNull null],
                                    @"participants" : participants,
                                    @"updated_at" : [NSNull null],
                                    @"namespace_id" : [self namespaceID],
                                    @"draft_ids" : [NSNull null],
                                    @"last_message_timestamp" : lastTimestamp,
                                    @"highestModSeq" : highestModSeq
                                    };
//    NSLog(@"%@", resourceDict);
    return resourceDict;
}

- (NSArray *)getMessageIDs
{
    NSMutableArray * messageIDs = [[NSMutableArray alloc] init];
    for (MCOIMAPMessage * message in _messages) {
        NSString * gmailMessageID = [[NSString alloc] initWithFormat:@"%llu", [message gmailMessageID]];
        [messageIDs addObject:gmailMessageID];
    }
    return messageIDs;
}

- (NSString *)getLastMessageTimestamp
{
    MCOIMAPMessage * last = (MCOIMAPMessage *)[_messages lastObject];
    NSDate * lastTimestamp = [[last header] date];
    NSString * lastTimestampString = [NSString stringWithFormat:@"%lf", [lastTimestamp timeIntervalSince1970]];
    return lastTimestampString;
}

- (NSArray *)getParticipants
{
    //TODO: add to, cc, bcc
    NSMutableArray * participants = [[NSMutableArray alloc] init];
    for (MCOIMAPMessage * message in _messages) {
        NSString * email = [[[message header] from] mailbox];
        NSString * name = [[[message header] from] displayName];
        if (name == nil) {
            name = email;
        }
        NSDictionary * senderDict = @{@"name" : name,
                                      @"email" : email};
        [participants addObject:senderDict];
    }
    return participants;
}

- (NSArray *)getTags
{
    NSMutableDictionary * tags = [[NSMutableDictionary alloc] init];
    for (MCOIMAPMessage * message in _messages) {
        NSArray * currentTags = [message gmailLabels];
        for (NSString * currentTag in currentTags) {
            if ([tags objectForKey:currentTag] == nil) {
                [tags setObject:@"" forKey:[MTTag translateTag:currentTag]];
            }
        }
        if ([message flags] & MCOMessageFlagSeen) {
        } else {
            [tags setObject:@"" forKey:@"unseen"];
            [tags setObject:@"" forKey:@"unread"];
        }
    }
    return [tags allKeys];
}

- (NSString *)getHighestModSeq
{
    uint64_t highestModSeq = 0;
    for (MCOIMAPMessage * message in _messages) {
        highestModSeq = MAX(highestModSeq, [message modSeqValue]);
    }
    return [NSString stringWithFormat:@"%llu", highestModSeq];
}

@end