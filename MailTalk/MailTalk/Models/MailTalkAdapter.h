//
//  MailTalkAdapter.h
//  mailtalkdemo
//
//  Created by anthony on 11/24/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void (^ VoidBlock)();
typedef void (^ ViewControllerBlock)(UIViewController *);
typedef void (^ ErrorBlock)(BOOL success, NSError * error);
typedef void (^ ResultBlock)(id result, NSError * error);

@class MCOIMAPSession;
@class GTMOAuth2Authentication;

/**
 Normally, InboxApp classes interface with the Inbox REST API over AFNetworking
 MailTalkAdapter replaces the API by serving as a middleman that interfaces with MailCore
 */
@interface MailTalkAdapter : NSObject {
    NSString * _keychainName;
    NSString * _clientID;
    NSString * _clientSecret;
    BOOL _isMCConnected;
    BOOL _isAuthenticated;
}

@property (nonatomic, strong) MCOIMAPSession * MC;
@property (nonatomic, strong) GTMOAuth2Authentication * GTMOAuth;

- (id)initWithAuthenticationCompleteHandler:(ErrorBlock)completionBlock;

- (void)getNamespacesWithParameters:(id)parameters
                           success:(ResultBlock)success
                           failure:(ErrorBlock)failure;
/** 
 Authenticates user with mail provider via a view controller that displays the mail provider's login screen
 Will pass the view controller to caller's present block, which should contain the logic to present the view controller
 Also, will pass the vivew controller to caller's dismiss block, which should contain the logic to dismiss the view controller
 Upon success or fail authentication, completion block is called
 */
- (void)authenticateWithPresentBlock:(ViewControllerBlock)presentBlock
                     andDismissBlock:(ViewControllerBlock)dismissBlock
                  andCompletionBlock:(ErrorBlock)completionBlock;

- (BOOL)isAuthenticated;

- (void)unauthenticate;

- (void)GET:(NSString *)namespaceID
   function:(NSString *)function
 parameters:(id)parameters
    success:(ResultBlock)success
    failure:(ErrorBlock)failure;

@end