
//
//  SUBasicUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/23/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUBasicUpdateDriver.h"

#import "SUHost.h"
#import "SUOperatingSystem.h"
#import "SUStandardVersionComparator.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUBinaryDeltaCommon.h"
#import "SUUpdaterPrivate.h"
#import "SUUpdaterDelegate.h"
#import "SUFileManager.h"
#import "SUUpdateValidator.h"
#import "SULocalizations.h"
#import "SUErrors.h"
#import "SUAppcast.h"
#import "SUAppcastItem.h"

#import "SUInstallerServiceProtocol.h"

@interface SUBasicUpdateDriver () <SUInstallerServiceAppProtocol>

@property (strong) SUAppcastItem *updateItem;
@property (copy) NSString *downloadPath;

@property (strong) SUAppcastItem *nonDeltaUpdateItem;
@property (copy) NSString *tempDir;
@property (copy) NSString *relaunchPath;

@property (nonatomic) SUUpdateValidator *updateValidator;

@property (strong) NSXPCConnection *installerServiceConnection;
@property (strong) id installerServiceProxy;

@end

@implementation SUBasicUpdateDriver

@synthesize updateItem;
@synthesize downloadPath;

@synthesize nonDeltaUpdateItem;
@synthesize tempDir;
@synthesize relaunchPath;

@synthesize updateValidator = _updateValidator;

@synthesize installerServiceConnection = _installerServiceConnection;
@synthesize installerServiceProxy = _installerServiceProxy;

- (void)xpcCheckConnection
{
    if (self.installerServiceConnection == nil) {
        [self xpcStartConnection];
    }
}

- (void)xpcStartConnection
{
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithServiceName:@"com.andymatuschak.Sparkle.install-service"];
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerServiceProtocol)];
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerServiceAppProtocol)];
    connection.exportedObject = self;
    self.installerServiceConnection = connection;
    self.installerServiceProxy = [connection remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull error) {
        NSLog(@"XPC Connection Error: %@", error);
    }];
    [connection resume];
}

- (void)xpcInvalidateConnection
{
    // @TODO: we must call this
    [self.installerServiceConnection invalidate];
    self.installerServiceConnection = nil;
}

#pragma mark - Load Appcast

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
    [super checkForUpdatesAtURL:URL host:aHost];
	if (aHost.runningOnReadOnlyVolume)
	{
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated, because it was opened from a read-only or a temporary location. Use Finder to copy %1$@ to the Applications folder, relaunch it from there, and try again.", nil), [aHost name]] }]];
        return;
    }

    id<SUUpdaterPrivate> updater = self.updater;
    NSString* userAgentString = updater.userAgentString;
    NSDictionary* httpHeaders = updater.httpHeaders;
    NSMutableDictionary<NSString*,id>* options = [@{} mutableCopy];
    options[SUInstallerServiceProtocolOptionsDownloadInBackground] = @(self.downloadsAppcastInBackground);
    if (userAgentString != nil) {
        options[SUInstallerServiceProtocolOptionsUserAgent] = userAgentString;
    }
    if (httpHeaders != nil) {
        options[SUInstallerServiceProtocolOptionsHTTPHeaders] = httpHeaders;
    }

    [self xpcCheckConnection];
    [self.installerServiceProxy checkForUpdatesAtURL:URL options:[options copy] completionBlock:^(SUAppcast * appcast, NSError * error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (appcast != nil) {
                [self appcastDidFinishLoading:appcast];
            } else {
                [self abortUpdateWithError:error];
            }
        });
    }];
}

- (id<SUVersionComparison>)versionComparator
{
    id<SUVersionComparison> comparator = nil;
    SUUpdater<SUUpdaterPrivate>* updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = ((id<SUUpdaterPrivate>)updater).delegate;
    
    // Give the delegate a chance to provide a custom version comparator
    if ([updaterDelegate respondsToSelector:@selector(versionComparatorForUpdater:)]) {
        comparator = [updaterDelegate versionComparatorForUpdater:updater];
    }

    // If we don't get a comparator from the delegate, use the default comparator
    if (comparator == nil) {
        comparator = [[SUStandardVersionComparator alloc] init];
    }

    return comparator;
}

