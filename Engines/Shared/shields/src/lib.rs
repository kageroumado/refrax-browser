//! Refrax Shields: one adblock-rust core behind a C ABI, called from Swift in Refrax.app and
//! from C++ in the Chromium engine host.
//!
//! `include/shields.h` is the contract and documents every function; the two files change
//! together. Every entry point catches panics and reports `SHIELDS_PANIC`, so a bad filter
//! list can fail a build without taking the calling process down.

use std::collections::HashSet;
use std::ffi::{c_char, CStr};
use std::mem::ManuallyDrop;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

use adblock::blocker::BlockerResult;
use adblock::lists::{FilterFormat, FilterSet, ParseOptions};
use adblock::request::Request;
use adblock::resources::{PermissionMask, Resource};
use adblock::sourcemap::FilterRuleDebugInfo;
use adblock::Engine;

/// Bumped whenever a signature or struct layout in `shields.h` changes.
pub const SHIELDS_ABI_VERSION: u32 = 1;

/// Identifies what a serialized engine can be read by. Part of every DAT cache key.
const ENGINE_FORMAT: &CStr = c"adblock-0.13.3;shields-1";

pub type ShieldsStatus = i32;
pub const SHIELDS_OK: ShieldsStatus = 0;
pub const SHIELDS_INVALID_ARGUMENT: ShieldsStatus = 1;
pub const SHIELDS_INVALID_URL: ShieldsStatus = 2;
pub const SHIELDS_INVALID_DATA: ShieldsStatus = 3;
pub const SHIELDS_UNSUPPORTED: ShieldsStatus = 4;
pub const SHIELDS_PANIC: ShieldsStatus = 5;

pub type ShieldsListFormat = u32;
pub const SHIELDS_LIST_FORMAT_STANDARD: ShieldsListFormat = 0;
pub const SHIELDS_LIST_FORMAT_HOSTS: ShieldsListFormat = 1;

/// Engine must be shareable across threads: Swift holds one handle from several actors and
/// the host matches on a thread pool. Fails to compile if adblock's `single-thread` is enabled.
#[allow(dead_code)]
fn assert_engine_is_shareable() {
    fn check<T: Send + Sync>() {}
    check::<Engine>();
}

// MARK: - Buffers

/// Bytes owned by this library and handed to the caller, released with `shields_buffer_free`.
#[repr(C)]
pub struct ShieldsBuffer {
    pub data: *mut u8,
    pub len: usize,
    pub capacity: usize,
}

impl ShieldsBuffer {
    const EMPTY: Self = Self {
        data: ptr::null_mut(),
        len: 0,
        capacity: 0,
    };

    fn from_vec(bytes: Vec<u8>) -> Self {
        if bytes.capacity() == 0 {
            return Self::EMPTY;
        }
        let mut bytes = ManuallyDrop::new(bytes);
        Self {
            data: bytes.as_mut_ptr(),
            len: bytes.len(),
            capacity: bytes.capacity(),
        }
    }

    fn from_optional(text: Option<String>) -> Self {
        text.map_or(Self::EMPTY, |text| Self::from_vec(text.into_bytes()))
    }

    /// # Safety
    /// `self` holds either `EMPTY` or parts produced by `from_vec`.
    unsafe fn release(&mut self) {
        if !self.data.is_null() {
            drop(Vec::from_raw_parts(self.data, self.len, self.capacity));
        }
        *self = Self::EMPTY;
    }
}

#[no_mangle]
pub unsafe extern "C" fn shields_buffer_free(buffer: *mut ShieldsBuffer) {
    if let Some(buffer) = buffer.as_mut() {
        buffer.release();
    }
}

// MARK: - Argument helpers

unsafe fn byte_arg<'a>(data: *const u8, len: usize) -> Option<&'a [u8]> {
    if len == 0 {
        Some(&[])
    } else if data.is_null() {
        None
    } else {
        Some(std::slice::from_raw_parts(data, len))
    }
}

unsafe fn text_arg<'a>(data: *const u8, len: usize) -> Option<&'a str> {
    std::str::from_utf8(byte_arg(data, len)?).ok()
}

