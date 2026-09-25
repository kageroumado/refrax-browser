// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.
//
// engine-harness: drives an engine bundle through RFXEngine.h the way Refrax does, without
// Refrax. Loads the bundle, starts it, opens one page in a window, prints every event, request
// and script message as a JSON line on stdout, and answers requests the way a user would
// (openURL: handled; permissions: deny; dialogs: confirm with "harness"; downloads: saved to
// <storage>/Downloads/<suggested name>).
//
//   engine-harness <path/to/X.engine> <url> [--storage DIR] [--policy FILE] [--eval JS]
//                  [--world NAME] [--gesture] [--seconds N]
//
// --policy sends each PolicyUpdate in FILE (a JSON array) before the page opens; --world makes
// --eval run in that isolated world. Script messages are answered with their own body.
//
// Exits 0 after --seconds (default 20), 1 if the engine fails to start.

#import <AppKit/AppKit.h>

#import "RFXEngine.h"

static void Emit(NSString* kind, NSData* json) {
  NSString* body = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"null";
  printf("{\"%s\":%s}\n", kind.UTF8String, body.UTF8String);
  fflush(stdout);
}

static void Note(NSString* message) {
  printf("{\"harness\":\"%s\"}\n", [message stringByReplacingOccurrencesOfString:@"\""
                                                                   withString:@"'"]
                                       .UTF8String);
  fflush(stdout);
}

@interface Harness : NSObject <NSApplicationDelegate, RFXEngineHostDelegate, RFXEnginePageDelegate>
@property(nonatomic) NSURL* engineURL;
@property(nonatomic) NSString* url;
@property(nonatomic) NSURL* storage;
@property(nonatomic) NSString* script;
@property(nonatomic) NSString* world;
@property(nonatomic) BOOL gesture;
@property(nonatomic) NSString* policyPath;
@property(nonatomic) NSTimeInterval seconds;
@property(nonatomic) id<RFXEngineHost> engine;
@property(nonatomic) id<RFXEnginePage> page;
@property(nonatomic) NSWindow* window;
@end

@implementation Harness

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  NSBundle* bundle = [NSBundle bundleWithURL:self.engineURL];
  NSError* error = nil;
  if (![bundle loadAndReturnError:&error]) {
    Note([@"load failed: " stringByAppendingString:error.localizedDescription]);
    exit(1);
  }
  Class principal = bundle.principalClass;
  if (![principal conformsToProtocol:@protocol(RFXEngineHost)]) {
    Note(@"principal class does not conform to RFXEngineHost");
    exit(1);
  }
  self.engine = [[principal alloc] init];
  self.engine.delegate = self;

  NSDictionary* configuration = @{
    @"storageDirectory" : self.storage.absoluteString,
    @"logFile" : [self.storage URLByAppendingPathComponent:@"engine.log"].absoluteString,
    @"languages" : @[ @"en-US" ],
  };
  NSData* configurationData = [NSJSONSerialization dataWithJSONObject:configuration
                                                              options:0
                                                                error:nil];
  NSDate* started = [NSDate date];
  Note(@"starting");
  [self.engine startWithConfiguration:configurationData
                           completion:^(NSError* startError) {
                             if (startError) {
                               Note([@"start failed: "
                                   stringByAppendingString:startError.localizedDescription]);
                               exit(1);
                             }
                             Note([NSString stringWithFormat:@"started in %.2fs",
                                                             -started.timeIntervalSinceNow]);
                             [self applyPolicy];
                             [self openPage];
                           }];
  [NSTimer scheduledTimerWithTimeInterval:self.seconds
                                  repeats:NO
                                    block:^(NSTimer* timer) {
                                      [self.page close];
                                      [self.engine shutdown];
                                      Note(@"done");
                                      exit(0);
                                    }];
}

- (void)applyPolicy {
  if (!self.policyPath) {
    return;
  }
  NSArray* updates = [NSJSONSerialization
      JSONObjectWithData:[NSData dataWithContentsOfFile:self.policyPath]
                 options:0
                   error:nil];
  for (id update in updates) {
    [self.engine applyPolicy:[NSJSONSerialization dataWithJSONObject:update options:0 error:nil]];
  }
  Note([NSString stringWithFormat:@"applied %lu policy updates", (unsigned long)[updates count]]);
}

- (void)openPage {
  NSDictionary* spec = @{
    @"id" : NSUUID.UUID.UUIDString,
    @"profile" : @{@"shared" : @{}},
    @"initialURL" : self.url,
  };
  NSError* error = nil;
  self.page = [self.engine
      makePageWithSpec:[NSJSONSerialization dataWithJSONObject:spec options:0 error:nil]
                 error:&error];
  if (!self.page) {
    Note([@"makePage failed: " stringByAppendingString:error.localizedDescription]);
    exit(1);
  }
  self.page.delegate = self;
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 1200, 800)
                                            styleMask:NSWindowStyleMaskTitled |
                                                      NSWindowStyleMaskResizable
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  self.window.title = @"engine-harness";
  NSView* view = self.page.view;
  view.frame = self.window.contentView.bounds;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [self.window.contentView addSubview:view];
  [self.window makeKeyAndOrderFront:nil];

  if (self.script) {
    [NSTimer scheduledTimerWithTimeInterval:self.seconds / 2
                                    repeats:NO
                                      block:^(NSTimer* timer) {
                                        [self evaluate];
                                      }];
  }
}

