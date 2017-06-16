//
//  SUAppcastItemDownloader.h
//  Sparkle
//
//  Created by Micha Mazaheri on 6/16/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SUAppcastItem;

NS_ASSUME_NONNULL_BEGIN

typedef void(^SUAppcastItemDownloaderUpdateBlock)(NSURL* _Nullable location, uint64_t totalBytesWritten, uint64_t totalBytesExpectedToWrite, NSError* _Nullable error);

@interface SUAppcastItemDownloader : NSObject

@property (nonatomic, strong, readonly) SUAppcastItem* appcastItem;
@property (nonatomic, strong, nullable) NSString *userAgentString;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NSString *> *httpHeaders;

- (instancetype)initWithAppcastItem:(SUAppcastItem*)appcastItem callbackQueue:(dispatch_queue_t)callbackQueue updateBlock:(SUAppcastItemDownloaderUpdateBlock)updateBlock;
- (void)downloadInBackground:(BOOL)background;

@end

NS_ASSUME_NONNULL_END
