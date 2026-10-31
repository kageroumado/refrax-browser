// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

#include "refrax/renderer/shields_frame_observer.h"

#include <utility>

#include "base/functional/bind.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_registry.h"
#include "third_party/blink/public/platform/scheduler/web_agent_group_scheduler.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/platform/web_url.h"
#include "third_party/blink/public/web/web_css_origin.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_script_source.h"
#include "v8/include/v8-array-buffer.h"
#include "v8/include/v8-container.h"
#include "v8/include/v8-context.h"
#include "v8/include/v8-function.h"
#include "v8/include/v8-function-callback.h"
#include "v8/include/v8-isolate.h"
#include "v8/include/v8-json.h"
#include "v8/include/v8-primitive.h"

namespace refrax {

namespace {

// Runs in the Shields world: procedural filters (adblock-rust's operator and action JSON) and,
// with `report`, the collector that sends the document's new classes and ids for generic
// hiding. Both follow the DOM as it changes.
constexpr char kShieldsWorldScript[] = R"JS(
(function (procedural, report) {
  'use strict';
  const filters = [];
  for (const text of procedural) {
    try { filters.push(JSON.parse(text)); } catch (e) {}
  }

  const regexOf = (arg) => {
    const match = /^\/(.*)\/([dgimsuy]*)$/.exec(arg);
    if (!match) return null;
    try { return new RegExp(match[1], match[2]); } catch (e) { return null; }
  };
  const matcherOf = (arg) => {
    const regex = regexOf(arg);
    return regex ? (text) => regex.test(text) : (text) => text.includes(arg);
  };
  const exactOrRegex = (arg) => {
    const regex = regexOf(arg);
    return regex ? (text) => regex.test(text) : (text) => text === arg;
  };
  const unquote = (text) => text.replace(/^(["'])(.*)\1$/, '$2');
  const elements = (nodes) => nodes.filter((node) => node instanceof Element);

  const descend = (nodes, selector) => {
    const result = [];
    const first = selector.trimStart()[0];
    for (const node of nodes) {
      try {
        if (node === document) {
          result.push(...document.querySelectorAll(selector));
        } else if (first === '+' || first === '~') {
          const rest = selector.trimStart().slice(1);
          for (let sibling = node.nextElementSibling; sibling; sibling = sibling.nextElementSibling) {
            if (sibling.matches(rest)) result.push(sibling);
            if (first === '+') break;
          }
        } else {
          result.push(...node.querySelectorAll(':scope' + (/^[\s>]/.test(selector) ? '' : ' ') + selector));
        }
      } catch (e) {}
    }
    return result;
  };

  const operators = {
    'css-selector': descend,
    'has-text': (nodes, arg) => {
      const test = matcherOf(arg);
      return elements(nodes).filter((node) => test(node.textContent || ''));
    },
    'min-text-length': (nodes, arg) => {
      const length = parseInt(arg, 10) || 0;
      return elements(nodes).filter((node) => (node.textContent || '').length >= length);
    },
    'matches-attr': (nodes, arg) => {
      const match = /^\s*("[^"]*"|[^=]+?)\s*(?:=\s*(.*?))?\s*$/.exec(arg);
      if (!match) return [];
      const name = exactOrRegex(unquote(match[1]));
      const value = match[2] === undefined ? () => true : exactOrRegex(unquote(match[2]));
      return elements(nodes).filter((node) =>
        Array.from(node.attributes).some((attribute) => name(attribute.name) && value(attribute.value)));
    },
    'matches-path': (nodes, arg) => {
      const test = matcherOf(arg);
      return test(location.pathname + location.search) ? nodes : [];
    },
    'upward': (nodes, arg) => {
      const count = /^\d+$/.test(arg) ? parseInt(arg, 10) : 0;
      const result = [];
      for (const node of elements(nodes)) {
        let target = null;
        if (count > 0) {
          target = node;
          for (let i = 0; i < count && target; i++) target = target.parentElement;
        } else {
          try { target = node.parentElement && node.parentElement.closest(arg); } catch (e) {}
        }
        if (target) result.push(target);
      }
      return result;
    },
    'xpath': (nodes, arg) => {
      const result = [];
      for (const node of nodes) {
        try {
          const found = document.evaluate(arg, node, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          for (let i = 0; i < found.snapshotLength; i++) result.push(found.snapshotItem(i));
        } catch (e) {}
      }
      return elements(result);
    },
  };
  const cssMatcher = (pseudo) => (nodes, arg) => {
    const separator = arg.indexOf(':');
    if (separator < 0) return [];
    const property = arg.slice(0, separator).trim();
    const test = exactOrRegex(arg.slice(separator + 1).trim());
    return elements(nodes).filter((node) => test(getComputedStyle(node, pseudo).getPropertyValue(property)));
  };
  operators['matches-css'] = cssMatcher(null);
  operators['matches-css-before'] = cssMatcher('::before');
  operators['matches-css-after'] = cssMatcher('::after');

  const done = new WeakMap();
  const act = (node, filter) => {
    const seen = done.get(node) || new Set();
    if (seen.has(filter)) return;
    seen.add(filter);
    done.set(node, seen);
    const action = filter.action;
    if (!action) {
      node.style.setProperty('display', 'none', 'important');
    } else if (action.type === 'remove') {
      node.remove();
    } else if (action.type === 'style') {
      node.setAttribute('style', (node.getAttribute('style') || '') + ';' + action.arg);
    } else if (action.type === 'remove-attr') {
      for (const name of action.arg.split('|')) node.removeAttribute(name);
    } else if (action.type === 'remove-class') {
      node.classList.remove(...action.arg.split('|'));
    }
  };
  const runFilters = () => {
    for (const filter of filters) {
      let nodes = [document];
      for (const step of filter.selector || []) {
        const operator = operators[step.type];
        nodes = operator ? operator(nodes, step.arg) : [];
        if (!nodes.length) break;
      }
      for (const node of elements(nodes)) act(node, filter);
    }
  };

  const seenClasses = new Set();
  const seenIds = new Set();
  const collect = () => {
    const classes = [];
    const ids = [];
    for (const node of document.querySelectorAll('[class],[id]')) {
      for (const name of node.classList) {
        if (!seenClasses.has(name)) { seenClasses.add(name); classes.push(name); }
      }
      if (node.id && !seenIds.has(node.id)) { seenIds.add(node.id); ids.push(node.id); }
    }
    if (classes.length || ids.length) report(classes, ids);
  };

  let scheduled = false;
  const run = () => {
    scheduled = false;
    if (filters.length) runFilters();
    if (report) collect();
  };
  const schedule = () => {
    if (scheduled) return;
    scheduled = true;
    setTimeout(run, 50);
  };
  new MutationObserver(schedule).observe(document, {childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'id']});
  document.addEventListener('DOMContentLoaded', run, {once: true});
  run();
})
)JS";

std::vector<std::string> StringsOf(v8::Isolate* isolate,
                                   v8::Local<v8::Context> context,
                                   v8::Local<v8::Value> value) {
  std::vector<std::string> strings;
  if (!value->IsArray()) {
    return strings;
  }
  v8::Local<v8::Array> array = value.As<v8::Array>();
  for (uint32_t i = 0; i < array->Length() && strings.size() < 10'000; ++i) {
    v8::Local<v8::Value> item;
    if (array->Get(context, i).ToLocal(&item) && item->IsString()) {
      v8::String::Utf8Value text(isolate, item);
      if (*text && text.length() <= 512) {
        strings.emplace_back(*text, text.length());
      }
    }
  }
  return strings;
}

bool SameDocumentURL(const GURL& a, const GURL& b) {
  GURL::Replacements no_ref;
  no_ref.ClearRef();
  return a.ReplaceComponents(no_ref) == b.ReplaceComponents(no_ref);
}

}  // namespace

ShieldsFrameObserver::Pending::Pending() = default;
ShieldsFrameObserver::Pending::Pending(Pending&&) = default;
ShieldsFrameObserver::Pending& ShieldsFrameObserver::Pending::operator=(Pending&&) = default;
ShieldsFrameObserver::Pending::~Pending() = default;

// static
void ShieldsFrameObserver::Create(content::RenderFrame* render_frame) {
  new ShieldsFrameObserver(render_frame);
}

ShieldsFrameObserver::ShieldsFrameObserver(content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame),
      content::RenderFrameObserverTracker<ShieldsFrameObserver>(render_frame) {
  render_frame->GetAssociatedInterfaceRegistry()->AddInterface<mojom::ShieldsFrame>(
      base::BindRepeating(
          [](ShieldsFrameObserver* self,
             mojo::PendingAssociatedReceiver<mojom::ShieldsFrame> receiver) {
            self->receivers_.Add(self, std::move(receiver));
          },
          base::Unretained(this)));
}

ShieldsFrameObserver::~ShieldsFrameObserver() = default;

void ShieldsFrameObserver::Apply(const GURL& url,
                                 const std::string& stylesheet,
                                 const std::string& scriptlets,
                                 const std::string& procedural_actions,
                                 mojo::PendingRemote<mojom::ShieldsHost> host) {
  Pending pending;
  pending.url = url;
  pending.stylesheet = stylesheet;
  pending.scriptlets = scriptlets;
  pending.procedural_actions = procedural_actions;
  pending.host = std::move(host);
  pending_ = std::move(pending);
}

void ShieldsFrameObserver::DidCreateDocumentElement() {
  host_.reset();
  document_.reset();
  if (!pending_) {
    return;
  }
  Pending pending = std::move(*pending_);
  pending_.reset();
  blink::WebLocalFrame* frame = render_frame()->GetWebFrame();
  if (!SameDocumentURL(GURL(frame->GetDocument().Url()), pending.url)) {
    return;
  }
  InsertStylesheet(pending.stylesheet);
  document_ = std::move(pending);
}

void ShieldsFrameObserver::RunScriptsAtDocumentStart() {
  if (!document_) {
    return;
  }
  Pending document = std::move(*document_);
  document_.reset();
  if (!document.scriptlets.empty()) {
    // uBO's scriptlets keep shared state in `scriptletGlobals`, which adblock-rust leaves for
    // the embedder to declare.
    render_frame()->GetWebFrame()->ExecuteScript(blink::WebScriptSource(blink::WebString::FromUtf8(
        "(function(){const scriptletGlobals={};\n" + document.scriptlets + "\n})();")));
  }
  const bool collect = document.host.is_valid();
  if (collect) {
    host_.Bind(std::move(document.host));
  }
  if (collect || document.procedural_actions != "[]") {
    StartShieldsWorld(document.procedural_actions, collect);
  }
}

void ShieldsFrameObserver::StartShieldsWorld(const std::string& procedural_actions,
                                             bool collect) {
  blink::WebLocalFrame* frame = render_frame()->GetWebFrame();
  v8::Isolate* isolate = frame->GetAgentGroupScheduler()->Isolate();
  v8::HandleScope handles(isolate);
  v8::Local<v8::Value> start = frame->ExecuteScriptInIsolatedWorldAndReturnValue(
      mojom::kShieldsWorldId,
      blink::WebScriptSource(blink::WebString::FromUtf8(kShieldsWorldScript)),
      blink::BackForwardCacheAware::kAllow);
  if (start.IsEmpty() || !start->IsFunction()) {
    return;
  }
  v8::Local<v8::Context> context =
      frame->GetScriptContextFromWorldId(isolate, mojom::kShieldsWorldId);
  v8::Context::Scope context_scope(context);
  v8::Local<v8::Value> procedural;
  if (!v8::JSON::Parse(context, v8::String::NewFromUtf8(isolate, procedural_actions.data(),
                                                        v8::NewStringType::kNormal,
                                                        static_cast<int>(procedural_actions.size()))
                                    .ToLocalChecked())
           .ToLocal(&procedural) ||
      !procedural->IsArray()) {
    procedural = v8::Array::New(isolate);
  }
  v8::Local<v8::Value> report = v8::Null(isolate);
  v8::Local<v8::Function> report_function;
  if (collect &&
      v8::Function::New(context, &ShieldsFrameObserver::OnReport).ToLocal(&report_function)) {
    report = report_function;
  }
  v8::Local<v8::Value> argv[] = {procedural, report};
  frame->CallFunctionEvenIfScriptDisabled(start.As<v8::Function>(), v8::Undefined(isolate), 2,
                                          argv);
}

// static
void ShieldsFrameObserver::OnReport(const v8::FunctionCallbackInfo<v8::Value>& info) {
  v8::Isolate* isolate = info.GetIsolate();
  v8::Local<v8::Context> context = isolate->GetCurrentContext();
  blink::WebLocalFrame* frame = blink::WebLocalFrame::FrameForContext(context);
  content::RenderFrame* render_frame =
      frame ? content::RenderFrame::FromWebFrame(frame) : nullptr;
  ShieldsFrameObserver* self = render_frame ? ShieldsFrameObserver::Get(render_frame) : nullptr;
  if (!self || !self->host_.is_bound() || info.Length() < 2) {
    return;
  }
  self->host_->HiddenClassIdSelectors(
      StringsOf(isolate, context, info[0]), StringsOf(isolate, context, info[1]),
      base::BindOnce(&ShieldsFrameObserver::InsertStylesheet, self->weak_factory_.GetWeakPtr()));
}

void ShieldsFrameObserver::InsertStylesheet(const std::string& css) {
  if (css.empty()) {
    return;
  }
  render_frame()->GetWebFrame()->GetDocument().InsertStyleSheet(
      blink::WebString::FromUtf8(css), nullptr, blink::WebCssOrigin::kUser);
}

void ShieldsFrameObserver::OnDestruct() {
  delete this;
}

}  // namespace refrax
