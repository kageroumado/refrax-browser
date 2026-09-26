// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/secrets.h"

#include "base/base64.h"
#include "base/values.h"
#include "refrax/host/contract_json.h"

namespace refrax::secrets {

std::string Request(std::string_view name) {
  return contract::Message("secret", base::DictValue().Set("name", name));
}

std::optional<std::vector<uint8_t>> ParseAnswer(std::string_view answer) {
  std::optional<std::pair<std::string, base::DictValue>> message =
      contract::ParseMessage(answer);
  if (!message || message->first != "secret") {
    return std::nullopt;
  }
  const std::string* value = message->second.FindString("value");
  if (!value) {
    return std::nullopt;
  }
  std::optional<std::vector<uint8_t>> secret = base::Base64Decode(*value);
  if (!secret || secret->size() != kSecretSize) {
    return std::nullopt;
  }
  return secret;
}

}  // namespace refrax::secrets
