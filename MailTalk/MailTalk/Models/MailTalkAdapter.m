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
#import "GTMHTTPFetcherService.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "MailCore.h"
#import "INNamespace.h"
#import "INModelResponseSerializer.h"
#import "MTThread.h"
#import "MTMessage.h"

@implementation MailTalkAdapter {
    NSString * _keychainName;
    NSString * _clientID;
    NSString * _clientSecret;
    BOOL _isMCConnected;
    BOOL _isAuthenticated;
    MCOIMAPMessagesRequestKind _requestKind;
//    MCOIMAPSession * _MC2;
    NSObject * _cacheLock;
    NSMutableDictionary * _cache;
    NSMutableDictionary * _messageIDToGmailIDCache;
    void (^_connectionLogger)(void * connectionID, MCOConnectionLogType type, NSData * data);
    dispatch_queue_t _messageQueue;
}

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
    
    _messageQueue = dispatch_queue_create("messageQueue", DISPATCH_QUEUE_SERIAL);
    
    _cacheLock = [[NSObject alloc] init];
    @synchronized(_cacheLock) {
        _cache = [[NSMutableDictionary alloc] init];
        _messageIDToGmailIDCache = [[NSMutableDictionary alloc] init];
    }
    
    _connectionLogger = ^(void * connectionID, MCOConnectionLogType type, NSData * data) {
        NSString * dataStr;
        if (data.length > 200) {
            dataStr = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 100)] encoding:NSUTF8StringEncoding];
            dataStr = [dataStr stringByAppendingString:@"..."];
            dataStr = [dataStr stringByAppendingString:[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(data.length-100, 100)] encoding:NSUTF8StringEncoding]];
        } else {
            dataStr = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, data.length)] encoding:NSUTF8StringEncoding];
        }
//        NSLog(@"[%p:%i]: %@", connectionID, type, dataStr);
    };
    
    _keychainName = @"MTOAuth2Token";
    _clientID = @"44193866924-dsqlj5easb9nl5kvl9i7cgk2846a82a6.apps.googleusercontent.com";
    _clientSecret = @"ehPi3wnIWhjso4WntmYQcSKH";
    _requestKind = MCOIMAPMessagesRequestKindUid |
    MCOIMAPMessagesRequestKindFlags |
    MCOIMAPMessagesRequestKindHeaders |
    MCOIMAPMessagesRequestKindStructure |
    //    MCOIMAPMessagesRequestKindInternalDate |
    MCOIMAPMessagesRequestKindFullHeaders |
    //    MCOIMAPMessagesRequestKindHeaderSubject |
    MCOIMAPMessagesRequestKindGmailLabels |
    MCOIMAPMessagesRequestKindGmailMessageID |
    MCOIMAPMessagesRequestKindGmailThreadID;
    //    MCOIMAPMessagesRequestKindExtraHeaders |
    //    MCOIMAPMessagesRequestKindSize
    
    GTMOAuth2Authentication * auth = [GTMOAuth2ViewControllerTouch authForGoogleFromKeychainForName:_keychainName clientID:_clientID clientSecret:_clientSecret];
    _GTMOAuth = auth;
    
    GTMHTTPFetcherService * fetcherService = [[GTMHTTPFetcherService alloc] init];
    [fetcherService setDelegateQueue:[[NSOperationQueue alloc] init]];
    [auth setFetcherService:fetcherService];
    
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
        [imapSession setConnectionLogger:_connectionLogger];
        _MC = imapSession;
        
