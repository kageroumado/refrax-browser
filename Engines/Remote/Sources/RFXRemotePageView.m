// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import "RFXRemotePageView.h"

#import "RFXRemotePage.h"

#import <QuartzCore/QuartzCore.h>

/// A layer that shows the tree of a Core Animation context in another process.
@interface CALayer (RFXRemoteLayerHost)
@property uint32_t contextId;
@end

/// The wire's modifier bits: shift, control, option, command and the numeric keypad.
static NSUInteger RFXWireModifiers(NSEventModifierFlags flags) {
    NSUInteger bits = 0;
    if (flags & NSEventModifierFlagShift) {
        bits |= 1;
    }
    if (flags & NSEventModifierFlagControl) {
        bits |= 2;
    }
    if (flags & NSEventModifierFlagOption) {
        bits |= 4;
    }
    if (flags & NSEventModifierFlagCommand) {
        bits |= 8;
    }
    if (flags & NSEventModifierFlagNumericPad) {
        bits |= 16;
    }
    return bits;
}

/// How many key events may wait on the page's answer; older ones are forgotten.
static const NSUInteger RFXMaximumPendingKeys = 64;
/// The distance one notch of a mouse wheel scrolls, in points.
static const CGFloat RFXWheelLineHeight = 40;

@implementation RFXRemotePageView {
    __weak RFXRemotePage *_page;
    CALayer *_remoteLayerHost;
    NSTrackingArea *_trackingArea;
    NSCursor *_cursor;
    /// The wire's bits of the buttons that are down, kept from the events themselves.
    NSUInteger _pressedButtons;
    NSMutableDictionary<NSNumber *, NSEvent *> *_pendingKeys;
    NSMutableArray<NSString *> *_keyCommands;
    BOOL _reportedFocus;
}

- (instancetype)initWithPage:(RFXRemotePage *)page {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)])) {
        _page = page;
        _pendingKeys = [NSMutableDictionary dictionary];
        _cursor = NSCursor.arrowCursor;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.whiteColor.CGColor;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

- (void)detachFromPage {
    _page = nil;
    self.remoteContextID = 0;
    [_pendingKeys removeAllObjects];
}

// MARK: The remote layer

- (void)setRemoteContextID:(uint32_t)remoteContextID {
    if (_remoteContextID == remoteContextID) {
        return;
    }
    _remoteContextID = remoteContextID;
    [_remoteLayerHost removeFromSuperlayer];
    _remoteLayerHost = nil;
    if (remoteContextID == 0) {
        return;
    }
    Class hostClass = NSClassFromString(@"CALayerHost");
    if (!hostClass) {
        return;
    }
    CALayer *host = [[hostClass alloc] init];
    host.anchorPoint = CGPointZero;
    host.contextId = remoteContextID;
    // Without this a new frame would slide into place as the view resizes.
    host.actions = @{@"bounds": NSNull.null, @"position": NSNull.null, @"hidden": NSNull.null};
    host.frame = self.layer.bounds;
    [self.layer addSublayer:host];
    _remoteLayerHost = host;
}

- (NSDictionary<NSString *, id> *)geometry {
    CGFloat scale = self.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor ?: 2;
    return @{
        @"width": @(MAX(1, (NSInteger)round(NSWidth(self.bounds)))),
        @"height": @(MAX(1, (NSInteger)round(NSHeight(self.bounds)))),
        @"scale": @(scale),
    };
}

- (void)geometryDidChange {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _remoteLayerHost.frame = self.layer.bounds;
    [CATransaction commit];
    [_page send:@"geometry" fields:self.geometry];
}

- (void)setFrameSize:(NSSize)newSize {
    BOOL changed = !NSEqualSizes(newSize, self.frame.size);
    [super setFrameSize:newSize];
    if (changed) {
        [self geometryDidChange];
    }
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [self geometryDidChange];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    [super viewWillMoveToWindow:newWindow];
    if (self.window) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidBecomeKeyNotification object:self.window];
        [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidResignKeyNotification object:self.window];
    }
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(focusMayHaveChanged) name:NSWindowDidBecomeKeyNotification object:self.window];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(focusMayHaveChanged) name:NSWindowDidResignKeyNotification object:self.window];
        [self geometryDidChange];
    }
    [self focusMayHaveChanged];
}

// MARK: Focus

