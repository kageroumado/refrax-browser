// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/permission_prompt.h"

#include <optional>
#include <set>
#include <utility>

#include "base/functional/bind.h"
#include "base/task/single_thread_task_runner.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_uma_util.h"
#include "components/permissions/request_type.h"
#include "components/permissions/resolvers/permission_prompt_options.h"
#include "refrax/host/contract_json.h"
#include "url/origin.h"

namespace refrax {

namespace {

// The contract's permission kind for a set of Chrome requests shown together, or nullopt when
// the contract has none (the engine then denies).
std::optional<std::string_view> ContractKind(
    const std::vector<std::unique_ptr<permissions::PermissionRequest>>& requests) {
  std::set<permissions::RequestType> types;
  for (const auto& request : requests) {
    types.insert(request->request_type());
  }
  using permissions::RequestType;
  if (types == std::set{RequestType::kCameraStream, RequestType::kMicStream}) {
    return "cameraAndMicrophone";
  }
  if (types.size() != 1) {
    return std::nullopt;
  }
  switch (*types.begin()) {
    case RequestType::kCameraStream:
      return "camera";
    case RequestType::kMicStream:
      return "microphone";
    case RequestType::kGeolocation:
      return "geolocation";
    case RequestType::kNotifications:
      return "notifications";
    case RequestType::kClipboard:
      return "clipboardRead";
    default:
      return std::nullopt;
  }
}

}  // namespace

// static
permissions::PermissionPrompt::Factory PermissionPrompt::Factory(RequestSender sender) {
  return base::BindRepeating(
      [](RequestSender sender, content::WebContents*,
         permissions::PermissionPrompt::Delegate* delegate)
          -> std::unique_ptr<permissions::PermissionPrompt> {
        return std::make_unique<PermissionPrompt>(delegate, sender);
      },
      std::move(sender));
}

PermissionPrompt::PermissionPrompt(Delegate* delegate, RequestSender sender)
    : delegate_(delegate->GetWeakPtr()) {
  std::optional<std::string_view> kind = ContractKind(delegate->Requests());
  if (!kind) {
    // Deciding while the request manager is still creating this prompt would re-enter it.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&PermissionPrompt::Decide,
                                  weak_factory_.GetWeakPtr(), /*allow=*/false));
    return;
  }
  base::DictValue fields;
  fields.Set("kind", *kind);
  fields.Set("origin", url::Origin::Create(delegate->GetRequestingOrigin()).Serialize());
  sender.Run(contract::Message("permission", std::move(fields)),
             base::BindOnce(&PermissionPrompt::OnAnswer, weak_factory_.GetWeakPtr()));
}

PermissionPrompt::~PermissionPrompt() = default;

void PermissionPrompt::OnAnswer(const std::string& answer) {
  auto message = contract::ParseMessage(answer);
  Decide(message && message->first == "allow");
}

void PermissionPrompt::Decide(bool allow) {
  if (!delegate_) {
    return;
  }
  const ::PromptOptions options = std::monostate();
  allow ? delegate_->Accept(options) : delegate_->Deny(options);
}

bool PermissionPrompt::UpdateAnchor() {
  return true;
}

permissions::PermissionPrompt::TabSwitchingBehavior
PermissionPrompt::GetTabSwitchingBehavior() {
  // The question stays with its page in Refrax, shown when the page is.
  return kKeepPromptAlive;
}

permissions::PermissionPromptDisposition PermissionPrompt::GetPromptDisposition() const {
  return permissions::PermissionPromptDisposition::NOT_APPLICABLE;
}

bool PermissionPrompt::IsAskPrompt() const {
  return false;
}

std::optional<gfx::Rect> PermissionPrompt::GetViewBoundsInScreen() const {
  return std::nullopt;
}

bool PermissionPrompt::ShouldFinalizeRequestAfterDecided() const {
  return true;
}

std::vector<permissions::ElementAnchoredBubbleVariant> PermissionPrompt::GetPromptVariants()
    const {
  return {};
}

std::optional<permissions::feature_params::PermissionElementPromptPosition>
PermissionPrompt::GetPromptPosition() const {
  return std::nullopt;
}

}  // namespace refrax
