//! WebKit user scripts for what content rule lists cannot express: scriptlets, procedural and
//! action filters, `:style()` rules, and every filter on an entity (`example.*`).
//!
//! The engine decides what each host gets (`url_cosmetic_resources`, so exceptions, trusted
//! scriptlets and entity rules follow adblock-rust exactly); this pass only repackages the
//! answers, in uBlock Origin Lite's shape:
//!
//! - one page-world script per scriptlet function, holding the function (with its
//!   dependencies) once and a table of host → argument lists, injected only on hosts that use
//!   it;
//! - one isolated-world script for procedural and `:style()` filters: the runner
//!   (`js/procedural.js`) and a table of host → filters;
//! - for entities, the same scripts keyed `label.*`, in every frame (no match pattern can name
//!   an entity); an entity's plain hides travel as `display: none` style filters.
//!
//! At run time a script looks up the frame's hostname, then each parent domain, and applies the
//! first entry it finds, checking at each level the host and then its `label.*` entity. Every
//! entry holds the engine's full answer for that host, so the nearest listed host is the right
//! one, and a host whose answer lacks a scriptlet its ancestor or entity has gets an empty entry
//! that stops the walk.
//!
//! No script runs by itself: each queues its work under `Symbol.for("refrax.shields.pending")`,
//! and a dispatcher Refrax registers after them (`ShieldsWebKit`) runs the queue unless the site
//! is exempt, before any page script. Exempting a site then replaces only the dispatcher.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use adblock::resources::{MimeType, Resource, ResourceType};
use adblock::Engine;
use serde::Serialize;
use serde_json::{json, Value};

use crate::webkit::Counts;

const PROCEDURAL_RUNNER: &str = include_str!("../js/procedural.js");

/// Hosts per user script. Small enough that a frame parses tens of kilobytes, not a whole table.
const MAX_HOSTS_PER_SCRIPT: usize = 300;

/// The suffix adblock-rust puts after every scriptlet invocation it assembles.
const INVOCATION_SUFFIX: &str = "\n} catch ( e ) { }\n";
const INVOCATION_PREFIX: &str = "try {\n";

/// A host under a top-level domain no list names, so the engine answers with an entity's
/// rules and generic ones only.
const ENTITY_PROBE_SUFFIX: &str = "shields-entity";
const BASELINE_HOST: &str = "shields-baseline.invalid";

/// The global the scripts queue their work in, run by Refrax's dispatcher.
pub const PENDING_KEY: &str = "refrax.shields.pending";

/// A user script to install in every frame at document start.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserScript {
    /// The scriptlet resource name, or `procedural`.
    pub name: String,
    /// `page` (the page's main world) or `shields` (an isolated world).
    pub world: &'static str,
    pub source: String,
    /// Match patterns: `*://host/*` and `*://*.host/*` for each host with an entry, or
    /// `*://*/*` for entity entries.
    pub includes: Vec<String>,
}

/// Host (or `label.*`) → this script's entries for it (argument lists, or procedural filters).
type Table = BTreeMap<String, Vec<Value>>;

#[derive(Default)]
struct Answer {
    /// Function name → argument lists, in the engine's order.
    invocations: BTreeMap<String, Vec<Value>>,
    procedural: Vec<Value>,
}

/// The `label.*` key a frame's walk checks at `host`'s level, if `host` has a dot.
fn entity_key(host: &str) -> Option<String> {
    host.find('.')
        .filter(|&dot| dot > 0)
        .map(|dot| format!("{}.*", &host[..dot]))
}