/// The page has the system's focus while its view is the first responder of the key window.
- (void)focusMayHaveChanged {
    BOOL focused = self.window.isKeyWindow && self.window.firstResponder == self;
    if (focused == _reportedFocus) {
        return;
    }
    _reportedFocus = focused;
    [_page send:@"focusState" fields:@{@"focused": @(focused)}];
}

- (BOOL)becomeFirstResponder {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self focusMayHaveChanged];
    });
    return YES;
}

- (BOOL)resignFirstResponder {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self focusMayHaveChanged];
    });
    return YES;
}

// MARK: Mouse

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    NSTrackingAreaOptions options = NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingCursorUpdate | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect;
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:options owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)sendMouse:(NSString *)type event:(NSEvent *)event button:(NSUInteger)button extra:(nullable NSDictionary<NSString *, id> *)extra {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    // The screen's origin is its top left for the page, as the view's is.
    NSPoint onScreen = self.window ? [self.window convertPointToScreen:event.locationInWindow] : NSEvent.mouseLocation;
    CGFloat screenHeight = NSHeight(NSScreen.screens.firstObject.frame);
    NSMutableDictionary *fields = [NSMutableDictionary dictionaryWithDictionary:@{
        @"type": type,
        @"x": @(point.x),
        @"y": @(point.y),
        @"screenX": @(onScreen.x),
        @"screenY": @(screenHeight - onScreen.y),
        @"button": @(button),
        @"buttons": @(_pressedButtons),
        @"modifiers": @(RFXWireModifiers(event.modifierFlags)),
    }];
    if (extra) {
        [fields addEntriesFromDictionary:extra];
    }
    [_page send:@"mouse" fields:fields];
}

- (void)buttonDown:(NSUInteger)button event:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    _pressedButtons |= button;
    [self sendMouse:@"down" event:event button:button extra:@{@"clickCount": @(event.clickCount)}];
}

- (void)buttonUp:(NSUInteger)button event:(NSEvent *)event {
    _pressedButtons &= ~button;
    [self sendMouse:@"up" event:event button:button extra:@{@"clickCount": @(event.clickCount)}];
}

/// The wire's bit of the button an other-mouse event is about: the middle one, or none.
static NSUInteger RFXOtherButton(NSEvent *event) {
    return event.buttonNumber == 2 ? 4 : 0;
}

- (void)mouseDown:(NSEvent *)event {
    [self buttonDown:1 event:event];
}

- (void)mouseUp:(NSEvent *)event {
    [self buttonUp:1 event:event];
}

- (void)rightMouseDown:(NSEvent *)event {
    [self buttonDown:2 event:event];
}

- (void)rightMouseUp:(NSEvent *)event {
    [self buttonUp:2 event:event];
}

- (void)otherMouseDown:(NSEvent *)event {
    if (RFXOtherButton(event)) {
        [self buttonDown:RFXOtherButton(event) event:event];
    }
}

- (void)otherMouseUp:(NSEvent *)event {
    if (RFXOtherButton(event)) {
        [self buttonUp:RFXOtherButton(event) event:event];
    }
}

- (void)mouseMoved:(NSEvent *)event {
    [self sendMouse:@"move" event:event button:0 extra:nil];
}

- (void)mouseDragged:(NSEvent *)event {
    [self sendMouse:@"move" event:event button:0 extra:nil];
}

- (void)rightMouseDragged:(NSEvent *)event {
    [self sendMouse:@"move" event:event button:0 extra:nil];
}

- (void)otherMouseDragged:(NSEvent *)event {
    [self sendMouse:@"move" event:event button:0 extra:nil];
}

- (void)mouseExited:(NSEvent *)event {
    [self sendMouse:@"leave" event:event button:0 extra:nil];
}

- (void)scrollWheel:(NSEvent *)event {
    BOOL precise = event.hasPreciseScrollingDeltas;
    CGFloat unit = precise ? 1 : RFXWheelLineHeight;
    NSString *phase = @"none";
    if (event.momentumPhase & (NSEventPhaseBegan | NSEventPhaseChanged)) {
        phase = @"momentum";
    } else if (event.momentumPhase & (NSEventPhaseEnded | NSEventPhaseCancelled)) {
        phase = @"ended";
    } else if (event.phase & (NSEventPhaseBegan | NSEventPhaseChanged)) {
        phase = @"ongoing";
    } else if (event.phase & (NSEventPhaseEnded | NSEventPhaseCancelled)) {
        phase = precise && event.momentumPhase == NSEventPhaseNone ? @"ongoing" : @"ended";
    }
    // A positive delta scrolls the content down or to the right.
    [self sendMouse:@"wheel" event:event button:0 extra:@{
        @"deltaX": @(-event.scrollingDeltaX * unit),
        @"deltaY": @(-event.scrollingDeltaY * unit),
        @"precise": @(precise),
        @"phase": phase,
    }];
}

