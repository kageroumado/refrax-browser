//! The Refrax pass: WebKit content rule lists and per-host cosmetic bundles from one filter set.
//!
//! adblock-rust's converter (`content_blocking`) turns a network filter into a WebKit trigger.
//! This pass decides what goes around those triggers, because WebKit's semantics differ from
//! adblock's in ways the converter leaves to the embedder:
//!
//! - `ignore-previous-rules` only lifts rules earlier in the *same* compiled list, and a list
//!   holds at most 150,000 rules. Every network list therefore carries all exceptions, after its
//!   share of the blocks, so an exception reaches every block it names.
//! - `$important` blocks come after the exceptions, so no exception lifts them.
//! - `$redirect` and `$removeparam` become WebKit `redirect` actions (a `data:` URL, a query
//!   transform). Each redirect is preceded by an `ignore-previous-rules` with its own trigger and
//!   repeated in every list, so a plain block in any list cannot pre-empt it.
//! - Cosmetic hiding lives in separate lists, so it can be detached while uBlock Origin runs
//!   without recompiling the network lists: generic selectors first (WebKit folds them into one
//!   global style sheet), then `$generichide`/`$document` exceptions, then host-specific
//!   selectors, then `$document` exceptions again.
//! - Scriptlets, procedural filters and `:style()` rules become user scripts (`bundles.rs`).

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use adblock::content_blocking::{CbRuleCreationFailure, CbRuleEquivalent, CbType};
use adblock::filters::cosmetic::{CosmeticFilter, CosmeticFilterMask};
use adblock::filters::network::{NetworkFilter, NetworkFilterMask};
use adblock::lists::{parse_filter, ParseOptions, ParsedLine};
use adblock::resources::Resource;
use adblock::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::bundles::{self, UserScript};
use crate::syntax;

/// Bumped whenever this pass's output changes for the same input; part of the app's cache key.
pub const PASS_VERSION: u32 = 1;

/// WebKit's `maxRuleCount` (`ContentExtensionParser.cpp`).
pub const MAX_RULES_PER_LIST: usize = 150_000;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Options {
    pub max_rules_per_list: usize,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            max_rules_per_list: MAX_RULES_PER_LIST,
        }
    }
}

/// One list's text and how to parse it.
pub struct ListText<'a> {
    pub text: &'a str,
    pub options: ParseOptions,
}

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Counts {
    pub network_rules: usize,
    pub exception_rules: usize,
    pub important_rules: usize,
    pub redirect_rules: usize,
    pub removeparam_rules: usize,
    pub generic_hide_rules: usize,
    pub specific_hide_rules: usize,
    /// Hosts the user scripts carry an entry for.
    pub bundle_hosts: usize,
    /// Filters WebKit cannot express, by reason. The Chromium engine applies all of them.
    pub unsupported: BTreeMap<&'static str, usize>,
}

impl Counts {
    pub(crate) fn unsupported(&mut self, reason: &'static str) {
        *self.unsupported.entry(reason).or_default() += 1;
    }
}

pub struct Output {
    pub network: Vec<Vec<Value>>,
    pub cosmetic: Vec<Vec<Value>>,
    pub scripts: Vec<UserScript>,
    pub counts: Counts,
}

pub fn compile(
    lists: &[ListText<'_>],
    redirects: &HashMap<String, String>,
    engine: &Engine,
    resources: &[Resource],
    options: &Options,
) -> Output {
    let mut counts = Counts::default();
    let mut network = NetworkPass::default();
    let mut cosmetic = CosmeticPass::default();

    for list in lists {
        for line in list.text.lines() {
            match parse_filter(line, true, list.options) {
                Ok(ParsedLine::Network(filter)) => network.filters.push(filter),
                Ok(ParsedLine::Cosmetic(filter)) => cosmetic.add(filter, &mut counts),
                Err(_) => {}
            }
        }
    }

    network.convert(redirects, &mut cosmetic, &mut counts);
    let network_lists = network.into_lists(options.max_rules_per_list, &mut counts);
    let bundle_hosts = std::mem::take(&mut cosmetic.bundle_hosts);
    let cosmetic_lists = cosmetic.into_lists(options.max_rules_per_list, &mut counts);
    let scripts = bundles::user_scripts(&bundle_hosts, engine, resources, &mut counts);

    Output {
        network: network_lists,
        cosmetic: cosmetic_lists,
        scripts,
        counts,
    }
}

// MARK: - Network

#[derive(Default)]
struct NetworkPass<'a> {
    filters: Vec<NetworkFilter<'a>>,
    blocks: Vec<Value>,
    exceptions: Vec<Value>,
    importants: Vec<Value>,
    /// `ignore-previous-rules` + `redirect` pairs, repeated in every list.
    redirects: Vec<Value>,
    removeparams: Vec<Value>,
}

