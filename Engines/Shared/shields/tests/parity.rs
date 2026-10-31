//! "Same list, same decisions": the decision stream over a slice of adblock-rust's request
//! corpus must hash identically for
//!   (a) the engine as built,
//!   (b) the same engine after a DAT round trip, and
//!   (c) that DAT loaded by the host's feature set (no embedded resolver, no content-blocking).
//! (a) and (b) run under the default (`app`) features and write the DAT; (c) runs under
//! `cargo test --no-default-features` and reads it, so run the default suite first.
//! All three must equal `tests/data/parity.golden`; a new hash after a list or crate change is
//! reviewed and committed (`examples/parity_fixture.rs` regenerates the fixture).

use std::ffi::CString;
use std::path::{Path, PathBuf};

use shields::*;

fn data(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/data")
        .join(name)
}

fn dat_path() -> PathBuf {
    Path::new(env!("CARGO_TARGET_TMPDIR")).join("parity.dat")
}

fn golden() -> String {
    std::fs::read_to_string(data("parity.golden"))
        .expect("tests/data/parity.golden exists")
        .trim()
        .to_string()
}

fn resources() -> Vec<u8> {
    std::fs::read(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../Refrax/Resources/Shields/resources.json"),
    )
    .expect("the app's resources.json exists")
}

/// FNV-1a over `(should_block, redirected, rewritten_url)` for every corpus request.
unsafe fn decision_hash(engine: *const ShieldsEngine) -> (String, usize) {
    let corpus = std::fs::read_to_string(data("requests.jsonl")).expect("the corpus slice exists");
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    let mut feed = |bytes: &[u8]| {
        for byte in bytes {
            hash ^= u64::from(*byte);
            hash = hash.wrapping_mul(0x0100_0000_01b3);
        }
    };
    let mut blocked = 0;
    for line in corpus.lines() {
        let request: serde_json::Value = serde_json::from_str(line).expect("corpus lines are JSON");
        let field = |name: &str| CString::new(request[name].as_str().unwrap_or_default()).unwrap();
        let (url, frame, kind) = (field("url"), field("frameUrl"), field("cpt"));
        let mut decision: ShieldsDecision = std::mem::zeroed();
        let status = shields_engine_check_request(
            engine,
            url.as_ptr(),
            frame.as_ptr(),
            kind.as_ptr(),
            c"GET".as_ptr(),
            &mut decision,
        );
        let rewritten = if decision.rewritten_url.data.is_null() {
            &[][..]
        } else {
            std::slice::from_raw_parts(decision.rewritten_url.data, decision.rewritten_url.len)
        };
        feed(&[
            status as u8,
            decision.should_block as u8,
            !decision.redirect.data.is_null() as u8,
        ]);
        feed(rewritten);
        feed(b"\n");
        blocked += decision.should_block as usize;
        shields_decision_free(&mut decision);
    }
    (format!("{hash:016x}"), blocked)
}

#[cfg(feature = "embedded-domain-resolver")]
#[test]
fn app_engine_and_its_dat_decide_alike() {
    unsafe {
        let list = std::fs::read(data("filters.txt")).expect("the filter slice exists");
        let set = shields_filter_set_new(true);
        assert_eq!(
            shields_filter_set_add_list(
                set,
                list.as_ptr(),
                list.len(),
                SHIELDS_LIST_FORMAT_STANDARD,
                0,
                std::ptr::null_mut()
            ),
            SHIELDS_OK
        );
        let built = shields_engine_build(set);
        shields_filter_set_free(set);
        let resources = resources();
        assert_eq!(
            shields_engine_use_resources(built, resources.as_ptr(), resources.len()),
            SHIELDS_OK
        );

        let (built_hash, blocked) = decision_hash(built);
        assert!(
            blocked > 100,
            "the slice exercises blocking ({blocked} blocked)"
        );

        let mut dat = ShieldsBuffer {
            data: std::ptr::null_mut(),
            len: 0,
            capacity: 0,
        };
        assert_eq!(shields_engine_serialize(built, &mut dat), SHIELDS_OK);
        let bytes = std::slice::from_raw_parts(dat.data, dat.len).to_vec();
        shields_buffer_free(&mut dat);
        std::fs::write(dat_path(), &bytes).expect("writes the DAT for the host-feature run");

        let restored = shields_engine_deserialize(bytes.as_ptr(), bytes.len());
        assert!(!restored.is_null());
        assert_eq!(
            shields_engine_use_resources(restored, resources.as_ptr(), resources.len()),
            SHIELDS_OK
        );
        let (restored_hash, _) = decision_hash(restored);

        assert_eq!(
            built_hash, restored_hash,
            "a DAT round trip changes no decision"
        );
        assert_eq!(
            built_hash,
            golden(),
            "decisions changed: review, then update tests/data/parity.golden"
        );
        shields_engine_free(built);
        shields_engine_free(restored);
    }
}

#[cfg(not(feature = "embedded-domain-resolver"))]
#[test]
fn host_features_decide_like_the_app() {
    unsafe extern "C" fn resolve(
        host: *const std::ffi::c_char,
        length: usize,
        start: *mut usize,
        end: *mut usize,
    ) {
        let host = std::str::from_utf8(std::slice::from_raw_parts(host.cast::<u8>(), length))
            .unwrap_or_default();
        let (from, to) = match addr::parse_domain_name(host)
            .ok()
            .and_then(|name| name.root())
        {
            Some(root) => (host.len() - root.len(), host.len()),
            None => (0, host.len()),
        };
        *start = from;
        *end = to;
    }
    unsafe {
        assert_eq!(shields_set_domain_resolver(Some(resolve)), SHIELDS_OK);
        let bytes = std::fs::read(dat_path())
            .expect("run `cargo test` (default features) first: it writes the DAT this test loads");
        let engine = shields_engine_deserialize(bytes.as_ptr(), bytes.len());
        assert!(!engine.is_null(), "the host features load the app's DAT");
        let resources = resources();
        assert_eq!(
            shields_engine_use_resources(engine, resources.as_ptr(), resources.len()),
            SHIELDS_OK
        );
        let (hash, _) = decision_hash(engine);
        assert_eq!(
            hash,
            golden(),
            "the host's feature set decides differently from the app's"
        );
        shields_engine_free(engine);
    }
}
