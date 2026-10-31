// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

//! shields-datgen: the engine files the conformance suite's `contentBlocking` policies name, built
//! through the same C ABI Refrax.app uses, and the decisions that engine predicts.
//!
//!   shields-datgen build <out.dat> <list.txt>…
//!       A debug engine of the lists, in order (list n has sourceIndex n), serialized.
//!   shields-datgen predict <engine.dat> <resources.json> <requests.json>
//!       For each {"url", "source", "type", "method"} in the array, the engine's decision:
//!       {"decision": blocked|redirected|rewritten|excepted|allowed, "rule"?, "redirect"?,
//!        "rewrittenURL"?}, one per line.

use std::ffi::CString;
use std::process::exit;

use serde_json::{json, Value};
use shields::*;

fn fail(message: &str) -> ! {
    eprintln!("shields-datgen: {message}");
    exit(1);
}

fn read(path: &str) -> Vec<u8> {
    std::fs::read(path).unwrap_or_else(|error| fail(&format!("{path}: {error}")))
}

unsafe fn take(buffer: &mut ShieldsBuffer) -> Option<String> {
    if buffer.data.is_null() || buffer.len == 0 {
        return None;
    }
    let bytes = std::slice::from_raw_parts(buffer.data, buffer.len);
    Some(String::from_utf8_lossy(bytes).into_owned())
}

fn build(out: &str, lists: &[String]) {
    unsafe {
        let set = shields_filter_set_new(true);
        for list in lists {
            let text = read(list);
            let mut index = 0u32;
            if shields_filter_set_add_list(set, text.as_ptr(), text.len(), SHIELDS_LIST_FORMAT_STANDARD, 0, &mut index) != SHIELDS_OK {
                fail(&format!("{list}: not a filter list"));
            }
        }
        let engine = shields_engine_build(set);
        if engine.is_null() {
            fail("the engine did not build");
        }
        let mut dat = ShieldsBuffer { data: std::ptr::null_mut(), len: 0, capacity: 0 };
        if shields_engine_serialize(engine, &mut dat) != SHIELDS_OK {
            fail("the engine did not serialize");
        }
        let bytes = std::slice::from_raw_parts(dat.data, dat.len);
        std::fs::write(out, bytes).unwrap_or_else(|error| fail(&format!("{out}: {error}")));
        shields_buffer_free(&mut dat);
        shields_engine_free(engine);
        shields_filter_set_free(set);
    }
}

fn predict(dat_path: &str, resources_path: &str, requests_path: &str) {
    let dat = read(dat_path);
    let resources = read(resources_path);
    let requests: Value = serde_json::from_slice(&read(requests_path))
        .unwrap_or_else(|error| fail(&format!("{requests_path}: {error}")));
    unsafe {
        let engine = shields_engine_deserialize(dat.as_ptr(), dat.len());
        if engine.is_null() {
            fail("the engine file did not load");
        }
        if shields_engine_use_resources(engine, resources.as_ptr(), resources.len()) != SHIELDS_OK {
            fail("the resources did not load");
        }
        for request in requests.as_array().unwrap_or_else(|| fail("requests must be an array")) {
            let field = |name: &str, default: &str| {
                CString::new(request.get(name).and_then(Value::as_str).unwrap_or(default)).unwrap()
            };
            let (url, source, kind, method) =
                (field("url", ""), field("source", ""), field("type", "other"), field("method", "GET"));
            let mut decision: ShieldsDecision = std::mem::zeroed();
            shields_engine_check_request(engine, url.as_ptr(), source.as_ptr(), kind.as_ptr(), method.as_ptr(), &mut decision);
            let redirect = take(&mut decision.redirect);
            let rewritten = take(&mut decision.rewritten_url);
            let name = if decision.should_block {
                if redirect.is_some() { "redirected" } else { "blocked" }
            } else if rewritten.is_some() {
                "rewritten"
            } else if decision.excepted && decision.matched {
                "excepted"
            } else {
                "allowed"
            };
            let mut out = json!({"url": request.get("url"), "type": request.get("type"), "decision": name});
            if let Some(rule) = take(&mut decision.rule) {
                out["rule"] = json!(rule);
            }
            if let Some(rewritten) = rewritten {
                out["rewrittenURL"] = json!(rewritten);
            }
            println!("{out}");
            shields_decision_free(&mut decision);
        }
        shields_engine_free(engine);
    }
}

fn cosmetic(dat_path: &str, resources_path: &str, url: &str) {
    let dat = read(dat_path);
    let resources = read(resources_path);
    unsafe {
        let engine = shields_engine_deserialize(dat.as_ptr(), dat.len());
        if engine.is_null() || shields_engine_use_resources(engine, resources.as_ptr(), resources.len()) != SHIELDS_OK {
            fail("the engine or its resources did not load");
        }
        let url = CString::new(url).unwrap();
        let mut out = ShieldsBuffer { data: std::ptr::null_mut(), len: 0, capacity: 0 };
        shields_engine_url_cosmetic_resources(engine, url.as_ptr(), &mut out);
        println!("{}", take(&mut out).unwrap_or_default());
        shields_buffer_free(&mut out);
        shields_engine_free(engine);
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("build") if args.len() >= 3 => build(&args[1], &args[2..]),
        Some("predict") if args.len() == 4 => predict(&args[1], &args[2], &args[3]),
        Some("cosmetic") if args.len() == 4 => cosmetic(&args[1], &args[2], &args[3]),
        _ => fail("usage: shields-datgen build <out.dat> <list>… | predict <dat> <resources.json> <requests.json> | cosmetic <dat> <resources.json> <url>"),
    }
}
