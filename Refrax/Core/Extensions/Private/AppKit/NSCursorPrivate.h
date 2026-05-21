@import AppKit;

NS_ASSUME_NONNULL_BEGIN

@interface NSCursor (Private)

/// Sets an override cursor that takes precedence over normal cursor changes.
/// This cursor persists until explicitly cleared with _clearOverrideCursorAndSetArrow.
+ (void)_setOverrideCursor:(NSCursor *)cursor;

/// Sets an override cursor with a type hint.
+ (void)_setOverrideCursor:(NSCursor *)cursor type:(NSInteger)type;

/// Clears the override cursor and sets the arrow cursor.
+ (void)_clearOverrideCursorAndSetArrow;

/// Returns the current override help cursor if set.
+ (nullable NSCursor *)_overrideHelpCursor;

/// Forcefully sets this cursor, potentially overriding other cursor mechanisms.
- (instancetype)forceSet;

/// Actually sets the cursor at the system level.
- (void)_reallySet;

@end

NS_ASSUME_NONNULL_END
