// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import "RFXRemotePageView.h"

#import "RFXRemoteAccessibility.h"

#import "RFXRemotePage.h"

#import <QuartzCore/QuartzCore.h>

/// A layer that shows the tree of a Core Animation context in another process.
@interface CALayer (RFXRemoteLayerHost)
@property uint32_t contextId;
@end

/// Core Animation runs these handlers as it commits a transaction: before the layer tree goes to
/// the window server, and once it has gone but before the window shows it.
typedef NS_ENUM(unsigned int, RFXTransactionPhase) {
    RFXTransactionPhasePreLayout,
    RFXTransactionPhasePreCommit,
    RFXTransactionPhasePostCommit,
};

@interface CATransaction (RFXCommitHandlers)
+ (void)addCommitHandler:(void (^)(void))block forPhase:(RFXTransactionPhase)phase;
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
/// A resize that follows another within this many frames is the same resizing going on.
static const CFTimeInterval RFXFramesThatEndAResize = 4;
/// How long the window's frame waits for the host to let go of the page's frame it held.
static const NSTimeInterval RFXHeldFrameReleaseLimit = 0.05;
/// The widest label a drag shows, in points.
static const CGFloat RFXMaximumDragLabelWidth = 240;

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

    /// A press of the primary button with Control held is one of the secondary button until it ends.
    BOOL _controlClickIsSecondary;
    /// The primary button's latest press or drag, which a drag of the page's content starts from.
    NSEvent *_dragOrigin;
    /// The item chosen from the context menu on screen.
    NSNumber *_contextMenuChoice;

    /// The resize whose frame the window's next commit waits for; 0 for none.
    uint64_t _resizeToken;
    CFTimeInterval _lastResizeTime;
    /// The page missed a frame of this resizing, so it is not waited for until the resizing pauses.
    BOOL _pageLagsBehindResize;

    /// What the host says of the page's text input.
    BOOL _inputMethodEnabled;
    NSRect _caretRect;
    NSInteger _cursorPosition;
    NSInteger _anchorPosition;
    NSString *_textBeforeCursor;
    NSString *_textAfterCursor;
    /// The text the input method is composing, where it began, and the selection within it.
    NSString *_markedText;
    NSInteger _markedStart;
    NSRange _markedSelection;
    /// The key going through the input context, and whether the input method used it.
    NSEvent *_interpretedKey;
    BOOL _inputMethodTookKey;
    /// The input context handed the key back, as text of its own or as a command.
    BOOL _keyCameBackFromInputContext;
    /// Whether something has read the view's accessibility children, which is what has the host build the tree.
    BOOL _accessibilityRequested;
    NSMutableDictionary<NSNumber *, RFXRemoteAccessibilityElement *> *_accessibilityElements;
    RFXRemoteAccessibilityElement *_accessibilityRoot;
}

- (instancetype)initWithPage:(RFXRemotePage *)page {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)])) {
        _page = page;
        _pendingKeys = [NSMutableDictionary dictionary];
        _accessibilityElements = [NSMutableDictionary dictionary];
        _cursor = NSCursor.arrowCursor;
        _textBeforeCursor = @"";
        _textAfterCursor = @"";
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
    _dragOrigin = nil;
    _markedText = nil;
    _inputMethodEnabled = NO;
    [_accessibilityElements removeAllObjects];
    _accessibilityRoot = nil;
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
    if (![self holdsFrameForResize]) {
        [_page send:@"geometry" fields:self.geometry];
    }
}

// MARK: Resizing in step with the page

