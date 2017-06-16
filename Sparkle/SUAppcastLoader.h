//
//  SUAppcastLoader.h
//  Sparkle
//
//  Created by Micha Mazaheri on 6/16/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SUAppcast;

NS_ASSUME_NONNULL_BEGIN

@interface SUAppcastLoader : NSObject

@property (copy, nullable) NSString *userAgentString;
@property (copy, nullable) NSDictionary<NSString *, NSString *> *httpHeaders;

- (void)fetchAppcastFromURL:(NSURL *)url inBackground:(BOOL)bg completionBlock:(void (^)(BOOL, SUAppcast* _Nullable, NSError *_Nullable))completionBlock;

@end

NS_ASSUME_NONNULL_END