- (void)evaluate {
  NSDictionary* request = @{
    @"source" : self.script,
    @"world" : self.world ? @{@"isolated" : @{@"name" : self.world}} : @{@"page" : @{}},
    @"userGesture" : @(self.gesture),
  };
  [self.page evaluateScript:[NSJSONSerialization dataWithJSONObject:request options:0 error:nil]
                 completion:^(NSData* result, NSError* error) {
                   if (result) {
                     Emit(@"evaluated", result);
                   } else {
                     Note([@"evaluate failed: "
                         stringByAppendingString:error.localizedDescription]);
                   }
                 }];
}

// MARK: RFXEngineHostDelegate

- (void)engineHostDidTerminateWithReason:(NSString*)reason {
  Note([@"engine terminated: " stringByAppendingString:reason]);
}

// MARK: RFXEnginePageDelegate

- (void)enginePage:(id<RFXEnginePage>)page didEmitEvent:(NSData*)event {
  Emit(@"event", event);
}

- (void)enginePage:(id<RFXEnginePage>)page
        didRequest:(NSData*)request
             reply:(void (^)(NSData*))reply {
  Emit(@"request", request);
  NSDictionary* parsed = [NSJSONSerialization JSONObjectWithData:request options:0 error:nil];
  NSString* kind = parsed.allKeys.firstObject;
  NSDictionary* answer = @{@"cancel" : @{}};
  if ([kind isEqualToString:@"openURL"]) {
    answer = @{@"handled" : @{}};
  } else if ([kind isEqualToString:@"permission"]) {
    answer = @{@"deny" : @{}};
  } else if ([kind isEqualToString:@"javaScriptDialog"]) {
    answer = @{@"confirm" : @{@"text" : @"harness"}};
  } else if ([kind isEqualToString:@"download"]) {
    NSURL* folder = [self.storage URLByAppendingPathComponent:@"Downloads" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    NSString* name = parsed[kind][@"suggestedFilename"] ?: @"download";
    answer = @{@"saveTo" : @{@"url" : [folder URLByAppendingPathComponent:name].absoluteString}};
  }
  reply([NSJSONSerialization dataWithJSONObject:answer options:0 error:nil]);
}

- (void)enginePage:(id<RFXEnginePage>)page
    didReceiveScriptMessage:(NSData*)message
                      reply:(void (^)(NSData*))reply {
  Emit(@"scriptMessage", message);
  NSDictionary* parsed = [NSJSONSerialization JSONObjectWithData:message options:0 error:nil];
  id body = parsed[@"body"] ?: NSNull.null;
  reply([NSJSONSerialization dataWithJSONObject:@{@"value" : @{@"value" : body}}
                                        options:NSJSONWritingFragmentsAllowed
                                          error:nil]);
}

@end

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    NSArray<NSString*>* arguments = NSProcessInfo.processInfo.arguments;
    if (arguments.count < 3) {
      fprintf(stderr,
              "usage: engine-harness <X.engine> <url> [--storage DIR] [--eval JS] "
              "[--seconds N]\n");
      return 2;
    }
    Harness* harness = [[Harness alloc] init];
    harness.engineURL = [NSURL fileURLWithPath:arguments[1]];
    harness.url = arguments[2];
    harness.seconds = 20;
    harness.storage = [NSURL fileURLWithPath:[NSTemporaryDirectory()
                                                 stringByAppendingPathComponent:@"engine-harness"]
                                 isDirectory:YES];
    harness.gesture = [arguments containsObject:@"--gesture"];
    for (NSUInteger i = 3; i + 1 < arguments.count; i += 2) {
      if ([arguments[i] isEqualToString:@"--gesture"]) {
        i -= 1;
        continue;
      }
      if ([arguments[i] isEqualToString:@"--storage"]) {
        harness.storage = [NSURL fileURLWithPath:arguments[i + 1] isDirectory:YES];
      } else if ([arguments[i] isEqualToString:@"--eval"]) {
        harness.script = arguments[i + 1];
      } else if ([arguments[i] isEqualToString:@"--world"]) {
        harness.world = arguments[i + 1];
      } else if ([arguments[i] isEqualToString:@"--policy"]) {
        harness.policyPath = arguments[i + 1];
      } else if ([arguments[i] isEqualToString:@"--seconds"]) {
        harness.seconds = arguments[i + 1].doubleValue;
      }
    }
    [NSFileManager.defaultManager createDirectoryAtURL:harness.storage
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    NSApplication* app = NSApplication.sharedApplication;
    app.activationPolicy = NSApplicationActivationPolicyRegular;
    app.delegate = harness;
    [app run];
  }
  return 0;
}
