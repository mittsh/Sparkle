//
//  SUInstallerService.m
//  Installation XPC Service
//
//  Created by Micha Mazaheri on 6/16/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SUInstallerService.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUAppcastLoader.h"
#import "SUAppcastItemDownloader.h"

#import "SUUnarchiverProtocol.h"
#import "SUUnarchiver.h"
#import "SUUpdateValidator.h"

#import "SUHost.h"
#import "SUFileManager.h"

#import "SUErrors.h"
#import "SULocalizations.h"

@interface SUInstallerService ()

@property (nonatomic, strong) dispatch_queue_t serviceQueue;
@property (nonatomic, strong) SUAppcast* appcast;
@property (nonatomic, strong) NSString* downloadedFilePath;
@property (nonatomic, strong) NSString* hostBundlePath;
@property (nonatomic, strong) SUUpdateValidator* updateValidator;

@end

@implementation SUInstallerService

@synthesize connection = _connection;
@synthesize serviceQueue = _serviceQueue;
@synthesize appcast = _appcast;
@synthesize downloadedFilePath = _downloadedFilePath;
@synthesize hostBundlePath = _hostBundlePath;
@synthesize updateValidator = _updateValidator;

- (instancetype)initWithConnection:(NSXPCConnection *)connection
{
    self = [super init];
    if (self) {
        _connection = connection;
        _serviceQueue = dispatch_queue_create("InstallerServiceQueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Check for Updates

- (void)checkForUpdatesAtURL:(NSURL *)URL options:(NSDictionary<NSString *,id> *)options completionBlock:(SUInstallerServiceCheckForUpdatesBlock)completionBlock
{
    dispatch_async(self.serviceQueue, ^{
        SUAppcastLoader *appcastLoader = [[SUAppcastLoader alloc] init];
        appcastLoader.userAgentString = options[SUInstallerServiceProtocolOptionsUserAgent];
        appcastLoader.httpHeaders = options[SUInstallerServiceProtocolOptionsHTTPHeaders];
        [appcastLoader fetchAppcastFromURL:URL inBackground:((NSNumber*)options[SUInstallerServiceProtocolOptionsDownloadInBackground]).boolValue completionBlock:^(BOOL success, SUAppcast * _Nullable appcast, NSError * _Nullable error) {
            dispatch_async(self.serviceQueue, ^{
                self.appcast = appcast;
                completionBlock(appcast, error);
            });
        }];
    });
}

#pragma mark - Download Update

- (void)downloadUpdateWithLocalIdentifier:(NSString *)localIdentifier options:(nonnull NSDictionary<NSString *,id> *)options
{
    dispatch_async(self.serviceQueue, ^{
        SUAppcastItem* item = [self.appcast itemWithLocalIdentifier:localIdentifier];
        if (item == nil) {
            // @TODO
//            [self.connection.remoteObjectProxy downloadUpdateDidFailWithError:(NSError*_Nonnull)error];
            return;
        }
        SUAppcastItemDownloader* downloader = [[SUAppcastItemDownloader alloc] initWithAppcastItem:item callbackQueue:self.serviceQueue updateBlock:^(NSString * _Nullable downloadedFilePath, uint64_t totalBytesWritten, uint64_t totalBytesExpectedToWrite, NSError * _Nullable error) {
            // completed
            if (downloadedFilePath != nil) {
                self.downloadedFilePath = downloadedFilePath;
                [self.connection.remoteObjectProxy downloadUpdateDidComplete];
            }
            // failed
            else if (error != nil) {
                [self.connection.remoteObjectProxy downloadUpdateDidFailWithError:(NSError*_Nonnull)error];
            }
            // in progress
            else {
                [self.connection.remoteObjectProxy downloadUpdateTotalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];
            }
        }];
        downloader.userAgentString = options[SUInstallerServiceProtocolOptionsUserAgent];
        downloader.httpHeaders = options[SUInstallerServiceProtocolOptionsHTTPHeaders];
        [downloader downloadInBackground:((NSNumber*)options[SUInstallerServiceProtocolOptionsDownloadInBackground]).boolValue];
        
    });
}

#pragma mark - Extract

- (void)extractUpdateWithLocalIdentifier:(NSString *)localIdentifier hostBundlePath:(NSString*)hostBundlePath
{
    dispatch_async(self.serviceQueue, ^{
        [self _extractWithLocalIdentifier:localIdentifier hostBundlePath:hostBundlePath];
    });
}

- (void)_extractWithLocalIdentifier:(NSString *)localIdentifier hostBundlePath:(NSString*)hostBundlePath
{
    SUHost* host = [[SUHost alloc] initWithBundle:[NSBundle bundleWithPath:hostBundlePath]];
    if (hostBundlePath == nil || host == nil) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract update (host bundle not found)."}];
        [self.connection.remoteObjectProxy extractUpdateDidFailWithError:error];
        return;
    }

    NSString* downloadedFilePath = self.downloadedFilePath;
    SUAppcastItem* item = [self.appcast itemWithLocalIdentifier:localIdentifier];
    if (downloadedFilePath == nil || item == nil || hostBundlePath == nil) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract update (update item not found)."}];
        [self.connection.remoteObjectProxy extractUpdateDidFailWithError:error];
        return;
    }

    id<SUUnarchiverProtocol> unarchiver = [SUUnarchiver unarchiverForPath:downloadedFilePath updatingHostBundlePath:hostBundlePath decryptionPassword:nil];
    if (unarchiver == nil) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract update (no valid archiver found)."}];
        [self.connection.remoteObjectProxy extractUpdateDidFailWithError:error];
        return;
    }

    // Currently unsafe archives are the only case where we can prevalidate before extraction, but that could change in the future
    BOOL needsPrevalidation = [[unarchiver class] unsafeIfArchiveIsNotValidated];
    self.updateValidator = [[SUUpdateValidator alloc] initWithDownloadPath:downloadedFilePath dsaSignature:item.DSASignature host:host performingPrevalidation:needsPrevalidation];
    if (!self.updateValidator.canValidate) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract update."}];
        [self.connection.remoteObjectProxy extractUpdateDidFailWithError:error];
        self.updateValidator = nil;
        return;
    }

    // Perform unarchiving
    [unarchiver unarchiveWithCompletionBlock:^(NSError *error){
        dispatch_async(self.serviceQueue, ^{
            if (error != nil) {
                [self.connection.remoteObjectProxy extractUpdateDidFailWithError:error];
                self.updateValidator = nil;
                return;
            }

            // Keep hostBundlePath for later
            self.hostBundlePath = hostBundlePath;

            // Call host app
            [self.connection.remoteObjectProxy extractUpdateDidComplete];
        });
    } progressBlock:^(double progress) {
        dispatch_async(self.serviceQueue, ^{
            [self.connection.remoteObjectProxy extractUpdateProgress:progress];
        });
    }];
}

