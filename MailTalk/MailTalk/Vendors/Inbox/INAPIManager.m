//
//  INAPIManager.m
//  BigSur
//
//  Created by Ben Gotow on 4/24/14.
//  Copyright (c) 2014 Inbox. All rights reserved.
//

#import "INAPIManager.h"
#import "INAPITask.h"
#import "INSyncEngine.h"
#import "INNamespace.h"
#import "INModelResponseSerializer.h"
#import "FMResultSet+INModelQueries.h"
#import "NSError+InboxErrors.h"
#import "AFNetworkActivityIndicatorManager.h"
#import "MailTalkAdapter.h"
#import "INModelObject+Uniquing.h"

#define OPERATIONS_FILE [@"~/Documents/operations.plist" stringByExpandingTildeInPath]


__attribute__((constructor))
static void initialize_INAPIManager() {
    [INAPIManager shared];
}

@implementation INAPIManager

+ (INAPIManager *)shared
{
	static INAPIManager * sharedManager = nil;
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		sharedManager = [[INAPIManager alloc] init];
	});
	return sharedManager;
}

- (id)init
{
//	NSDictionary * info = [[NSBundle mainBundle] infoDictionary];
//	NSString * api = info[INAPIPathInfoDictionaryKey];
//
//    NSAssert(api, @"Please add INAPIPath to your Info.plist. If you're using your local development environment, you probably want the value 'http://localhost:5555/'");
//    if (!api) {
//        api = @"https://api.inboxapp.com/";
//	}

    self = [super init];
	if (self) {
        
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        _MT = [[MailTalkAdapter alloc] initWithAuthenticationCompleteHandler:^(BOOL success, NSError *error) {
            dispatch_semaphore_signal(semaphore);
            if (success) {
                [self fetchNamespaces:NULL];
            }
        }];
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
//        _AF = [[AFHTTPRequestOperationManager alloc] initWithBaseURL: [NSURL URLWithString: api]];
//        
//        [[_AF operationQueue] setMaxConcurrentOperationCount: 5];
//		[_AF setResponseSerializer:[AFJSONResponseSerializer serializerWithReadingOptions:NSJSONReadingAllowFragments]];
//		[_AF setRequestSerializer:[AFJSONRequestSerializer serializerWithWritingOptions:NSJSONWritingPrettyPrinted]];
//
//        AFSecurityPolicy * policy = [AFSecurityPolicy defaultPolicy];
//        [policy setAllowInvalidCertificates: YES];
//        [_AF setSecurityPolicy: policy];
//        [_AF.requestSerializer setCachePolicy: NSURLRequestReloadRevalidatingCacheData];
//    
//        [[AFNetworkActivityIndicatorManager sharedManager] setEnabled:YES];
//
//		// Register for changes to application state
//		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAppBroughtToForeground) name:UIApplicationDidBecomeActiveNotification object:nil];
//
//		// Start listening for reachability changes
//        typeof(self) __weak __self = self;
//		_AF.reachabilityManager = [AFNetworkReachabilityManager managerForDomain: [_AF.baseURL host]];
//		[_AF.reachabilityManager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
//			BOOL hasConnection = (status == AFNetworkReachabilityStatusReachableViaWiFi) || (status == AFNetworkReachabilityStatusReachableViaWWAN);
//			BOOL hasSuspended = __self.taskQueueSuspended;
//            
//			if (hasConnection && hasSuspended)
//				[__self setTaskQueueSuspended: NO];
//			else if (!hasConnection && !hasSuspended)
//				[__self setTaskQueueSuspended: YES];
//		}];
//		[_AF.reachabilityManager startMonitoring];
//
//
//		// Make sure the application has an Inbox App ID in it's info.plist
//		_appID = [info objectForKey: INAppIDInfoDictionaryKey];
//
//		// TODO: Assertion disabled because clients are using their own local instances
//		// NSAssert(_appID, @"Your application's Info.plist should include, INAppID, your Inbox App ID. If you don't have an app ID, grab one from developer.inboxapp.com");
//
//		// Reload our API token and refresh the namespaces list
//        NSString * token = [[PDKeychainBindings sharedKeychainBindings] objectForKey:INKeychainAPITokenKey];
//		NSLog(@"DEBUG: Auth token is %@", token);
//
//		[_AF.requestSerializer setAuthorizationHeaderFieldWithUsername:token password:nil];
//        if (token) {
//            [self fetchNamespaces: NULL];
//        }
		
		// Restart paused tasks (sending mail, etc.)
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadTasks];
        });
    }
	return self;
}

