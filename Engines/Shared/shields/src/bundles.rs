//! WebKit user scripts for what content rule lists cannot express: scriptlets, procedural and
//! action filters, `:style()` rules.
//!
//! The engine decides what each host gets (`url_cosmetic_resources`, so exceptions, trusted
//! scriptlets and entity rules follow adblock-rust exactly); this pass only repackages the
//! answers. Grouping hosts by identical answer, as the design first proposed, measured 5,463
//! distinct groups and 70 MB of script for the default lists, because every group repeats the
//! scriptlet functions it calls. So the output is uBlock Origin Lite's shape instead:
//!
//! - one page-world script per scriptlet function, holding the function (with its
//!   dependencies) once and a table of host → argument lists, injected only on hosts that use
//!   it;
//! - one isolated-world script for procedural and `:style()` filters: the runner
//!   (`js/procedural.js`) and a table of host → filters.
//!
//! At run time a script looks up the frame's hostname, then each parent domain, and applies the
//! first entry it finds. Every entry holds the engine's full answer for that host, so the
//! nearest listed host is the right one, and a host whose answer lacks a scriptlet its ancestor
//! has gets an empty entry that stops the walk.

use std::collections::{BTreeMap, BTreeSet, HashMap};

use adblock::resources::{MimeType, Resource, ResourceType};
use adblock::Engine;
use serde::Serialize;
use serde_json::Value;

use crate::webkit::Counts;

const PROCEDURAL_RUNNER: &str = include_str!("../js/procedural.js");

/// Hosts per user script. Small enough that a frame parses tens of kilobytes, not a whole table.
const MAX_HOSTS_PER_SCRIPT: usize = 300;

/// The suffix adblock-rust puts after every scriptlet invocation it assembles.
const INVOCATION_SUFFIX: &str = "\n} catch ( e ) { }\n";
const INVOCATION_PREFIX: &str = "try {\n";

/// A user script to install in every frame at document start.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserScript {
    /// The scriptlet resource name, or `procedural`.
    pub name: String,
    /// `page` (the page's main world) or `shields` (an isolated world).
    pub world: &'static str,
    pub source: String,
    /// Match patterns: `*://host/*` and `*://*.host/*` for each host with an entry.
    pub includes: Vec<String>,
}

/// Host → this script's entries for it (argument lists, or procedural filters).
type Table = BTreeMap<String, Vec<Value>>;

#[derive(Default)]
struct Answer {
    /// Function name → argument lists, in the engine's order.
    invocations: BTreeMap<String, Vec<Value>>,
    procedural: Vec<Value>,
}

pub fn user_scripts(
    hosts: &BTreeSet<String>,
    engine: &Engine,
    resources: &[Resource],
    counts: &mut Counts,
) -> Vec<UserScript> {
    let hosts: Vec<&String> = hosts.iter().collect();
    let answers = answers(&hosts, engine, counts);
    let functions = FunctionLibrary::new(resources);

    let mut scripts = Vec::new();
    let mut function_names: BTreeSet<&str> = BTreeSet::new();
    for answer in answers.values() {
        function_names.extend(answer.invocations.keys().map(String::as_str));
    }
    for function in function_names {
        let Some((resource_name, code)) = functions.code(function) else {
            counts.unsupported("scriptletFunction");
            continue;
        };
        let table = table(&answers, |answer| answer.invocations.get(function).cloned());
        let call = format!(
            "for (const args of entry) {{ try {{ {function}(...args); }} catch (e) {{ }} }}"
        );
        for shard in shards(table) {
            scripts.push(UserScript {
                name: resource_name.to_string(),
                world: "page",
                includes: includes(&shard),
                source: format!(
                    "(function() {{\nconst scriptletGlobals = {{}};\n{code}\nconst table = {};\n{}\n}})();\n",
                    serde_json::to_string(&shard).expect("tables serialize"),
                    lookup(&call),
                ),
            });
        }
    }

    let procedural = table(&answers, |answer| {
        (!answer.procedural.is_empty()).then(|| answer.procedural.clone())
    });
    for shard in shards(procedural) {
        scripts.push(UserScript {
            name: "procedural".to_string(),
            world: "shields",
            includes: includes(&shard),
            source: format!(
                "(function() {{\n{PROCEDURAL_RUNNER}\nconst table = {};\n{}\n}})();\n",
                serde_json::to_string(&shard).expect("tables serialize"),
                lookup("if (entry.length > 0) { shieldsApplyProcedural(entry); }"),
            ),
        });
    }
    counts.bundle_hosts = answers.len();
    scripts
}

/// JavaScript that finds `table`'s entry for the frame's host or its nearest listed parent
/// domain and runs `body` with it bound to `entry`.
fn lookup(body: &str) -> String {
    format!(
        "let host = location.hostname;\n\
         while (host) {{\n\
         if (Object.prototype.hasOwnProperty.call(table, host)) {{ const entry = table[host]; {body} break; }}\n\
         const dot = host.indexOf('.');\n\
         if (dot < 0) {{ break; }}\n\
         host = host.slice(dot + 1);\n\
         }}"
    )
}

