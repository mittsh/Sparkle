//
//  SUAppcast.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUAPPCAST_H
#define SUAPPCAST_H

@import Foundation;
#import "SUExport.h"

@class SUAppcastItem;

NS_ASSUME_NONNULL_BEGIN

SU_EXPORT @interface SUAppcast : NSObject <NSSecureCoding>

- (nullable instancetype)initWithAppcastXMLData:(NSData*)appcastXMLData error:(NSError*__autoreleasing _Nullable * _Nullable)__error;

@property (readonly, copy, nullable) NSArray<SUAppcastItem*>*items;

- (nullable SUAppcastItem*)itemWithLocalIdentifier:(NSString*)localIdentifier;

- (SUAppcast *)copyWithoutDeltaUpdates;

@end

NS_ASSUME_NONNULL_END

#endif