+ (SUAppcastItem *)bestItemFromAppcastItems:(NSArray<SUAppcastItem*>*)appcastItems getDeltaItem:(SUAppcastItem * __autoreleasing *)__deltaItem withHostVersion:(NSString *)hostVersion comparator:(id<SUVersionComparison>)comparator
{
    SUAppcastItem *item = nil;
    for(SUAppcastItem *candidate in appcastItems) {
        if ([self hostSupportsItem:candidate]) {
            if (item == nil || [comparator compareVersion:item.versionString toVersion:candidate.versionString] == NSOrderedAscending) {
                item = candidate;
            }
        }
    }
    
    if (item != nil && __deltaItem != NULL) {
        SUAppcastItem *deltaUpdateItem = [item.deltaUpdates objectForKey:hostVersion];
        if (deltaUpdateItem != nil && [self hostSupportsItem:deltaUpdateItem]) {
            *__deltaItem = deltaUpdateItem;
        }
    }
    
    return item;
}

+ (BOOL)hostSupportsItem:(SUAppcastItem *)ui
{
    BOOL osOK = [ui isMacOsUpdate];
	if (([ui minimumSystemVersion] == nil || [[ui minimumSystemVersion] isEqualToString:@""]) &&
        ([ui maximumSystemVersion] == nil || [[ui maximumSystemVersion] isEqualToString:@""])) {
        return osOK;
    }

    BOOL minimumVersionOK = TRUE;
    BOOL maximumVersionOK = TRUE;

    id<SUVersionComparison> versionComparator = [[SUStandardVersionComparator alloc] init];

    // Check minimum and maximum System Version
    if ([ui minimumSystemVersion] != nil && ![[ui minimumSystemVersion] isEqualToString:@""]) {
        minimumVersionOK = [versionComparator compareVersion:[ui minimumSystemVersion] toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedDescending;
    }
    if ([ui maximumSystemVersion] != nil && ![[ui maximumSystemVersion] isEqualToString:@""]) {
        maximumVersionOK = [versionComparator compareVersion:[ui maximumSystemVersion] toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedAscending;
    }

    return minimumVersionOK && maximumVersionOK && osOK;
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui
{
    return [[self versionComparator] compareVersion:[self.host version] toVersion:[ui versionString]] == NSOrderedAscending;
}

- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)ui
{
    NSString *skippedVersion = [self.host objectForUserDefaultsKey:SUSkippedVersionKey];
	if (skippedVersion == nil) { return NO; }
    return [[self versionComparator] compareVersion:[ui versionString] toVersion:skippedVersion] != NSOrderedDescending;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
    return ui && [[self class] hostSupportsItem:ui] && [self isItemNewer:ui] && ![self itemContainsSkippedVersion:ui];
}

- (void)appcastDidFinishLoading:(SUAppcast *)appcast
{
    SUUpdater<SUUpdaterPrivate>* updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = ((id<SUUpdaterPrivate>)updater).delegate;
    if ([updaterDelegate respondsToSelector:@selector(updater:didFinishLoadingAppcast:)]) {
        [updaterDelegate updater:self.updater didFinishLoadingAppcast:appcast];
    }

    NSDictionary *userInfo = @{ SUUpdaterAppcastNotificationKey: appcast };
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:self.updater userInfo:userInfo];

    SUAppcastItem *item = nil;

    // Now we have to find the best valid update in the appcast.
    // Does the delegate want to handle it?
    if ([updaterDelegate respondsToSelector:@selector(bestValidUpdateInAppcast:forUpdater:)]) {
        item = [updaterDelegate bestValidUpdateInAppcast:appcast forUpdater:self.updater];
        if (item != nil && item.isDeltaUpdate) {
            self.nonDeltaUpdateItem = [updaterDelegate bestValidUpdateInAppcast:[appcast copyWithoutDeltaUpdates] forUpdater:self.updater];
        }
    }

    // Find the best supported update ourselves
    if (item == nil) {
        SUAppcastItem *deltaUpdateItem = nil;
        item = [[self class] bestItemFromAppcastItems:appcast.items getDeltaItem:&deltaUpdateItem withHostVersion:self.host.version comparator:[self versionComparator]];
        if (item != nil && deltaUpdateItem != nil) {
            self.nonDeltaUpdateItem = item;
            item = deltaUpdateItem;
        }
    }

    if ([self itemContainsValidUpdate:item]) {
        self.updateItem = item;
        [self didFindValidUpdate];
    } else {
        self.updateItem = nil;
        [self didNotFindUpdate];
    }
}

- (void)didFindValidUpdate
{
    assert(self.updateItem);
    
    SUUpdater<SUUpdaterPrivate>* updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = ((id<SUUpdaterPrivate>)updater).delegate;

    if ([updaterDelegate respondsToSelector:@selector(updater:didFindValidUpdate:)]) {
        [updaterDelegate updater:self.updater didFindValidUpdate:self.updateItem];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification object:updater userInfo:@{ SUUpdaterAppcastItemNotificationKey: self.updateItem }];
    [self downloadUpdate];
}

- (void)didNotFindUpdate
{
    id<SUUpdaterPrivate> updater = self.updater;
    
    if ([[updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
        [[updater delegate] updaterDidNotFindUpdate:self.updater];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];

    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain
                                                   code:SUNoUpdateError
                                               userInfo:@{
                                                   NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"You already have the newest version of %@.", "'Error' message when the user checks for updates but is already current or the feed doesn't contain any updates. (not necessarily shown in UI)"), self.host.name]
                                               }]];
}

