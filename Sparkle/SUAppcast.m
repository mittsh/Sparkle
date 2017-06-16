//
//  SUAppcast.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SULog.h"
#import "SULocalizations.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@interface NSXMLElement (SUAppcastExtensions)
@property (readonly, copy) NSDictionary *attributesAsDictionary;
@end

@implementation NSXMLElement (SUAppcastExtensions)
- (NSDictionary *)attributesAsDictionary
{
    NSEnumerator *attributeEnum = [[self attributes] objectEnumerator];
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    for (NSXMLNode *attribute in attributeEnum) {
        NSString *attrName = [attribute name];
        if (!attrName) {
            continue;
        }
        NSString *attributeStringValue = [attribute stringValue];
        if (attributeStringValue != nil) {
            [dictionary setObject:attributeStringValue forKey:attrName];
        }
    }
    return dictionary;
}
@end

@interface SUAppcast ()
@property (copy) NSArray<SUAppcastItem*>*items;
@end

@implementation SUAppcast

@synthesize items = _items;

#pragma mark - Parsing

- (instancetype)initWithAppcastXMLData:(NSData*)appcastXMLData error:(NSError*__autoreleasing*)__error
{
    self = [self init];
    if (self) {
        NSError *error = nil;
        NSArray<SUAppcastItem*>*appcastItems = [SUAppcast parseAppcastItemsFromXMLData:appcastXMLData error:&error];

        if (appcastItems != nil) {
            _items = appcastItems;
        } else {
            NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while parsing the update feed.", nil)} mutableCopy];
            if (error != nil) {
                [userInfo setObject:error forKey:NSUnderlyingErrorKey];
            }
            if (__error != NULL) {
                *__error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:[userInfo copy]];
            }
            return nil;
        }
    }
    return self;
}

+ (NSDictionary *)attributesOfNode:(NSXMLElement *)node
{
    NSEnumerator *attributeEnum = [[node attributes] objectEnumerator];
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    for (NSXMLNode *attribute in attributeEnum) {
        NSString *attrName = [self sparkleNamespacedNameOfNode:attribute];
        if (!attrName) {
            continue;
        }
        NSString *stringValue = [attribute stringValue];
        if (stringValue) {
            [dictionary setObject:stringValue forKey:attrName];
        }
    }
    return [dictionary copy];
}

+ (NSString *)sparkleNamespacedNameOfNode:(NSXMLNode *)node {
    // XML namespace prefix is semantically meaningless, so compare namespace URI
    // NS URI isn't used to fetch anything, and must match exactly, so we look for http:// not https://
    if ([[node URI] isEqualToString:@"http://www.andymatuschak.org/xml-namespaces/sparkle"]) {
        NSString *localName = [node localName];
        assert(localName);
        return [@"sparkle:" stringByAppendingString:localName];
    } else {
        return [node name]; // Backwards compatibility
    }
}