impl NetworkPass<'_> {
    fn convert(
        &mut self,
        redirect_urls: &HashMap<String, String>,
        cosmetic: &mut CosmeticPass,
        counts: &mut Counts,
    ) {
        let bad_filters: HashSet<_> = self
            .filters
            .iter()
            .filter(|filter| filter.is_badfilter())
            .map(|filter| filter.get_id())
            .collect();

        for filter in std::mem::take(&mut self.filters) {
            if filter.is_badfilter() || bad_filters.contains(&filter.get_id()) {
                continue;
            }
            let Some(raw) = filter.raw_line.as_deref().map(str::to_string) else {
                continue;
            };
            let is_exception = filter.mask.contains(NetworkFilterMask::IS_EXCEPTION);

            if filter.is_csp() {
                // WebKit parses modify-headers' response-headers but applies only request
                // headers (ContentExtensionActions.cpp), so a CSP cannot be added.
                counts.unsupported("csp");
            } else if filter.is_redirect() {
                self.convert_redirect(&filter, &raw, is_exception, redirect_urls, counts);
            } else if filter.is_removeparam() {
                self.convert_removeparam(&filter, &raw, is_exception, counts);
            } else if filter.is_generic_hide() {
                if is_exception {
                    let stripped = syntax::without_options(&raw, &["generichide", "ghide"]);
                    if let Some(rules) = stripped.and_then(|line| document_exception(&line)) {
                        cosmetic.generic_exceptions.extend(rules);
                    }
                }
            } else {
                let is_document_exception =
                    is_exception && filter.mask.contains(NetworkFilterMask::FROM_DOCUMENT);
                let is_important = filter.mask.contains(NetworkFilterMask::IS_IMPORTANT);
                match CbRuleEquivalent::try_from(filter) {
                    Ok(equivalent) => {
                        for rule in equivalent {
                            let value = serde_json::to_value(&rule).expect("rules serialize");
                            match rule.action.typ {
                                CbType::IgnorePreviousRules => {
                                    if is_document_exception {
                                        cosmetic.document_exceptions.push(value.clone());
                                    }
                                    self.exceptions.push(value);
                                }
                                _ if is_important => self.importants.push(value),
                                _ => self.blocks.push(value),
                            }
                        }
                    }
                    Err(failure) => counts.unsupported(failure_reason(&failure)),
                }
            }
        }
    }

    fn convert_redirect(
        &mut self,
        filter: &NetworkFilter<'_>,
        raw: &str,
        is_exception: bool,
        redirect_urls: &HashMap<String, String>,
        counts: &mut Counts,
    ) {
        if is_exception {
            counts.unsupported("redirectException");
            return;
        }
        if !filter.also_block_redirect() {
            // $redirect-rule redirects only what another filter blocks; WebKit cannot condition
            // one rule on another.
            counts.unsupported("redirectRule");
            return;
        }
        let name = filter
            .modifier_option
            .map(|option| option.split(':').next().unwrap_or(option))
            .unwrap_or_default();
        let Some(url) = redirect_urls.get(name) else {
            counts.unsupported("redirectResource");
            return;
        };
        let Some(triggers) = stripped_triggers(raw, &["redirect", "rewrite"], counts) else {
            return;
        };
        for trigger in triggers {
            self.redirects.push(json!({
                "trigger": trigger,
                "action": {"type": "ignore-previous-rules"},
            }));
            self.redirects.push(json!({
                "trigger": trigger,
                "action": {"type": "redirect", "redirect": {"url": url}},
            }));
        }
    }

    fn convert_removeparam(
        &mut self,
        filter: &NetworkFilter<'_>,
        raw: &str,
        is_exception: bool,
        counts: &mut Counts,
    ) {
        let parameter = filter.modifier_option.unwrap_or_default();
        if is_exception
            || parameter.is_empty()
            || parameter.starts_with('/')
            || parameter.starts_with('~')
        {
            counts.unsupported("removeparamForm");
            return;
        }
        let Some(triggers) = stripped_triggers(raw, &["removeparam", "queryprune"], counts) else {
            return;
        };
        for mut trigger in triggers {
            let url_filter = trigger["url-filter"].as_str().unwrap_or_default();
            if matches!(url_filter, ".*" | "^https?://" | "^http://" | "^https://") {
                trigger["url-filter"] = json!(format!("[?&]{}=", syntax::escape_regex(parameter)));
            }
            self.removeparams.push(json!({
                "trigger": trigger,
                "action": {"type": "redirect", "redirect": {"transform": {
                    "query-transform": {"remove-parameters": [parameter]},
                }}},
            }));
        }
    }

    fn into_lists(self, max_rules: usize, counts: &mut Counts) -> Vec<Vec<Value>> {
        counts.network_rules = self.blocks.len();
        counts.exception_rules = self.exceptions.len();
        counts.important_rules = self.importants.len();
        counts.redirect_rules = self.redirects.len() / 2;
        counts.removeparam_rules = self.removeparams.len();

        let fp_documents =
            serde_json::to_value(adblock::content_blocking::ignore_previous_fp_documents())
                .expect("rules serialize");
        let shared = self.redirects.len() + self.exceptions.len() + 1;
        let capacity = max_rules.saturating_sub(shared).max(1);

        // Blocks and importants are cut into the same number of lists; removeparams ride in the
        // first one, because a query transform applies once wherever it sits.
        let list_count = (self.blocks.len() + self.importants.len() + self.removeparams.len())
            .div_ceil(capacity)
            .max(1);
        let mut blocks = self.blocks.into_iter();
        let mut importants = self.importants.into_iter();
        let mut removeparams = Some(self.removeparams);
        (0..list_count)
            .map(|_| {
                let mut list = Vec::with_capacity(max_rules);
                list.extend(removeparams.take().unwrap_or_default());
                let room = capacity.saturating_sub(list.len());
                list.extend(blocks.by_ref().take(room));
                list.extend(self.redirects.iter().cloned());
                list.extend(self.exceptions.iter().cloned());
                let room = (capacity + self.redirects.len() + self.exceptions.len())
                    .saturating_sub(list.len());
                list.extend(importants.by_ref().take(room));
                list.push(fp_documents.clone());
                list
            })
            .collect()
    }
}