/// The window's next frame waits for the page's frame of the new size, so the two change together
/// and the page never shows stretched or cut short. YES when the size goes to the host with that
/// frame's commit.
- (BOOL)holdsFrameForResize {
    if (_remoteContextID == 0 || !_page || !self.window.isVisible || self.isHiddenOrHasHiddenAncestor
        || ![CATransaction respondsToSelector:@selector(addCommitHandler:forPhase:)]) {
        return NO;
    }
    if (_resizeToken != 0) {
        return YES;
    }
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval frameInterval = 1.0 / (self.window.screen.maximumFramesPerSecond ?: 60);
    if (now - _lastResizeTime >= frameInterval * RFXFramesThatEndAResize) {
        _pageLagsBehindResize = NO;
    }
    _lastResizeTime = now;
    if (_pageLagsBehindResize) {
        return NO;
    }

    uint64_t token = [_page nextRequestID];
    _resizeToken = token;
    [_page send:@"resizeBegin" fields:@{@"token": @(token)}];
    __weak RFXRemotePageView *weakSelf = self;
    [CATransaction addCommitHandler:^{
        [weakSelf awaitFrameOfResize:token within:frameInterval];
    } forPhase:RFXTransactionPhasePreCommit];
    [CATransaction addCommitHandler:^{
        [weakSelf releaseFrameOfResize:token];
    } forPhase:RFXTransactionPhasePostCommit];
    return YES;
}

/// The commit waits no longer than a frame of the display: the window could resize no faster
/// than the page lays out otherwise.
- (void)awaitFrameOfResize:(uint64_t)token within:(CFTimeInterval)frameInterval {
    NSMutableDictionary<NSString *, id> *geometry = [self.geometry mutableCopy];
    geometry[@"token"] = @(token);
    [_page send:@"geometry" fields:geometry];
    if (![_page waitForMessageNamed:@"resizeHeld" token:token timeout:frameInterval]) {
        _pageLagsBehindResize = YES;
    }
}

- (void)releaseFrameOfResize:(uint64_t)token {
    _resizeToken = 0;
    [_page send:@"resizeCommit" fields:@{@"token": @(token)}];
    [_page waitForMessageNamed:@"resizeCommitted" token:token timeout:RFXHeldFrameReleaseLimit];
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
    [self sendMouse:type atWindowPoint:event.locationInWindow modifiers:event.modifierFlags button:button extra:extra];
}

