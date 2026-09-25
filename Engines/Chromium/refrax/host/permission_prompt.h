// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_PERMISSION_PROMPT_H_
#define REFRAX_HOST_PERMISSION_PROMPT_H_

#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "components/permissions/permission_prompt.h"

namespace refrax {

// Chrome's permission prompt for a Refrax page: each request becomes the contract's
// `permission` request, which Refrax answers from the site's settings or by asking in the
// page's pane. A request the contract has no kind for is denied (CONTRACT.md §4.3).
class PermissionPrompt : public permissions::PermissionPrompt {
 public:
  // Sends a PageRequestKind (contract JSON); the callback takes the PageRequestAnswer.
  using RequestSender = base::RepeatingCallback<void(
      std::string request,
      base::OnceCallback<void(const std::string& answer)> answer)>;

  // The factory PermissionRequestManager calls for each request it would show.
  static permissions::PermissionPrompt::Factory Factory(RequestSender sender);

  PermissionPrompt(Delegate* delegate, RequestSender sender);
  PermissionPrompt(const PermissionPrompt&) = delete;
  PermissionPrompt& operator=(const PermissionPrompt&) = delete;
  ~PermissionPrompt() override;

  // permissions::PermissionPrompt:
  bool UpdateAnchor() override;
  TabSwitchingBehavior GetTabSwitchingBehavior() override;
  permissions::PermissionPromptDisposition GetPromptDisposition() const override;
  bool IsAskPrompt() const override;
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override;
  bool ShouldFinalizeRequestAfterDecided() const override;
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants()
      const override;
  std::optional<permissions::feature_params::PermissionElementPromptPosition>
  GetPromptPosition() const override;

 private:
  void Decide(bool allow);
  void OnAnswer(const std::string& answer);

  base::WeakPtr<Delegate> delegate_;
  base::WeakPtrFactory<PermissionPrompt> weak_factory_{this};
};

}  // namespace refrax

#endif  // REFRAX_HOST_PERMISSION_PROMPT_H_
