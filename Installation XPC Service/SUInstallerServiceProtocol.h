//
//  SUInstallerServiceProtocol.h
//  Installation XPC Service
//
//  Created by Micha Mazaheri on 6/16/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#define SUInstallerServiceProtocolOptionsUserAgent @"UserAgent"
#define SUInstallerServiceProtocolOptionsHTTPHeaders @"HTTPHeaders"
#define SUInstallerServiceProtocolOptionsDownloadInBackground @"DownloadInBackground"

@class SUAppcast;

NS_ASSUME_NONNULL_BEGIN

typedef void(^SUInstallerServiceCheckWriteOnHostBundleBlock)(BOOL canWrite, NSError* _Nullable error);
typedef void(^SUInstallerServiceCheckForUpdatesBlock)(SUAppcast* _Nullable appcast, NSError* _Nullable error);
typedef void(^SUInstallerServiceCanInstallAndRelaunchBlock)(BOOL canInstallAndRelaunch);

@protocol SUInstallerServiceProtocol

- (void)checkWriteOnHostBundlePath:(NSString*)hostBundlePath completionBlock:(SUInstallerServiceCheckWriteOnHostBundleBlock)completionBlock;

// @TODO: security around the URL used here
- (void)checkForUpdatesAtURL:(NSURL *)URL options:(NSDictionary<NSString*,id>*)options completionBlock:(SUInstallerServiceCheckForUpdatesBlock)completionBlock;

- (void)downloadUpdateWithLocalIdentifier:(NSString*)localIdentifier options:(NSDictionary<NSString*,id>*)options;
- (void)cancelDownload;

// @TODO: security around host path
- (void)extractUpdateWithLocalIdentifier:(NSString *)localIdentifier hostBundlePath:(NSString*)hostBundlePath;

- (void)installWithLocalIdentifier:(NSString *)localIdentifier relaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI hostAppPid:(uint64_t)hostAppPid;
    
@end

@protocol SUInstallerServiceAppProtocol

- (void)downloadUpdateDidComplete;
- (void)downloadUpdateDidFailWithError:(NSError*)error;
- (void)downloadUpdateTotalBytesWritten:(uint64_t)totalBytesWritten totalBytesExpectedToWrite:(uint64_t)totalBytesExpectedToWrite;

- (void)extractUpdateDidComplete;
- (void)extractUpdateDidFailWithError:(NSError*)error;
- (void)extractUpdateProgress:(double)progress;

- (void)canInstallAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI completionBlock:(SUInstallerServiceCanInstallAndRelaunchBlock)completionBlock;
- (void)willRelaunchApplication;
- (void)shouldTerminateApplication;
- (void)installUpdateDidFailWithError:(NSError*)error;

@end

NS_ASSUME_NONNULL_END
