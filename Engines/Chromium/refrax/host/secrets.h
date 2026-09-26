// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_SECRETS_H_
#define REFRAX_HOST_SECRETS_H_

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// The contract's `secret` request (CONTRACT.md §4.6): key material Refrax keeps in its keychain
// for the engine, so the engine never creates keychain items of its own.
namespace refrax::secrets {

// The secret Chromium's stored data (cookies, saved form data) is encrypted with.
inline constexpr std::string_view kStorageKey = "storageKey";

// Every secret Refrax creates is this long.
inline constexpr size_t kSecretSize = 32;

// The request for the secret `name`.
std::string Request(std::string_view name);

// The secret in Refrax's answer, or nullopt when Refrax answered `unavailable`, or with anything
// other than a secret of kSecretSize bytes.
std::optional<std::vector<uint8_t>> ParseAnswer(std::string_view answer);

}  // namespace refrax::secrets

#endif  // REFRAX_HOST_SECRETS_H_