//        _MC2 = [[MCOIMAPSession alloc] init];
//        [_MC2 setConnectionType:MCOConnectionTypeTLS];
//        [_MC2 setHostname:@"imap.gmail.com"];
//        [_MC2 setPort:993];
//        [_MC2 setAuthType:MCOAuthTypeXOAuth2];
//        [_MC2 setOAuth2Token:[_GTMOAuth accessToken]];
//        [_MC2 setUsername:[_GTMOAuth userEmail]];
//        [_MC2 setDispatchQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)];
//        [_MC2 setConnectionLogger:^(void * connectionID, MCOConnectionLogType type, NSData * data) {
////            NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
//        }];

        
        if (error != nil) {
            NSLog(@"Unable to retrieve access token. Error: %@", error);
            _isAuthenticated = NO;
            completionBlock(NO, error);
        } else {
            NSLog(@"Retreived access token: %@", [auth accessToken]);
            
            [_MC setOAuth2Token:[auth accessToken]];
            [_MC setUsername:[auth userEmail]];
            
            _isAuthenticated = YES;
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
                                                                                                   [imapSession setConnectionLogger:_connectionLogger];
                                                                                                   [imapSession setOAuth2Token:[auth accessToken]];
                                                                                                   [imapSession setUsername:[auth userEmail]];
                                                                                                   
                                                                                                   _MC = imapSession;
                                                                                                   _GTMOAuth = auth;
                                                                                                   
//                                                                                                   _MC2 = [[MCOIMAPSession alloc] init];
//                                                                                                   [_MC2 setConnectionType:MCOConnectionTypeTLS];
//                                                                                                   [_MC2 setHostname:@"imap.gmail.com"];
//                                                                                                   [_MC2 setPort:993];
//                                                                                                   [_MC2 setAuthType:MCOAuthTypeXOAuth2];
//                                                                                                   [_MC2 setOAuth2Token:[_GTMOAuth accessToken]];
//                                                                                                   [_MC2 setUsername:[_GTMOAuth userEmail]];
//                                                                                                   [_MC2 setDispatchQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)];
//                                                                                                   [_MC2 setConnectionLogger:^(void * connectionID, MCOConnectionLogType type, NSData * data) {
////                                                                                                       NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
//                                                                                                   }];
                                                                                                   
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
    [_cache removeAllObjects];
    [_messageIDToGmailIDCache removeAllObjects];
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
    } else if ([function compare:@"messages"] == NSOrderedSame) {
        [self getMessagesWithNamespace:namespaceID parameters:parameters success:success failure:failure];
    }
}

- (void)cancelAllOperations
{
    [_MC cancelAllOperations];
//    [_MC2 cancelAllOperations];
}

- (void)getThreadsWithNamespace:(NSString *)namespaceID
                     parameters:(id)parameters
                        success:(ResultBlock)success
                        failure:(ErrorBlock)failure
{
    NSLog(@"MT threads: namespace:%@, params:%@", namespaceID, parameters);
    
    NSString * folder = @"[Gmail]/All Mail";
    
//    MCOIndexSet *uids = [MCOIndexSet indexSetWithRange:MCORangeMake(1, UINT64_MAX)];
    NSDate * threeMonthsAgo = [[[NSDate alloc] init] dateByAddingTimeInterval:-90*24*60*60];
    MCOIMAPSearchExpression * expression = [MCOIMAPSearchExpression searchOr:[MCOIMAPSearchExpression searchSinceDate:threeMonthsAgo]
                                                                       other:[MCOIMAPSearchExpression searchSinceReceivedDate:threeMonthsAgo]];
    expression = [MCOIMAPSearchExpression searchSinceDate:threeMonthsAgo];
    MCOIMAPSearchOperation * searchOp = [_MC searchExpressionOperationWithFolder:folder expression:expression];
    [searchOp start:^(NSError *error, MCOIndexSet *searchResult) {
        NSLog(@"Emails within last 90 days: [%d]: %@", searchResult.count, searchResult);
        NSString * countStr = [[NSString alloc] initWithFormat:@"%d", searchResult.count];
        [[NSNotificationCenter defaultCenter] postNotificationName:INThreadsPrefetchNotification object:nil userInfo:@{INThreadsPrefetchCountInfoKey:countStr}];
        MCOIMAPFetchMessagesOperation *fetchOperation = [_MC fetchMessagesOperationWithFolder:folder
                                                                                  requestKind:_requestKind
                                                                                         uids:searchResult];
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
                    
                    @synchronized(_cacheLock) {
                        NSString * gmailThreadID = [[NSString alloc] initWithFormat:@"%llu", [fetchedMessage gmailThreadID]];
                        NSMutableArray * existingMessagesForThread = [_cache objectForKey:gmailThreadID];
                        if (existingMessagesForThread == nil) {
                            existingMessagesForThread = [[NSMutableArray alloc] init];
                            [_cache setObject:existingMessagesForThread forKey:gmailThreadID];
                        }
                        [existingMessagesForThread addObject:fetchedMessage];
                        
                        NSString * gmailMessageID = [[NSString alloc] initWithFormat:@"%llu", [fetchedMessage gmailMessageID]];
                        NSString * messageID = [[fetchedMessage header] messageID];
                        [_messageIDToGmailIDCache setObject:gmailMessageID forKey:messageID];
                    }
                }
                
                NSMutableArray * threadsDictionary = [[NSMutableArray alloc] init];
                NSEnumerator * threadLookupEnumerator = [threadsLookup objectEnumerator];
                id thread;
                
                while (thread = [threadLookupEnumerator nextObject]) {
                    NSDictionary * threadDictionary = [(MTThread *)thread resourceDictionary];
                    [threadsDictionary addObject:threadDictionary];
                }
                
                NSLog(@"MT threads: retrieved: %lu", (unsigned long)threadsDictionary.count);
                
                NSData * json = [NSJSONSerialization dataWithJSONObject:threadsDictionary options:NSJSONWritingPrettyPrinted error:&error];
                
                if (error == nil) {
                    success(json, nil);
                } else {
                    failure(NO, error);
                }
            } else {
                NSLog(@"MT threads: Error downloading threads via MailCore: %@", error);
                failure(NO, error);
            }
        }];
        
    }];
    
