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

typedef void(^SUInstallerServiceCheckForUpdatesBlock)(SUAppcast* _Nullable appcast, NSError* _Nullable error);

@protocol SUInstallerServiceProtocol

// @TODO: security around the URL used here
- (void)checkForUpdatesAtURL:(NSURL *)URL options:(NSDictionary<NSString*,id>*)options completionBlock:(SUInstallerServiceCheckForUpdatesBlock)completionBlock;

- (void)downloadUpdateWithLocalIdentifier:(NSString*)localIdentifier options:(NSDictionary<NSString*,id>*)options;

// @TODO: security around host path
- (void)extractUpdateWithLocalIdentifier:(NSString *)localIdentifier hostBundlePath:(NSString*)hostBundlePath;
    
@end

@protocol SUInstallerServiceAppProtocol

- (void)downloadUpdateDidComplete;
- (void)downloadUpdateDidFailWithError:(NSError*)error;
- (void)downloadUpdateTotalBytesWritten:(uint64_t)totalBytesWritten totalBytesExpectedToWrite:(uint64_t)totalBytesExpectedToWrite;

- (void)extractUpdateDidComplete;
- (void)extractUpdateDidFailWithError:(NSError*)error;
- (void)extractUpdateProgress:(double)progress;

@end

NS_ASSUME_NONNULL_END
