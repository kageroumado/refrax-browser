// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/world_registry.h"

#include "content/public/common/isolated_world_ids.h"

namespace refrax {

namespace {

// Refrax's isolated worlds, clear of content's and Chrome's fixed ids and of the ids
// extensions allocate upward from ISOLATED_WORLD_ID_EXTENSIONS, and below blink's embedder
// limit (1 << 29).
constexpr int32_t kFirstRefraxWorld = 1 << 24;

}  // namespace

WorldRegistry::WorldRegistry() = default;
WorldRegistry::~WorldRegistry() = default;

std::optional<int32_t> WorldRegistry::WorldID(const base::DictValue& world) {
  if (world.contains("page")) {
    return content::ISOLATED_WORLD_ID_GLOBAL;
  }
  const base::DictValue* isolated = world.FindDict("isolated");
  const std::string* name = isolated ? isolated->FindString("name") : nullptr;
  if (!name || name->empty()) {
    return std::nullopt;
  }
  auto [it, inserted] = isolated_.try_emplace(
      *name, kFirstRefraxWorld + static_cast<int32_t>(isolated_.size()));
  return it->second;
}

}  // namespace refrax
