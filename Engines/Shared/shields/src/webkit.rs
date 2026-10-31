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
//! - `$redirect` becomes a WebKit `redirect` to a `data:` URL, preceded by an
//!   `ignore-previous-rules` with its own trigger and repeated in every list, so a plain block in
//!   any list cannot pre-empt it; a redirect whose resource is missing becomes a plain block.
//! - `$removeparam` becomes a query transform that triggers only on URLs carrying the
//!   parameter, placed after every block and after the first-party document exception in every
//!   list: WebKit applies no block once a load is redirected, so a transform must never come
//!   first.
//! - `$generichide` and `$document` exceptions lift rules for every load of a page whose top URL
//!   they match (`if-top-url`), not only for the document load: WebKit applies the global hide
//!   style sheet on any load that saw no `ignore-previous-rules`.
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
pub const PASS_VERSION: u32 = 3;

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
    /// Entities (`example.*`) the user scripts resolve at run time.
    pub entities: usize,
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
    let entities = std::mem::take(&mut cosmetic.entities);
    let cosmetic_lists = cosmetic.into_lists(options.max_rules_per_list, &mut counts);
    let scripts = bundles::user_scripts(&bundle_hosts, &entities, engine, resources, &mut counts);

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
    /// `$document` exceptions as page-wide `ignore-previous-rules`.
    page_exceptions: Vec<Value>,
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
            let is_document_exception =
                is_exception && filter.mask.contains(NetworkFilterMask::FROM_DOCUMENT);
            if is_document_exception {
                // Lifts every rule for the page's own loads, not only the document request.
                let stripped =
                    syntax::without_options(&raw, &["document", "doc"]).unwrap_or_default();
                if let Some(rules) = page_exception(&stripped) {
                    self.page_exceptions.extend(rules.iter().cloned());
                    cosmetic.document_exceptions.extend(rules);
                }
            }

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
                    match stripped.and_then(|line| page_exception(&line)) {
                        Some(rules) => cosmetic.generic_exceptions.extend(rules),
                        None => counts.unsupported("pageException"),
                    }
                }
            } else {
                let is_important = filter.mask.contains(NetworkFilterMask::IS_IMPORTANT);
                match CbRuleEquivalent::try_from(filter) {
                    Ok(equivalent) => {
                        for rule in equivalent {
                            let value = serde_json::to_value(&rule).expect("rules serialize");
                            match rule.action.typ {
                                CbType::IgnorePreviousRules => self.exceptions.push(value),
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
        let Some(triggers) = stripped_triggers(raw, &["redirect", "rewrite"], counts) else {
            return;
        };
        let Some(url) = redirect_urls.get(name) else {
            // Without the resource the filter still blocks, as adblock-rust does.
            counts.unsupported("redirectResource");
            for trigger in triggers {
                self.blocks
                    .push(json!({"trigger": trigger, "action": {"type": "block"}}));
            }
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
        let parameter_filter = format!("[?&]{}=", syntax::escape_regex(parameter));
        for mut trigger in triggers {
            // Only URLs that carry the parameter: a transform on any other URL of the host
            // would still count as a redirect and switch off WebKit's blocks for it.
            let url_filter = trigger["url-filter"].as_str().unwrap_or_default();
            trigger["url-filter"] =
                if matches!(url_filter, ".*" | "^https?://" | "^http://" | "^https://") {
                    json!(parameter_filter)
                } else {
                    json!(format!(
                        "{}.*{parameter_filter}",
                        url_filter.trim_end_matches('$')
                    ))
                };
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
        // Every list: its share of blocks, all redirects, all exceptions, its share of
        // importants, the first-party document exception, then all removeparam transforms.
        let shared = self.redirects.len()
            + self.exceptions.len()
            + self.page_exceptions.len()
            + 1
            + self.removeparams.len();
        let capacity = max_rules.saturating_sub(shared).max(1);
        let mut blocks = self.blocks.into_iter().peekable();
        let mut importants = self.importants.into_iter().peekable();
        let mut lists = Vec::new();
        while lists.is_empty() || blocks.peek().is_some() || importants.peek().is_some() {
            let own_blocks: Vec<Value> = blocks.by_ref().take(capacity).collect();
            let own_importants: Vec<Value> = importants
                .by_ref()
                .take(capacity - own_blocks.len())
                .collect();
            let mut list = own_blocks;
            list.extend(self.redirects.iter().cloned());
            list.extend(self.exceptions.iter().cloned());
            list.extend(self.page_exceptions.iter().cloned());
            list.extend(own_importants);
            list.push(fp_documents.clone());
            list.extend(self.removeparams.iter().cloned());
            lists.push(list);
        }
        lists
    }
}

/// WebKit triggers for `raw` with the named options removed, so an action filter can reuse
/// the converter's trigger. `None` (counted) when the remainder does not convert.
fn stripped_triggers(raw: &str, options: &[&str], counts: &mut Counts) -> Option<Vec<Value>> {
    let Some(stripped) = syntax::without_options(raw, options) else {
        counts.unsupported("other");
        return None;
    };
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

/// `ignore-previous-rules` for every load of a page whose top URL `line` (an exception filter
/// without its page option) matches: `url-filter` `.*` with the pattern as `if-top-url`.
/// `None` when the filter does not convert or carries `domain=` (WebKit allows one condition).
fn page_exception(line: &str) -> Option<Vec<Value>> {
    let pattern = line.strip_prefix("@@").unwrap_or(line);
    if pattern.is_empty() || syntax::has_option(line, "domain") || syntax::has_option(line, "from")
    {
        return None;
    }
    let Ok(ParsedLine::Network(filter)) = parse_filter(pattern, true, ParseOptions::default())
    else {
        return None;
    };
    let equivalent = CbRuleEquivalent::try_from(filter).ok()?;
    let mut top_urls: Vec<String> = equivalent
        .into_iter()
        .map(|rule| rule.trigger.url_filter)
        .collect();
    top_urls.dedup();
    Some(vec![json!({
        "trigger": {"url-filter": ".*", "if-top-url": top_urls},
        "action": {"type": "ignore-previous-rules"},
    })])
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
    /// Entity labels (`example` of `example.*`) any cosmetic filter names; the user scripts
    /// apply their rules at run time.
    entities: BTreeSet<String>,
}

impl CosmeticPass {
    fn add(&mut self, filter: CosmeticFilter, counts: &mut Counts) {
        let Some(raw) = filter.raw_line.as_deref() else {
            return;
        };
        let locations = syntax::cosmetic_locations(raw);
        for _ in 0..locations.unsupported {
            counts.unsupported("entity");
        }
        let selector = filter.plain_css_selector().map(str::to_string);
        let needs_bundle = filter.mask.contains(CosmeticFilterMask::SCRIPT_INJECT)
            || filter.action.is_some()
            || selector.is_none();
        let unhide = filter.mask.contains(CosmeticFilterMask::UNHIDE);
        if !(unhide && !needs_bundle) {
            self.entities.extend(locations.entities.iter().cloned());
        }
        if needs_bundle {
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
        if unhide {
            if !locations.entities.is_empty() {
                // `example.*#@#.ad` would need every generic hide to skip a set of hosts no
                // domain list can name.
                counts.unsupported("entityException");
            }
            if locations.hostnames.is_empty() && locations.entities.is_empty() {
                self.unhidden_everywhere.insert(selector);
            } else {
                self.unhidden
                    .entry(selector)
                    .or_default()
                    .extend(locations.hostnames);
            }
        } else if locations.hostnames.is_empty() {
            if !locations.entities.is_empty() {
                return; // applied by the entity user scripts
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
        let mut generic = generic.into_iter().peekable();
        let mut specific = specific.into_iter().peekable();
        let mut lists = Vec::new();
        while generic.peek().is_some() || specific.peek().is_some() {
            let own_generic: Vec<Value> = generic.by_ref().take(capacity).collect();
            let own_specific: Vec<Value> = specific
                .by_ref()
                .take(capacity - own_generic.len())
                .collect();
            let mut list = own_generic;
            list.extend(self.generic_exceptions.iter().cloned());
            list.extend(self.document_exceptions.iter().cloned());
            list.extend(own_specific);
            list.extend(self.document_exceptions.iter().cloned());
            lists.push(list);
        }
        lists
    }
}
