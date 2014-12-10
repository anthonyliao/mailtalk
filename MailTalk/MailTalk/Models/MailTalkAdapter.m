//
//  MailTalkAdapter.m
//  mailtalkdemo
//
//  Created by anthony on 11/24/14.
//  Copyright (c) 2014 com.anthonyliao. All rights reserved.
//

#import "MailTalkAdapter.h"
#import "GTMOAuth2Authentication.h"
#import "GTMOAuth2SignIn.h"
#import "GTMHTTPFetcher.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "MailCore.h"
#import "INNamespace.h"
#import "INModelResponseSerializer.h"
#import "MTThread.h"

@implementation MailTalkAdapter

- (id)init
{
    NSAssert(false, @"Do not use default init method. Use initWithAuthenticationCompleteHandler: instead");
    return nil;
}

- (id)initWithAuthenticationCompleteHandler:(ErrorBlock)completionBlock
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _isAuthenticated = NO;
    
    _keychainName = @"MTOAuth2Token";
    _clientID = @"44193866924-dsqlj5easb9nl5kvl9i7cgk2846a82a6.apps.googleusercontent.com";
    _clientSecret = @"ehPi3wnIWhjso4WntmYQcSKH";
    
    GTMOAuth2Authentication * auth = [GTMOAuth2ViewControllerTouch authForGoogleFromKeychainForName:_keychainName clientID:_clientID clientSecret:_clientSecret];
    _GTMOAuth = auth;
    
    [auth authorizeRequest:nil completionHandler:^(NSError *error) {
        NSLog(@"Authorize completionHandler on main thread - %d", [NSThread isMainThread]);
        MCOIMAPSession * imapSession = [[MCOIMAPSession alloc] init];
        [imapSession setConnectionType:MCOConnectionTypeTLS];
        [imapSession setHostname:@"imap.gmail.com"];
        [imapSession setPort:993];
        [imapSession setAuthType:MCOAuthTypeXOAuth2];
        [imapSession setOAuth2Token:@""];
        [imapSession setUsername:@""];
        //Move callbacks to a background thread, so they won't interfere with main thread - can cause deadlock issues
        //Also allows us to use semaphores to make asynchronous calls feel synchronous
        [imapSession setDispatchQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)];
        [imapSession setConnectionLogger:^(void * connectionID, MCOConnectionLogType type, NSData * data) {
            NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        }];
        _MC = imapSession;
        
        if (error != nil) {
            NSLog(@"Unable to retrieve access token. Error: %@", error);
            _isAuthenticated = NO;
            completionBlock(NO, error);
        } else {
            NSLog(@"Retreived access token: %@", [auth accessToken]);
            _isAuthenticated = YES;
            
            [_MC setOAuth2Token:[auth accessToken]];
            [_MC setUsername:[auth userEmail]];
            completionBlock(YES, error);
        }
    }];
    
    return self;
}

- (void)authenticateWithPresentBlock:(ViewControllerBlock)presentBlock
                     andDismissBlock:(ViewControllerBlock)dismissBlock
                  andCompletionBlock:(ErrorBlock)completionBlock
{
    GTMOAuth2ViewControllerTouch * oauthViewController = [[GTMOAuth2ViewControllerTouch alloc] initWithScope:@"https://mail.google.com"
                                                                                                    clientID:_clientID
                                                                                                clientSecret:_clientSecret
                                                                                            keychainItemName:_keychainName
                                                                                           completionHandler:^(GTMOAuth2ViewControllerTouch *viewController, GTMOAuth2Authentication *auth, NSError *error) {
                                                                                               if (error != nil) {
                                                                                                   NSLog(@"GTMOAuth2ViewControllerTouch authentication failed. Error: %@", error);
                                                                                                   _isAuthenticated = NO;
                                                                                                   completionBlock(NO, error);
                                                                                               } else {
                                                                                                   NSLog(@"GTMOAuth2ViewControllerTouch authentication succeed with auth %@", auth);
                                                                                                   _isAuthenticated = YES;
                                                                                                   MCOIMAPSession * imapSession = [[MCOIMAPSession alloc] init];
                                                                                                   [imapSession setConnectionType:MCOConnectionTypeTLS];
                                                                                                   [imapSession setHostname:@"imap.gmail.com"];
                                                                                                   [imapSession setPort:993];
                                                                                                   [imapSession setAuthType:MCOAuthTypeXOAuth2];
                                                                                                   [imapSession setDispatchQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)];
                                                                                                   
                                                                                                   [imapSession setOAuth2Token:[auth accessToken]];
                                                                                                   [imapSession setUsername:[auth userEmail]];
                                                                                                   
                                                                                                   _MC = imapSession;
                                                                                                   _GTMOAuth = auth;
                                                                                                   
                                                                                                   completionBlock(YES, nil);
                                                                                               }}];
    
    GTMOAuth2ViewControllerTouch * __weak weak_oauthViewController = oauthViewController;
    
    oauthViewController.popViewBlock = ^ {
        dismissBlock(weak_oauthViewController);
    };
    
    presentBlock(weak_oauthViewController);
}

- (BOOL)isAuthenticated
{
    return _isAuthenticated;
}

