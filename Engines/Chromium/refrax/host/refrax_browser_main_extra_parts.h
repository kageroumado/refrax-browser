// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_REFRAX_BROWSER_MAIN_EXTRA_PARTS_H_
#define REFRAX_HOST_REFRAX_BROWSER_MAIN_EXTRA_PARTS_H_

#include <memory>

#include "chrome/browser/chrome_browser_main_extra_parts.h"

class ScopedKeepAlive;

namespace refrax {

class EngineConnection;
class EngineHostImpl;

// Turns a browser process launched with --refrax-bootstrap into an engine host: connects to
// the client once the browser has started, keeps the process alive with no windows, and quits
// when the client goes away.
class RefraxBrowserMainExtraParts : public ChromeBrowserMainExtraParts {
 public:
  RefraxBrowserMainExtraParts();
  RefraxBrowserMainExtraParts(const RefraxBrowserMainExtraParts&) = delete;
  RefraxBrowserMainExtraParts& operator=(const RefraxBrowserMainExtraParts&) =
      delete;
  ~RefraxBrowserMainExtraParts() override;

  // ChromeBrowserMainExtraParts:
  void PreEarlyInitialization() override;
  void PostBrowserStart() override;
  void PostMainMessageLoopRun() override;

 private:
  void OnClientDisconnected();

  std::unique_ptr<ScopedKeepAlive> keep_alive_;
  std::unique_ptr<EngineConnection> connection_;
  std::unique_ptr<EngineHostImpl> engine_;
};

}  // namespace refrax

#endif  // REFRAX_HOST_REFRAX_BROWSER_MAIN_EXTRA_PARTS_H_
