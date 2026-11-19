// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class RFXRemotePage;

/// Shows a page's remote layer and turns AppKit's input into the host's messages.
@interface RFXRemotePageView : NSView <NSTextInputClient, NSDraggingSource>

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
/// The nodes of `nodes` are new or changed, and the ones numbered in `removed` are gone.
- (void)changeAccessibilityNodes:(NSArray<NSDictionary<NSString *, id> *> *)nodes removing:(NSArray<NSNumber *> *)removed;

/// What the host says of the page's text input (PROTOCOL.md §7): whether it takes composed text,
/// where its caret is, and the text around it.
- (void)setInputMethodState:(NSDictionary<NSString *, id> *)state;

/// Shows a menu of the host's `items` at `point` and tells the host which was chosen (PROTOCOL.md §8).
- (void)showContextMenuWithItems:(NSArray<NSDictionary<NSString *, id> *> *)items identifier:(NSNumber *)identifier atPoint:(NSPoint)point;

/// The user began dragging something of the page's: the drag continues as the system's, so it
/// can end on anything that takes its `items` (PROTOCOL.md §9).
- (void)beginDragWithItems:(NSArray<NSDictionary<NSString *, id> *> *)items title:(NSString *)title;

/// An assistive technology acted on a node: `press` or `focus`.
- (void)performAccessibilityAction:(NSString *)action onNode:(NSNumber *)node;

@end

NS_ASSUME_NONNULL_END
