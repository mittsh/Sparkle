//
//  SUInstallerService.h
//  Installation XPC Service
//
//  Created by Micha Mazaheri on 6/16/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerServiceProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SUInstallerService : NSObject <SUInstallerServiceProtocol>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithConnection:(NSXPCConnection*)connection;

@property (nonatomic, weak, readonly) NSXPCConnection* connection;

@end

NS_ASSUME_NONNULL_END
