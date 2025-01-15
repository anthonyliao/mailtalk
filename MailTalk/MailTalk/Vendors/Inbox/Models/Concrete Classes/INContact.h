//
//  INContact.h
//  BigSur
//
//  Created by Ben Gotow on 4/22/14.
//  Copyright (c) 2014 Inbox. All rights reserved.
//

#import "INModelObject.h"

/** The INContact class provides a native wrapper around Inbox contacts
 http://inboxapp.com/docs/api#contacts
*/
@interface INContact : INModelObject

@property (nonatomic, strong) NSString * name;
@property (nonatomic, strong) NSString * email;
@property (nonatomic, strong) NSString * source;
@property (nonatomic, strong) NSString * providerName;
@property (nonatomic, strong) NSString * accountID;
@property (nonatomic, strong) NSString * UID;

@end