- (void)setCursorNamed:(NSString *)name {
    static NSDictionary<NSString *, NSCursor *> *cursors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cursors = @{
            @"Arrow": NSCursor.arrowCursor,
            @"Crosshair": NSCursor.crosshairCursor,
            @"IBeam": NSCursor.IBeamCursor,
            @"ResizeHorizontal": NSCursor.resizeLeftRightCursor,
            @"ResizeVertical": NSCursor.resizeUpDownCursor,
            @"ResizeColumn": NSCursor.resizeLeftRightCursor,
            @"ResizeRow": NSCursor.resizeUpDownCursor,
            @"Hand": NSCursor.pointingHandCursor,
            @"OpenHand": NSCursor.openHandCursor,
            @"Drag": NSCursor.closedHandCursor,
            @"DragCopy": NSCursor.dragCopyCursor,
            @"Disallowed": NSCursor.operationNotAllowedCursor,
        };
    });
    _cursor = cursors[name] ?: NSCursor.arrowCursor;
    NSPoint mouse = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    if (self.window.isKeyWindow && NSPointInRect(mouse, self.bounds)) {
        [_cursor set];
    }
}

- (void)cursorUpdate:(NSEvent *)event {
    [_cursor set];
}

// MARK: Keys

- (void)sendKey:(NSEvent *)event down:(BOOL)down {
    uint64_t identifier = [_page nextRequestID];
    NSMutableDictionary *fields = [NSMutableDictionary dictionaryWithDictionary:@{
        @"id": @(identifier),
        @"type": down ? @"down" : @"up",
        @"keyCode": @(event.keyCode),
        @"characters": event.characters ?: @"",
        @"charactersIgnoringModifiers": event.charactersIgnoringModifiers ?: @"",
        @"modifiers": @(RFXWireModifiers(event.modifierFlags)),
        @"repeat": @(event.isARepeat),
    }];
    if (down) {
        // The system's key bindings name what the key does to text, such as moveWordBackward:.
        _keyCommands = [NSMutableArray array];
        [self interpretKeyEvents:@[event]];
        fields[@"commands"] = _keyCommands;
        _keyCommands = nil;

        if (_pendingKeys.count >= RFXMaximumPendingKeys) {
            [_pendingKeys removeAllObjects];
        }
        _pendingKeys[@(identifier)] = event;
    }
    [_page send:@"key" fields:fields];
}

- (void)keyDown:(NSEvent *)event {
    [self sendKey:event down:YES];
}

- (void)keyUp:(NSEvent *)event {
    [self sendKey:event down:NO];
}

/// The page sees a command key before Refrax's menus do, and the menus get it only if the page
/// leaves it alone.
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown || self.window.firstResponder != self || !_page) {
        return [super performKeyEquivalent:event];
    }
    [self sendKey:event down:YES];
    return YES;
}

- (void)doCommandBySelector:(SEL)selector {
    [_keyCommands addObject:NSStringFromSelector(selector)];
}

- (void)insertText:(id)string {
    // The key's characters travel with the key event itself.
}

- (void)keyWasHandled:(uint64_t)identifier {
    _pendingKeys[@(identifier)] = nil;
}

- (void)keyWasUnhandled:(uint64_t)identifier {
    NSEvent *event = _pendingKeys[@(identifier)];
    if (!event) {
        return;
    }
    _pendingKeys[@(identifier)] = nil;
    if (!(event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
        return;
    }
    if (![NSApp.mainMenu performKeyEquivalent:event]) {
        [self.nextResponder keyDown:event];
    }
}

// MARK: Editing commands from Refrax's menus

- (void)sendEdit:(NSString *)action {
    [_page send:@"edit" fields:@{@"action": action}];
}

- (void)selectAll:(id)sender {
    [self sendEdit:@"selectAll"];
}

- (void)copy:(id)sender {
    [self sendEdit:@"copy"];
}

- (void)cut:(id)sender {
    [self sendEdit:@"cut"];
}

- (void)paste:(id)sender {
    [self sendEdit:@"paste"];
}

- (void)undo:(id)sender {
    [self sendEdit:@"undo"];
}

- (void)redo:(id)sender {
    [self sendEdit:@"redo"];
}

@end
