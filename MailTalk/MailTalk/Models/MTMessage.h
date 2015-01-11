//
//  MTMessage.h
//  MailTalk
//
//  Created by anthony on 12/10/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MCOIMAPMessage;

@interface MTMessage : NSObject

@property (nonatomic, strong) NSString * namespaceID;
@property (nonatomic, strong) NSString * threadID;
@property (nonatomic, strong) NSString * snippet;
@property (nonatomic, strong) NSString * body;

/**
 Init with this message
 */
- (id)initWithMessage:(MCOIMAPMessage *)message;

/**
 @return An NSDictionary of JSON-compatible key-value pairs.
 */
- (NSMutableDictionary *)resourceDictionary;

@end