pub fn user_scripts(
    hosts: &BTreeSet<String>,
    entities: &BTreeSet<String>,
    engine: &Engine,
    resources: &[Resource],
    counts: &mut Counts,
) -> Vec<UserScript> {
    let host_list: Vec<String> = hosts.iter().cloned().collect();
    let probes: Vec<String> = entities
        .iter()
        .map(|label| format!("{label}.{ENTITY_PROBE_SUFFIX}"))
        .collect();
    let baseline_hides: HashSet<String> = engine
        .url_cosmetic_resources(&format!("https://{BASELINE_HOST}/"))
        .hide_selectors
        .into_iter()
        .collect();
    let mut answers = answers(&host_list, engine, None, counts);
    let probe_answers = answers_for_entities(&probes, engine, &baseline_hides, counts);
    let entity_answers: BTreeMap<String, Answer> = entities
        .iter()
        .zip(probe_answers)
        .map(|(label, answer)| (format!("{label}.*"), answer))
        .collect();
    // A listed host's entry stops its walk, so it carries its entity's hides as well.
    for (host, answer) in &mut answers {
        let mut suffix = host.as_str();
        loop {
            if let Some(entity) = entity_key(suffix).and_then(|key| entity_answers.get(&key)) {
                let hides = entity
                    .procedural
                    .iter()
                    .filter(|filter| is_entity_hide(filter));
                answer.procedural.extend(hides.cloned());
                break;
            }
            match suffix.find('.') {
                Some(dot) => suffix = &suffix[dot + 1..],
                None => break,
            }
        }
    }
    let functions = FunctionLibrary::new(resources);

    let mut scripts = Vec::new();
    let mut function_names: BTreeSet<&str> = BTreeSet::new();
    for answer in answers.values().chain(entity_answers.values()) {
        function_names.extend(answer.invocations.keys().map(String::as_str));
    }
    for function in function_names {
        let Some((resource_name, code)) = functions.code(function) else {
            counts.unsupported("scriptletFunction");
            continue;
        };
        let (hosts, entities) = tables(&answers, &entity_answers, |answer| {
            answer.invocations.get(function).cloned()
        });
        let call = format!(
            "for (const args of entry) {{ try {{ {function}(...args); }} catch (e) {{ }} }}"
        );
        let shards = shards(hosts)
            .into_iter()
            .map(|shard| (includes(&shard), shard));
        for (includes, shard) in shards.chain(entity_shard(entities)) {
            scripts.push(UserScript {
                name: resource_name.to_string(),
                world: "page",
                includes,
                source: queued(&format!(
                    "const scriptletGlobals = {{}};\n{code}\nconst table = {};\n{}",
                    serde_json::to_string(&shard).expect("tables serialize"),
                    lookup(&call),
                )),
            });
        }
    }

    let (hosts, entities) = tables(&answers, &entity_answers, |answer| {
        (!answer.procedural.is_empty()).then(|| answer.procedural.clone())
    });
    let shards = shards(hosts)
        .into_iter()
        .map(|shard| (includes(&shard), shard));
    for (includes, shard) in shards.chain(entity_shard(entities)) {
        scripts.push(UserScript {
            name: "procedural".to_string(),
            world: "shields",
            includes,
            source: queued(&format!(
                "{PROCEDURAL_RUNNER}\nconst table = {};\n{}",
                serde_json::to_string(&shard).expect("tables serialize"),
                lookup("if (entry.length > 0) { shieldsApplyProcedural(entry); }"),
            )),
        });
    }
    counts.bundle_hosts = answers.len();
    counts.entities = entity_answers.len();
    scripts
}

/// Wraps a script body so it runs when Refrax's dispatcher runs the queue.
fn queued(body: &str) -> String {
    format!(
        "(function() {{\nconst run = () => {{\n{body}\n}};\n\
         (globalThis[Symbol.for({key})] ||= []).push(run);\n}})();\n",
        key = serde_json::to_string(PENDING_KEY).expect("strings serialize"),
    )
}

/// JavaScript that finds `table`'s entry for the frame's host, its nearest listed parent
/// domain, or the first matching `label.*` entity on the way, and runs `body` with it bound to
/// `entry`.
///
/// A frame without a host of its own (`about:blank`, `about:srcdoc`, a `javascript:` frame),
/// which Refrax's dispatcher reaches through its creator, takes the host of the nearest
/// same-origin ancestor that has one: it shares that document's origin.
fn lookup(body: &str) -> String {
    format!(
        "const has = (key) => Object.prototype.hasOwnProperty.call(table, key);\n\
         let host = location.hostname;\n\
         try {{ for (let w = window; !host && w !== w.parent; w = w.parent) {{ host = w.parent.location.hostname; }} }} catch (e) {{ }}\n\
         while (host) {{\n\
         const dot = host.indexOf('.');\n\
         const key = has(host) ? host : (dot > 0 && has(host.slice(0, dot) + '.*') ? host.slice(0, dot) + '.*' : null);\n\
         if (key !== null) {{ const entry = table[key]; {body} break; }}\n\
         if (dot < 0) {{ break; }}\n\
         host = host.slice(dot + 1);\n\
         }}"
    )
}

