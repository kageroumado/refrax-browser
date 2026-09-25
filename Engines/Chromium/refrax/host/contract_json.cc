// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/contract_json.h"

#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "url/gurl.h"

namespace refrax::contract {

std::string Message(std::string_view name, base::DictValue fields) {
  base::DictValue message;
  message.Set(name, std::move(fields));
  return base::WriteJson(message).value_or("{}");
}

std::optional<std::pair<std::string, base::DictValue>> ParseMessage(
    std::string_view json) {
  std::optional<base::Value> value = base::JSONReader::Read(json, base::JSON_PARSE_RFC);
  if (!value || !value->is_dict() || value->GetDict().size() != 1) {
    return std::nullopt;
  }
  auto&& [name, fields] = *value->GetDict().begin();
  if (!fields.is_dict()) {
    return std::nullopt;
  }
  return std::make_pair(name, std::move(fields.GetDict()));
}

base::Value URLValue(const GURL& url) {
  if (!url.is_valid() || url.is_empty()) {
    return base::Value();
  }
  return base::Value(url.spec());
}

}  // namespace refrax::contract
