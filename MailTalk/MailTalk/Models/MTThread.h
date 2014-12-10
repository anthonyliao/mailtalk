//
//  MTThread.h
//  mailtalkdemo
//
//  Created by anthony on 11/26/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MCOIMAPMessage;

@interface MTThread : NSObject {
    NSMutableArray * _messages;
}

@property (nonatomic, strong) NSString * namespaceID;

/**
 Get the gmail thread id
 */
- (NSString *)threadID;

/**
 Append this message to the thread
 */
- (void)addMessage:(MCOIMAPMessage *)message;

/**
 @return An NSDictionary of JSON-compatible key-value pairs.
 */
- (NSMutableDictionary *)resourceDictionary;

@end