/// The engine's answer for every host, computed on all cores (the engine is `Sync`).
fn answers(
    hosts: &[String],
    engine: &Engine,
    entity_hides: Option<&HashSet<String>>,
    counts: &mut Counts,
) -> BTreeMap<String, Answer> {
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
                            let mut procedural: Vec<Value> = procedural
                                .iter()
                                .filter_map(|filter| serde_json::from_str(filter).ok())
                                .collect();
                            if let Some(baseline) = entity_hides {
                                let mut hides: Vec<String> = resources
                                    .hide_selectors
                                    .into_iter()
                                    .filter(|selector| !baseline.contains(selector))
                                    .collect();
                                hides.sort();
                                procedural.extend(
                                    hides.into_iter().map(|selector| entity_hide(&selector)),
                                );
                            }
                            (
                                host.clone(),
                                Answer {
                                    invocations,
                                    procedural,
                                },
                                malformed,
                            )
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

/// The answers for entity probe hosts, in probe order, with the entity's plain hides (what the
/// probe hides beyond the generic baseline) as style filters.
fn answers_for_entities(
    probes: &[String],
    engine: &Engine,
    baseline_hides: &HashSet<String>,
    counts: &mut Counts,
) -> Vec<Answer> {
    let mut answers = answers(probes, engine, Some(baseline_hides), counts);
    probes
        .iter()
        .map(|probe| answers.remove(probe).unwrap_or_default())
        .collect()
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

const ENTITY_HIDE_STYLE: &str = "display: none !important";

fn entity_hide(selector: &str) -> Value {
    json!({
        "selector": [{"type": "css-selector", "arg": selector}],
        "action": {"type": "style", "arg": ENTITY_HIDE_STYLE},
    })
}

fn is_entity_hide(filter: &Value) -> bool {
    filter["action"]["arg"] == ENTITY_HIDE_STYLE
}

/// The host table and the entity table for one script.
///
/// The host table has an entry for every host whose answer has one, plus an empty entry for
/// each host whose nearest listed ancestor has one but it does not. The entity table has the
/// `label.*` entries, plus an empty entry for every listed host whose walk would reach one: the
/// host scripts carry that host's full answer, entity rules included.
fn tables(
    answers: &BTreeMap<String, Answer>,
    entity_answers: &BTreeMap<String, Answer>,
    entry: impl Fn(&Answer) -> Option<Vec<Value>>,
) -> (Table, Table) {
    let mut hosts: Table = answers
        .iter()
        .filter_map(|(host, answer)| entry(answer).map(|value| (host.clone(), value)))
        .collect();
    let blocked: Vec<String> = answers
        .keys()
        .filter(|host| !hosts.contains_key(*host))
        .filter(|host| {
            let mut suffix = host.as_str();
            while let Some(dot) = suffix.find('.') {
                suffix = &suffix[dot + 1..];
                if hosts.contains_key(suffix) {
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
        hosts.insert(host, Vec::new());
    }

    let mut entities: Table = entity_answers
        .iter()
        .filter_map(|(key, answer)| entry(answer).map(|value| (key.clone(), value)))
        .collect();
    if !entities.is_empty() {
        let reaching: Vec<String> = answers
            .keys()
            .filter(|host| reaches_entity(host, &entities))
            .cloned()
            .collect();
        for host in reaching {
            entities.insert(host, Vec::new());
        }
    }
    (hosts, entities)
}

fn reaches_entity(host: &str, entities: &Table) -> bool {
    let mut suffix = host;
    loop {
        if entity_key(suffix).is_some_and(|key| entities.contains_key(&key)) {
            return true;
        }
        match suffix.find('.') {
            Some(dot) => suffix = &suffix[dot + 1..],
            None => return false,
        }
    }
}

/// The entity table as one script for every frame, when any entity has an entry.
fn entity_shard(entities: Table) -> Option<(Vec<String>, Table)> {
    let has_entries = entities
        .iter()
        .any(|(key, entry)| key.ends_with(".*") && !entry.is_empty());
    has_entries.then(|| (vec!["*://*/*".to_string()], entities))
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
        let (table, entities) = tables(&answers, &BTreeMap::new(), |answer| {
            (!answer.procedural.is_empty()).then(|| answer.procedural.clone())
        });
        assert!(entities.is_empty());
        assert_eq!(table.len(), 2);
        assert!(table["sub.example.com"].is_empty());
        assert_eq!(
            includes(&table),
            ["*://example.com/*", "*://*.example.com/*"]
        );
    }

    #[test]
    fn entity_entries_run_everywhere_and_listed_hosts_stop_their_walk() {
        let mut answers = BTreeMap::new();
        answers.insert("example.com".to_string(), Answer::default());
        let mut entity = Answer::default();
        entity.procedural.push(entity_hide(".ad"));
        let mut entity_answers = BTreeMap::new();
        entity_answers.insert("example.*".to_string(), entity);
        let (hosts, entities) = tables(&answers, &entity_answers, |answer| {
            (!answer.procedural.is_empty()).then(|| answer.procedural.clone())
        });
        assert!(hosts.is_empty());
        assert_eq!(entities["example.*"].len(), 1);
        assert!(
            entities["example.com"].is_empty(),
            "the listed host answers for itself"
        );
        let (includes, _) = entity_shard(entities).expect("an entity shard");
        assert_eq!(includes, ["*://*/*"]);
        assert_eq!(entity_key("www.example.co.uk").as_deref(), Some("www.*"));
        assert_eq!(entity_key("localhost"), None);
    }
}
