//
//  Inbox.h
//  InboxFramework
//
//  Created by Ben Gotow on 5/8/14.
//  Copyright (c) 2014 Inbox. All rights reserved.
//

#import <UIKit/UIKit.h>

#ifndef InboxFramework_Inb_xh_h
#define InboxFramework_Inb_xh_h

//! Project version number for Inbox.
FOUNDATION_EXPORT double InboxVersionNumber;

//! Project version string for Inbox.
FOUNDATION_EXPORT const unsigned char InboxVersionString[];


/** If you're getting errors saying "Header could not be found," select the
 header file in Xcode and make sure it's visibility is "Public" in the framework
 build target.
*/

#import "INAPIManager.h"

#import "MailTalkAdapter.h"
#import "GTMOAuth2Authentication.h"
#import "GTMOAuth2SignIn.h"
#import "GTMHTTPFetcher.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "MailCore.h"

#import "INDatabaseManager.h"
#import "INMessageProvider.h"
#import "INThreadProvider.h"
#import "INThread.h"
#import "INModelObject.h"
#import "INMessage.h"
#import "INContact.h"
#import "INNamespace.h"
#import "INTag.h"
#import "INAPITask.h"
#import "INAddRemoveTagsTask.h"
#import "INSendDraftTask.h"
#import "INUploadFileTask.h"
#import "INSaveDraftTask.h"
#import "INDeleteDraftTask.h"
#import "INSaveTagTask.h"
#import "INSyncEngine.h"
#import "INDeltaSyncEngine.h"
#import "INFile.h"
#import "INDraft.h"
#import "NSError+InboxErrors.h"

/*
#ifdef TARGET_OS_IPHONE
#import "INMessageContentView.h"
#import "INRecipientsLabel.h"
#endif
*/
#endif