- (void)sendMouse:(NSString *)type atWindowPoint:(NSPoint)windowPoint modifiers:(NSEventModifierFlags)modifiers button:(NSUInteger)button extra:(nullable NSDictionary<NSString *, id> *)extra {
    NSPoint point = [self convertPoint:windowPoint fromView:nil];
    // The screen's origin is its top left for the page, as the view's is.
    NSPoint onScreen = self.window ? [self.window convertPointToScreen:windowPoint] : NSEvent.mouseLocation;
    CGFloat screenHeight = NSHeight(NSScreen.screens.firstObject.frame);
    NSMutableDictionary *fields = [NSMutableDictionary dictionaryWithDictionary:@{
        @"type": type,
        @"x": @(point.x),
        @"y": @(point.y),
        @"screenX": @(onScreen.x),
        @"screenY": @(screenHeight - onScreen.y),
        @"button": @(button),
        @"buttons": @(_pressedButtons),
        @"modifiers": @(RFXWireModifiers(modifiers)),
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

/// Every button the page takes for held comes up where the pointer is: something else, such as
/// a menu, has the mouse from here and the buttons' own releases with it.
- (void)releaseButtons {
    NSPoint point = self.window.mouseLocationOutsideOfEventStream;
    for (NSUInteger button = 1; button <= 4; button <<= 1) {
        if (_pressedButtons & button) {
            _pressedButtons &= ~button;
            [self sendMouse:@"up" atWindowPoint:point modifiers:NSEvent.modifierFlags button:button extra:@{@"clickCount": @1}];
        }
    }
    _controlClickIsSecondary = NO;
    _dragOrigin = nil;
}

- (void)mouseDown:(NSEvent *)event {
    // A click elsewhere ends a composition with the text it has.
    if (self.hasMarkedText) {
        [self unmarkText];
        [[super inputContext] discardMarkedText];
    }
    _controlClickIsSecondary = (event.modifierFlags & NSEventModifierFlagControl) != 0;
    _dragOrigin = _controlClickIsSecondary ? nil : event;
    [self buttonDown:_controlClickIsSecondary ? 2 : 1 event:event];
}

- (void)mouseUp:(NSEvent *)event {
    [self buttonUp:_controlClickIsSecondary ? 2 : 1 event:event];
    _controlClickIsSecondary = NO;
    _dragOrigin = nil;
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
    if (_dragOrigin) {
        _dragOrigin = event;
    }
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

/// Runs a key through the input method and the system's key bindings. YES when the input method
/// used the key, which the page then hears of as composed text and never as a key.
- (BOOL)inputMethodTakesKey:(NSEvent *)event commands:(NSArray<NSString *> *_Nullable *_Nonnull)commands {
    NSEventModifierFlags flags = event.modifierFlags;
    // The system's key bindings name what a Control key does to text, such as
    // moveToBeginningOfParagraph: for ^A. Every other key is the engine's to interpret.
    BOOL followsBindings = (flags & NSEventModifierFlagControl) && !(flags & NSEventModifierFlagCommand);
    BOOL composes = _inputMethodEnabled && !(flags & NSEventModifierFlagCommand);
    if (!followsBindings && !composes) {
        return NO;
    }
    BOOL wasComposing = self.hasMarkedText;
    _keyCommands = [NSMutableArray array];
    _interpretedKey = event;
    _inputMethodTookKey = NO;
    _keyCameBackFromInputContext = NO;
    [self interpretKeyEvents:@[event]];
    // A key pressed during a composition is the input method's, whatever it did with it, and so
    // is one that never came back: the repeats of a held letter, which open its accents.
    BOOL taken = composes && (_inputMethodTookKey || wasComposing || self.hasMarkedText || !_keyCameBackFromInputContext);
    if (followsBindings) {
        *commands = _keyCommands;
    }
    _keyCommands = nil;
    _interpretedKey = nil;
    return taken;
}

- (void)sendKey:(NSEvent *)event down:(BOOL)down commands:(nullable NSArray<NSString *> *)commands {
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
        if (commands) {
            fields[@"commands"] = commands;
        }
        if (_pendingKeys.count >= RFXMaximumPendingKeys) {
            [_pendingKeys removeAllObjects];
        }
        _pendingKeys[@(identifier)] = event;
    }
    [_page send:@"key" fields:fields];
}

- (void)keyDown:(NSEvent *)event {
    NSArray<NSString *> *commands = nil;
    if (![self inputMethodTakesKey:event commands:&commands]) {
        [self sendKey:event down:YES commands:commands];
    }
}

- (void)keyUp:(NSEvent *)event {
    [self sendKey:event down:NO commands:nil];
}

/// The page sees a command key before Refrax's menus do, and the menus get it only if the page
/// leaves it alone.
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown || self.window.firstResponder != self || !_page) {
        return [super performKeyEquivalent:event];
    }
    [self keyDown:event];
    return YES;
}

- (void)doCommandBySelector:(SEL)selector {
    _keyCameBackFromInputContext = YES;
    [_keyCommands addObject:NSStringFromSelector(selector)];
}

// MARK: Text input

/// Only a page that takes composed text has an input context: elsewhere a key is a key, and an
/// input method composes nothing out of it.
- (NSTextInputContext *)inputContext {
    return _inputMethodEnabled ? [super inputContext] : nil;
}

- (void)setInputMethodState:(NSDictionary<NSString *, id> *)state {
    BOOL enabled = [state[@"enabled"] isEqual:@YES];
    if (!enabled && self.hasMarkedText) {
        _markedText = nil;
        [[super inputContext] discardMarkedText];
    }
    _inputMethodEnabled = enabled;
    _cursorPosition = [state[@"cursor"] isKindOfClass:[NSNumber class]] ? [state[@"cursor"] integerValue] : 0;
    _anchorPosition = [state[@"anchor"] isKindOfClass:[NSNumber class]] ? [state[@"anchor"] integerValue] : _cursorPosition;
    _textBeforeCursor = [state[@"textBefore"] isKindOfClass:[NSString class]] ? state[@"textBefore"] : @"";
    _textAfterCursor = [state[@"textAfter"] isKindOfClass:[NSString class]] ? state[@"textAfter"] : @"";
    NSArray *caret = [state[@"caret"] isKindOfClass:[NSArray class]] && [state[@"caret"] count] == 4 ? state[@"caret"] : nil;
    _caretRect = NSZeroRect;
    if (caret && [caret[0] isKindOfClass:[NSNumber class]] && [caret[1] isKindOfClass:[NSNumber class]]
        && [caret[2] isKindOfClass:[NSNumber class]] && [caret[3] isKindOfClass:[NSNumber class]]) {
        _caretRect = NSMakeRect([caret[0] doubleValue], [caret[1] doubleValue], MAX(1, [caret[2] doubleValue]), MAX(1, [caret[3] doubleValue]));
    }
    [[super inputContext] invalidateCharacterCoordinates];
}

static NSString *RFXPlainText(id string) {
    return [string isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString *)string string] : ([string isKindOfClass:[NSString class]] ? string : @"");
}

