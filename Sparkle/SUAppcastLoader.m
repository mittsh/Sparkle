//
//  SUAppcastLoader.m
//  Sparkle
//
//  Created by Micha Mazaheri on 6/16/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SUAppcastLoader.h"

#import "SUAppcast.h"
#import "SULog.h"
#import "SULocalizations.h"
#import "SUErrors.h"

#include "AppKitPrevention.h"

@implementation SUAppcastLoader

@synthesize userAgentString = _userAgentString;
@synthesize httpHeaders = _httpHeaders;

- (NSURLRequest*)fetchAppcastRequestFromURL:(NSURL *)url inBackground:(BOOL)background
{
    NSString *userAgentString = self.userAgentString;
    NSDictionary<NSString *, NSString *> *httpHeaders = self.httpHeaders;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
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
    [request setValue:@"application/rss+xml,*/*;q=0.1" forHTTPHeaderField:@"Accept"];
    return [request copy];
}

- (void)fetchAppcastFromURL:(NSURL *)url inBackground:(BOOL)background completionBlock:(nonnull void (^)(BOOL, SUAppcast * _Nullable, NSError * _Nullable))completionBlock
{
    NSURLRequest *request = [self fetchAppcastRequestFromURL:url inBackground:background];

    NSURLSessionConfiguration* sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    
    /* Create session, and optionally set a NSURLSessionDelegate. */
    NSURLSession* session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:nil delegateQueue:nil];
    
    /* Start a new Task */
    NSURLSessionDataTask* task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data != nil) {
            // Success
            NSError* parsingError = nil;
            SUAppcast* appcast = [[SUAppcast alloc] initWithAppcastXMLData:data error:&parsingError];
            if (appcast != nil) {
                completionBlock(YES, appcast, nil);
            }
            else {
                completionBlock(NO, nil, parsingError);
            }
        }
        else {
            // Failure
            completionBlock(NO, nil, [self appcastError:error]);
        }
    }];
    [task resume];
    [session finishTasksAndInvalidate];
}

- (NSError*)appcastError:(NSError *)error
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
        NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred in retrieving update information. Please try again later.", nil),
        NSLocalizedFailureReasonErrorKey: [error localizedDescription],
        NSUnderlyingErrorKey: error,
    }];

    NSURL *failingUrl = [error.userInfo objectForKey:NSURLErrorFailingURLErrorKey];
    if (failingUrl) {
        [userInfo setObject:failingUrl forKey:NSURLErrorFailingURLErrorKey];
    }
    return [NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastError userInfo:userInfo];
}

@end
