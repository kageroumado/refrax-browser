// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_ENGINE_HOST_IMPL_H_
#define REFRAX_HOST_ENGINE_HOST_IMPL_H_

#include <map>
#include <memory>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/values.h"
#include "chrome/browser/profiles/profile.h"
#include "components/remote_cocoa/common/application.mojom.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "refrax/common/mojom/engine.mojom.h"
#include "refrax/host/world_registry.h"

class ScopedProfileKeepAlive;

namespace refrax {

class HostPage;

// The host's side of the engine contract: one per client connection. Maps Refrax's spaces to
// Chrome profiles and owns every page.
class EngineHostImpl : public mojom::EngineHost {
 public:
  EngineHostImpl(mojo::PendingReceiver<mojom::EngineHost> receiver,
                 base::OnceClosure on_disconnect);
  EngineHostImpl(const EngineHostImpl&) = delete;
  EngineHostImpl& operator=(const EngineHostImpl&) = delete;
  ~EngineHostImpl() override;

  // Where each page's NSViews are built: the client's remote_cocoa Application.
  remote_cocoa::mojom::Application* application() const {
    return application_.get();
  }

  // Script worlds, shared by every page so a named world is one world everywhere.
  WorldRegistry& worlds() { return worlds_; }

  // The latest `scripts` policy; pages created later start with it.
  const base::ListValue& scripts() const { return scripts_; }

  // Called by a page when the client closes it or the page closes itself.
  void DestroyPage(HostPage* page);

  // mojom::EngineHost:
  void Start(const std::string& configuration,
             mojo::PendingAssociatedRemote<remote_cocoa::mojom::Application>
                 application,
             StartCallback callback) override;
  void CreatePage(const std::string& spec,
                  mojo::PendingAssociatedReceiver<mojom::Page> page,
                  mojo::PendingAssociatedRemote<mojom::PageClient> client,
                  CreatePageCallback callback) override;
  void ApplyPolicy(const std::string& update) override;
  void RemoveProfile(const std::string& profile,
                     RemoveProfileCallback callback) override;

 private:
  // Resolves the contract's EngineProfileSpec to a profile, loading it if needed; runs
  // `callback` with nullptr for a spec it doesn't understand or a profile that failed to load.
  void ResolveProfile(const base::DictValue& spec,
                      base::OnceCallback<void(Profile*)> callback);
  void OnIsolatedProfileLoaded(const std::string& space_id,
                               base::OnceCallback<void(Profile*)> callback,
                               Profile* profile);
  void CreatePageInProfile(std::string page_id,
                           GURL initial_url,
                           mojo::PendingAssociatedReceiver<mojom::Page> page,
                           mojo::PendingAssociatedRemote<mojom::PageClient> client,
                           CreatePageCallback callback,
                           Profile* profile);

  mojo::Receiver<mojom::EngineHost> receiver_;
  mojo::AssociatedRemote<remote_cocoa::mojom::Application> application_;
  std::vector<std::unique_ptr<HostPage>> pages_;
  WorldRegistry worlds_;
  base::ListValue scripts_;

  // Isolated spaces, kept loaded while the client runs.
  std::map<std::string, std::unique_ptr<ScopedProfileKeepAlive>> isolated_spaces_;
  // Ephemeral spaces: one off-the-record profile each, discarded with the space.
  std::map<std::string, Profile::OTRProfileID> ephemeral_spaces_;

  base::WeakPtrFactory<EngineHostImpl> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_HOST_ENGINE_HOST_IMPL_H_
