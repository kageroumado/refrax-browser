// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class RFXRemotePageView;

/// One node of a page's accessibility tree, as the host describes it (PROTOCOL.md §6). The
/// elements live in Refrax's process, under the page's view, and answer assistive technologies
/// from what the host last sent.
@interface RFXRemoteAccessibilityElement : NSAccessibilityElement

- (instancetype)initWithIdentifier:(NSNumber *)identifier view:(RFXRemotePageView *)view NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) NSNumber *identifier;
/// The host's description of the node.
@property (nonatomic, copy) NSDictionary<NSString *, id> *node;
@property (nonatomic, copy) NSArray<RFXRemoteAccessibilityElement *> *childElements;
/// The element above this one; nil for the root, whose parent is the view.
@property (nonatomic, weak, nullable) RFXRemoteAccessibilityElement *parentElement;

/// The deepest element whose box holds `point`, in the view's coordinates.
- (RFXRemoteAccessibilityElement *)elementAtPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END