- (NSString *)appCachePath
{
    // @TODO remove
    NSArray *cachePaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachePath = nil;
    if ([cachePaths count]) {
        cachePath = [cachePaths objectAtIndex:0];
    }
    if (!cachePath) {
        SULog(SULogLevelError, @"Failed to find user's cache directory! Using system default");
        cachePath = NSTemporaryDirectory();
    }
    
    NSString *name = [self.host.bundle bundleIdentifier];
    if (!name) {
        name = [self.host name];
    }
    
    cachePath = [cachePath stringByAppendingPathComponent:name];
    cachePath = [cachePath stringByAppendingPathComponent:@SPARKLE_BUNDLE_IDENTIFIER];
    return cachePath;
}

#pragma mark - Download Update

- (void)downloadUpdate
{
    // Call delegate
    id<SUUpdaterPrivate> updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = updater.delegate;
    if ([updaterDelegate respondsToSelector:@selector(updater:willDownloadUpdate:)]) {
        [updaterDelegate updater:self.updater willDownloadUpdate:self.updateItem];
    }

    // Create options
    NSString* userAgentString = updater.userAgentString;
    NSDictionary* httpHeaders = updater.httpHeaders;
    NSMutableDictionary<NSString*,id>* options = [@{} mutableCopy];
    options[SUInstallerServiceProtocolOptionsDownloadInBackground] = @(self.downloadsAppcastInBackground);
    if (userAgentString != nil) {
        options[SUInstallerServiceProtocolOptionsUserAgent] = userAgentString;
    }
    if (httpHeaders != nil) {
        options[SUInstallerServiceProtocolOptionsHTTPHeaders] = httpHeaders;
    }

    // Start download in XPC service
    [self xpcCheckConnection];
    [self.installerServiceProxy downloadUpdateWithLocalIdentifier:self.updateItem.localIdentifier options:[options copy]];
}

- (void)downloadUpdateDidComplete
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self extractUpdate];
    });
}

- (void)downloadUpdateDidFailWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self downloadDidFailWithError:error];
    });
}

- (void)downloadUpdateTotalBytesWritten:(uint64_t)totalBytesWritten totalBytesExpectedToWrite:(uint64_t)totalBytesExpectedToWrite
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self didDownloadTotalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    });
}

