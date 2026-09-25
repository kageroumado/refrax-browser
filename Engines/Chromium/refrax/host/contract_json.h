// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#ifndef REFRAX_HOST_CONTRACT_JSON_H_
#define REFRAX_HOST_CONTRACT_JSON_H_

#include <optional>
#include <string>
#include <string_view>
#include <utility>

#include "base/values.h"

class GURL;

// The contract's JSON shape (Engines/CONTRACT.md §4): every message is an object with one key
// naming the case, whose value holds its fields.
namespace refrax::contract {

// `value` as contract JSON: integral numbers without a decimal point (base::Value keeps large
// integers such as byte counts as doubles; the contract's integers are integers).
std::string Serialize(const base::Value& value);
std::string Serialize(const base::DictValue& value);

// {"<name>": fields} serialized.
std::string Message(std::string_view name, base::DictValue fields = {});

// The case name and fields of a message, or nullopt if `json` is not one.
std::optional<std::pair<std::string, base::DictValue>> ParseMessage(
    std::string_view json);

// A contract URL string, or null for an empty or invalid URL.
base::Value URLValue(const GURL& url);

}  // namespace refrax::contract

#endif  // REFRAX_HOST_CONTRACT_JSON_H_
