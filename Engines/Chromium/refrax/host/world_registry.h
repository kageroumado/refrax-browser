// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_WORLD_REGISTRY_H_
#define REFRAX_HOST_WORLD_REGISTRY_H_

#include <cstdint>
#include <map>
#include <optional>
#include <string>

#include "base/values.h"

namespace refrax {

// Maps the contract's script worlds to V8 world ids, stable for the host's life so a named
// world is the same world in every page and across policy updates.
class WorldRegistry {
 public:
  WorldRegistry();
  WorldRegistry(const WorldRegistry&) = delete;
  WorldRegistry& operator=(const WorldRegistry&) = delete;
  ~WorldRegistry();

  // The world id for a contract world ({"page":{}} or {"isolated":{"name":…}}), or nullopt for
  // anything else.
  std::optional<int32_t> WorldID(const base::DictValue& world);

 private:
  std::map<std::string, int32_t> isolated_;
};

}  // namespace refrax

#endif  // REFRAX_HOST_WORLD_REGISTRY_H_