/// Text for the page from the input method, or from anything else that types: the Character
/// Viewer, dictation, a press-and-hold accent.
- (void)commitText:(NSString *)text replacementRange:(NSRange)replacementRange {
    _inputMethodTookKey = YES;
    _markedText = nil;
    // The range to replace is counted from the caret, in UTF-16 code units.
    NSInteger start = 0;
    NSUInteger length = 0;
    if (replacementRange.location != NSNotFound) {
        start = (NSInteger)replacementRange.location - _cursorPosition;
        length = replacementRange.length;
    }
    [_page send:@"insertText" fields:@{@"text": text, @"replacementStart": @(start), @"replacementLength": @(length)}];
    [_page send:@"composition" fields:@{@"text": @""}];
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    NSString *text = RFXPlainText(string);
    // A key that types its own character reaches the page as that key.
    if (_interpretedKey && !self.hasMarkedText && replacementRange.location == NSNotFound && [text isEqualToString:_interpretedKey.characters]) {
        _keyCameBackFromInputContext = YES;
        return;
    }
    [self commitText:text replacementRange:replacementRange];
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
    NSString *text = RFXPlainText(string);
    _inputMethodTookKey = YES;
    if (!self.hasMarkedText) {
        _markedStart = MIN(_cursorPosition, _anchorPosition);
    }
    _markedText = text.length > 0 ? [text copy] : nil;
    _markedSelection = selectedRange.location == NSNotFound ? NSMakeRange(text.length, 0) : selectedRange;
    [_page send:@"composition" fields:@{@"text": text}];
}

- (void)unmarkText {
    if (self.hasMarkedText) {
        [self commitText:_markedText replacementRange:NSMakeRange(NSNotFound, 0)];
    }
}

- (BOOL)hasMarkedText {
    return _markedText.length > 0;
}

- (NSRange)markedRange {
    return self.hasMarkedText ? NSMakeRange((NSUInteger)MAX(0, _markedStart), _markedText.length) : NSMakeRange(NSNotFound, 0);
}

- (NSRange)selectedRange {
    if (self.hasMarkedText) {
        return NSMakeRange((NSUInteger)MAX(0, _markedStart) + _markedSelection.location, _markedSelection.length);
    }
    NSInteger start = MAX(0, MIN(_cursorPosition, _anchorPosition));
    return NSMakeRange((NSUInteger)start, (NSUInteger)(MAX(_cursorPosition, _anchorPosition) - start));
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
    return @[];
}

