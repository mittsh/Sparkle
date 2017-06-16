//
//  SUAppcastItemDownloader.m
//  Sparkle
//
//  Created by Micha Mazaheri on 6/16/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SUAppcastItemDownloader.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SULog.h"
#import "SULocalizations.h"
#import "SUErrors.h"

#include "AppKitPrevention.h"

@interface SUAppcastItemDownloader () <NSURLSessionDownloadDelegate>

@property (nonatomic, strong, readwrite) SUAppcastItem* appcastItem;
@property (nonatomic, strong) NSURLSession* session;
@property (nonatomic, strong) SUAppcastItemDownloaderUpdateBlock updateBlock;
@property (nonatomic, strong) dispatch_queue_t callbackQueue;

@end

@implementation SUAppcastItemDownloader

@synthesize appcastItem = _appcastItem;
@synthesize userAgentString = _userAgentString;
@synthesize httpHeaders = _httpHeaders;
@synthesize session = _session;
@synthesize updateBlock = _updateBlock;
@synthesize callbackQueue = _callbackQueue;

- (instancetype)initWithAppcastItem:(SUAppcastItem*)appcastItem callbackQueue:(nonnull dispatch_queue_t)callbackQueue updateBlock:(nonnull SUAppcastItemDownloaderUpdateBlock)updateBlock
{
    self = [super init];
    if (self) {
        _appcastItem = appcastItem;
        _callbackQueue = callbackQueue;
        _updateBlock = updateBlock;
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (NSURLRequest*)downloadRequestInBackground:(BOOL)background
{
    NSString *userAgentString = self.userAgentString;
    NSDictionary<NSString *, NSString *> *httpHeaders = self.httpHeaders;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.appcastItem.fileURL];
    if (background) {
        request.networkServiceType = NSURLNetworkServiceTypeBackground;
    }
    if (userAgentString != nil) {
        [request setValue:userAgentString forHTTPHeaderField:@"User-Agent"];
    }
    if (httpHeaders != nil) {
        [httpHeaders enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull value, BOOL * _Nonnull stop) {
            [request setValue:value forHTTPHeaderField:key];
        }];
    }
    return [request copy];
}

- (void)downloadInBackground:(BOOL)background
{
    NSURLRequest *request = [self downloadRequestInBackground:background];
    NSURLSessionDownloadTask* task = [self.session downloadTaskWithRequest:request];
    [task resume];
}

- (void)clear
{
    [self.session finishTasksAndInvalidate];
    self.session = nil;
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    dispatch_async(self.callbackQueue, ^{
        self.updateBlock(nil, (uint64_t)totalBytesWritten, (uint64_t)totalBytesExpectedToWrite, nil);
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (error == nil) {
        return;
    }
    [self clear];
    dispatch_async(self.callbackQueue, ^{
        self.updateBlock(nil, 0, 0, error);
    });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    [self clear];
    dispatch_async(self.callbackQueue, ^{
        self.updateBlock(location, (uint64_t)downloadTask.countOfBytesReceived, (uint64_t)downloadTask.countOfBytesExpectedToReceive, nil);
    });
}

@end
