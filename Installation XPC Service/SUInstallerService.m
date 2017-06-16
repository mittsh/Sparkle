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

#import "SUErrors.h"

@interface SUInstallerService ()

@property (nonatomic, strong) dispatch_queue_t serviceQueue;
@property (nonatomic, strong) SUAppcast* appcast;
@property (nonatomic, strong) NSString* downloadedFilePath;
@property (nonatomic, strong) SUUpdateValidator* updateValidator;

@end

@implementation SUInstallerService

@synthesize connection = _connection;
@synthesize serviceQueue = _serviceQueue;
@synthesize appcast = _appcast;
@synthesize downloadedFilePath = _downloadedFilePath;
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

- (void)extractUpdateWithLocalIdentifier:(NSString *)localIdentifier hostBundlePath:(NSString*)hostBundlePath
{
    dispatch_async(self.serviceQueue, ^{
        [self _extractWithLocalIdentifier:localIdentifier hostBundlePath:hostBundlePath];
    });
}

#pragma mark - Extract

- (void)_extractWithLocalIdentifier:(NSString *)localIdentifier hostBundlePath:(NSString*)hostBundlePath
{
    NSString* downloadedUpdatePath = self.downloadedFilePath;
    SUAppcastItem* item = [self.appcast itemWithLocalIdentifier:localIdentifier];
    SUHost* host = [[SUHost alloc] initWithBundle:[NSBundle bundleWithPath:hostBundlePath]];
    if (downloadedUpdatePath == nil || item == nil || hostBundlePath == nil) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract update (update item not found)."}];
        [self.connection.remoteObjectProxy extractUpdateDidFailWithError:error];
        return;
    }

    id<SUUnarchiverProtocol> unarchiver = [SUUnarchiver unarchiverForPath:downloadedUpdatePath updatingHostBundlePath:hostBundlePath decryptionPassword:nil];
    if (unarchiver == nil) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract update (no valid archiver found)."}];
        [self.connection.remoteObjectProxy extractUpdateDidFailWithError:error];
        return;
    }

    // Currently unsafe archives are the only case where we can prevalidate before extraction, but that could change in the future
    BOOL needsPrevalidation = [[unarchiver class] unsafeIfArchiveIsNotValidated];
    self.updateValidator = [[SUUpdateValidator alloc] initWithDownloadPath:downloadedUpdatePath dsaSignature:item.DSASignature host:host performingPrevalidation:needsPrevalidation];
    if (!self.updateValidator.canValidate) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{NSLocalizedDescriptionKey: @"Failed to extract update."}];
        [self.connection.remoteObjectProxy extractUpdateDidFailWithError:error];
        return;
    }

    [unarchiver unarchiveWithCompletionBlock:^(NSError *error){
        dispatch_async(self.serviceQueue, ^{
            if (error != nil) {
                [self.connection.remoteObjectProxy extractUpdateDidFailWithError:error];
                return;
            }
            [self.connection.remoteObjectProxy extractUpdateDidComplete];
        });
    } progressBlock:^(double progress) {
        dispatch_async(self.serviceQueue, ^{
            [self.connection.remoteObjectProxy extractUpdateProgress:progress];
        });
    }];
}

@end
