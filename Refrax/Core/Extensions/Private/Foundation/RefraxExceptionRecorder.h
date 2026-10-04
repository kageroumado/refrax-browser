/**
 * RefraxExceptionRecorder.h
 * Refrax Browser
 *
 * Records the most recent Objective-C exceptions to a file as they are thrown.
 *
 * AppKit ends the process on an exception raised during layout or event
 * handling by calling +[NSApplication _crashOnException:], which traps
 * without invoking the uncaught-exception handler. The resulting .ips keeps
 * the backtrace and drops the exception's name and reason. An exception
 * preprocessor runs inside objc_exception_throw for every throw, caught or
 * not, so it sees the exception before AppKit's trap; each record is written
 * synchronously, and the file on disk always holds the last few throws.
 */

@import Foundation;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

/// Installs the exception preprocessor, chaining to the one already
/// installed (CoreFoundation's, which fills in the call stack).
///
/// Truncates the file at @c path and rewrites it after every recorded throw
/// with the newest records last. Call early in launch; a later call starts an
/// empty record set in its own file and keeps the one preprocessor.
void RefraxExceptionRecorderInstall(NSString *path);

NS_HEADER_AUDIT_END(nullability, sendability)