/// WebKit triggers for `raw` with the named options removed, so an action filter can reuse
/// the converter's trigger. `None` (counted) when the remainder does not convert.
fn stripped_triggers(raw: &str, options: &[&str], counts: &mut Counts) -> Option<Vec<Value>> {
    let stripped = syntax::without_options(raw, options)?;
    if matches!(stripped.as_str(), "" | "*" | "|") {
        // A filter that is nothing but its option applies to every URL; adblock-rust parses no
        // bare pattern, so the trigger is written directly.
        return Some(vec![json!({"url-filter": ".*"})]);
    }
    let parsed = match parse_filter(&stripped, true, ParseOptions::default()) {
        Ok(ParsedLine::Network(filter)) => filter,
        _ => {
            counts.unsupported("other");
            return None;
        }
    };
    match CbRuleEquivalent::try_from(parsed) {
        Ok(equivalent) => Some(
            equivalent
                .into_iter()
                .map(|rule| serde_json::to_value(&rule.trigger).expect("triggers serialize"))
                .collect(),
        ),
        Err(failure) => {
            counts.unsupported(failure_reason(&failure));
            None
        }
    }
}

/// `ignore-previous-rules` for the documents `line` (an exception filter without its
/// cosmetic option) names.
fn document_exception(line: &str) -> Option<Vec<Value>> {
    let line = if syntax::options_start(line).is_some() {
        format!("{line},document")
    } else {
        format!("{line}$document")
    };
    let Ok(ParsedLine::Network(filter)) = parse_filter(&line, true, ParseOptions::default()) else {
        return None;
    };
    let equivalent = CbRuleEquivalent::try_from(filter).ok()?;
    Some(
        equivalent
            .into_iter()
            .map(|rule| serde_json::to_value(&rule).expect("rules serialize"))
            .collect(),
    )
}

fn failure_reason(failure: &CbRuleCreationFailure) -> &'static str {
    match failure {
        CbRuleCreationFailure::FullRegexUnsupported => "regex",
        CbRuleCreationFailure::FromNotSupported => "domainForm",
        CbRuleCreationFailure::UnlessAndIfDomainTogetherUnsupported => "mixedDomains",
        CbRuleCreationFailure::NoSupportedNetworkOptions(_) => "resourceType",
        CbRuleCreationFailure::RuleContainsNonASCII => "nonASCII",
        CbRuleCreationFailure::OptimizedRulesUnsupported => "optimized",
        _ => "other",
    }
}

// MARK: - Cosmetic

#[derive(Default)]
struct CosmeticPass {
    /// Generic selectors in list order, with the hosts excluded from each.
    generic: Vec<(String, BTreeSet<String>)>,
    generic_index: HashMap<String, usize>,
    /// Generic selectors that some filter applies everywhere (no `~host`).
    unconditional: HashSet<String>,
    specific: Vec<(String, Vec<String>)>,
    /// Hosts where `#@#selector` lifts a hide.
    unhidden: HashMap<String, BTreeSet<String>>,
    /// Selectors `#@#selector` lifts everywhere.
    unhidden_everywhere: HashSet<String>,
    generic_exceptions: Vec<Value>,
    document_exceptions: Vec<Value>,
    /// Hosts named by any filter whose effect the rule lists cannot carry: scriptlets (and
    /// their exceptions), procedural and action filters.
    bundle_hosts: BTreeSet<String>,
}

