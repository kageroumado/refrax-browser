// RFXEngine.h — binary interface between Refrax and an engine bundle.
//
// Engine contract 1.x. The message schema (every JSON payload named below) is
// specified in Engines/CONTRACT.md; this header only carries it.
//
// An engine is a loadable bundle (`<Name>.engine`) whose principal class
// conforms to RFXEngineHost. Refrax reads the bundle's Info.plist (see the
// RFXEngineInfoKey constants) and verifies its code signature before loading
// any of its code. Every method is called on the main thread, and every
// delegate callback must be delivered on the main thread.
//
// This header must stay free of C++ so both Swift and engine code can import it.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Info.plist keys

typedef NSString *RFXEngineInfoKey NS_TYPED_ENUM;
/// "1.0": the contract version the engine implements.
static RFXEngineInfoKey const RFXEngineInfoContractVersion = @"RFXEngineContractVersion";
/// Name shown in Settings → Engines, e.g. "Chromium".
static RFXEngineInfoKey const RFXEngineInfoDisplayName = @"RFXEngineDisplayName";
/// Version of the rendering engine itself, e.g. "Chromium 155.0.8059.12".
static RFXEngineInfoKey const RFXEngineInfoEngineVersion = @"RFXEngineVersion";
static RFXEngineInfoKey const RFXEngineInfoVendor = @"RFXEngineVendor";
/// Array of capability names (CONTRACT.md §Capabilities).
static RFXEngineInfoKey const RFXEngineInfoCapabilities = @"RFXEngineCapabilities";
/// Boolean: whether pages render in processes separate from Refrax.
static RFXEngineInfoKey const RFXEngineInfoOutOfProcess = @"RFXEngineOutOfProcess";

// MARK: - Delegates (implemented by Refrax)

@protocol RFXEnginePage;

NS_SWIFT_UI_ACTOR
@protocol RFXEngineHostDelegate <NSObject>
/// The engine's processes are gone; every page it hosted is dead.
- (void)engineHostDidTerminateWithReason:(NSString *)reason;
@end

NS_SWIFT_UI_ACTOR
@protocol RFXEnginePageDelegate <NSObject>
/// `event`: UTF-8 JSON of one PageEvent.
- (void)enginePage:(id<RFXEnginePage>)page didEmitEvent:(NSData *)event;
/// `request`: JSON PageRequestKind. `reply` takes JSON PageRequestAnswer and must be called once.
- (void)enginePage:(id<RFXEnginePage>)page
        didRequest:(NSData *)request
             reply:(void (^)(NSData *answer))reply;
/// `message`: JSON ScriptMessage posted by a Refrax-injected script.
- (void)enginePage:(id<RFXEnginePage>)page didReceiveScriptMessage:(NSData *)message;
@end

// MARK: - Engine (implemented by the engine)

NS_SWIFT_UI_ACTOR
@protocol RFXEngineHost <NSObject>
- (instancetype)init;

@property (nonatomic, weak, nullable) id<RFXEngineHostDelegate> delegate;

/// `configuration`: JSON EngineConfiguration. Calls `completion` once, with nil on success.
- (void)startWithConfiguration:(NSData *)configuration
                    completion:(void (^)(NSError *_Nullable error))completion;

/// `spec`: JSON EnginePageSpec.
- (nullable id<RFXEnginePage>)makePageWithSpec:(NSData *)spec error:(NSError *_Nullable *_Nullable)error;

/// `update`: JSON PolicyUpdate. Applies to existing and future pages.
- (void)applyPolicy:(NSData *)update;

/// `profile`: JSON EngineProfileSpec. Deletes everything stored for it.
- (void)removeProfile:(NSData *)profile completion:(void (^)(void))completion;

/// Closes every page and stops the engine. Called once, at quit or before an update.
- (void)shutdown;
@end

NS_SWIFT_UI_ACTOR
@protocol RFXEnginePage <NSObject>
/// The view that displays the page. Refrax re-parents it; the page owns it.
@property (nonatomic, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<RFXEnginePageDelegate> delegate;

/// `command`: JSON PageCommand.
- (void)performCommand:(NSData *)command;

/// `request`: JSON ScriptRequest. Completes with JSON ScriptValue or an error.
- (void)evaluateScript:(NSData *)request
            completion:(void (^)(NSData *_Nullable result, NSError *_Nullable error))completion;

/// Renders `rect` (view coordinates; NSZeroRect for the whole view) into an image.
- (void)snapshotRect:(NSRect)rect
          completion:(void (^)(CGImageRef _Nullable image, NSError *_Nullable error))completion;

/// Tears the page down. No delegate callbacks follow.
- (void)close;
@end

NS_ASSUME_NONNULL_END