#pragma mark - Install

- (void)installWithLocalIdentifier:(NSString *)localIdentifier relaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI hostAppPid:(uint64_t)hostAppPid
{
    dispatch_async(self.serviceQueue, ^{
        [self _installWithLocalIdentifier:localIdentifier relaunch:relaunch displayingUserInterface:showUI hostAppPid:hostAppPid];
    });
}

- (void)_installWithLocalIdentifier:(NSString *)localIdentifier relaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI hostAppPid:(uint64_t)hostAppPid
{
    NSString* downloadedFilePath = self.downloadedFilePath;
    NSString* downloadedDirPath = downloadedFilePath.stringByDeletingLastPathComponent;
    SUAppcastItem* item = [self.appcast itemWithLocalIdentifier:localIdentifier];
    if (downloadedFilePath == nil || downloadedDirPath == nil || item == nil) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingUpdateError userInfo:@{NSLocalizedDescriptionKey: @"Failed to install update (update item not found)."}];
        [self.connection.remoteObjectProxy installUpdateDidFailWithError:error];
        return;
    }
    
    NSString* hostBundlePath = self.hostBundlePath;
    if (hostBundlePath == nil) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingUpdateError userInfo:@{NSLocalizedDescriptionKey: @"Failed to install update (host bundle not found)."}];
        [self.connection.remoteObjectProxy installUpdateDidFailWithError:error];
        return;
    }

    // Validate update
    BOOL validationCheckSuccess = [self.updateValidator validateWithUpdateDirectory:downloadedDirPath];
    if (!validationCheckSuccess) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUSignatureError userInfo:@{
			NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil),
			NSLocalizedFailureReasonErrorKey: SULocalizedString(@"The update is improperly signed.", nil),
        }];
        [self.connection.remoteObjectProxy installUpdateDidFailWithError:error];
        return;
    }

    // Ask host app if we can install
    [self.connection.remoteObjectProxy canInstallAndRelaunch:relaunch displayingUserInterface:showUI completionBlock:^(BOOL canInstallAndRelaunch) {
        dispatch_async(self.serviceQueue, ^{
            if (canInstallAndRelaunch) {
                [self _continueInstallWithLocalIdentifier:localIdentifier relaunch:relaunch displayingUserInterface:showUI hostBundlePath:hostBundlePath downloadedDirPath:downloadedDirPath hostAppPid:hostAppPid];
            }
        });
    }];
}

