// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/host/page_scripts.h"

#include <map>
#include <set>
#include <utility>
#include <vector>

#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/strcat.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "components/js_injection/browser/js_communication_host.h"
#include "components/js_injection/browser/web_message.h"
#include "components/js_injection/browser/web_message_host.h"
#include "components/js_injection/browser/web_message_host_factory.h"
#include "components/js_injection/browser/web_message_reply_proxy.h"
#include "components/js_injection/common/interfaces.mojom.h"
#include "refrax/host/contract_json.h"
#include "refrax/host/url_matching.h"
#include "refrax/host/world_registry.h"
#include "url/gurl.h"

namespace refrax {

namespace {

// The js_injection object each world's prelude captures and hides.
constexpr char16_t kChannelObjectName[] = u"__refraxChannels";

// Every frame of every origin, as WebKit user scripts run; Refrax's own scripts decide what
// to do on a page.
const std::vector<std::string>& AllOrigins() {
  static const base::NoDestructor<std::vector<std::string>> all({"*"});
  return *all;
}

// The strings in `list`; nullptr and non-string entries contribute nothing.
std::vector<std::string> Strings(const base::ListValue* list) {
  std::vector<std::string> strings;
  if (list) {
    for (const base::Value& value : *list) {
      if (value.is_string()) {
        strings.push_back(value.GetString());
      }
    }
  }
  return strings;
}

// Gives a world's scripts WebKit's call shape: window.webkit.messageHandlers.<channel>
// .postMessage(body) returns a promise that Refrax's reply settles.
std::u16string Prelude(const std::set<std::string>& channels) {
  base::ListValue names;
  for (const std::string& channel : channels) {
    names.Append(channel);
  }
  std::string script = R"JS((() => {
  const port = globalThis.__refraxChannels;
  if (!port) return;
  try { delete globalThis.__refraxChannels; } catch (e) {}
  const stringify = JSON.stringify, parse = JSON.parse;
  const pending = new Map();
  let nextID = 1;
  port.addEventListener('message', (event) => {
    let message;
    try { message = parse(event.data); } catch (e) { return; }
    const call = pending.get(message.id);
    if (!call) return;
    pending.delete(message.id);
    const reply = message.reply;
    if (reply && reply.value) call.resolve(reply.value.value);
    else call.reject(new Error(reply && reply.error ? reply.error.message : 'No reply'));
  });
  const handlers = {};
  for (const channel of CHANNELS) {
    handlers[channel] = Object.freeze({ postMessage(body) {
      const id = nextID++;
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        port.postMessage(stringify({ id, channel, body }));
      });
    } });
  }
  Object.defineProperty(globalThis, 'webkit', {
    value: Object.freeze({ messageHandlers: Object.freeze(handlers) }),
  });
})();)JS";
  const size_t at = script.find("CHANNELS");
  script.replace(at, 8, base::WriteJson(names).value_or("[]"));
  return base::UTF8ToUTF16(script);
}

// One frame's end of a world's channels: forwards granted messages to Refrax and posts each
// reply back to the call that made it.
class ChannelHost : public js_injection::WebMessageHost {
 public:
  ChannelHost(base::DictValue world,
              std::set<std::string> channels,
              std::string origin,
              bool is_main_frame,
              js_injection::WebMessageReplyProxy* proxy,
              PageScripts::MessageSender sender)
      : world_(std::move(world)),
        channels_(std::move(channels)),
        origin_(std::move(origin)),
        is_main_frame_(is_main_frame),
        proxy_(proxy),
        sender_(std::move(sender)) {}

  void OnPostMessage(std::unique_ptr<js_injection::WebMessage> message) override {
    const std::u16string* text = std::get_if<std::u16string>(&message->message);
    if (!text) {
      return;
    }
    std::optional<base::Value> parsed =
        base::JSONReader::Read(base::UTF16ToUTF8(*text), base::JSON_PARSE_RFC);
    base::DictValue* call = parsed ? parsed->GetIfDict() : nullptr;
    std::optional<int> id = call ? call->FindInt("id") : std::nullopt;
    const std::string* channel = call ? call->FindString("channel") : nullptr;
    // A script may only post on channels granted to its world.
    if (!id || !channel || !channels_.contains(*channel)) {
      return;
    }
    base::DictValue delivery;
    delivery.Set("channel", *channel);
    delivery.Set("world", world_.Clone());
    if (base::Value* body = call->Find("body")) {
      delivery.Set("body", std::move(*body));
    } else {
      delivery.Set("body", base::Value());
    }
    // The posting frame's origin, from the browser's side: never a URL the page supplied.
    if (GURL origin(origin_); origin.is_valid()) {
      delivery.Set("frameURL", origin.spec());
    }
    delivery.Set("isMainFrame", is_main_frame_);
    sender_.Run(contract::Serialize(delivery),
                base::BindOnce(&ChannelHost::Reply, weak_factory_.GetWeakPtr(), *id));
  }