unsafe fn c_str_arg<'a>(text: *const c_char) -> Option<&'a str> {
    if text.is_null() {
        None
    } else {
        CStr::from_ptr(text).to_str().ok()
    }
}

fn guarded(body: impl FnOnce() -> ShieldsStatus) -> ShieldsStatus {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(SHIELDS_PANIC)
}

unsafe fn write_json<T: serde::Serialize>(value: &T, out: *mut ShieldsBuffer) -> ShieldsStatus {
    match serde_json::to_vec(value) {
        Ok(json) => {
            out.write(ShieldsBuffer::from_vec(json));
            SHIELDS_OK
        }
        Err(_) => SHIELDS_INVALID_DATA,
    }
}

// MARK: - Version

#[no_mangle]
pub extern "C" fn shields_abi_version() -> u32 {
    SHIELDS_ABI_VERSION
}

#[no_mangle]
pub extern "C" fn shields_engine_format() -> *const c_char {
    ENGINE_FORMAT.as_ptr()
}

// MARK: - Filter sets

/// Filter lists collected for one engine build.
pub struct ShieldsFilterSet {
    set: FilterSet,
}

#[no_mangle]
pub extern "C" fn shields_filter_set_new(debug: bool) -> *mut ShieldsFilterSet {
    Box::into_raw(Box::new(ShieldsFilterSet {
        set: FilterSet::new(debug),
    }))
}

#[no_mangle]
pub unsafe extern "C" fn shields_filter_set_free(set: *mut ShieldsFilterSet) {
    if !set.is_null() {
        drop(Box::from_raw(set));
    }
}

