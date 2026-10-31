//! Per-list filter counts and parse failures for the Filters settings.

use adblock::filters::cosmetic::CosmeticFilterMask;
use adblock::lists::{parse_filter, ParseOptions, ParsedLine};
use serde::Serialize;

/// Invalid lines kept per list, so the settings can show what failed without carrying a list.
const INVALID_EXAMPLES: usize = 5;

#[derive(Debug, Default, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ListStats {
    pub source_index: usize,
    pub network: usize,
    pub cosmetic: usize,
    /// Cosmetic filters that inject a scriptlet (`##+js(…)`).
    pub scriptlets: usize,
    /// Cosmetic filters with procedural operators or an action (`:has-text`, `:style()`, …).
    pub procedural: usize,
    /// Lines that are neither comments nor filters adblock-rust understands.
    pub invalid: usize,
    pub invalid_examples: Vec<String>,
}

pub fn list_stats(source_index: usize, text: &str, options: ParseOptions) -> ListStats {
    let mut stats = ListStats {
        source_index,
        ..ListStats::default()
    };
    for line in text.lines() {
        let trimmed = line.trim();
        if is_comment(trimmed) {
            continue;
        }
        match parse_filter(trimmed, false, options) {
            Ok(ParsedLine::Network(_)) => stats.network += 1,
            Ok(ParsedLine::Cosmetic(filter)) => {
                stats.cosmetic += 1;
                if filter.mask.contains(CosmeticFilterMask::SCRIPT_INJECT) {
                    stats.scriptlets += 1;
                } else if filter.action.is_some() || filter.plain_css_selector().is_none() {
                    stats.procedural += 1;
                }
            }
            Err(_) => {
                stats.invalid += 1;
                if stats.invalid_examples.len() < INVALID_EXAMPLES {
                    stats.invalid_examples.push(trimmed.to_string());
                }
            }
        }
    }
    stats
}

fn is_comment(line: &str) -> bool {
    line.is_empty()
        || line.starts_with('!')
        || line.starts_with("[Adblock")
        || (line.starts_with('#') && !line.starts_with("##") && !line.starts_with("#@#"))
}

// Procedural operators are recognized only with selector validation (the app's features).
#[cfg(all(test, feature = "css-validation"))]
mod tests {
    use super::*;

    #[test]
    fn counts_each_kind() {
        let list = "! Title: test\n||ads.example^\nexample.com##.ad\nexample.com##+js(set-constant, a, 1)\nexample.com##div:has-text(Ad)\n||bad^$unknownoption\n";
        let stats = list_stats(0, list, ParseOptions::default());
        assert_eq!(
            (
                stats.network,
                stats.cosmetic,
                stats.scriptlets,
                stats.procedural
            ),
            (1, 3, 1, 1)
        );
        assert_eq!(stats.invalid, 1);
        assert_eq!(stats.invalid_examples, ["||bad^$unknownoption"]);
    }
}
