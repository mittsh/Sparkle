
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
#import "SULocalizations.h"
#import "SUErrors.h"
#import "SUAppcast.h"
#import "SUAppcastItem.h"

#import "SUInstallerServiceProtocol.h"

@interface SUBasicUpdateDriver () <SUInstallerServiceAppProtocol>

@property (strong, nonatomic) SUAppcastItem *nonDeltaUpdateItem;
@property (strong, nonatomic) NSXPCConnection *installerServiceConnection;
@property (strong, nonatomic) id installerServiceProxy;
@property (strong, nonatomic, readwrite) SUAppcastItem *updateItem;
@property (strong, nonatomic, readonly) id<SUVersionComparison> versionComparator;

@end

@implementation SUBasicUpdateDriver

@synthesize updateItem;

@synthesize nonDeltaUpdateItem;

@synthesize installerServiceConnection = _installerServiceConnection;
@synthesize installerServiceProxy = _installerServiceProxy;

- (void)dealloc
{
    [self xpcInvalidateConnection];
}

#pragma mark - XPC Connection

- (void)xpcCheckConnection
{
    if (self.installerServiceConnection == nil) {
        [self xpcStartConnection];
    }
}

- (void)xpcStartConnection
{
    __weak SUBasicUpdateDriver* weakSelf = self;
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.Sparkle.install-service"];
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerServiceProtocol)];
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerServiceAppProtocol)];
    connection.exportedObject = self;
    connection.interruptionHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SULog(SULogLevelError, @"XPC Connection Interrupted");
            [weakSelf abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: SULocalizedString(@"Update failed (connection with installation helper was interrupted).", nil) }]];
        });
    };
    self.installerServiceConnection = connection;
    self.installerServiceProxy = [connection remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SULog(SULogLevelError, @"XPC Connection Error: %@", error.localizedDescription);
            [weakSelf abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: SULocalizedString(@"Update failed (connection error with installation helper).", nil) }]];
        });
    }];
    [connection resume];
}

- (void)xpcInvalidateConnection
{
    [self.installerServiceConnection invalidate];
    self.installerServiceConnection = nil;
}

#pragma mark - Load Appcast

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
    [super checkForUpdatesAtURL:URL host:aHost];

    // Test ability to write on the host path
    [self xpcCheckConnection];
    [self.installerServiceProxy checkWriteOnHostBundlePath:aHost.bundlePath completionBlock:^(BOOL canWrite, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (canWrite) {
                [self _performCheckForUpdatesAtURL:URL host:aHost];
            }
            else {
                [self abortUpdateWithError:error];
            }
        });
    }];
}

- (void)_performCheckForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
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

+ (BOOL)hostSupportsItem:(SUAppcastItem *)item
{
    // Check that it's macOS compatible
    if (!item.isMacOsUpdate) {
        return NO;
    }

    NSString *minimumSystemVersion = item.minimumSystemVersion;
    NSString *maximumSystemVersion = item.maximumSystemVersion;

    // If no minimum and maximum system version specified, it's good
	if ((minimumSystemVersion == nil || [minimumSystemVersion isEqualToString:@""]) &&
        (maximumSystemVersion == nil || [maximumSystemVersion isEqualToString:@""])) {
        return YES;
    }

    BOOL minimumVersionOK = YES;
    BOOL maximumVersionOK = YES;

    id<SUVersionComparison> versionComparator = [[SUStandardVersionComparator alloc] init];
    NSString* systemVersionString = [SUOperatingSystem systemVersionString];

    // Check minimum and maximum system version
    if (minimumSystemVersion != nil && ![minimumSystemVersion isEqualToString:@""]) {
        minimumVersionOK = [versionComparator compareVersion:minimumSystemVersion toVersion:systemVersionString] != NSOrderedDescending;
    }
    if (maximumSystemVersion != nil && ![maximumSystemVersion isEqualToString:@""]) {
        maximumVersionOK = [versionComparator compareVersion:maximumSystemVersion toVersion:systemVersionString] != NSOrderedAscending;
    }

    return minimumVersionOK && maximumVersionOK;
}

- (BOOL)isItemNewer:(SUAppcastItem *)item
{
    return [self.versionComparator compareVersion:self.host.version toVersion:item.versionString] == NSOrderedAscending;
}

- (BOOL)itemContainsSkippedVersion:(SUAppcastItem *)item
{
    NSString* skippedVersion = [self.host objectForUserDefaultsKey:SUSkippedVersionKey];
	if (skippedVersion == nil) {
        return NO;
    }
    return [self.versionComparator compareVersion:item.versionString toVersion:skippedVersion] != NSOrderedDescending;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)item
{
    return item != nil && [[self class] hostSupportsItem:item] && [self isItemNewer:item] && ![self itemContainsSkippedVersion:item];
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
        item = [[self class] bestItemFromAppcastItems:appcast.items getDeltaItem:&deltaUpdateItem withHostVersion:self.host.version comparator:self.versionComparator];
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
    id<SUUpdaterDelegate> updaterDelegate = ((id<SUUpdaterPrivate>)updater).delegate;
    
    if ([updaterDelegate respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
        [updaterDelegate updaterDidNotFindUpdate:self.updater];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];

    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain
                                                   code:SUNoUpdateError
                                               userInfo:@{
                                                   NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"You already have the newest version of %@.", "'Error' message when the user checks for updates but is already current or the feed doesn't contain any updates. (not necessarily shown in UI)"), self.host.name]
                                               }]];
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

