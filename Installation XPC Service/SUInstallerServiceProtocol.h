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

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol SUInstallerServiceProtocol

// Replace the API of this protocol with an API appropriate to the service you are vending.
- (void)upperCaseString:(NSString *)aString withReply:(void (^)(NSString *))reply;

// @TODO: security around the URL used here
- (void)checkForUpdatesAtURL:(NSURL *)URL options:(NSDictionary<NSString*,id>*)options completionBlock:(void (^)(BOOL, SUAppcast*, NSError*))completionBlock;
    
@end

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     _connectionToService = [[NSXPCConnection alloc] initWithServiceName:@"com.andymatuschak.Sparkle.Installation-XPC-Service"];
     _connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerServiceProtocol)];
     [_connectionToService resume];

Once you have a connection to the service, you can use it like this:

     [[_connectionToService remoteObjectProxy] upperCaseString:@"hello" withReply:^(NSString *aString) {
         // We have received a response. Update our text field, but do it on the main thread.
         NSLog(@"Result string was: %@", aString);
     }];

 And, when you are finished with the service, clean up the connection like this:

     [_connectionToService invalidate];
*/