- (void)_continueInstallWithLocalIdentifier:(NSString *)localIdentifier relaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI hostBundlePath:(NSString*)hostBundlePath downloadedDirPath:(NSString*)downloadedDirPath hostAppPid:(uint64_t)hostAppPid
{
    NSError* error = nil;
    NSURL* relaunchToolFileURL = [[self class] _copyRelaunchToolWithHostBundlePath:hostBundlePath destinationDirPath:downloadedDirPath error:&error];
    if (relaunchToolFileURL == nil) {
        [self.connection.remoteObjectProxy installUpdateDidFailWithError:error];
        return;
    }

    // Notify the host app that we're about to relaunch
    [self.connection.remoteObjectProxy willRelaunchApplication];
    
    // Perform relaunch
    if (![[self class] _performRelaunchWithHostBundlePath:hostBundlePath relaunchToolFileURL:relaunchToolFileURL downloadedDirPath:downloadedDirPath relaunch:relaunch displayingUserInterface:showUI hostAppPid:hostAppPid error:&error]) {
        [self.connection.remoteObjectProxy installUpdateDidFailWithError:error];
        return;
    }

    // Ask the host app to terminate
    [self.connection.remoteObjectProxy shouldTerminateApplication];
}

+ (BOOL)_performRelaunchWithHostBundlePath:(NSString*)hostBundlePath relaunchToolFileURL:(NSURL*)relaunchToolFileURL downloadedDirPath:(NSString*)downloadedDirPath relaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI hostAppPid:(uint64_t)hostAppPid error:(NSError*__autoreleasing*)__error
{
    SUHost* host = [[SUHost alloc] initWithBundle:[NSBundle bundleWithPath:hostBundlePath]];
    if (hostBundlePath == nil || host == nil) {
        *__error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey: @"Failed to install update (host bundle not found)."}];
        return NO;
    }

    NSString *relaunchToolPath = [NSBundle bundleWithPath:(NSString* _Nonnull)relaunchToolFileURL.path].executablePath;
    if (relaunchToolPath == nil ||
        ![[NSFileManager defaultManager] fileExistsAtPath:(NSString* _Nonnull)relaunchToolFileURL.path]) {
        // Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
        *__error = [NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), host.name],
            NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@)", relaunchToolFileURL.path],
        }];
        return NO;
    }

    [NSTask launchedTaskWithLaunchPath:relaunchToolPath arguments:@[hostBundlePath,
                                                                    hostBundlePath,
                                                                    [NSString stringWithFormat:@"%llud", hostAppPid],
                                                                    downloadedDirPath,
                                                                    relaunch ? @"1" : @"0",
                                                                    showUI ? @"1" : @"0"]];
    return YES;
}