- (void)loadTasks
{
    _taskQueue = [NSMutableArray array];
	@try {
		[_taskQueue addObjectsFromArray: [NSKeyedUnarchiver unarchiveObjectWithFile:OPERATIONS_FILE]];
	}
	@catch (NSException *exception) {
		NSLog(@"Unable to unserialize tasks: %@", [exception description]);
		[[NSFileManager defaultManager] removeItemAtPath:OPERATIONS_FILE error:NULL];
	}
    
    NSArray * toStart = [_taskQueue copy];
	for (INAPITask * task in toStart)
        [self tryStartTask: task];
	
    [[NSNotificationCenter defaultCenter] postNotificationName:INTaskQueueChangedNotification object:nil];
    [self describeTasks];
}

- (void)saveTasks
{
	if (![NSKeyedArchiver archiveRootObject:_taskQueue toFile:OPERATIONS_FILE])
		NSLog(@"Writing pending changes to disk failed? Path may be invalid.");
}

- (NSArray*)taskQueue
{
    return [_taskQueue copy];
}

- (void)setTaskQueueSuspended:(BOOL)suspended
{
    NSLog(@"Change processing is %@.", (suspended ? @"off" : @"on"));

    _taskQueueSuspended = suspended;
    [[NSNotificationCenter defaultCenter] postNotificationName:INTaskQueueChangedNotification object:nil];

	if (!suspended) {
        for (INAPITask * change in _taskQueue)
            [self tryStartTask: change];
    }
}

- (BOOL)queueTask:(INAPITask *)change
{
    NSAssert([NSThread isMainThread], @"Sorry, INAPIManager's change queue is not threadsafe. Please call this method on the main thread.");
    
    for (NSInteger ii = [_taskQueue count] - 1; ii >= 0; ii -- ) {
        INAPITask * a = [_taskQueue objectAtIndex: ii];

        // Can the change we're currently queuing obviate the need for A? If it
        // can, there's no need to make the API call for A.
        // Example: DeleteDraft cancels pending SaveDraft or SendDraft
        if (![a inProgress] && [change canCancelPendingTask: a]) {
            NSLog(@"%@ CANCELLING CHANGE %@", NSStringFromClass([change class]), NSStringFromClass([a class]));
            [a setState: INAPITaskStateCancelled];
            [_taskQueue removeObjectAtIndex: ii];
        }
        
        // Can the change we're currently queueing happen after A? We can't cancel
        // A since it's already started.
        // Example: DeleteDraft can't be queued if SendDraft has started.
        if ([a inProgress] && ![change canStartAfterTask: a]) {
            NSLog(@"%@ CANNOT BE QUEUED AFTER %@", NSStringFromClass([change class]), NSStringFromClass([a class]));
            return NO;
        }
    }

    // Local effects always take effect immediately
    [change applyLocally];

    // Queue the task, and try to start it after a short delay. The delay is purely for
    // asthethic purposes. Things almost always look better when they appear to take a
    // short amount of time, and lots of animations look like shit when they happen too
    // fast. This ensures that, for example, the "draft synced" passive reload doesn't
    // happen while the "draft saved!" animation is still playing, which results in the
    // animation being disrupted. Unless there's really a good reason to make developers
    // worry about stuff like that themselves, let's keep this here.
    [_taskQueue addObject: change];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self tryStartTask: change];
    });

    [[NSNotificationCenter defaultCenter] postNotificationName:INTaskQueueChangedNotification object:nil];
    [self describeTasks];
    [self saveTasks];

    return YES;
}

- (void)describeTasks
{
	NSMutableString * description = [NSMutableString string];
	[description appendFormat:@"\r---------- Tasks (%lu) Suspended: %d -----------", (unsigned long)_taskQueue.count, _taskQueueSuspended];

	for (INAPITask * change in _taskQueue) {
		[description appendFormat:@"\r%@", [change extendedDescription]];
	}
    [description appendFormat:@"\r-------- ------ ------ ------ ------ ---------"];

	NSLog(@"%@", description);
}

- (void)retryTasks
{
    for (INAPITask * task in _taskQueue) {
        if ([task state] == INAPITaskStateServerUnreachable)
            [task setState: INAPITaskStateWaiting];
        [self tryStartTask: task];
    }
}