/// The engine's answer for every host, computed on all cores (the engine is `Sync`).
fn answers(hosts: &[&String], engine: &Engine, counts: &mut Counts) -> BTreeMap<String, Answer> {
    let threads = std::thread::available_parallelism().map_or(4, usize::from);
    let chunk = hosts.len().div_ceil(threads).max(1);
    let results: Vec<(String, Answer, usize)> = std::thread::scope(|scope| {
        let workers: Vec<_> = hosts
            .chunks(chunk)
            .map(|chunk| {
                scope.spawn(move || {
                    chunk
                        .iter()
                        .map(|host| {
                            let resources =
                                engine.url_cosmetic_resources(&format!("https://{host}/"));
                            let (invocations, malformed) =
                                parse_invocations(&resources.injected_script);
                            let mut procedural: Vec<String> =
                                resources.procedural_actions.into_iter().collect();
                            procedural.sort();
                            let answer = Answer {
                                invocations,
                                procedural: procedural
                                    .iter()
                                    .filter_map(|filter| serde_json::from_str(filter).ok())
                                    .collect(),
                            };
                            (host.to_string(), answer, malformed)
                        })
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        workers
            .into_iter()
            .flat_map(|worker| worker.join().expect("cosmetic workers do not panic"))
            .collect()
    });
    let mut answers = BTreeMap::new();
    for (host, answer, malformed) in results {
        for _ in 0..malformed {
            counts.unsupported("scriptletInvocation");
        }
        answers.insert(host, answer);
    }
    answers
}

/// Splits an assembled `injected_script` into `function(args…)` invocations. Returns them by
/// function name, plus how many invocations had another shape.
fn parse_invocations(script: &str) -> (BTreeMap<String, Vec<Value>>, usize) {
    let mut invocations: BTreeMap<String, Vec<Value>> = BTreeMap::new();
    let mut malformed = 0;
    let mut rest = script;
    let mut calls = Vec::new();
    while let Some(body) = rest.strip_suffix(INVOCATION_SUFFIX) {
        let Some(start) = body.rfind(INVOCATION_PREFIX) else {
            break;
        };
        calls.push(&body[start + INVOCATION_PREFIX.len()..]);
        rest = &body[..start];
    }
    calls.reverse();
    for call in calls {
        let parsed = call
            .find('(')
            .filter(|_| call.ends_with(')'))
            .and_then(|paren| {
                let name = &call[..paren];
                let arguments: Value =
                    serde_json::from_str(&format!("[{}]", &call[paren + 1..call.len() - 1]))
                        .ok()?;
                let is_identifier = !name.is_empty()
                    && name.chars().all(|character| {
                        character.is_alphanumeric() || character == '_' || character == '$'
                    });
                is_identifier.then(|| (name.to_string(), arguments))
            });
        match parsed {
            Some((name, arguments)) => invocations.entry(name).or_default().push(arguments),
            None => malformed += 1,
        }
    }
    (invocations, malformed)
}

/// Host → entry for every host whose answer has one, plus an empty entry for each host whose
/// nearest listed ancestor has one but it does not.
fn table(
    answers: &BTreeMap<String, Answer>,
    entry: impl Fn(&Answer) -> Option<Vec<Value>>,
) -> Table {
    let mut table: Table = answers
        .iter()
        .filter_map(|(host, answer)| entry(answer).map(|value| (host.clone(), value)))
        .collect();
    let blocked: Vec<String> = answers
        .keys()
        .filter(|host| !table.contains_key(*host))
        .filter(|host| {
            let mut suffix = host.as_str();
            while let Some(dot) = suffix.find('.') {
                suffix = &suffix[dot + 1..];
                if table.contains_key(suffix) {
                    return true;
                }
                if answers.contains_key(suffix) {
                    return false;
                }
            }
            false
        })
        .cloned()
        .collect();
    for host in blocked {
        table.insert(host, Vec::new());
    }
    table
}

/// Splits a table into pieces of about `MAX_HOSTS_PER_SCRIPT` hosts, keeping each host with
/// its listed ancestors (its walk must find them in the same script). A frame then parses only
/// the piece for its site instead of every host's entry.
fn shards(table: Table) -> Vec<Table> {
    let mut by_root: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for host in table.keys() {
        let mut root = host.as_str();
        let mut suffix = host.as_str();
        while let Some(dot) = suffix.find('.') {
            suffix = &suffix[dot + 1..];
            if table.contains_key(suffix) {
                root = suffix;
            }
        }
        by_root
            .entry(root.to_string())
            .or_default()
            .push(host.clone());
    }
    let mut table = table;
    let mut shards = Vec::new();
    let mut shard = BTreeMap::new();
    for hosts in by_root.into_values() {
        for host in hosts {
            if let Some(entry) = table.remove(&host) {
                shard.insert(host, entry);
            }
        }
        if shard.len() >= MAX_HOSTS_PER_SCRIPT {
            shards.push(std::mem::take(&mut shard));
        }
    }
    shards.push(shard);
    shards.retain(|shard| !includes(shard).is_empty());
    shards
}

fn includes(table: &Table) -> Vec<String> {
    table
        .iter()
        .filter(|(_, entry)| !entry.is_empty())
        .flat_map(|(host, _)| host_patterns(host))
        .collect()
}

/// Match patterns for `host` and its subdomains; an IP address has no subdomains.
fn host_patterns(host: &str) -> Vec<String> {
    let is_address = host.parse::<std::net::IpAddr>().is_ok() || host.starts_with('[');
    if is_address {
        vec![format!("*://{host}/*")]
    } else {
        vec![format!("*://{host}/*"), format!("*://*.{host}/*")]
    }
}

/// Scriptlet function name → its resource and the code that defines it with its dependencies.
struct FunctionLibrary {
    by_function: HashMap<String, String>,
    text: HashMap<String, (String, Vec<String>)>,
}

impl FunctionLibrary {
    fn new(resources: &[Resource]) -> Self {
        let mut by_function = HashMap::new();
        let mut text = HashMap::new();
        for resource in resources {
            let is_script = matches!(
                resource.kind,
                ResourceType::Mime(MimeType::ApplicationJavascript | MimeType::FnJavascript)
            );
            let Some(source) = is_script
                .then(|| decode_base64(&resource.content))
                .flatten()
            else {
                continue;
            };
            if let Some(name) = function_name(&source) {
                by_function.insert(name.to_string(), resource.name.clone());
            }
            text.insert(
                resource.name.clone(),
                (source, resource.dependencies.clone()),
            );
        }
        Self { by_function, text }
    }

    fn code(&self, function: &str) -> Option<(&str, String)> {
        let resource = self.by_function.get(function)?;
        let mut order = Vec::new();
        self.collect(resource, &mut order);
        let code = order
            .iter()
            .filter_map(|name| self.text.get(*name).map(|(source, _)| source.as_str()))
            .collect::<Vec<_>>()
            .join("\n");
        Some((resource, code))
    }

    fn collect<'a>(&'a self, name: &'a str, order: &mut Vec<&'a str>) {
        if order.contains(&name) {
            return;
        }
        order.push(name);
        if let Some((_, dependencies)) = self.text.get(name) {
            for dependency in dependencies {
                self.collect(dependency, order);
            }
        }
    }
}

fn function_name(source: &str) -> Option<&str> {
    let rest = source.strip_prefix("function")?.trim_start();
    let end = rest.find(|character: char| character == '(' || character.is_whitespace())?;
    (end > 0).then(|| &rest[..end])
}

fn decode_base64(text: &str) -> Option<String> {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut values = [255u8; 256];
    for (index, &character) in ALPHABET.iter().enumerate() {
        values[character as usize] = index as u8;
    }
    let mut bytes = Vec::with_capacity(text.len() * 3 / 4);
    let mut buffer = 0u32;
    let mut bits = 0;
    for &character in text.as_bytes() {
        if character == b'=' || character.is_ascii_whitespace() {
            continue;
        }
        let value = values[character as usize];
        if value == 255 {
            return None;
        }
        buffer = (buffer << 6) | u32::from(value);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            bytes.push((buffer >> bits) as u8);
        }
    }
    String::from_utf8(bytes).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_assembled_invocations() {
        let script = "function setConstant(a, b) {}\ntry {\nsetConstant(\"ads\", \"false\")\n} catch ( e ) { }\ntry {\nnoWindowOpen()\n} catch ( e ) { }\n";
        let (invocations, malformed) = parse_invocations(script);
        assert_eq!(malformed, 0);
        assert_eq!(
            invocations["setConstant"],
            vec![serde_json::json!(["ads", "false"])]
        );
        assert_eq!(invocations["noWindowOpen"], vec![serde_json::json!([])]);
    }

    #[test]
    fn decodes_base64() {
        assert_eq!(
            decode_base64("ZnVuY3Rpb24gYSgpIHt9").as_deref(),
            Some("function a() {}")
        );
        assert_eq!(function_name("function a() {}"), Some("a"));
    }

    #[test]
    fn stops_the_walk_where_an_exception_removes_an_entry() {
        let mut answers = BTreeMap::new();
        let mut parent = Answer::default();
        parent.procedural.push(serde_json::json!({"selector": []}));
        answers.insert("example.com".to_string(), parent);
        answers.insert("sub.example.com".to_string(), Answer::default());
        answers.insert("other.org".to_string(), Answer::default());
        let table = table(&answers, |answer| {
            (!answer.procedural.is_empty()).then(|| answer.procedural.clone())
        });
        assert_eq!(table.len(), 2);
        assert!(table["sub.example.com"].is_empty());
        assert_eq!(
            includes(&table),
            ["*://example.com/*", "*://*.example.com/*"]
        );
    }
}