- (void)didDownloadTotalBytesWritten:(uint64_t)totalBytesWritten totalBytesExpectedToWrite:(uint64_t)totalBytesExpectedToWrite
{
    // nothing to do (to be overridden)
}

- (void)downloadDidFailWithError:(NSError *)error
{
    NSURL *failingUrl = [error.userInfo objectForKey:NSURLErrorFailingURLErrorKey];
    if (failingUrl == nil) {
        failingUrl = self.updateItem.fileURL;
    }

    // Call delegate
    id<SUUpdaterPrivate> updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = updater.delegate;
    if ([updaterDelegate respondsToSelector:@selector(updater:failedToDownloadUpdate:error:)]) {
        [updaterDelegate updater:(SUUpdater*)updater failedToDownloadUpdate:self.updateItem error:error];
    }

    // Abort update with error
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
        NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil),
        NSUnderlyingErrorKey: error,
    }];
    if (failingUrl != nil) {
        [userInfo setObject:failingUrl forKey:NSURLErrorFailingURLErrorKey];
    }
    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:[userInfo copy]]];
}

#pragma mark - Extract Update

- (void)extractUpdate
{
    // Start extract in XPC service
    [self xpcCheckConnection];
    [self.installerServiceProxy extractUpdateWithLocalIdentifier:self.updateItem.localIdentifier hostBundlePath:self.host.bundlePath];
}

- (void)extractUpdateProgress:(double)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self unarchiver:nil extractedProgress:progress];
    });
}

- (void)extractUpdateDidComplete
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self unarchiverDidFinish:nil];
    });
}

- (void)extractUpdateDidFailWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.updateValidator = nil;
        if (self.updateItem.isDeltaUpdate) {
            [self failedToApplyDeltaUpdate];
            return;
        }
        [self abortUpdateWithError:error];
    });
}

- (void)failedToApplyDeltaUpdate
{
    // When a delta update fails to apply we fall back on updating via a full install.
    self.updateItem = self.nonDeltaUpdateItem;
    self.nonDeltaUpdateItem = nil;

    [self downloadUpdate];
}

// By default does nothing, can be overridden
- (void)unarchiver:(id)__unused ua extractedProgress:(double)__unused progress
{
}

// Note this method can be overridden (and is)
- (void)unarchiverDidFinish:(id)__unused ua
{
    assert(self.updateItem);
    
    [self installWithToolAndRelaunch:YES];
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
    // Perhaps a poor assumption but: if we're not relaunching, we assume we shouldn't be showing any UI either. Because non-relaunching installations are kicked off without any user interaction, we shouldn't be interrupting them.
    [self installWithToolAndRelaunch:relaunch displayingUserInterface:relaunch];
}