/// The host sends the text around the caret, which is all of the page's text there is to give.
- (nullable NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(nullable NSRangePointer)actualRange {
    NSString *around = [_textBeforeCursor stringByAppendingString:_textAfterCursor];
    NSInteger first = _cursorPosition - (NSInteger)_textBeforeCursor.length;
    if (first < 0 || range.location == NSNotFound) {
        return nil;
    }
    NSRange held = NSIntersectionRange(range, NSMakeRange((NSUInteger)first, around.length));
    if (held.length == 0) {
        return nil;
    }
    if (actualRange) {
        *actualRange = held;
    }
    return [[NSAttributedString alloc] initWithString:[around substringWithRange:NSMakeRange(held.location - (NSUInteger)first, held.length)]];
}

/// Where the input method puts its candidates: at the caret.
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(nullable NSRangePointer)actualRange {
    if (actualRange) {
        *actualRange = range;
    }
    if (!self.window) {
        return NSZeroRect;
    }
    NSRect caret = NSIsEmptyRect(_caretRect) ? NSMakeRect(0, 0, 1, 1) : _caretRect;
    return [self.window convertRectToScreen:[self convertRect:caret toView:nil]];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    return NSNotFound;
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

// MARK: The context menu

- (void)showContextMenuWithItems:(NSArray<NSDictionary<NSString *, id> *> *)items identifier:(NSNumber *)identifier atPoint:(NSPoint)point {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    menu.autoenablesItems = NO;
    for (NSDictionary<NSString *, id> *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        if ([item[@"separator"] isEqual:@YES]) {
            [menu addItem:NSMenuItem.separatorItem];
            continue;
        }
        NSString *title = [item[@"title"] isKindOfClass:[NSString class]] ? item[@"title"] : nil;
        NSNumber *number = [item[@"item"] isKindOfClass:[NSNumber class]] ? item[@"item"] : nil;
        if (!title || !number) {
            continue;
        }
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title action:@selector(contextMenuItemWasChosen:) keyEquivalent:@""];
        menuItem.target = self;
        menuItem.representedObject = number;
        menuItem.enabled = ![item[@"enabled"] isEqual:@NO];
        [menu addItem:menuItem];
    }

    [self releaseButtons];
    // The menu runs a loop of its own until it closes, which the wire's handler is not held for.
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_contextMenuChoice = nil;
        if (self->_page && self.window && menu.numberOfItems > 0) {
            [menu popUpMenuPositioningItem:nil atLocation:point inView:self];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary<NSString *, id> *choice = [NSMutableDictionary dictionaryWithObject:identifier forKey:@"id"];
            choice[@"item"] = self->_contextMenuChoice;
            self->_contextMenuChoice = nil;
            [self->_page send:@"contextMenuChoice" fields:choice];
        });
    });
}

- (void)contextMenuItemWasChosen:(NSMenuItem *)item {
    _contextMenuChoice = item.representedObject;
}

// MARK: Dragging the page's content out

/// The first URL of a `text/uri-list` that another application may be handed as a link.
static NSString *_Nullable RFXFirstWebURL(NSString *list) {
    for (NSString *line in [list componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *candidate = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *scheme = [NSURL URLWithString:candidate].scheme.lowercaseString;
        if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
            return candidate;
        }
    }
    return nil;
}

/// What follows the pointer during a drag: the words that name what is dragged.
static NSImage *RFXDragLabel(NSString *text) {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize],
        NSForegroundColorAttributeName: NSColor.labelColor,
        NSParagraphStyleAttributeName: style,
    };
    const CGFloat inset = 6;
    NSSize textSize = [text sizeWithAttributes:attributes];
    NSSize size = NSMakeSize(ceil(MIN(textSize.width, RFXMaximumDragLabelWidth)) + inset * 2, ceil(textSize.height) + inset);
    return [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor.windowBackgroundColor colorWithAlphaComponent:0.9] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:inset yRadius:inset] fill];
        [text drawInRect:NSInsetRect(rect, inset, inset / 2) withAttributes:attributes];
        return YES;
    }];
}