- (void)cancelDownload
{
    [self.installerServiceProxy cancelDownload];
}

#pragma mark - Extract Update

- (void)extractUpdate
{
    assert(self.updateItem);

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

#pragma mark - Install Update

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
    // Perhaps a poor assumption but: if we're not relaunching, we assume we shouldn't be showing any UI either. Because non-relaunching installations are kicked off without any user interaction, we shouldn't be interrupting them.
    [self installWithToolAndRelaunch:relaunch displayingUserInterface:relaunch];
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    assert(self.updateItem);

    // Start install in XPC service
    [self xpcCheckConnection];
    [self.installerServiceProxy installWithLocalIdentifier:self.updateItem.localIdentifier relaunch:relaunch displayingUserInterface:showUI hostAppPid:(uint64_t)[NSProcessInfo processInfo].processIdentifier];
}

- (BOOL)mayUpdateAndRestart
{
    id<SUUpdaterPrivate> updater = self.updater;
    return (!updater.delegate || ![updater.delegate respondsToSelector:@selector(updaterShouldRelaunchApplication:)] || [updater.delegate updaterShouldRelaunchApplication:self.updater]);
}

- (void)installUpdateDidFailWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self abortUpdateWithError:error];
    });
}

- (void)canInstallAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI completionBlock:(SUInstallerServiceCanInstallAndRelaunchBlock)completionBlock
{
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL canInstallAndRelaunch = [self _canInstallAndRelaunch:relaunch displayingUserInterface:showUI];
        completionBlock(canInstallAndRelaunch);
    });
}

- (void)willRelaunchApplication
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.updateItem != nil) {
            [self _willRelaunchApplication];
        }
    });
}

- (void)shouldTerminateApplication
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.updateItem != nil) {
            [self terminateApp];
        }
    });
}

- (BOOL)_canInstallAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    if (self.updateItem == nil) {
        return NO;
    }

    id<SUUpdaterPrivate> updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = updater.delegate;

    // Make sure we can restart now
    if (![self mayUpdateAndRestart]) {
        [self abortUpdate];
        return NO;
    }

    // Give the host app an opportunity to postpone the install and relaunch.
    static BOOL postponedOnce = NO;
    if (!postponedOnce && [updaterDelegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)]) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:)]];
        [invocation setSelector:@selector(installWithToolAndRelaunch:)];
        [invocation setArgument:&relaunch atIndex:2];
        [invocation setTarget:self];
        postponedOnce = YES;
        if ([updaterDelegate updater:(SUUpdater<SUUpdaterPrivate>*)updater shouldPostponeRelaunchForUpdate:self.updateItem untilInvoking:invocation]) {
            return NO;
        }
    }

    // Call delegate willInstallUpdate:
    if ([updaterDelegate respondsToSelector:@selector(updater:willInstallUpdate:)]) {
        [updaterDelegate updater:(SUUpdater<SUUpdaterPrivate>*)updater willInstallUpdate:self.updateItem];
    }

    return YES;
}

- (void)_willRelaunchApplication
{
    id<SUUpdaterPrivate> updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = updater.delegate;
    // Call delegate updaterWillRelaunchApplication:
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
    if ([updaterDelegate respondsToSelector:@selector(updaterWillRelaunchApplication:)]) {
        [updaterDelegate updaterWillRelaunchApplication:self.updater];
    }
}

// Note: this is overridden by the automatic update driver to not terminate in some cases
- (void)terminateApp
{
    [self xpcInvalidateConnection];
    [NSApp terminate:self];
}

#pragma mark - Abort / Error

- (void)abortUpdate
{
    // Stop XPC connection
    [self xpcInvalidateConnection];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.updateItem = nil;
    [super abortUpdate];
}

- (void)abortUpdateWithError:(NSError *)error
{
    if (error.code != SUNoUpdateError) { // Let's not bother logging this.
        NSError *errorToDisplay = error;
        int finiteRecursion=5;
        do {
            SULog(SULogLevelError, @"Error: %@ %@ (URL %@)", errorToDisplay.localizedDescription, errorToDisplay.localizedFailureReason, [errorToDisplay.userInfo objectForKey:NSURLErrorFailingURLErrorKey]);
            errorToDisplay = [errorToDisplay.userInfo objectForKey:NSUnderlyingErrorKey];
        } while(--finiteRecursion && errorToDisplay);
    }

    // Cancel download (if pending)
    [self cancelDownload];
    
    // Notify host app that update has aborted
    id<SUUpdaterPrivate> updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = updater.delegate;
    if ([updaterDelegate respondsToSelector:@selector(updater:didAbortWithError:)]) {
        [updaterDelegate updater:self.updater didAbortWithError:error];
    }

    [self abortUpdate];
}

@end