- (BOOL)tryStartTask:(INAPITask *)change
{
    if ([change state] != INAPITaskStateWaiting)
        return NO;
    
    if (_changesInProgress > 5)
        return NO;
    
    if (_taskQueueSuspended)
        return NO;
    
    if ([[change dependenciesIn: _taskQueue] count] > 0)
        return NO;

    _changesInProgress += 1;
    [change applyRemotelyWithCallback: ^(INAPITask * change, BOOL finished) {
        _changesInProgress -= 1;
        
        if (finished) {
            [_taskQueue removeObject: change];
            for (INAPITask * change in _taskQueue)
                if ([self tryStartTask: change])
                    break;
        }

        [[NSNotificationCenter defaultCenter] postNotificationName:INTaskQueueChangedNotification object:nil];
        [self describeTasks];
        [self saveTasks];
    }];
    return YES;
}

#pragma Convenience Serializers

- (AFHTTPResponseSerializer*)responseSerializerForClass:(Class)klass
{
    return [[INModelResponseSerializer alloc] initWithModelClass: klass];
}


#pragma Authentication

- (BOOL)isAuthenticated
{
    BOOL isAuthenticated = [_MT isAuthenticated];
//    NSLog(@"INAPIManager is authenticated %d", isAuthenticated);
    return isAuthenticated;
//    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
//    __block BOOL authenticated = YES;
//    NSLog(@"isAuthenticated on main thread %d", [NSThread isMainThread]);
//    
//    MCOIMAPOperation * op;
//    
//    //checkAccountOperation crashes if session already connected. If connected, just want to make sure the server is responding
//    //or the user has a working internet connection. https://github.com/MailCore/mailcore2/issues/577
//    if (_isMCConnected) {
//        op = [_MC noopOperation];
//    } else {
//        op = [_MC checkAccountOperation];
//    }
//    
//    [op start:^(NSError *error) {
//        NSLog(@"Is on main thread %d", [NSThread isMainThread]);
//        if (error != nil) {
//            NSLog(@"Is not authenticated. MC Error: %@", error);
//            authenticated = NO;
//        } else {
//            authenticated = YES;
//        }
//        dispatch_semaphore_signal(semaphore);
//    }];
//    
//    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
//    return authenticated;
}

- (void)cancelAllOperations
{
    [_MT cancelAllOperations];
}

//- (void)authenticateWithCompletionBlock:(ErrorBlock)completionBlock;
//{
//    [self authenticateWithEmail:nil andCompletionBlock:completionBlock];
//}

- (void)authenticateWithPresentBlock:(ViewControllerBlock)presentBlock andDismissBlock:(ViewControllerBlock)dismissBlock andCompletionBlock:(ErrorBlock)completionBlock
{
    if (_authenticationCompletionBlock && (_authenticationCompletionBlock != completionBlock))
        NSLog(@"A call to authenticateWithEmail: is replacing an authentication completion block that has not yet been fired. The old authentication block will never be called!");
    _authenticationCompletionBlock = completionBlock;

    [_MT authenticateWithPresentBlock:presentBlock andDismissBlock:dismissBlock andCompletionBlock:^(BOOL success, NSError *error) {
        if (error != nil) {
            [self handleAuthenticationCompleted:NO withError:error];
        } else {
            [self fetchNamespaces:^(BOOL success, NSError *error) {
                if (success) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:INAuthenticationChangedNotification object:nil];
                }
                [self handleAuthenticationCompleted:success withError:error];
            }];
        }
    }];
    
//    if (address == nil)
//        address = @"";
//    
//    GTMOAuth2ViewControllerTouch * oauthViewController = [[GTMOAuth2ViewControllerTouch alloc] initWithScope:@"https://mail.google.com" clientID:_clientID clientSecret:_clientSecret keychainItemName:_keychainName completionHandler:^(GTMOAuth2ViewControllerTouch *viewController, GTMOAuth2Authentication *auth, NSError *error) {
//        if (error != nil) {
//            NSLog(@"GTMOAuth2ViewControllerTouch authentication failed. Error: %@", error);
//            [self handleAuthenticationCompleted: NO withError: error];
//        } else {
//            NSLog(@"GTMOAuth2ViewControllerTouch authentication succeed with auth %@", auth);
//            MCOIMAPSession * imapSession = [[MCOIMAPSession alloc] init];
//            [imapSession setConnectionType:MCOConnectionTypeTLS];
//            [imapSession setHostname:@"imap.gmail.com"];
//            [imapSession setPort:993];
//            [imapSession setAuthType:MCOAuthTypeXOAuth2];
//            [imapSession setOAuth2Token:@""];
//            [imapSession setUsername:@""];
//            [imapSession setDispatchQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)];
//            
//            [imapSession setOAuth2Token:[auth accessToken]];
//            [imapSession setUsername:[auth userEmail]];
//            
//            _MC = imapSession;
//            _GTMOAuth = auth;
//            
//            [self fetchNamespaces:^(BOOL success, NSError * error) {
//                if (success) {
//                    [[NSNotificationCenter defaultCenter] postNotificationName:INAuthenticationChangedNotification object:nil];
//                }
//                [self handleAuthenticationCompleted: success withError: error];
//            }];
//        }}];
//    GTMOAuth2ViewControllerTouch * __weak weak_oauthViewController = oauthViewController;
//    oauthViewController.popViewBlock = ^ {
//        [viewController dismissViewControllerAnimated:weak_oauthViewController completion:NULL];
//    };
//    [viewController presentViewController:oauthViewController animated:true completion:NULL];
}