// Creates intermediate directories up until targetPath if they don't already exist,
// and removes the directory at targetPath if one already exists there
- (BOOL)preparePathForRelaunchTool:(NSString *)targetPath error:(NSError * __autoreleasing *)error
{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    if ([fileManager fileExistsAtPath:targetPath]) {
        NSError *removeError = nil;
        if (![fileManager removeItemAtPath:targetPath error:&removeError]) {
            if (error != NULL) {
                *error = removeError;
            }
            return NO;
        }
    } else {
        NSError *createDirectoryError = nil;
        if (![fileManager createDirectoryAtPath:[targetPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{} error:&createDirectoryError]) {
            if (error != NULL) {
                *error = createDirectoryError;
            }
            return NO;
        }
    }
    return YES;
}

- (BOOL)mayUpdateAndRestart
{
    id<SUUpdaterPrivate> updater = self.updater;
    return (!updater.delegate || ![updater.delegate respondsToSelector:@selector(updaterShouldRelaunchApplication:)] || [updater.delegate updaterShouldRelaunchApplication:self.updater]);
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    assert(self.updateItem);
    assert(self.updateValidator);
    
    BOOL validationCheckSuccess = [self.updateValidator validateWithUpdateDirectory:self.tempDir];
    if (!validationCheckSuccess) {
        NSDictionary *userInfo = @{
                                   NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil),
                                   NSLocalizedFailureReasonErrorKey: SULocalizedString(@"The update is improperly signed.", nil),
                                   };
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUSignatureError userInfo:userInfo]];
        return;
    }

    if (![self mayUpdateAndRestart])
    {
        [self abortUpdate];
        return;
    }

    // Give the host app an opportunity to postpone the install and relaunch.
    id<SUUpdaterPrivate> updater = self.updater;
    static BOOL postponedOnce = NO;
    id<SUUpdaterDelegate> updaterDelegate = [updater delegate];
    if (!postponedOnce && [updaterDelegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)])
    {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:)]];
        [invocation setSelector:@selector(installWithToolAndRelaunch:)];
        [invocation setArgument:&relaunch atIndex:2];
        [invocation setTarget:self];
        postponedOnce = YES;
        if ([updaterDelegate updater:self.updater shouldPostponeRelaunchForUpdate:self.updateItem untilInvoking:invocation]) {
            return;
        }
    }


    if ([updaterDelegate respondsToSelector:@selector(updater:willInstallUpdate:)]) {
        [updaterDelegate updater:self.updater willInstallUpdate:self.updateItem];
    }

    NSBundle *sparkleBundle = updater.sparkleBundle;
    if (!sparkleBundle) {
        SULog(SULogLevelError, @"Sparkle bundle is gone?");
        return;
    }

    // Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
    // Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
    NSString *const relaunchToolSourceName = @"" SPARKLE_RELAUNCH_TOOL_NAME;
    NSString *const relaunchToolSourcePath = [sparkleBundle pathForResource:relaunchToolSourceName ofType:@"app"];
    NSString *relaunchCopyTargetPath = nil;
    NSError *error = nil;
    BOOL copiedRelaunchPath = NO;

    if (!relaunchToolSourceName || ![relaunchToolSourceName length]) {
        SULog(SULogLevelError, @"SPARKLE_RELAUNCH_TOOL_NAME not configued");
    }

    if (!relaunchToolSourcePath) {
        SULog(SULogLevelError, @"Sparkle.framework is damaged. %@ is missing", relaunchToolSourceName);
    }

    if (relaunchToolSourcePath) {
        NSString *hostBundleBaseName = [[self.host.bundlePath lastPathComponent] stringByDeletingPathExtension];
        if (!hostBundleBaseName) {
            SULog(SULogLevelError, @"Unable to get bundlePath");
            hostBundleBaseName = @"Sparkle";
        }
        NSString *relaunchCopyBaseName = [NSString stringWithFormat:@"%@ (Autoupdate).app", hostBundleBaseName];

        relaunchCopyTargetPath = [[self appCachePath] stringByAppendingPathComponent:relaunchCopyBaseName];

        SUFileManager *fileManager = [SUFileManager defaultManager];

        NSURL *relaunchToolSourceURL = [NSURL fileURLWithPath:relaunchToolSourcePath];
        NSURL *relaunchCopyTargetURL = [NSURL fileURLWithPath:relaunchCopyTargetPath];

        // We only need to run our copy of the app by spawning a task
        // Since we are copying the app to a directory that is write-accessible, we don't need to muck with owner/group IDs
        if ([self preparePathForRelaunchTool:relaunchCopyTargetPath error:&error] && [fileManager copyItemAtURL:relaunchToolSourceURL toURL:relaunchCopyTargetURL error:&error]) {
            copiedRelaunchPath = YES;

            // We probably don't need to release the quarantine, but we'll do it just in case it's necessary.
            // Perhaps in a sandboxed environment this matters more. Note that this may not be a fatal error.
            NSError *quarantineError = nil;
            if (![fileManager releaseItemFromQuarantineAtRootURL:relaunchCopyTargetURL error:&quarantineError]) {
                SULog(SULogLevelError, @"Failed to release quarantine on %@ with error %@", relaunchCopyTargetPath, quarantineError);
            }
        }
    }

    if (!copiedRelaunchPath) {
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [self.host name]],
            NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't copy relauncher (%@) to temporary path (%@)! %@",
                                                                         relaunchToolSourcePath, relaunchCopyTargetPath, (error ? [error localizedDescription] : @"")],
        }]];
        return;
    }

    self.relaunchPath = relaunchCopyTargetPath; // Set for backwards compatibility, in case any delegates modify it
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
    if ([updaterDelegate respondsToSelector:@selector(updaterWillRelaunchApplication:)])
        [updaterDelegate updaterWillRelaunchApplication:self.updater];

    NSString *relaunchToolPath = [[NSBundle bundleWithPath:self.relaunchPath] executablePath];
    if (!relaunchToolPath || ![[NSFileManager defaultManager] fileExistsAtPath:self.relaunchPath]) {
        // Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
        [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [self.host name]],
            NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@ and %@)", relaunchToolSourcePath, self.relaunchPath],
        }]];
        return;
    }

    NSString *pathToRelaunch = [self.host bundlePath];
    if ([updaterDelegate respondsToSelector:@selector(pathToRelaunchForUpdater:)]) {
        NSString *delegateRelaunchPath = [updaterDelegate pathToRelaunchForUpdater:self.updater];
        if (delegateRelaunchPath != nil) {
            pathToRelaunch = delegateRelaunchPath;
        }
    }
    
    [NSTask launchedTaskWithLaunchPath:relaunchToolPath arguments:@[[self.host bundlePath],
                                                                    pathToRelaunch,
                                                                    [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]],
                                                                    self.tempDir,
                                                                    relaunch ? @"1" : @"0",
                                                                    showUI ? @"1" : @"0"]];
    [self terminateApp];
}

