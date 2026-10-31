//! The WebKit pass's ordering and action rules, and the resources pipeline (S2) end to end.

use std::ffi::CStr;
use std::ptr;

use serde_json::Value;

use crate::*;

fn resources() -> Vec<u8> {
    std::fs::read(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../../Refrax/Resources/Shields/resources.json"
    ))
    .expect("the app's resources.json exists")
}

struct Built {
    set: *mut ShieldsFilterSet,
    engine: *mut ShieldsEngine,
}

impl Built {
    fn new(lists: &[&str]) -> Self {
        unsafe {
            let set = shields_filter_set_new(true);
            for list in lists {
                assert_eq!(
                    shields_filter_set_add_list(
                        set,
                        list.as_ptr(),
                        list.len(),
                        SHIELDS_LIST_FORMAT_STANDARD,
                        1,
                        ptr::null_mut()
                    ),
                    SHIELDS_OK
                );
            }
            let engine = shields_engine_build(set);
            let resources = resources();
            assert_eq!(
                shields_engine_use_resources(engine, resources.as_ptr(), resources.len()),
                SHIELDS_OK
            );
            Self { set, engine }
        }
    }

    fn compile(&self, max_rules: usize) -> webkit::Output {
        unsafe {
            let set = &*self.set;
            let engine = &*self.engine;
            let lists: Vec<_> = set
                .lists
                .iter()
                .map(|(text, options)| webkit::ListText {
                    text,
                    options: *options,
                })
                .collect();
            webkit::compile(
                &lists,
                &redirect_urls(&engine.resources),
                &engine.engine,
                &engine.resources,
                &webkit::Options {
                    max_rules_per_list: max_rules,
                },
            )
        }
    }

    fn decision(&self, url: &CStr, source: &CStr, kind: &CStr) -> ShieldsDecision {
        unsafe {
            let mut decision = ShieldsDecision::EMPTY;
            shields_engine_check_request(
                self.engine,
                url.as_ptr(),
                source.as_ptr(),
                kind.as_ptr(),
                c"GET".as_ptr(),
                &mut decision,
            );
            decision
        }
    }
}

impl Drop for Built {
    fn drop(&mut self) {
        unsafe {
            shields_engine_free(self.engine);
            shields_filter_set_free(self.set);
        }
    }
}

fn position(list: &[Value], predicate: impl Fn(&Value) -> bool) -> Option<usize> {
    list.iter().position(predicate)
}

fn url_filter(rule: &Value) -> &str {
    rule["trigger"]["url-filter"].as_str().unwrap_or_default()
}

fn action(rule: &Value) -> &str {
    rule["action"]["type"].as_str().unwrap_or_default()
}

#[test]
fn every_network_list_carries_every_exception_after_its_blocks() {
    let list = (0..8)
        .map(|index| format!("||ads{index}.example^\n"))
        .collect::<String>()
        + "@@||ads3.example^\n";
    let built = Built::new(&[&list]);
    let output = built.compile(6);
    assert!(output.network.len() > 1, "small lists force several chunks");
    for chunk in &output.network {
        let exception = position(chunk, |rule| {
            action(rule) == "ignore-previous-rules" && url_filter(rule).contains("ads3")
        })
        .expect("each chunk carries the exception");
        let last_block = chunk
            .iter()
            .rposition(|rule| action(rule) == "block")
            .expect("each chunk has blocks");
        assert!(
            exception > last_block,
            "the exception follows the chunk's blocks"
        );
        assert!(chunk.len() <= 6);
    }
}

#[test]
fn important_blocks_follow_exceptions() {
    let built = Built::new(&["||tracker.example^$important\n@@||tracker.example^\n"]);
    let output = built.compile(webkit::MAX_RULES_PER_LIST);
    let chunk = &output.network[0];
    let exception = position(chunk, |rule| {
        action(rule) == "ignore-previous-rules" && url_filter(rule).contains("tracker")
    })
    .unwrap();
    let important = position(chunk, |rule| {
        action(rule) == "block" && url_filter(rule).contains("tracker")
    })
    .unwrap();
    assert!(important > exception);
}

#[test]
fn redirects_and_removeparam_become_redirect_actions() {
    let built =
        Built::new(&["||ads.example/x.js$script,redirect=noop.js\n*$removeparam=utm_source\n"]);
    let output = built.compile(webkit::MAX_RULES_PER_LIST);
    let chunk = &output.network[0];
    let redirect = position(chunk, |rule| {
        action(rule) == "redirect" && rule["action"]["redirect"]["url"].is_string()
    })
    .unwrap();
    assert_eq!(
        action(&chunk[redirect - 1]),
        "ignore-previous-rules",
        "a redirect lifts blocks on its URL first"
    );
    let url = chunk[redirect]["action"]["redirect"]["url"]
        .as_str()
        .unwrap();
    assert!(url.starts_with("data:application/javascript;base64,"));
    let transform = position(chunk, |rule| {
        rule["action"]["redirect"]["transform"].is_object()
    })
    .unwrap();
    assert_eq!(url_filter(&chunk[transform]), "[?&]utm_source=");
    assert_eq!(
        chunk[transform]["action"]["redirect"]["transform"]["query-transform"]["remove-parameters"],
        serde_json::json!(["utm_source"])
    );
}

