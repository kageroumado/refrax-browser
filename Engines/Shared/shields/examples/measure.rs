//! Measures a Shields build over real lists: parse + build time, DAT size (debug and
//! non-debug), deserialize time, a deserialized engine's resident memory, and the WebKit pass.
//!
//! cargo run --release --example measure -- <resources.json> <output dir> <list.txt>...
//!
//! Resident memory is read with `ps` around a deserialize in a child process
//! (`measure --load <engine.dat>`), so the build's own allocations don't count.

use std::ffi::CString;
use std::process::Command;
use std::ptr;
use std::time::Instant;

use shields::*;

fn resident_kilobytes() -> u64 {
    let output = Command::new("ps")
        .args(["-o", "rss=", "-p", &std::process::id().to_string()])
        .output()
        .expect("ps runs");
    String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse()
        .unwrap_or(0)
}

fn bytes(buffer: &ShieldsBuffer) -> &[u8] {
    if buffer.data.is_null() {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(buffer.data, buffer.len) }
    }
}

fn load(dat_path: &str) {
    let dat = std::fs::read(dat_path).expect("reads the DAT");
    let before = resident_kilobytes();
    let start = Instant::now();
    let engine = unsafe { shields_engine_deserialize(dat.as_ptr(), dat.len()) };
    let elapsed = start.elapsed();
    assert!(!engine.is_null(), "DAT loads");
    drop(dat);
    let after = resident_kilobytes();
    println!(
        "deserialize {:.0} ms, resident +{:.1} MB",
        elapsed.as_secs_f64() * 1000.0,
        (after.saturating_sub(before)) as f64 / 1024.0
    );
    unsafe { shields_engine_free(engine) };
}

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    if arguments.len() == 3 && arguments[1] == "--load" {
        return load(&arguments[2]);
    }
    let [_, resources_path, output, lists @ ..] = arguments.as_slice() else {
        eprintln!("usage: measure <resources.json> <output dir> <list.txt>...");
        std::process::exit(64);
    };
    let texts: Vec<Vec<u8>> = lists
        .iter()
        .map(|path| std::fs::read(path).expect("reads a list"))
        .collect();
    let resources = std::fs::read(resources_path).expect("reads resources.json");
    std::fs::create_dir_all(output).expect("creates the output directory");

    for debug in [false, true] {
        let start = Instant::now();
        let set = shields_filter_set_new(debug);
        for text in &texts {
            unsafe {
                shields_filter_set_add_list(set, text.as_ptr(), text.len(), 0, 0, ptr::null_mut());
            }
        }
        let engine = unsafe { shields_engine_build(set) };
        let build = start.elapsed();
        assert!(!engine.is_null(), "engine builds");
        unsafe { shields_engine_use_resources(engine, resources.as_ptr(), resources.len()) };
        let mut dat = ShieldsBuffer {
            data: ptr::null_mut(),
            len: 0,
            capacity: 0,
        };
        unsafe { shields_engine_serialize(engine, &mut dat) };
        let name = if debug {
            "engine-debug.dat"
        } else {
            "engine.dat"
        };
        let dat_path = format!("{output}/{name}");
        std::fs::write(&dat_path, bytes(&dat)).expect("writes the DAT");
        println!(
            "{}: parse + build {:.0} ms, DAT {:.2} MB",
            if debug { "debug" } else { "release" },
            build.as_secs_f64() * 1000.0,
            dat.len as f64 / 1_048_576.0
        );
        unsafe { shields_buffer_free(&mut dat) };
        let status = Command::new(&arguments[0])
            .args(["--load", &dat_path])
            .status();
        assert!(
            status.is_ok_and(|status| status.success()),
            "child load succeeds"
        );

        if debug {
            let mut stats = ShieldsBuffer {
                data: ptr::null_mut(),
                len: 0,
                capacity: 0,
            };
            let start = Instant::now();
            unsafe { shields_filter_set_stats(set, &mut stats) };
            println!(
                "stats {:.0} ms: {}",
                start.elapsed().as_secs_f64() * 1000.0,
                String::from_utf8_lossy(bytes(&stats))
            );
            unsafe { shields_buffer_free(&mut stats) };

            let directory = CString::new(format!("{output}/webkit")).unwrap();
            let mut summary = ShieldsBuffer {
                data: ptr::null_mut(),
                len: 0,
                capacity: 0,
            };
            let start = Instant::now();
            let status = unsafe {
                shields_webkit_compile(
                    set,
                    engine,
                    ptr::null(),
                    0,
                    directory.as_ptr(),
                    &mut summary,
                )
            };
            println!(
                "webkit pass {:.0} ms (status {status}): {}",
                start.elapsed().as_secs_f64() * 1000.0,
                String::from_utf8_lossy(bytes(&summary))
            );
            unsafe { shields_buffer_free(&mut summary) };
        }
        unsafe {
            shields_engine_free(engine);
            shields_filter_set_free(set);
        }
    }
}