- (void)beginDragWithItems:(NSArray<NSDictionary<NSString *, id> *> *)items title:(NSString *)title {
    // A drag is the user's: the primary button is down on the page and the pointer has moved
    // since it went down. A host that names a drag at any other time starts none.
    NSEvent *origin = _dragOrigin;
    if (origin.type != NSEventTypeLeftMouseDragged || !(_pressedButtons & 1) || !self.window) {
        return;
    }
    NSPasteboardItem *pasteboardItem = [[NSPasteboardItem alloc] init];
    NSString *link = nil;
    NSString *plain = nil;
    for (NSDictionary<NSString *, id> *item in items) {
        NSString *type = [item isKindOfClass:[NSDictionary class]] && [item[@"type"] isKindOfClass:[NSString class]] ? item[@"type"] : nil;
        NSString *value = type && [item[@"value"] isKindOfClass:[NSString class]] ? item[@"value"] : nil;
        if (value.length == 0) {
            continue;
        }
        if ([type isEqualToString:@"text/uri-list"]) {
            link = link ?: RFXFirstWebURL(value);
        } else if ([type isEqualToString:@"text/plain"]) {
            plain = plain ?: value;
        } else if ([type isEqualToString:@"text/html"]) {
            [pasteboardItem setString:value forType:NSPasteboardTypeHTML];
        }
    }
    if (link) {
        [pasteboardItem setString:link forType:NSPasteboardTypeURL];
        if (title.length > 0) {
            [pasteboardItem setString:title forType:@"public.url-name"];
        }
    }
    if (plain ?: link) {
        [pasteboardItem setString:plain ?: link forType:NSPasteboardTypeString];
    }
    if (pasteboardItem.types.count == 0) {
        return;
    }

    NSString *words = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSImage *label = RFXDragLabel(words.length > 0 ? words : (link ?: plain ?: @""));
    NSPoint point = [self convertPoint:origin.locationInWindow fromView:nil];
    NSDraggingItem *draggingItem = [[NSDraggingItem alloc] initWithPasteboardWriter:pasteboardItem];
    [draggingItem setDraggingFrame:NSMakeRect(point.x + 8, point.y + 8, label.size.width, label.size.height) contents:label];
    NSDraggingSession *session = [self beginDraggingSessionWithItems:@[draggingItem] event:origin source:self];
    session.animatesToStartingPositionsOnCancelOrFail = NO;
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationCopy | NSDragOperationLink | NSDragOperationGeneric;
}

/// The system's drag has the mouse, so the page hears of the pointer from the drag: its own
/// drag-and-drop goes on from these, over the page and off it.
- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint {
    if (self.window) {
        [self sendMouse:@"move" atWindowPoint:[self.window convertPointFromScreen:screenPoint] modifiers:NSEvent.modifierFlags button:0 extra:nil];
    }
}

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
    _dragOrigin = nil;
    if (!(_pressedButtons & 1) || !self.window) {
        return;
    }
    // The button's release drops on the page what ended over it, and ends the page's drag anywhere else.
    _pressedButtons &= ~(NSUInteger)1;
    [self sendMouse:@"up" atWindowPoint:[self.window convertPointFromScreen:screenPoint] modifiers:NSEvent.modifierFlags button:1 extra:@{@"clickCount": @1}];
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

// MARK: Accessibility

- (void)requestAccessibilityTree {
    if (_accessibilityRequested || !_page) {
        return;
    }
    _accessibilityRequested = YES;
    [_page send:@"accessibility" fields:@{@"enabled": @YES}];
}

- (void)setAccessibilityNodes:(NSArray<NSDictionary<NSString *, id> *> *)nodes root:(NSNumber *)root {
    // An element keeps its identity across updates, so an assistive technology's cursor stays on it.
    NSMutableDictionary<NSNumber *, RFXRemoteAccessibilityElement *> *elements = [NSMutableDictionary dictionaryWithCapacity:nodes.count];
    for (NSDictionary<NSString *, id> *node in nodes) {
        NSNumber *identifier = node[@"id"];
        if (![node isKindOfClass:[NSDictionary class]] || ![identifier isKindOfClass:[NSNumber class]]) {
            continue;
        }
        RFXRemoteAccessibilityElement *element = _accessibilityElements[identifier]
            ?: [[RFXRemoteAccessibilityElement alloc] initWithIdentifier:identifier view:self];
        element.node = node;
        element.parentElement = nil;
        elements[identifier] = element;
    }
    _accessibilityElements = elements;
    for (RFXRemoteAccessibilityElement *element in elements.objectEnumerator) {
        [self linkChildrenOfAccessibilityElement:element];
    }
    _accessibilityRoot = root ? elements[root] : nil;
    _accessibilityRoot.parentElement = nil;
    NSAccessibilityPostNotification(self, NSAccessibilityLayoutChangedNotification);
}

