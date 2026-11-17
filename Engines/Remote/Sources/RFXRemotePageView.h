// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class RFXRemotePage;

/// Shows a page's remote layer and turns AppKit's input into the host's messages.
@interface RFXRemotePageView : NSView

- (instancetype)initWithPage:(RFXRemotePage *)page NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// The Core Animation context the host renders the page into; 0 shows nothing.
@property (nonatomic) uint32_t remoteContextID;

/// The page's size in points and its scale, as the host needs them.
- (NSDictionary<NSString *, id> *)geometry;

- (void)setCursorNamed:(NSString *)name;
/// The page left key event `identifier` alone, so Refrax's menus and responders get it.
- (void)keyWasUnhandled:(uint64_t)identifier;
- (void)keyWasHandled:(uint64_t)identifier;
/// The page is closed: nothing more is sent for it.
- (void)detachFromPage;

/// The page's accessibility tree as the host has it now (PROTOCOL.md §6): `nodes` by their
/// numbers, under the node numbered `root`.
- (void)setAccessibilityNodes:(NSArray<NSDictionary<NSString *, id> *> *)nodes root:(nullable NSNumber *)root;
/// An assistive technology acted on a node: `press` or `focus`.
- (void)performAccessibilityAction:(NSString *)action onNode:(NSNumber *)node;

@end

NS_ASSUME_NONNULL_END