impl CosmeticPass {
    fn add(&mut self, filter: CosmeticFilter, counts: &mut Counts) {
        let Some(raw) = filter.raw_line.as_deref() else {
            return;
        };
        let locations = syntax::cosmetic_locations(raw);
        let selector = filter.plain_css_selector().map(str::to_string);
        let needs_bundle = filter.mask.contains(CosmeticFilterMask::SCRIPT_INJECT)
            || filter.action.is_some()
            || selector.is_none();
        if needs_bundle {
            if locations.hostnames.is_empty() && locations.entities > 0 {
                counts.unsupported("entity");
            }
            self.bundle_hosts.extend(locations.hostnames);
            self.bundle_hosts.extend(locations.not_hostnames);
            return;
        }
        let Some(selector) = selector else {
            return;
        };
        if !selector.is_ascii() {
            counts.unsupported("nonASCII");
            return;
        }
        let unhide = filter.mask.contains(CosmeticFilterMask::UNHIDE);

        if unhide {
            if locations.hostnames.is_empty() && locations.entities == 0 {
                self.unhidden_everywhere.insert(selector);
            } else {
                self.unhidden
                    .entry(selector)
                    .or_default()
                    .extend(locations.hostnames);
            }
        } else if locations.hostnames.is_empty() {
            if locations.entities > 0 && locations.not_hostnames.is_empty() {
                counts.unsupported("entity");
                return;
            }
            let index = *self
                .generic_index
                .entry(selector.clone())
                .or_insert_with(|| {
                    self.generic.push((selector.clone(), BTreeSet::new()));
                    self.generic.len() - 1
                });
            if locations.not_hostnames.is_empty() {
                self.unconditional.insert(selector);
            } else {
                self.generic[index].1.extend(locations.not_hostnames);
            }
        } else {
            if locations.entities > 0 {
                counts.unsupported("entity");
            }
            self.specific.push((selector, locations.hostnames));
        }
    }

    fn into_lists(self, max_rules: usize, counts: &mut Counts) -> Vec<Vec<Value>> {
        let domains = |hosts: &mut dyn Iterator<Item = &String>| -> Vec<String> {
            hosts.map(|host| format!("*{host}")).collect()
        };

        let mut generic = Vec::new();
        for (selector, not_hosts) in &self.generic {
            if self.unhidden_everywhere.contains(selector) {
                continue;
            }
            let mut unless: BTreeSet<&String> = BTreeSet::new();
            if !self.unconditional.contains(selector) {
                unless.extend(not_hosts);
            }
            if let Some(hosts) = self.unhidden.get(selector) {
                unless.extend(hosts);
            }
            let mut trigger = json!({"url-filter": ".*"});
            if !unless.is_empty() {
                trigger["unless-domain"] = json!(domains(&mut unless.into_iter()));
            }
            generic.push(json!({
                "trigger": trigger,
                "action": {"type": "css-display-none", "selector": selector},
            }));
        }

        let mut specific = Vec::new();
        for (selector, hosts) in &self.specific {
            if self.unhidden_everywhere.contains(selector) {
                continue;
            }
            let unhidden = self.unhidden.get(selector);
            let hosts: Vec<&String> = hosts
                .iter()
                .filter(|host| !unhidden.is_some_and(|unhidden| unhidden.contains(*host)))
                .collect();
            if hosts.is_empty() {
                continue;
            }
            specific.push(json!({
                "trigger": {"url-filter": ".*", "if-domain": domains(&mut hosts.into_iter())},
                "action": {"type": "css-display-none", "selector": selector},
            }));
        }

        counts.generic_hide_rules = generic.len();
        counts.specific_hide_rules = specific.len();
        if generic.is_empty() && specific.is_empty() {
            return Vec::new();
        }

        let shared = self.generic_exceptions.len() + 2 * self.document_exceptions.len();
        let capacity = max_rules.saturating_sub(shared).max(1);
        let list_count = (generic.len() + specific.len()).div_ceil(capacity).max(1);
        let generic_per_list = generic.len().div_ceil(list_count);
        let specific_per_list = specific.len().div_ceil(list_count);
        let mut generic = generic.into_iter();
        let mut specific = specific.into_iter();
        (0..list_count)
            .map(|_| {
                let mut list = Vec::new();
                list.extend(generic.by_ref().take(generic_per_list));
                list.extend(self.generic_exceptions.iter().cloned());
                list.extend(self.document_exceptions.iter().cloned());
                list.extend(specific.by_ref().take(specific_per_list));
                list.extend(self.document_exceptions.iter().cloned());
                list
            })
            .collect()
    }
}
