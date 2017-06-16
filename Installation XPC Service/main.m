//
//  main.m
//  Installation XPC Service
//
//  Created by Micha Mazaheri on 6/16/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerService.h"

@interface SUInstallerServiceDelegate : NSObject <NSXPCListenerDelegate>
@end

@implementation SUInstallerServiceDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerServiceAppProtocol)];
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerServiceProtocol)];
    newConnection.exportedObject = [[SUInstallerService alloc] initWithConnection:newConnection];
    [newConnection resume];
    return YES;
}

@end

int main(int argc, const char *argv[])
{
    // Create the delegate for the service.
    SUInstallerServiceDelegate *delegate = [[SUInstallerServiceDelegate alloc] init];
    
    // Set up the one NSXPCListener for this service. It will handle all incoming connections.
    NSXPCListener *listener = [NSXPCListener serviceListener];
    listener.delegate = delegate;
    
    // Resuming the serviceListener starts this service. This method does not return.
    [listener resume];
    return 0;
}
