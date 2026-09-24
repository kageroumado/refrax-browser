// Sub-process entry point shared by every Chromium helper app (GPU, renderer,
// plug-in, utility). The helper bundles sit next to the framework, which is the
// layout CefScopedLibraryLoader::LoadInHelper resolves ("../../..").

#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"

int main(int argc, char* argv[]) {
  CefScopedLibraryLoader libraryLoader;
  if (!libraryLoader.LoadInHelper()) {
    return 1;
  }
  CefMainArgs mainArgs(argc, argv);
  return CefExecuteProcess(mainArgs, nullptr, nullptr);
}
