// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/secret_key_provider.h"

#include <optional>
#include <string>
#include <vector>

#include "base/functional/bind.h"
#include "base/types/expected.h"
#include "components/os_crypt/async/common/algorithm.mojom.h"
#include "components/os_crypt/async/common/encryptor.h"
#include "refrax/host/engine_requests.h"
#include "refrax/host/secrets.h"

namespace refrax {

namespace {

// Prefixes everything encrypted with the key, naming the provider that can decrypt it.
constexpr char kKeyTag[] = "rfx1";

static_assert(secrets::kSecretSize == os_crypt_async::Encryptor::Key::kAES256GCMKeySize);

}  // namespace

SecretKeyProvider::SecretKeyProvider() = default;
SecretKeyProvider::~SecretKeyProvider() = default;

void SecretKeyProvider::GetKey(KeyCallback callback) {
  EngineRequests::Get().Send(
      secrets::Request(secrets::kStorageKey),
      base::BindOnce(
          [](KeyCallback callback, const std::string& answer) {
            std::optional<std::vector<uint8_t>> secret = secrets::ParseAnswer(answer);
            if (!secret) {
              // Temporarily: data already encrypted with the key stays, for when Refrax can
              // read its keychain again.
              std::move(callback).Run(
                  kKeyTag, base::unexpected(KeyError::kTemporarilyUnavailable));
              return;
            }
            std::move(callback).Run(
                kKeyTag, os_crypt_async::Encryptor::Key(
                             *secret, os_crypt_async::mojom::Algorithm::kAES256GCM));
          },
          std::move(callback)));
}

bool SecretKeyProvider::UseForEncryption() {
  return true;
}

}  // namespace refrax
