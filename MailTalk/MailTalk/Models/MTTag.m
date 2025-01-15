//
//  MTTag.m
//  mailtalkdemo
//
//  Created by anthony on 11/26/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MTTag.h"

@implementation MTTag

+ (NSDictionary *)tagsDictionary
{
    static NSDictionary * tagsDict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tagsDict = @{
                     @"\\Inbox" : @"inbox",
                     @"\\Sent" : @"sent",
                     @"\\Starred" : @"starred"
                     };
    });
    return tagsDict;
}

+ (NSString *)translateTag:(NSString *)gmailTag;
{
    NSString * jsonTag = [[self tagsDictionary] objectForKey:gmailTag];
    if (jsonTag != nil) {
        return jsonTag;
    }
    return [[gmailTag lowercaseString] stringByReplacingOccurrencesOfString:@"\\" withString:@""];
}
@end