- (void)getNamespacesWithParameters:(id)parameters
                            success:(ResultBlock)success
                            failure:(ErrorBlock)failure
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        if (_isAuthenticated) {
            NSMutableArray * namespaces = [[NSMutableArray alloc] init];
            NSDictionary * namespace = @{@"status" : [NSNull null],
                                         @"provider" : @"gmail",
                                         @"id" : [_GTMOAuth userEmail],
                                         @"scope" : [NSNull null],
                                         @"created_at" : [NSNull null],
                                         @"last_sync" : [NSNull null],
                                         @"namespace_id" : [_GTMOAuth userEmail],
                                         @"updated_at" : [NSNull null],
                                         @"last_accessed_at" : [NSString stringWithFormat:@"%lf", [[NSDate date] timeIntervalSince1970]],
                                         @"email_address" : [_GTMOAuth userEmail]
                                         };
            [namespaces addObject:namespace];
            NSLog(@"MT namespaces: %@", namespaces);
            NSError * error = nil;
            NSData * json = [NSJSONSerialization dataWithJSONObject:namespaces options:NSJSONWritingPrettyPrinted error:&error];
            
            if (error != nil) {
                failure(NO, error);
            } else {
                success(json, nil);
            }
        } else {
            failure(NO, [NSError errorWithDomain:@"MailTalk" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"MT namespaces: Unable to fetch namespaces, not authenticated"}]);
        }
    });
}

- (void)unauthenticate
{
    _isAuthenticated = NO;
    [GTMOAuth2ViewControllerTouch removeAuthFromKeychainForName:_keychainName];
    [GTMOAuth2ViewControllerTouch revokeTokenForGoogleAuthentication:_GTMOAuth];
}

- (void)GET:(NSString *)namespaceID
   function:(NSString *)function
 parameters:(id)parameters
    success:(ResultBlock)success
    failure:(ErrorBlock)failure
{
    NSLog(@"MT GET: %@, function: %@, params: %@", namespaceID, function, parameters);
    
    if ([function compare:@"threads"] == NSOrderedSame) {
        [self getThreadsWithNamespace:namespaceID parameters:parameters success:success failure:failure];
    }
}

- (void)getThreadsWithNamespace:(NSString *)namespaceID
                     parameters:(id)parameters
                        success:(ResultBlock)success
                        failure:(ErrorBlock)failure
{
    NSLog(@"MT threads: namespace:%@, params:%@", namespaceID, parameters);
    
    MCOIMAPMessagesRequestKind requestKind = MCOIMAPMessagesRequestKindGmailMessageID |
    MCOIMAPMessagesRequestKindFullHeaders |
    MCOIMAPMessagesRequestKindGmailLabels |
    MCOIMAPMessagesRequestKindGmailMessageID |
    MCOIMAPMessagesRequestKindGmailThreadID;
    
    NSString * folder = @"[Gmail]/All Mail";
    
    MCOIndexSet *uids = [MCOIndexSet indexSetWithRange:MCORangeMake(1, UINT64_MAX)];
    
    MCOIMAPFetchMessagesOperation *fetchOperation = [_MC fetchMessagesByNumberOperationWithFolder:folder
                                                                                      requestKind:requestKind
                                                                                          numbers:uids];
    
    [fetchOperation start:^(NSError * error, NSArray * fetchedMessages, MCOIndexSet * vanishedMessages) {
        NSAssert(![NSThread isMainThread], @"MT threads: fetch op should not be called on main thread.");
        
        if (error == nil) {
            NSMutableDictionary * threadsLookup = [[NSMutableDictionary alloc] initWithCapacity:[fetchedMessages count]];
            
            for (MCOIMAPMessage * fetchedMessage in fetchedMessages) {
                NSString * gmailThreadID = [[NSString alloc] initWithFormat:@"%llu", [fetchedMessage gmailThreadID]];
                MTThread * existingThread = (MTThread *)[threadsLookup objectForKey:gmailThreadID];
                if (existingThread == nil) {
                    existingThread = [[MTThread alloc] init];
                    [existingThread setNamespaceID:[_GTMOAuth userEmail]];
                    [threadsLookup setObject:existingThread forKey:gmailThreadID];
                }
                [existingThread addMessage:fetchedMessage];
            }
            
            NSMutableArray * threadsDictionary = [[NSMutableArray alloc] init];
            NSEnumerator * threadLookupEnumerator = [threadsLookup objectEnumerator];
            id thread;
            
            while (thread = [threadLookupEnumerator nextObject]) {
                NSDictionary * threadDictionary = [(MTThread *)thread resourceDictionary];
                [threadsDictionary addObject:threadDictionary];
            }
            
            NSLog(@"MT threads: retrieved: %@", threadsDictionary);
            
            NSData * json = [NSJSONSerialization dataWithJSONObject:threadsDictionary options:NSJSONWritingPrettyPrinted error:&error];
            
            if (error == nil) {
                success(json, nil);
            } else {
                failure(NO, error);
            }
        } else {
            NSLog(@"MT threads: Error downloading messages via MailCore: %@", error);
            failure(NO, error);
        }
    }];
}

@end