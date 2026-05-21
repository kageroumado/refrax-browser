// # Refrax Application Entry Point
//
// This file bootstraps the Cocoa application using the modern programmatic pattern
// rather than `NSApplicationMain`.
//
// ## App Lifecycle Architecture
//
// ### The `NSApp` Global
//
// `NSApp` is a C global variable declared as `_Null_unspecified` (implicitly unwrapped
// optional in Swift). It starts as **nil** and is only populated when
// `NSApplication.shared` is accessed. This is why we must call `NSApplication.shared`
// before using `NSApp`—accessing `NSApp` directly would crash with nil dereference.
//
// ### `NSApplication.shared` (sharedApplication)
//
// The class method performs lazy initialization with double-checked locking:
//
// 1. Check `_isSharedApplicationInited` flag (fast path if already initialized)
// 2. Acquire `_NSAppKitLock` for thread safety
// 3. Double-check flag (DCL pattern)
// 4. Create instance via `[[principalClass allocWithZone:nil] init]`
// 5. Store instance to `_NSApp` global
// 6. Set initialized flag, release lock
// 7. Return `_NSApp`
//
// ### `NSApplication.run()`
//
// The run method enters the main event loop:
//
// 1. Call `_NSApplicationBeginRunning` (sets running flag, posts notifications)
// 2. Install memory pressure dispatch sources
// 3. Set `windowsNeedUpdate: true`
// 4. Enter event loop:
//    - Get run loop mode via `_outerRunLoopMode`
//    - Call `nextEventMatchingMask:untilDate:inMode:dequeue:`
//    - Dispatch event via `sendEvent:`
//    - Check running flag, loop until `stop:` or `terminate:`
// 5. Never returns under normal operation
//
// ### `NSApplicationMain` vs `NSApplication.shared.run()`
//
// `NSApplicationMain` is the traditional entry point that:
// - Reads `NSPrincipalClass`, `NSMainStoryboardFile`, `NSMainNibFile` from Info.plist
// - Creates the shared application instance
// - Loads main storyboard/nib if specified (sets delegate from outlets)
// - Calls `[NSApp run]`
// - Returns `Int32` (for C compatibility, though it never actually returns)
//
// For programmatic apps without a main nib/storyboard (like Refrax), calling
// `NSApplication.shared.run()` directly is equivalent and more explicit—no Info.plist
// parsing, no nib loading, clear control flow.
//
// ### Delegate Lifecycle Callbacks
//
// The delegate receives notifications in this order:
//
// 1. `applicationWillFinishLaunching:` — Before nib loaded (if any)
// 2. `applicationDidFinishLaunching:` — After nib, before event loop
// 3. `applicationDidBecomeActive:` — App activated
// 4. ... event loop runs ...
// 5. `applicationWillTerminate:` — App quitting
//
// ## Why This Pattern
//
// ```swift
// // This crashes—NSApp is nil until sharedApplication is called:
// NSApp.delegate = appDelegate
//
// // This works—sharedApplication creates instance and populates NSApp:
// let app = NSApplication.shared
// app.delegate = appDelegate
// app.run()
// ```
//
// The explicit pattern makes the initialization sequence clear and avoids the
// implicit side effects of `NSApplicationMain`.

import Cocoa

let arguments = CommandLine.Arguments()

if arguments.showHelp {
    CommandLine.printUsage()
    exit(0)
}

let app = NSApplication.shared
let appDelegate = AppDelegate(arguments: arguments)
app.delegate = appDelegate
app.run()