#[no_mangle]
pub unsafe extern "C" fn shields_filter_set_add_list(
    set: *mut ShieldsFilterSet,
    text: *const u8,
    text_len: usize,
    format: ShieldsListFormat,
    permissions: u8,
    out_source_index: *mut u32,
) -> ShieldsStatus {
    guarded(|| {
        let (Some(set), Some(text)) = (set.as_mut(), text_arg(text, text_len)) else {
            return SHIELDS_INVALID_ARGUMENT;
        };
        let format = match format {
            SHIELDS_LIST_FORMAT_STANDARD => FilterFormat::Standard,
            SHIELDS_LIST_FORMAT_HOSTS => FilterFormat::Hosts,
            _ => return SHIELDS_INVALID_ARGUMENT,
        };
        let options = ParseOptions {
            format,
            permissions: PermissionMask::from_bits(permissions),
            ..ParseOptions::default()
        };
        let record = set.set.add_filter_list(text.to_owned(), options);
        if let Some(out) = out_source_index.as_mut() {
            *out = record.source_index as u32;
        }
        SHIELDS_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn shields_filter_set_to_webkit_rules(
    set: *const ShieldsFilterSet,
    out_json: *mut ShieldsBuffer,
) -> ShieldsStatus {
    guarded(|| {
        let Some(set) = set.as_ref() else {
            return SHIELDS_INVALID_ARGUMENT;
        };
        if out_json.is_null() {
            return SHIELDS_INVALID_ARGUMENT;
        }
        out_json.write(ShieldsBuffer::EMPTY);
        webkit_rules(&set.set, out_json)
    })
}

#[cfg(feature = "content-blocking")]
unsafe fn webkit_rules(set: &FilterSet, out_json: *mut ShieldsBuffer) -> ShieldsStatus {
    #[derive(serde::Serialize)]
    #[serde(rename_all = "camelCase")]
    struct WebKitRules {
        rules: Vec<adblock::content_blocking::CbRule>,
        converted_filter_count: usize,
    }
    // Conversion needs each filter's raw line, which only a debug set keeps.
    let Ok((rules, converted)) = set.clone().into_content_blocking() else {
        return SHIELDS_INVALID_ARGUMENT;
    };
    write_json(
        &WebKitRules {
            rules,
            converted_filter_count: converted.len(),
        },
        out_json,
    )
}

#[cfg(not(feature = "content-blocking"))]
unsafe fn webkit_rules(_set: &FilterSet, _out_json: *mut ShieldsBuffer) -> ShieldsStatus {
    SHIELDS_UNSUPPORTED
}

// MARK: - Engines

/// An immutable compiled engine. Safe to query from any number of threads at once.
pub struct ShieldsEngine {
    engine: Engine,
}

fn into_handle(engine: Engine) -> *mut ShieldsEngine {
    Box::into_raw(Box::new(ShieldsEngine { engine }))
}

#[no_mangle]
pub unsafe extern "C" fn shields_engine_build(set: *const ShieldsFilterSet) -> *mut ShieldsEngine {
    let Some(set) = set.as_ref() else {
        return ptr::null_mut();
    };
    catch_unwind(AssertUnwindSafe(|| {
        Engine::new_with_filter_set(set.set.clone())
    }))
    .map_or(ptr::null_mut(), into_handle)
}

#[no_mangle]
pub unsafe extern "C" fn shields_engine_deserialize(
    dat: *const u8,
    dat_len: usize,
) -> *mut ShieldsEngine {
    let Some(dat) = byte_arg(dat, dat_len) else {
        return ptr::null_mut();
    };
    catch_unwind(AssertUnwindSafe(|| {
        let mut engine = Engine::default();
        engine.deserialize(dat).ok().map(|()| engine)
    }))
    .ok()
    .flatten()
    .map_or(ptr::null_mut(), into_handle)
}

#[no_mangle]
pub unsafe extern "C" fn shields_engine_serialize(
    engine: *const ShieldsEngine,
    out_dat: *mut ShieldsBuffer,
) -> ShieldsStatus {
    guarded(|| {
        let Some(engine) = engine.as_ref() else {
            return SHIELDS_INVALID_ARGUMENT;
        };
        if out_dat.is_null() {
            return SHIELDS_INVALID_ARGUMENT;
        }
        out_dat.write(ShieldsBuffer::from_vec(engine.engine.serialize()));
        SHIELDS_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn shields_engine_use_resources(
    engine: *mut ShieldsEngine,
    json: *const u8,
    json_len: usize,
) -> ShieldsStatus {
    guarded(|| {
        let (Some(engine), Some(json)) = (engine.as_mut(), byte_arg(json, json_len)) else {
            return SHIELDS_INVALID_ARGUMENT;
        };
        let Ok(resources) = serde_json::from_slice::<Vec<Resource>>(json) else {
            return SHIELDS_INVALID_DATA;
        };
        engine.engine.use_resources(resources);
        SHIELDS_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn shields_engine_free(engine: *mut ShieldsEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

// MARK: - Network requests

/// How to handle one request. See `ShieldsDecision` in shields.h for how the fields combine.
#[repr(C)]
pub struct ShieldsDecision {
    pub matched: bool,
    pub excepted: bool,
    pub important: bool,
    pub should_block: bool,
    pub rule_source_index: i32,
    pub rule_line: i32,
    pub redirect: ShieldsBuffer,
    pub rewritten_url: ShieldsBuffer,
    pub rule: ShieldsBuffer,
    pub exception_rule: ShieldsBuffer,
}

impl ShieldsDecision {
    const EMPTY: Self = Self {
        matched: false,
        excepted: false,
        important: false,
        should_block: false,
        rule_source_index: -1,
        rule_line: -1,
        redirect: ShieldsBuffer::EMPTY,
        rewritten_url: ShieldsBuffer::EMPTY,
        rule: ShieldsBuffer::EMPTY,
        exception_rule: ShieldsBuffer::EMPTY,
    };

    fn from_result(result: BlockerResult) -> Self {
        let should_block = result.should_block();
        let (rule_source_index, rule_line) = result
            .filter
            .as_ref()
            .and_then(|rule| rule.source_location.as_ref())
            .map_or((-1, -1), |location| {
                (location.source_index as i32, location.line_number as i32)
            });
        let raw_line = |rule: Option<FilterRuleDebugInfo>| rule.and_then(|rule| rule.raw_line);
        Self {
            matched: result.filter.is_some(),
            excepted: result.exception.is_some(),
            important: result.important,
            should_block,
            rule_source_index,
            rule_line,
            redirect: ShieldsBuffer::from_optional(result.redirect),
            rewritten_url: ShieldsBuffer::from_optional(result.rewritten_url),
            rule: ShieldsBuffer::from_optional(raw_line(result.filter)),
            exception_rule: ShieldsBuffer::from_optional(raw_line(result.exception)),
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn shields_decision_free(decision: *mut ShieldsDecision) {
    if let Some(decision) = decision.as_mut() {
        decision.redirect.release();
        decision.rewritten_url.release();
        decision.rule.release();
        decision.exception_rule.release();
        *decision = ShieldsDecision::EMPTY;
    }
}

unsafe fn check(
    engine: *const ShieldsEngine,
    out: *mut ShieldsDecision,
    make_request: impl FnOnce() -> Option<Result<Request, adblock::request::RequestError>>,
) -> ShieldsStatus {
    guarded(|| {
        if out.is_null() {
            return SHIELDS_INVALID_ARGUMENT;
        }
        out.write(ShieldsDecision::EMPTY);
        let Some(engine) = engine.as_ref() else {
            return SHIELDS_INVALID_ARGUMENT;
        };
        let request = match make_request() {
            None => return SHIELDS_INVALID_ARGUMENT,
            Some(Err(_)) => return SHIELDS_INVALID_URL,
            Some(Ok(request)) => request,
        };
        out.write(ShieldsDecision::from_result(
            engine.engine.check_network_request(&request),
        ));
        SHIELDS_OK
    })
}

#[no_mangle]
pub unsafe extern "C" fn shields_engine_check_request(
    engine: *const ShieldsEngine,
    url: *const c_char,
    source_url: *const c_char,
    request_type: *const c_char,
    method: *const c_char,
    out: *mut ShieldsDecision,
) -> ShieldsStatus {
    check(engine, out, || {
        let url = c_str_arg(url)?;
        let source_url = c_str_arg(source_url)?;
        let request_type = c_str_arg(request_type)?;
        let method = c_str_arg(method)?;
        Some(Request::new(url, source_url, request_type, method))
    })
}

#[no_mangle]
pub unsafe extern "C" fn shields_engine_check_request_preparsed(
    engine: *const ShieldsEngine,
    url: *const c_char,
    hostname: *const c_char,
    source_hostname: *const c_char,
    request_type: *const c_char,
    third_party: bool,
    method: *const c_char,
    out: *mut ShieldsDecision,
) -> ShieldsStatus {
    check(engine, out, || {
        Some(Ok(Request::preparsed(
            c_str_arg(url)?,
            c_str_arg(hostname)?,
            c_str_arg(source_hostname)?,
            c_str_arg(request_type)?,
            third_party,
            c_str_arg(method)?,
        )))
    })
}

#[no_mangle]
pub unsafe extern "C" fn shields_engine_csp_directives(
    engine: *const ShieldsEngine,
    url: *const c_char,
    source_url: *const c_char,
    request_type: *const c_char,
    out: *mut ShieldsBuffer,
) -> ShieldsStatus {
    guarded(|| {
        let Some(engine) = engine.as_ref() else {
            return SHIELDS_INVALID_ARGUMENT;
        };
        if out.is_null() {
            return SHIELDS_INVALID_ARGUMENT;
        }
        out.write(ShieldsBuffer::EMPTY);
        let (Some(url), Some(source_url), Some(request_type)) = (
            c_str_arg(url),
            c_str_arg(source_url),
            c_str_arg(request_type),
        ) else {
            return SHIELDS_INVALID_ARGUMENT;
        };
        let Ok(request) = Request::new(url, source_url, request_type, "") else {
            return SHIELDS_INVALID_URL;
        };
        out.write(ShieldsBuffer::from_optional(
            engine.engine.get_csp_directives(&request),
        ));
        SHIELDS_OK
    })
}

// MARK: - Cosmetic filtering

#[no_mangle]
pub unsafe extern "C" fn shields_engine_url_cosmetic_resources(
    engine: *const ShieldsEngine,
    url: *const c_char,
    out_json: *mut ShieldsBuffer,
) -> ShieldsStatus {
    guarded(|| {
        let (Some(engine), Some(url)) = (engine.as_ref(), c_str_arg(url)) else {
            return SHIELDS_INVALID_ARGUMENT;
        };
        if out_json.is_null() {
            return SHIELDS_INVALID_ARGUMENT;
        }
        out_json.write(ShieldsBuffer::EMPTY);
        write_json(&engine.engine.url_cosmetic_resources(url), out_json)
    })
}

#[no_mangle]
pub unsafe extern "C" fn shields_engine_hidden_class_id_selectors(
    engine: *const ShieldsEngine,
    query_json: *const u8,
    query_len: usize,
    out_json: *mut ShieldsBuffer,
) -> ShieldsStatus {
    #[derive(serde::Deserialize)]
    struct Query {
        #[serde(default)]
        classes: Vec<String>,
        #[serde(default)]
        ids: Vec<String>,
        #[serde(default)]
        exceptions: HashSet<String>,
    }
    guarded(|| {
        let (Some(engine), Some(query)) = (engine.as_ref(), byte_arg(query_json, query_len)) else {
            return SHIELDS_INVALID_ARGUMENT;
        };
        if out_json.is_null() {
            return SHIELDS_INVALID_ARGUMENT;
        }
        out_json.write(ShieldsBuffer::EMPTY);
        let Ok(query) = serde_json::from_slice::<Query>(query) else {
            return SHIELDS_INVALID_DATA;
        };
        let selectors =
            engine
                .engine
                .hidden_class_id_selectors(&query.classes, &query.ids, &query.exceptions);
        write_json(&selectors, out_json)
    })
}

// MARK: - Domain resolution

/// Writes the byte range of `host`'s registrable domain (eTLD+1) to `start`/`end`, or
/// `0`/`host_len` when it has none.
pub type ShieldsDomainResolver =
    unsafe extern "C" fn(host: *const c_char, host_len: usize, start: *mut usize, end: *mut usize);

#[cfg(not(feature = "embedded-domain-resolver"))]
struct ExternalResolver(ShieldsDomainResolver);

#[cfg(not(feature = "embedded-domain-resolver"))]
impl adblock::url_parser::ResolvesDomain for ExternalResolver {
    fn get_host_domain(&self, host: &str) -> (usize, usize) {
        let (mut start, mut end) = (0, host.len());
        unsafe { (self.0)(host.as_ptr().cast(), host.len(), &mut start, &mut end) };
        let valid = start <= end
            && end <= host.len()
            && host.is_char_boundary(start)
            && host.is_char_boundary(end);
        if valid {
            (start, end)
        } else {
            (0, host.len())
        }
    }
}

#[no_mangle]
pub extern "C" fn shields_set_domain_resolver(
    resolver: Option<ShieldsDomainResolver>,
) -> ShieldsStatus {
    let Some(resolver) = resolver else {
        return SHIELDS_INVALID_ARGUMENT;
    };
    set_resolver(resolver)
}

#[cfg(not(feature = "embedded-domain-resolver"))]
fn set_resolver(resolver: ShieldsDomainResolver) -> ShieldsStatus {
    match adblock::url_parser::set_domain_resolver(Box::new(ExternalResolver(resolver))) {
        Ok(()) => SHIELDS_OK,
        // Already installed: adblock keeps the first resolver for the life of the process.
        Err(_) => SHIELDS_INVALID_ARGUMENT,
    }
}

#[cfg(feature = "embedded-domain-resolver")]
fn set_resolver(_resolver: ShieldsDomainResolver) -> ShieldsStatus {
    SHIELDS_UNSUPPORTED
}

#[cfg(all(test, feature = "embedded-domain-resolver"))]
mod tests {
    use super::*;

    const LIST: &str = "||ads.example^\n@@||ads.example/allowed^\nexample.com##.banner\n";

    unsafe fn engine_from(list: &str) -> *mut ShieldsEngine {
        let set = shields_filter_set_new(true);
        let status = shields_filter_set_add_list(
            set,
            list.as_ptr(),
            list.len(),
            SHIELDS_LIST_FORMAT_STANDARD,
            0,
            ptr::null_mut(),
        );
        assert_eq!(status, SHIELDS_OK);
        let engine = shields_engine_build(set);
        shields_filter_set_free(set);
        assert!(!engine.is_null());
        engine
    }

    unsafe fn blocks(engine: *const ShieldsEngine, url: &CStr) -> bool {
        let mut decision = ShieldsDecision::EMPTY;
        let status = shields_engine_check_request(
            engine,
            url.as_ptr(),
            c"https://example.com/".as_ptr(),
            c"script".as_ptr(),
            c"GET".as_ptr(),
            &mut decision,
        );
        assert_eq!(status, SHIELDS_OK);
        let should_block = decision.should_block;
        shields_decision_free(&mut decision);
        should_block
    }

    #[test]
    fn blocks_and_excepts() {
        unsafe {
            let engine = engine_from(LIST);
            assert!(blocks(engine, c"https://ads.example/x.js"));
            assert!(!blocks(engine, c"https://ads.example/allowed/x.js"));
            assert!(!blocks(engine, c"https://cdn.example.org/x.js"));
            shields_engine_free(engine);
        }
    }

    #[test]
    fn reports_the_matched_rule() {
        unsafe {
            let engine = engine_from(LIST);
            let mut decision = ShieldsDecision::EMPTY;
            shields_engine_check_request(
                engine,
                c"https://ads.example/x.js".as_ptr(),
                c"https://example.com/".as_ptr(),
                c"script".as_ptr(),
                c"GET".as_ptr(),
                &mut decision,
            );
            let rule = std::slice::from_raw_parts(decision.rule.data, decision.rule.len);
            assert_eq!(rule, b"||ads.example^");
            assert_eq!((decision.rule_source_index, decision.rule_line), (0, 0));
            shields_decision_free(&mut decision);
            shields_engine_free(engine);
        }
    }

    #[test]
    fn round_trips_through_a_dat() {
        unsafe {
            let engine = engine_from(LIST);
            let mut dat = ShieldsBuffer::EMPTY;
            assert_eq!(shields_engine_serialize(engine, &mut dat), SHIELDS_OK);
            let restored = shields_engine_deserialize(dat.data, dat.len);
            assert!(!restored.is_null());
            assert!(blocks(restored, c"https://ads.example/x.js"));
            shields_buffer_free(&mut dat);
            shields_engine_free(restored);
            shields_engine_free(engine);
        }
    }

    #[test]
    fn rejects_a_corrupt_dat() {
        unsafe {
            let garbage = [0u8; 64];
            assert!(shields_engine_deserialize(garbage.as_ptr(), garbage.len()).is_null());
        }
    }

    #[test]
    fn serves_host_cosmetics() {
        unsafe {
            let engine = engine_from(LIST);
            let mut json = ShieldsBuffer::EMPTY;
            let status = shields_engine_url_cosmetic_resources(
                engine,
                c"https://example.com/page".as_ptr(),
                &mut json,
            );
            assert_eq!(status, SHIELDS_OK);
            let value: serde_json::Value =
                serde_json::from_slice(std::slice::from_raw_parts(json.data, json.len)).unwrap();
            assert_eq!(value["hide_selectors"], serde_json::json!([".banner"]));
            shields_buffer_free(&mut json);
            shields_engine_free(engine);
        }
    }

    #[cfg(feature = "content-blocking")]
    #[test]
    fn exports_webkit_rules() {
        unsafe {
            let set = shields_filter_set_new(true);
            shields_filter_set_add_list(
                set,
                LIST.as_ptr(),
                LIST.len(),
                SHIELDS_LIST_FORMAT_STANDARD,
                0,
                ptr::null_mut(),
            );
            let mut json = ShieldsBuffer::EMPTY;
            assert_eq!(
                shields_filter_set_to_webkit_rules(set, &mut json),
                SHIELDS_OK
            );
            let value: serde_json::Value =
                serde_json::from_slice(std::slice::from_raw_parts(json.data, json.len)).unwrap();
            assert!(value["convertedFilterCount"].as_u64().unwrap() > 0);
            assert!(!value["rules"].as_array().unwrap().is_empty());
            shields_buffer_free(&mut json);
            shields_filter_set_free(set);
        }
    }
}