/// Gives `element` the children its node names. A node has one parent: the first that names it.
- (void)linkChildrenOfAccessibilityElement:(RFXRemoteAccessibilityElement *)element {
    NSMutableArray<RFXRemoteAccessibilityElement *> *children = [NSMutableArray array];
    NSArray *childIdentifiers = element.node[@"children"];
    if ([childIdentifiers isKindOfClass:[NSArray class]]) {
        for (NSNumber *childIdentifier in childIdentifiers) {
            RFXRemoteAccessibilityElement *child = [childIdentifier isKindOfClass:[NSNumber class]] ? _accessibilityElements[childIdentifier] : nil;
            if (child && child != element && child != _accessibilityRoot && (!child.parentElement || child.parentElement == element) && ![children containsObject:child]) {
                child.parentElement = element;
                [children addObject:child];
            }
        }
    }
    element.childElements = children;
}

- (void)changeAccessibilityNodes:(NSArray<NSDictionary<NSString *, id> *> *)nodes removing:(NSArray<NSNumber *> *)removed {
    for (NSNumber *identifier in removed) {
        if ([identifier isKindOfClass:[NSNumber class]] && _accessibilityElements[identifier] != _accessibilityRoot) {
            _accessibilityElements[identifier] = nil;
        }
    }
    NSMutableArray<RFXRemoteAccessibilityElement *> *changed = [NSMutableArray arrayWithCapacity:nodes.count];
    for (NSDictionary<NSString *, id> *node in nodes) {
        NSNumber *identifier = [node isKindOfClass:[NSDictionary class]] ? node[@"id"] : nil;
        if (![identifier isKindOfClass:[NSNumber class]]) {
            continue;
        }
        RFXRemoteAccessibilityElement *element = _accessibilityElements[identifier];
        if (!element) {
            element = [[RFXRemoteAccessibilityElement alloc] initWithIdentifier:identifier view:self];
            _accessibilityElements[identifier] = element;
        }
        element.node = node;
        // The children it had are free for whichever changed node names them now.
        for (RFXRemoteAccessibilityElement *child in element.childElements) {
            if (child.parentElement == element) {
                child.parentElement = nil;
            }
        }
        [changed addObject:element];
    }
    for (RFXRemoteAccessibilityElement *element in changed) {
        [self linkChildrenOfAccessibilityElement:element];
    }
    NSAccessibilityPostNotification(self, NSAccessibilityLayoutChangedNotification);
}

- (void)performAccessibilityAction:(NSString *)action onNode:(NSNumber *)node {
    [_page send:@"accessibilityAction" fields:@{@"node": node, @"action": action}];
}

- (BOOL)isAccessibilityElement {
    return NO;
}

- (NSArray *)accessibilityChildren {
    [self requestAccessibilityTree];
    return _accessibilityRoot ? @[_accessibilityRoot] : @[];
}

- (id)accessibilityHitTest:(NSPoint)point {
    [self requestAccessibilityTree];
    if (!_accessibilityRoot || !self.window) {
        return [super accessibilityHitTest:point];
    }
    NSPoint inView = [self convertPoint:[self.window convertPointFromScreen:point] fromView:nil];
    return [_accessibilityRoot elementAtPoint:inView];
}

- (id)accessibilityFocusedUIElement {
    for (RFXRemoteAccessibilityElement *element in _accessibilityElements.objectEnumerator) {
        if (element.isAccessibilityFocused) {
            return element;
        }
    }
    return _accessibilityRoot ?: [super accessibilityFocusedUIElement];
}

@end