//    MCOIMAPFetchMessagesOperation *fetchOperation = [_MC fetchMessagesByNumberOperationWithFolder:folder
//                                                                                      requestKind:_requestKind
//                                                                                          numbers:uids];
    
//    [fetchOperation start:^(NSError * error, NSArray * fetchedMessages, MCOIndexSet * vanishedMessages) {
//        NSAssert(![NSThread isMainThread], @"MT threads: fetch op should not be called on main thread.");
//        
//        if (error == nil) {
//            NSMutableDictionary * threadsLookup = [[NSMutableDictionary alloc] initWithCapacity:[fetchedMessages count]];
//            
//            for (MCOIMAPMessage * fetchedMessage in fetchedMessages) {
//                NSString * gmailThreadID = [[NSString alloc] initWithFormat:@"%llu", [fetchedMessage gmailThreadID]];
//                MTThread * existingThread = (MTThread *)[threadsLookup objectForKey:gmailThreadID];
//                if (existingThread == nil) {
//                    existingThread = [[MTThread alloc] init];
//                    [existingThread setNamespaceID:[_GTMOAuth userEmail]];
//                    [threadsLookup setObject:existingThread forKey:gmailThreadID];
//                }
//                [existingThread addMessage:fetchedMessage];
//            }
//            
//            NSMutableArray * threadsDictionary = [[NSMutableArray alloc] init];
//            NSEnumerator * threadLookupEnumerator = [threadsLookup objectEnumerator];
//            id thread;
//            
//            while (thread = [threadLookupEnumerator nextObject]) {
//                NSDictionary * threadDictionary = [(MTThread *)thread resourceDictionary];
//                [threadsDictionary addObject:threadDictionary];
//            }
//            
//            NSLog(@"MT threads: retrieved: %@", threadsDictionary);
//            
//            NSData * json = [NSJSONSerialization dataWithJSONObject:threadsDictionary options:NSJSONWritingPrettyPrinted error:&error];
//            
//            if (error == nil) {
//                success(json, nil);
//            } else {
//                failure(NO, error);
//            }
//        } else {
//            NSLog(@"MT threads: Error downloading threads via MailCore: %@", error);
//            failure(NO, error);
//        }
//    }];
}