 private:
  void Reply(int id, const std::string& reply) {
    std::optional<base::Value> value = base::JSONReader::Read(reply, base::JSON_PARSE_RFC);
    base::DictValue message;
    message.Set("id", id);
    message.Set("reply", value ? std::move(*value) : base::Value());
    proxy_->PostWebMessage(
        blink::WebMessagePayload(base::UTF8ToUTF16(contract::Serialize(message))));
  }

  const base::DictValue world_;
  const std::set<std::string> channels_;
  const std::string origin_;
  const bool is_main_frame_;
  raw_ptr<js_injection::WebMessageReplyProxy> proxy_;
  PageScripts::MessageSender sender_;
  base::WeakPtrFactory<ChannelHost> weak_factory_{this};
};

class ChannelHostFactory : public js_injection::WebMessageHostFactory {
 public:
  ChannelHostFactory(base::DictValue world,
                     std::set<std::string> channels,
                     PageScripts::MessageSender sender)
      : world_(std::move(world)),
        channels_(std::move(channels)),
        sender_(std::move(sender)) {}

  std::unique_ptr<js_injection::WebMessageHost> CreateHost(
      const std::string& top_level_origin_string,
      const std::string& origin_string,
      bool is_main_frame,
      js_injection::WebMessageReplyProxy* proxy) override {
    return std::make_unique<ChannelHost>(world_.Clone(), channels_, origin_string,
                                         is_main_frame, proxy, sender_);
  }

 private:
  const base::DictValue world_;
  const std::set<std::string> channels_;
  PageScripts::MessageSender sender_;
};

}  // namespace

PageScripts::PageScripts(content::WebContents* web_contents,
                         WorldRegistry* worlds,
                         MessageSender sender)
    : communication_(
          std::make_unique<js_injection::JsCommunicationHost>(web_contents)),
      worlds_(worlds),
      sender_(std::move(sender)) {}

PageScripts::~PageScripts() = default;

void PageScripts::Clear() {
  for (int id : script_ids_) {
    communication_->RemovePersistentJavaScript(id);
  }
  script_ids_.clear();
  for (int32_t world_id : channel_worlds_) {
    communication_->RemoveWebMessageHostFactory(kChannelObjectName, world_id);
  }
  channel_worlds_.clear();
}

void PageScripts::Apply(const base::ListValue& scripts) {
  Clear();

  // Channels are granted per world: the union of what that world's scripts declare.
  std::map<int32_t, std::pair<base::DictValue, std::set<std::string>>> channels_by_world;
  for (const base::Value& entry : scripts) {
    const base::DictValue* script = entry.GetIfDict();
    const base::DictValue* world = script ? script->FindDict("world") : nullptr;
    std::optional<int32_t> world_id = world ? worlds_->WorldID(*world) : std::nullopt;
    const base::ListValue* channels = script ? script->FindList("channels") : nullptr;
    if (!world_id || !channels) {
      continue;
    }
    auto& [world_value, names] = channels_by_world[*world_id];
    world_value = world->Clone();
    for (const base::Value& channel : *channels) {
      if (channel.is_string()) {
        names.insert(channel.GetString());
      }
    }
  }
  for (auto& [world_id, entry] : channels_by_world) {
    auto& [world, names] = entry;
    if (names.empty()) {
      continue;
    }
    communication_->AddWebMessageHostFactory(
        std::make_unique<ChannelHostFactory>(world.Clone(), names, sender_),
        kChannelObjectName, AllOrigins(), world_id);
    channel_worlds_.push_back(world_id);
    auto result = communication_->AddPersistentJavaScript(
        Prelude(names), js_injection::mojom::DocumentInjectionTime::kDocumentStart,
        AllOrigins(), world_id);
    if (result.script_id) {
      script_ids_.push_back(*result.script_id);
    }
  }

  for (const base::Value& entry : scripts) {
    const base::DictValue* script = entry.GetIfDict();
    const std::string* source = script ? script->FindString("source") : nullptr;
    const base::DictValue* world = script ? script->FindDict("world") : nullptr;
    std::optional<int32_t> world_id = world ? worlds_->WorldID(*world) : std::nullopt;
    if (!source || !world_id) {
      continue;
    }
    std::vector<std::string> conditions;
    if (script->FindBool("mainFrameOnly").value_or(false)) {
      conditions.push_back("window.top === window");
    }
    std::vector<std::string> matches = Strings(script->FindList("matches"));
    std::vector<std::string> excludes = Strings(script->FindList("excludes"));
    if (!matches.empty() || !excludes.empty()) {
      conditions.push_back(url_matching::ScriptGuard(matches, excludes));
    }
    std::string code = *source;
    if (!conditions.empty()) {
      code = base::StrCat(
          {"if (", base::JoinString(conditions, " && "), ") {\n", code, "\n}"});
    }
    const std::string* time = script->FindString("injectionTime");
    auto injection_time =
        time && *time == "documentEnd"
            ? js_injection::mojom::DocumentInjectionTime::kDocumentEnd
            : js_injection::mojom::DocumentInjectionTime::kDocumentStart;
    auto result = communication_->AddPersistentJavaScript(
        base::UTF8ToUTF16(code), injection_time, AllOrigins(), *world_id);
    if (result.script_id) {
      script_ids_.push_back(*result.script_id);
    }
  }
}

}  // namespace refrax