// Note: this is overridden by the automatic update driver to not terminate in some cases
- (void)terminateApp
{
    [NSApp terminate:self];
}

- (void)cleanUpDownload
{
    if (self.tempDir != nil) // tempDir contains downloadPath, so we implicitly delete both here.
    {
        BOOL success = NO;
        NSError *error = nil;
        success = [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:&error]; // Clean up the copied relauncher
        if (!success)
            [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[self.tempDir stringByDeletingLastPathComponent] destination:@"" files:@[[self.tempDir lastPathComponent]] tag:NULL];
    }
}

- (void)installerForHost:(SUHost *)aHost failedWithError:(NSError *)error
{
    if (aHost != self.host) {
        return;
    }
    NSError *dontThrow = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.relaunchPath error:&dontThrow]; // Clean up the copied relauncher
    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{
        NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while installing the update. Please try again later.", nil),
        NSLocalizedFailureReasonErrorKey: [error localizedDescription],
        NSUnderlyingErrorKey: error,
    }]];
}

- (void)abortUpdate
{
    [self cleanUpDownload];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.updateItem = nil;
    [super abortUpdate];
}

- (void)abortUpdateWithError:(NSError *)error
{
    if ([error code] != SUNoUpdateError) { // Let's not bother logging this.
        NSError *errorToDisplay = error;
        int finiteRecursion=5;
        do {
            SULog(SULogLevelError, @"Error: %@ %@ (URL %@)", errorToDisplay.localizedDescription, errorToDisplay.localizedFailureReason, [errorToDisplay.userInfo objectForKey:NSURLErrorFailingURLErrorKey]);
            errorToDisplay = [errorToDisplay.userInfo objectForKey:NSUnderlyingErrorKey];
        } while(--finiteRecursion && errorToDisplay);
    }
// @TODO cancel
//    if (self.download) {
//        [self.download cancel];
//    }

    // Notify host app that update has aborted
    id<SUUpdaterPrivate> updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = [updater delegate];
    if ([updaterDelegate respondsToSelector:@selector(updater:didAbortWithError:)]) {
        [updaterDelegate updater:self.updater didAbortWithError:error];
    }

    [self abortUpdate];
}

@end
