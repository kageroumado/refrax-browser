// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#import "RFXRemoteAccessibility.h"

#import "RFXRemotePageView.h"

@implementation RFXRemoteAccessibilityElement {
    __weak RFXRemotePageView *_view;
}

- (instancetype)initWithIdentifier:(NSNumber *)identifier view:(RFXRemotePageView *)view {
    if ((self = [super init])) {
        _identifier = identifier;
        _view = view;
        _node = @{};
        _childElements = @[];
    }
    return self;
}

- (nullable NSString *)text:(NSString *)key {
    NSString *text = _node[key];
    return [text isKindOfClass:[NSString class]] && text.length > 0 ? text : nil;
}

/// The node's box in the view's coordinates: points from the view's top left.
- (NSRect)boxInView {
    NSArray<NSNumber *> *frame = _node[@"frame"];
    if (![frame isKindOfClass:[NSArray class]] || frame.count != 4) {
        return NSZeroRect;
    }
    return NSMakeRect(frame[0].doubleValue, frame[1].doubleValue, frame[2].doubleValue, frame[3].doubleValue);
}

- (RFXRemoteAccessibilityElement *)elementAtPoint:(NSPoint)point {
    for (RFXRemoteAccessibilityElement *child in _childElements.reverseObjectEnumerator) {
        if (NSPointInRect(point, child.boxInView)) {
            return [child elementAtPoint:point];
        }
    }
    return self;
}

// MARK: NSAccessibility

- (BOOL)isAccessibilityElement {
    return YES;
}

- (NSAccessibilityRole)accessibilityRole {
    return [self text:@"role"] ?: NSAccessibilityGroupRole;
}

- (NSAccessibilitySubrole)accessibilitySubrole {
    return [self text:@"subrole"];
}

- (NSString *)accessibilityRoleDescription {
    return [self text:@"roleDescription"] ?: NSAccessibilityRoleDescription(self.accessibilityRole, self.accessibilitySubrole);
}

- (NSString *)accessibilityLabel {
    return [self text:@"label"];
}

- (NSString *)accessibilityTitle {
    return [self text:@"title"];
}

- (id)accessibilityValue {
    return _node[@"value"];
}

- (NSString *)accessibilityHelp {
    return [self text:@"help"];
}

- (NSURL *)accessibilityURL {
    NSString *url = [self text:@"url"];
    return url ? [NSURL URLWithString:url] : nil;
}

- (BOOL)isAccessibilityEnabled {
    return ![_node[@"disabled"] boolValue];
}

- (BOOL)isAccessibilityFocused {
    return [_node[@"focused"] boolValue];
}

- (NSRect)accessibilityFrame {
    RFXRemotePageView *view = _view;
    if (!view.window) {
        return NSZeroRect;
    }
    return [view.window convertRectToScreen:[view convertRect:self.boxInView toView:nil]];
}

- (id)accessibilityParent {
    return _parentElement ?: NSAccessibilityUnignoredAncestor(_view);
}

- (NSArray *)accessibilityChildren {
    return _childElements;
}

- (id)accessibilityWindow {
    return _view.window;
}

- (id)accessibilityTopLevelUIElement {
    return _view.window;
}

- (BOOL)accessibilityPerformPress {
    [_view performAccessibilityAction:@"press" onNode:_identifier];
    return YES;
}

- (void)setAccessibilityFocused:(BOOL)focused {
    if (focused) {
        [_view performAccessibilityAction:@"focus" onNode:_identifier];
    }
}

@end