//- (void)authenticateWithEmail:(NSString*)address andCompletionBlock:(ErrorBlock)completionBlock;
//{
//	if (_authenticationCompletionBlock && (_authenticationCompletionBlock != completionBlock))
//		NSLog(@"A call to authenticateWithEmail: is replacing an authentication completion block that has not yet been fired. The old authentication block will never be called!");
//	_authenticationCompletionBlock = completionBlock;
//	
//	// make sure the application is registered for it's application url scheme
//	BOOL found = NO;
//	_appURLScheme = [[NSString stringWithFormat:@"in-%@", _appID] lowercaseString];
//	for (NSDictionary * urlType in [[NSBundle mainBundle] infoDictionary][@"CFBundleURLTypes"]) {
//		for (NSString * scheme in urlType[@"CFBundleURLSchemes"]) {
//			if ([[scheme lowercaseString] isEqualToString: _appURLScheme])
//				found = YES;
//		}
//	}
//	NSAssert(found, @"Your application's Info.plist should register your app for the '%@' URL scheme to handle Inbox authentication correctly.", _appURLScheme);
//
//	// make sure we can reach the server before we try to open the auth page in safari
//	if ([[_AF reachabilityManager] networkReachabilityStatus] == AFNetworkReachabilityStatusNotReachable) {
//		NSError * err = [NSError inboxErrorWithDescription: @"Sorry, you need to be connected to the internet to connect your account."];
//		[self handleAuthenticationCompleted: NO withError: err];
//		return;
//	}
//	
//	// try to visit the auth URL in Safari
//    if (address == nil)
//        address = @"";
//    NSString * uri = [NSString stringWithFormat: @"%@://app/auth-response", _appURLScheme];
//	NSString * authPage = [NSString stringWithFormat: @"https://www.inboxapp.com/oauth/authorize?client_id=%@&response_type=token&login_hint=%@&redirect_uri=%@", _appID, address, uri];
//
//    dispatch_async(dispatch_get_main_queue(), ^{
//        if ([[UIApplication sharedApplication] openURL: [NSURL URLWithString:authPage]]) {
//            _authenticationWaitingForInboundURL = YES;
//
//        } else {
//            NSError * err = [NSError inboxErrorWithDescription: @"Sorry, we weren't able to switch to Safari to open the authentication URL."];
//            [self handleAuthenticationCompleted: NO withError: err];
//        }
//    });
//}

//- (void)authenticateWithAuthToken:(NSString*)authToken andCompletionBlock:(ErrorBlock)completionBlock
//{
//TODO: REMOVE, not needed since we're using OAuth2 authentication through GTM's view controllers
//	if (_authenticationCompletionBlock && (_authenticationCompletionBlock != completionBlock))
//		NSLog(@"A call to authenticateWithAuthToken: is replacing an authentication completion block that has not yet been fired. The old authentication block will never be called!");
//	_authenticationCompletionBlock = completionBlock;
//	
//	NSLog(@"DEBUG: Auth token is %@", authToken);
//	
//	[[_AF requestSerializer] setAuthorizationHeaderFieldWithUsername:authToken password:@""];
//    [self fetchNamespaces:^(BOOL success, NSError * error) {
//        if (success) {
//            [[PDKeychainBindings sharedKeychainBindings] setObject:authToken forKey:INKeychainAPITokenKey accessibleAttribute:kSecAttrAccessibleAfterFirstUnlock];
//            [[NSNotificationCenter defaultCenter] postNotificationName:INAuthenticationChangedNotification object:nil];
//		} else {
//            [[_AF requestSerializer] clearAuthorizationHeader];
//        }
//
//		[self handleAuthenticationCompleted: success withError: error];
//    }];
//}


