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

@interface SUInstallerService ()

@property (nonatomic, strong) dispatch_queue_t serviceQueue;
@property (nonatomic, strong) SUAppcast* appcast;

@end

@implementation SUInstallerService

@synthesize connection = _connection;
@synthesize serviceQueue = _serviceQueue;
@synthesize appcast = _appcast;

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
            
            return;
        }
        SUAppcastItemDownloader* downloader = [[SUAppcastItemDownloader alloc] initWithAppcastItem:item callbackQueue:self.serviceQueue updateBlock:^(NSURL * _Nullable location, uint64_t totalBytesWritten, uint64_t totalBytesExpectedToWrite, NSError * _Nullable error) {
            // completed
            if (location != nil) {
                [self.connection.remoteObjectProxy downloadUpdateDidComplete];
            }
            // failed
            else if (error != nil) {
                [self.connection.remoteObjectProxy downloadUpdateDidFailWithError:error];
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

@end