- (void)getMessagesWithNamespace:(NSString *)namespaceID
                      parameters:(id)parameters
                         success:(ResultBlock)success
                         failure:(ErrorBlock)failure
{
    NSLog(@"MT messages: namespace:%@, params:%@", namespaceID, parameters);
    
    NSString * folder = @"[Gmail]/All Mail";
    NSString * threadIDString = (NSString *)[parameters objectForKey:@"thread_id"];
    
    if (threadIDString != nil) {
        __block BOOL found = NO;
        @synchronized(_cacheLock) {
            found = [_cache objectForKey:threadIDString] == nil ? NO : YES;
            NSLog(@"Found %@ in cache: %d", threadIDString, found);
        }
        
        if (found) {
            dispatch_async(_messageQueue, ^{
                __block NSError * error;
                __block NSMutableArray * messagesDictionary = [[NSMutableArray alloc] init];
                @synchronized(_cacheLock) {
                    NSArray * fetchedMessages = [_cache objectForKey:threadIDString];
                    NSLog(@"MT messages [%d]: fetched messsages from cache for [threadId:%@]: %lu", [NSThread isMainThread], threadIDString, (unsigned long)[fetchedMessages count]);
                    for (MCOIMAPMessage * fetchedMessage in fetchedMessages) {
                        MTMessage * message = [[MTMessage alloc] initWithMessage:fetchedMessage];
                        NSString * snippet = @"";
                        [message setNamespaceID:namespaceID];
                        [message setThreadID:threadIDString];
                        NSString * inReplyToMessageID = (NSString *)[[[fetchedMessage header] inReplyTo] firstObject];
                        NSString * inReplyTo = [_messageIDToGmailIDCache objectForKey:inReplyToMessageID];
                        [message setInReplyTo:inReplyTo];
                        [message setSnippet:snippet];
                        //TODO: Set to body for now. Will change in future
                        [message setBody:snippet];
                        [messagesDictionary addObject:[message resourceDictionary]];
                    }
                }
                NSData * json = [NSJSONSerialization dataWithJSONObject:messagesDictionary options:NSJSONWritingPrettyPrinted error:&error];
                
                if (error == nil) {
                    success(json, nil);
                } else {
                    failure(NO, error);
                }
            });
        } else {
            uint64_t threadID = [[[[NSNumberFormatter alloc] init] numberFromString:threadIDString] unsignedLongLongValue];
            MCOIMAPSearchExpression * searchExpression = [MCOIMAPSearchExpression searchGmailThreadID:threadID];
            
            MCOIMAPSearchOperation * searchOp = [_MC searchExpressionOperationWithFolder:folder expression:searchExpression];
            [searchOp start:^(NSError *error, MCOIndexSet *searchResult) {
                if (error == nil) {
                    __block NSMutableArray * messagesDictionary = [[NSMutableArray alloc] init];
                    
                    NSLog(@"MT messages [%d]: search results: %@", [NSThread isMainThread], searchResult);
                    MCOIMAPFetchMessagesOperation * fetchMessagesOp = [_MC fetchMessagesOperationWithFolder:folder requestKind:_requestKind uids:searchResult];
                    [fetchMessagesOp start:^(NSError * error, NSArray * fetchedMessages, MCOIndexSet * vanishedMessages) {
                        if (error == nil) {
                            NSLog(@"MT messages [%d]: fetched messsages: %lu", [NSThread isMainThread], (unsigned long)[fetchedMessages count]);
                            
                            for (MCOIMAPMessage * fetchedMessage in fetchedMessages) {
                                MTMessage * message = [[MTMessage alloc] initWithMessage:fetchedMessage];
                                
                                __block NSString * snippet;
                                snippet = @"";
                                //                        Comment out for now. Figure out how to make faster. Too slow currently
                                //                        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                                //                        MCOIMAPMessageRenderingOperation * plainTextOp = [_MC2 plainTextBodyRenderingOperationWithMessage:fetchedMessage folder:folder stripWhitespace:YES];
                                //                        [plainTextOp start:^(NSString *htmlString, NSError *error) {
                                //                            if (error == nil) {
                                //                                NSLog(@"MT messages: rendered body: %@", htmlString);
                                //                                snippet = htmlString;
                                //                            }
                                //                            dispatch_semaphore_signal(semaphore);
                                //                        }];
                                //
                                //                        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                                [message setNamespaceID:namespaceID];
                                [message setThreadID:threadIDString];
                                [message setSnippet:snippet];
                                //TODO: Set to body for now. Will change in future
                                [message setBody:snippet];
                                [messagesDictionary addObject:[message resourceDictionary]];
                            }
                            
                            NSData * json = [NSJSONSerialization dataWithJSONObject:messagesDictionary options:NSJSONWritingPrettyPrinted error:&error];
                            
                            if (error == nil) {
                                success(json, nil);
                            } else {
                                failure(NO, error);
                            }
                        } else {
                            NSLog(@"MT messages: Error fetching for messages with gmailThreadID: %@", error);
                            failure(NO, error);
                        }
                    }];
                } else {
                    NSLog(@"MT messages: Error searching for messages with gmailThreadID: %@", error);
                    failure(NO, error);
                }
            }];
        }
    }
}
@end