+ (NSURL*)_copyRelaunchToolWithHostBundlePath:(NSString*)hostBundlePath destinationDirPath:(NSString*)destinationDirPath error:(NSError*__autoreleasing*)__error
{
    // Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
    // Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.

    SUHost* host = [[SUHost alloc] initWithBundle:[NSBundle bundleWithPath:hostBundlePath]];
    if (hostBundlePath == nil || host == nil) {
        *__error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey: @"Failed to install update (host bundle not found)."}];
        return nil;
    }

    // Get XPC service bundle
    NSBundle *xpcServiceBundle = [NSBundle bundleForClass:[SUInstallerService class]];
    if (xpcServiceBundle == nil) {
        *__error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey: @"Failed to install update (cannot find Sparkle bundle)."}];
        return nil;
    }

    // Get relaunch app source path
    NSString *relaunchToolSourcePath = [xpcServiceBundle pathForResource:@SPARKLE_RELAUNCH_TOOL_NAME ofType:@"app"];
    if (relaunchToolSourcePath == nil) {
        *__error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey: @"Failed to install update (relaunch app not found)."}];
        return nil;
    }
    NSURL *relaunchToolSourceFileURL = [NSURL fileURLWithPath:relaunchToolSourcePath];

    // Get host app name
    NSString *hostBundleBaseName = host.bundlePath.lastPathComponent.stringByDeletingPathExtension;
    if (hostBundleBaseName == nil) {
        *__error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey: @"Failed to install update (host app name not found)."}];
        return nil;
    }

    // Get relaunch app target path
    NSString *relaunchCopyBaseName = [NSString stringWithFormat:@"%@ (Autoupdate).app", hostBundleBaseName];
    NSURL *relaunchCopyTargetFileURL = [NSURL fileURLWithPath:[destinationDirPath stringByAppendingPathComponent:relaunchCopyBaseName]];
    if (relaunchCopyTargetFileURL == nil) {
        *__error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey: @"Failed to install update (relaunch app target path not found)."}];
        return nil;
    }

    // We only need to run our copy of the app by spawning a task
    // Since we are copying the app to a directory that is write-accessible, we don't need to muck with owner/group IDs
    NSError* copyError = nil;
    SUFileManager *fileManager = [SUFileManager defaultManager];
    if (![self _preparePathForRelaunchTool:relaunchCopyTargetFileURL.path error:&copyError] ||
        ![fileManager copyItemAtURL:relaunchToolSourceFileURL toURL:relaunchCopyTargetFileURL error:&copyError]) {
        *__error = [NSError errorWithDomain:SUSparkleErrorDomain code:SURelaunchError userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), host.name],
            NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't copy relauncher (%@) to temporary path (%@)! %@",
                                                                         relaunchToolSourceFileURL.path, relaunchCopyTargetFileURL.path, (copyError != nil ? copyError.localizedDescription : @"")],
        }];
        return nil;
    }

    // We probably don't need to release the quarantine, but we'll do it just in case it's necessary.
    // Perhaps in a sandboxed environment this matters more. Note that this may not be a fatal error.
    NSError *quarantineError = nil;
    if (![fileManager releaseItemFromQuarantineAtRootURL:relaunchCopyTargetFileURL error:&quarantineError]) {
        // @TODO log
        NSLog(@"Failed to release quarantine on %@ with error %@", relaunchCopyTargetFileURL.path, quarantineError);
        //            SULog(SULogLevelError, @"Failed to release quarantine on %@ with error %@", relaunchCopyTargetFileURL.path, quarantineError);
    }

    return relaunchCopyTargetFileURL;
}

// Creates intermediate directories up until targetPath if they don't already exist,
// and removes the directory at targetPath if one already exists there
+ (BOOL)_preparePathForRelaunchTool:(NSString *)targetPath error:(NSError * __autoreleasing *)error
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

@end
