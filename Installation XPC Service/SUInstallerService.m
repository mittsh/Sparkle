//
//  SUInstallerService.m
//  Installation XPC Service
//
//  Created by Micha Mazaheri on 6/16/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SUInstallerService.h"

#import "SUAppcast.h"
#import "SUAppcastLoader.h"

@implementation SUInstallerService

// This implements the example protocol. Replace the body of this class with the implementation of this service's protocol.
- (void)upperCaseString:(NSString *)aString withReply:(void (^)(NSString *))reply {
    NSString *response = [aString uppercaseString];
    reply(response);
}

- (void)checkForUpdatesAtURL:(NSURL *)URL options:(NSDictionary<NSString *,id> *)options completionBlock:(void (^)(BOOL, SUAppcast *, NSError *))completionBlock
{
    SUAppcastLoader *appcastLoader = [[SUAppcastLoader alloc] init];
    appcastLoader.userAgentString = options[SUInstallerServiceProtocolOptionsUserAgent];
    appcastLoader.httpHeaders = options[SUInstallerServiceProtocolOptionsHTTPHeaders];
    [appcastLoader fetchAppcastFromURL:URL inBackground:((NSNumber*)options[SUInstallerServiceProtocolOptionsDownloadInBackground]).boolValue completionBlock:completionBlock];
}

@end
