// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_SECRET_KEY_PROVIDER_H_
#define REFRAX_HOST_SECRET_KEY_PROVIDER_H_

#include "components/os_crypt/async/browser/key_provider.h"

namespace refrax {

// Chromium's storage encryption key (os_crypt_async: cookies, saved form data), from Refrax's
// keychain as the contract's `storageKey` secret, used as an AES-256-GCM key. It is the host's
// only key provider: Chromium's own would create and read a keychain item under the host's code
// signature, and an engine update signed differently would stop every load at a keychain prompt
// the host has no window for.
class SecretKeyProvider : public os_crypt_async::KeyProvider {
 public:
  SecretKeyProvider();
  ~SecretKeyProvider() override;

  // os_crypt_async::KeyProvider:
  void GetKey(KeyCallback callback) override;
  bool UseForEncryption() override;
};

}  // namespace refrax

#endif  // REFRAX_HOST_SECRET_KEY_PROVIDER_H_
