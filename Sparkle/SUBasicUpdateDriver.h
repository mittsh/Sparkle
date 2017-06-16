//
//  SUBasicUpdateDriver.h
//  Sparkle,
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUBASICUPDATEDRIVER_H
#define SUBASICUPDATEDRIVER_H

#import "SUUpdateDriver.h"

@class SUAppcast, SUAppcastItem, SUHost;
@interface SUBasicUpdateDriver : SUUpdateDriver

@property (strong, readonly) SUAppcastItem *updateItem;
@property (copy, readonly) NSString *downloadPath;

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)host;

- (BOOL)isItemNewer:(SUAppcastItem *)ui;
+ (BOOL)hostSupportsItem:(SUAppcastItem *)ui;
- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui;
- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui;
- (void)appcastDidFinishLoading:(SUAppcast *)ac;
- (void)didFindValidUpdate;
- (void)didNotFindUpdate;

- (void)downloadUpdate;
- (void)didDownloadTotalBytesWritten:(uint64_t)totalBytesWritten totalBytesExpectedToWrite:(uint64_t)totalBytesExpectedToWrite;

- (void)extractUpdate;
- (void)failedToApplyDeltaUpdate;

// Needed to preserve compatibility to subclasses, even though our unarchiver code uses blocks now
- (void)unarchiver:(id)ua extractedProgress:(double)progress;
- (void)unarchiverDidFinish:(id)ua;

- (void)installWithToolAndRelaunch:(BOOL)relaunch;
- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI;
- (void)installerForHost:(SUHost *)host failedWithError:(NSError *)error;

- (void)cleanUpDownload;

- (void)abortUpdate;
- (void)abortUpdateWithError:(NSError *)error;
- (void)terminateApp;

@end

#endif
