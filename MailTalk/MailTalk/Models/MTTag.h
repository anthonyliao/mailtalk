//
//  MTTag.h
//  mailtalkdemo
//
//  Created by anthony on 11/26/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MTTag : NSObject

+ (NSDictionary *)tagsDictionary;

+ (NSString *)translateTag:(NSString *)gmailTag;

@end