+ (NSArray<SUAppcastItem*>*)parseAppcastItemsFromXMLData:(NSData *)appcastXMLData error:(NSError *__autoreleasing*)__error {
    if (__error != NULL) {
        *__error = nil;
    }

    if (appcastXMLData == nil) {
        return nil;
    }

    NSUInteger options = NSXMLNodeLoadExternalEntitiesNever; // Prevent inclusion from file://
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:appcastXMLData options:options error:__error];
	if (nil == document) {
        return nil;
    }

    NSArray *xmlItems = [document nodesForXPath:@"/rss/channel/item" error:__error];
    if (nil == xmlItems) {
        return nil;
    }

    NSMutableArray<SUAppcastItem*>*appcastItems = [NSMutableArray array];
    NSEnumerator *nodeEnum = [xmlItems objectEnumerator];
    NSXMLNode *node;

	while((node = [nodeEnum nextObject])) {
        NSMutableDictionary *nodesDict = [NSMutableDictionary dictionary];
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];

        // First, we'll "index" all the first-level children of this appcast item so we can pick them out by language later.
        if ([[node children] count]) {
            node = [node childAtIndex:0];
            while (nil != node) {
                NSString *name = [self sparkleNamespacedNameOfNode:node];
                if (name) {
                    NSMutableArray *nodes = [nodesDict objectForKey:name];
                    if (nodes == nil) {
                        nodes = [NSMutableArray array];
                        [nodesDict setObject:nodes forKey:name];
                    }
                    [nodes addObject:node];
                }
                node = [node nextSibling];
            }
        }

        for (NSString *name in nodesDict) {
            node = [self bestNodeInNodes:[nodesDict objectForKey:name]];
            if ([name isEqualToString:SURSSElementEnclosure]) {
                // enclosure is flattened as a separate dictionary for some reason
                NSDictionary *encDict = [self attributesOfNode:(NSXMLElement *)node];
                [dict setObject:encDict forKey:name];
			}
            else if ([name isEqualToString:SURSSElementPubDate]) {
                // We don't want to parse and create a NSDate instance -
                // that's a risk we can avoid. We don't use the date anywhere other
                // than it being accessible from SUAppcastItem
                NSString *dateString = node.stringValue;
                if (dateString) {
                    [dict setObject:dateString forKey:name];
                }
			}
			else if ([name isEqualToString:SUAppcastElementDeltas]) {
                NSMutableArray *deltas = [NSMutableArray array];
                NSEnumerator *childEnum = [[node children] objectEnumerator];
                for (NSXMLNode *child in childEnum) {
                    if ([[child name] isEqualToString:SURSSElementEnclosure]) {
                        [deltas addObject:[self attributesOfNode:(NSXMLElement *)child]];
                    }
                }
                [dict setObject:[deltas copy] forKey:name];
			}
            else if ([name isEqualToString:SUAppcastElementTags]) {
                NSMutableArray *tags = [NSMutableArray array];
                NSEnumerator *childEnum = [[node children] objectEnumerator];
                for (NSXMLNode *child in childEnum) {
                    NSString *childName = child.name;
                    if (childName) {
                        [tags addObject:childName];
                    }
                }
                [dict setObject:[tags copy] forKey:name];
            }
			else if (name != nil) {
                // add all other values as strings
                NSString *theValue = [[node stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (theValue != nil) {
                    [dict setObject:theValue forKey:name];
                }
            }
        }

        NSString *errString;
        SUAppcastItem *anItem = [[SUAppcastItem alloc] initWithDictionary:dict failureReason:&errString];
        if (anItem) {
            [appcastItems addObject:anItem];
		}
        else {
            SULog(SULogLevelError, @"Sparkle Updater: Failed to parse appcast item: %@.\nAppcast dictionary was: %@", errString, dict);
            if (__error != NULL) {
                *__error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:@{NSLocalizedDescriptionKey: errString}];
            }
            return nil;
        }
    }
    
    return [appcastItems copy];
}

+ (NSXMLNode *)bestNodeInNodes:(NSArray *)nodes
{
    // We use this method to pick out the localized version of a node when one's available.
    if ([nodes count] == 1)
        return [nodes objectAtIndex:0];
    else if ([nodes count] == 0)
        return nil;

    NSMutableArray *languages = [NSMutableArray array];
    NSString *lang;
    NSUInteger i;
    for (NSXMLElement *node in nodes) {
        lang = [[node attributeForName:@"xml:lang"] stringValue];
        [languages addObject:(lang ? lang : @"")];
    }
    lang = [[NSBundle preferredLocalizationsFromArray:languages] objectAtIndex:0];
    i = [languages indexOfObject:([languages containsObject:lang] ? lang : @"")];
    if (i == NSNotFound) {
        i = 0;
    }
    return [nodes objectAtIndex:i];
}

#pragma mark - Item Lookup

- (SUAppcastItem *)itemWithLocalIdentifier:(NSString *)localIdentifier
{
    __block SUAppcastItem* item = nil;
    [self.items enumerateObjectsUsingBlock:^(SUAppcastItem * _Nonnull anItem, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([anItem.localIdentifier.uppercaseString isEqualToString:localIdentifier.uppercaseString]) {
            item = anItem;
            *stop = YES;
        }
    }];
    return item;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self) {
        NSArray<SUAppcastItem*>* items = [aDecoder decodeObjectOfClasses:[NSSet setWithArray:@[[NSArray class], [SUAppcastItem class]]] forKey:@"items"];
        if (items == nil) {
            return nil;
        }
        _items = [items copy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:[self.items copy] forKey:@"items"];
}

#pragma mark - Filter Delta Updates

- (SUAppcast *)copyWithoutDeltaUpdates
{
    SUAppcast *other = [SUAppcast new];
    NSMutableArray *nonDeltaItems = [NSMutableArray new];

    for(SUAppcastItem *item in self.items) {
        if (![item isDeltaUpdate]) [nonDeltaItems addObject:item];
    }

    other.items = nonDeltaItems;
    return other;
}

@end
