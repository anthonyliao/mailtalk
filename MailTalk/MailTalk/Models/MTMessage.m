//
//  MTMessage.m
//  MailTalk
//
//  Created by anthony on 12/10/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTMessage.h"
#import "MCOIMAPMessage.h"
#import "MCOMessageHeader.h"
#import "MCOAddress.h"
#import "MTTag.h"

@implementation MTMessage {
    MCOIMAPMessage * _message;
}

- (id)initWithMessage:(MCOIMAPMessage *)message
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _message = message;
    _threadID = [NSString stringWithFormat:@"%llu", [message gmailThreadID]];
    
    return self;
}

- (NSDictionary *)resourceDictionary
{
    NSString * gmailID = [NSString stringWithFormat:@"%llu", [_message gmailMessageID]];
    MCOMessageHeader * header = [_message header];
    NSString * messageID = [header messageID];
    NSString * subject = [header subject] == nil ? @"" : [header subject];
    NSArray * from = [self getParticipants:@[[header from]]];
    NSArray * bcc = [self getParticipants:[header bcc]];
    NSArray * cc = [self getParticipants:[header cc]];
    NSArray * to = [self getParticipants:[header to]];
    NSString * date = [self getTimestamp:[header date]];
    NSNumber * unread = ([_message flags] & MCOMessageFlagSeen) ? [NSNumber numberWithBool:NO] : [NSNumber numberWithBool:YES];
    NSArray * fileIds = [[NSArray alloc] init];
    NSArray * files = [[NSArray alloc] init];
    NSObject * inReplyTo = [[header inReplyTo] firstObject] == nil ? [NSNull null] : [[header inReplyTo] firstObject];
    NSNumber * modSeq = [NSNumber numberWithInteger:[_message modSeqValue]];
    NSString * uid = [NSString stringWithFormat:@"%u", [_message uid]];
    NSAssert(subject != nil, @"subject can not be nil");
    NSAssert(modSeq != nil, @"modSeq can not be nil");
    NSDictionary * resourceDict = @{@"id" : gmailID,
                                    @"message_id": messageID,
                                    @"subject" : subject,
                                    @"thread_id" : [self threadID],
                                    @"body" : [self body],
                                    @"last_accessed_at" : [NSNull null],
                                    @"created_at" : [NSNull null],
                                    @"from" : from,
                                    @"snippet" : [self snippet],
                                    @"bcc" : bcc,
                                    @"files" : files,
                                    @"cc" : cc,
                                    @"date" : date,
                                    @"updated_at" : [NSNull null],
                                    @"namespace_id" : [self namespaceID],
                                    @"file_ids" : fileIds,
                                    @"in_reply_to" : inReplyTo,
                                    @"unread" : unread,
                                    @"to" : to,
                                    @"mod_seq": modSeq,
                                    @"uid":uid
                                    };
//    NSLog(@"%@", resourceDict);
    return resourceDict;
}

- (NSArray *)getParticipants:(NSArray *)addresses
{
    NSMutableArray * participants = [[NSMutableArray alloc] init];
    for (MCOAddress * address in addresses) {
        NSString * email = [address mailbox];
        NSString * name = [address displayName];
        if (name == nil) {
            name = email;
        }
        NSDictionary * senderDict = @{@"name" : name,
                                      @"email" : email};
        [participants addObject:senderDict];
    }
    return participants;
}

- (NSString *)getTimestamp:(NSDate *)date
{
    NSString * timestampString = [NSString stringWithFormat:@"%lf", [date timeIntervalSince1970]];
    return timestampString;
}
@end