#[test]
fn cosmetic_exceptions_become_domain_conditions_and_document_rules() {
    let built = Built::new(&[
        "##.ad\nexample.com#@#.ad\nexample.com##.banner\n@@||news.example^$generichide\n",
    ]);
    let output = built.compile(webkit::MAX_RULES_PER_LIST);
    let chunk = &output.cosmetic[0];
    let generic = position(chunk, |rule| rule["action"]["selector"] == ".ad").unwrap();
    assert_eq!(
        chunk[generic]["trigger"]["unless-domain"],
        serde_json::json!(["*example.com"])
    );
    let generichide = position(chunk, |rule| action(rule) == "ignore-previous-rules").unwrap();
    let specific = position(chunk, |rule| rule["action"]["selector"] == ".banner").unwrap();
    assert_eq!(
        chunk[specific]["trigger"]["if-domain"],
        serde_json::json!(["*example.com"])
    );
    assert!(
        generic < generichide && generichide < specific,
        "generichide lifts generic hides only"
    );
}

#[test]
fn scriptlets_become_per_function_scripts_with_host_tables() {
    let built = Built::new(&["example.com##+js(set-constant, ads, false)\nsub.example.com#@#+js(set-constant, ads, false)\nexample.com##.promo:has-text(Sponsored)\n"]);
    let output = built.compile(webkit::MAX_RULES_PER_LIST);
    let script = output
        .scripts
        .iter()
        .find(|script| script.name == "set-constant.js")
        .expect("a set-constant script");
    assert_eq!(script.world, "page");
    assert_eq!(
        script.includes,
        ["*://example.com/*", "*://*.example.com/*"]
    );
    assert!(script.source.contains("const scriptletGlobals = {};"));
    assert!(script.source.contains(r#""example.com":[["ads","false"]]"#));
    assert!(
        script.source.contains(r#""sub.example.com":[]"#),
        "the exception stops the walk"
    );
    let procedural = output
        .scripts
        .iter()
        .find(|script| script.name == "procedural")
        .expect("a procedural script");
    assert_eq!(procedural.world, "shields");
    assert!(procedural.source.contains("has-text"));
}

#[test]
fn resources_serve_redirects_and_scriptlets() {
    let built = Built::new(&[
        "||ads.example/x.js$script,redirect=noop.js\nexample.com##+js(set-constant, ads, false)\n",
    ]);
    let mut decision = built.decision(
        c"https://ads.example/x.js",
        c"https://example.com/",
        c"script",
    );
    assert!(decision.should_block);
    let redirect =
        unsafe { std::slice::from_raw_parts(decision.redirect.data, decision.redirect.len) };
    assert!(redirect.starts_with(b"data:application/javascript;base64,"));
    unsafe { shields_decision_free(&mut decision) };

    let mut json = ShieldsBuffer::EMPTY;
    unsafe {
        shields_engine_url_cosmetic_resources(
            built.engine,
            c"https://example.com/".as_ptr(),
            &mut json,
        );
        let value: Value =
            serde_json::from_slice(std::slice::from_raw_parts(json.data, json.len)).unwrap();
        let script = value["injected_script"].as_str().unwrap();
        assert!(script.contains("function setConstant("));
        assert!(script.contains(r#"setConstant("ads", "false")"#));
        shields_buffer_free(&mut json);
    }
}

#[test]
fn explains_exceptions_without_a_block() {
    let built = Built::new(&["@@||cdn.example^\n"]);
    let mut json = ShieldsBuffer::EMPTY;
    unsafe {
        assert_eq!(
            shields_engine_explain(
                built.engine,
                c"https://cdn.example/a.js".as_ptr(),
                c"https://site.example/".as_ptr(),
                c"script".as_ptr(),
                c"GET".as_ptr(),
                &mut json,
            ),
            SHIELDS_OK
        );
        let value: Value =
            serde_json::from_slice(std::slice::from_raw_parts(json.data, json.len)).unwrap();
        assert_eq!(value["shouldBlock"], false);
        assert_eq!(value["exception"]["text"], "@@||cdn.example^");
        assert_eq!(value["exception"]["sourceIndex"], 0);
        shields_buffer_free(&mut json);
    }
}

#[test]
fn checks_resources() {
    let resources = resources();
    let mut json = ShieldsBuffer::EMPTY;
    unsafe {
        assert_eq!(
            shields_resources_check(resources.as_ptr(), resources.len(), &mut json),
            SHIELDS_OK
        );
        let value: Value =
            serde_json::from_slice(std::slice::from_raw_parts(json.data, json.len)).unwrap();
        assert!(value["scriptlets"].as_u64().unwrap() > 100);
        assert!(value["redirects"].as_u64().unwrap() > 40);
        shields_buffer_free(&mut json);
        let broken = br#"[{"name":"a.js","kind":{"mime":"application/javascript"},"content":"","dependencies":["missing.fn"]}]"#;
        assert_eq!(
            shields_resources_check(broken.as_ptr(), broken.len(), &mut json),
            SHIELDS_INVALID_DATA
        );
    }
}