- (void)unauthenticate
{
	[_taskQueue removeAllObjects];
    [_syncEngine resetSyncState];
//    [[PDKeychainBindings sharedKeychainBindings] removeObjectForKey: INKeychainAPITokenKey];
//    [[_AF requestSerializer] clearAuthorizationHeader];
    [_MT unauthenticate];
    [[INDatabaseManager shared] resetDatabase];
    [[INModelObject class] resetAllInstances];
    _namespaces = nil;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:INTaskQueueChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:INNamespacesChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:INAuthenticationChangedNotification object:nil];
}

//- (BOOL)handleURL:(NSURL*)url
//{
//	if (![[[url scheme] lowercaseString] isEqualToString: _appURLScheme])
//		return NO;
//		
//	if ([[url path] isEqualToString: @"/auth-response"]) {
//		_authenticationWaitingForInboundURL = NO;
//
//		NSMutableDictionary * responseComponents = [NSMutableDictionary dictionary];
//		for (NSString * arg in [[url query] componentsSeparatedByString:@"&"]) {
//			NSArray * kv = [arg componentsSeparatedByString: @"="];
//			if ([kv count] < 2) continue;
//			[responseComponents setObject:kv[1] forKey:kv[0]];
//		}
//
//		if (responseComponents[@"access_token"]) {
//			// we got an auth token! Continue authentication with this token
//			[self authenticateWithAuthToken:responseComponents[@"access_token"] andCompletionBlock: _authenticationCompletionBlock];
//			
//		} else if (responseComponents[@"code"]) {
//			// we got a code that we need to exchange for an auth token. We can't do this locally
//			// because the client secret should never be in the application. Just report an error
//			NSError * err = [NSError inboxErrorWithDescription: @"Inbox received an auth code instead of an auth token and can't exchange the code for a valid token."];
//			[self handleAuthenticationCompleted: NO withError: err];
//		}
//	}
//
//	return YES;
//}

//- (void)handleAppBroughtToForeground
//{
//	// If the app is brought to the foreground after being backgrounded during an authentication
//	// request, and we _don't_ receive a call to handleURL: after 0.5 seconds, we should assume
//	// that they're trying to get out of the auth process and end it.
//	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//		if (_authenticationWaitingForInboundURL) {
//			[self handleAuthenticationCompleted: NO withError:nil];
//		}
//	});
//}

- (void)handleAuthenticationCompleted:(BOOL)success withError:(NSError*)error
{
//	_authenticationWaitingForInboundURL = NO;
	
	if (_authenticationCompletionBlock) {
		_authenticationCompletionBlock(success, error);
		_authenticationCompletionBlock = nil;
		
	} else {
		if (error) {
			[[[UIAlertView alloc] initWithTitle:@"Login Error" message:[error localizedDescription] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles: nil] show];
		}
	}
}

- (void)fetchNamespaces:(ErrorBlock)completionBlock
{
    NSLog(@"Fetching Namespaces (/n/)");    
    [_MT getNamespacesWithParameters:nil
                             success:^(id json, NSError *error) {
                                 INModelResponseSerializer * serializer = [[INModelResponseSerializer alloc] initWithModelClass: [INNamespace class]];
                                 id namespaces = [serializer responseObjectForResponse:nil data:json error:&error];
                                 
                                 if (!error) {
                                     NSLog(@"INAPIManager deserialized namespaces - %lu", (unsigned long)[namespaces count]);
                                     // broadcast a notification about this change
                                     _namespaces = namespaces;
                                     
                                     [[NSNotificationCenter defaultCenter] postNotificationName:INNamespacesChangedNotification object:nil];
                                     
                                     if ([(NSArray *)namespaces count] == 0) {
                                         if (completionBlock)
                                             completionBlock(NO, [NSError inboxErrorWithDescription: @"The token was valid, but returned no namespaces."]);
                                     } else {
                                         if (completionBlock)
                                             completionBlock(YES, nil);
                                     }
                                 } else {
                                     completionBlock(NO, error);
                                 }
                             }
                             failure:^(BOOL success, NSError *error) {
                                 if (completionBlock) {
                                     completionBlock(NO, error);
                                 }
                             }];
}

- (NSArray*)namespaces
{
	if (!_namespaces) {
        [[INDatabaseManager shared] selectModelsOfClassSync:[INNamespace class] withQuery:@"SELECT * FROM INNamespace" andParameters:nil andCallback:^(NSArray *objects) {
            _namespaces = objects;
        }];
    }
    
    if ([_namespaces count] == 0)
        return nil;
    
	return _namespaces;
}

- (NSArray*)namespaceEmailAddresses
{
    return [[self namespaces] valueForKey:@"emailAddress"];
}

@end
