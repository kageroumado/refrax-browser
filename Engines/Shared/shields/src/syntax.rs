//! Text-level helpers over filter lines: the parts of a raw line adblock-rust parses but does
//! not expose (the option list, a cosmetic filter's location prefix).

/// Where a network filter's `$options` start, or `None` when it has none.
///
/// A regex pattern (`/…/`) may itself contain `$`, so options start after its closing slash. A
/// pattern that only starts with `/` is a path (`/ads/x.js$script`).
pub fn options_start(line: &str) -> Option<usize> {
    let pattern_start = if line.starts_with("@@") { 2 } else { 0 };
    let pattern = &line[pattern_start..];
    let is_bare_regex = pattern.len() > 1 && pattern.starts_with('/') && pattern.ends_with('/');
    if is_bare_regex {
        return None;
    }
    let search_from = match pattern.strip_prefix('/').and_then(|rest| rest.rfind("/$")) {
        Some(index) => pattern_start + 1 + index + 1,
        None => pattern_start,
    };
    line[search_from..]
        .rfind('$')
        .map(|index| search_from + index)
}

/// `line` without the options named in `names` (each matched as `name` or `name=…`), or
/// `None` when the line has no options. Removing every option drops the `$`.
pub fn without_options(line: &str, names: &[&str]) -> Option<String> {
    let start = options_start(line)?;
    let kept: Vec<&str> = line[start + 1..]
        .split(',')
        .filter(|option| {
            let key = option.split('=').next().unwrap_or(option);
            !names.contains(&key)
        })
        .collect();
    let pattern = &line[..start];
    Some(if kept.is_empty() {
        pattern.to_string()
    } else {
        format!("{pattern}${}", kept.join(","))
    })
}

/// Whether the line's options include `name` (bare or with a value).
pub fn has_option(line: &str, name: &str) -> bool {
    options_start(line).is_some_and(|start| {
        line[start + 1..]
            .split(',')
            .any(|option| option.split('=').next() == Some(name))
    })
}

/// The hostnames before a cosmetic filter's separator (`##`, `#@#`, `#?#`, `#$#`, …).
#[derive(Debug, Default, PartialEq)]
pub struct CosmeticLocations {
    pub hostnames: Vec<String>,
    pub not_hostnames: Vec<String>,
    /// The labels of `example.*` entries, which WebKit match patterns and domain lists cannot
    /// express; user scripts resolve them at run time.
    pub entities: Vec<String>,
    /// Negated (`~example.*`), multi-label (`example.co.*`) and regex locations.
    pub unsupported: usize,
}

pub fn cosmetic_locations(line: &str) -> CosmeticLocations {
    let mut locations = CosmeticLocations::default();
    let Some(sharp) = line.find('#') else {
        return locations;
    };
    for part in line[..sharp].split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        let (negated, location) = match part.strip_prefix('~') {
            Some(rest) => (true, rest),
            None => (false, part),
        };
        if location.contains('/') {
            locations.unsupported += 1;
            continue;
        }
        if let Some(label) = location.strip_suffix(".*") {
            match ascii_hostname(label) {
                Some(label) if !negated && !label.contains('.') => locations.entities.push(label),
                _ => locations.unsupported += 1,
            }
            continue;
        }
        let Some(hostname) = ascii_hostname(location) else {
            continue;
        };
        if negated {
            locations.not_hostnames.push(hostname);
        } else {
            locations.hostnames.push(hostname);
        }
    }
    locations
}

/// A lowercase ASCII (punycode) form of `hostname`, or `None` if it is not a valid hostname.
pub fn ascii_hostname(hostname: &str) -> Option<String> {
    let lowercase = hostname.to_lowercase();
    let ascii = if lowercase.is_ascii() {
        lowercase
    } else {
        idna::domain_to_ascii(&lowercase).ok()?
    };
    let valid = !ascii.is_empty()
        && ascii.bytes().all(|byte| {
            byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_' | b':' | b'[' | b']')
        });
    valid.then_some(ascii)
}

/// Escapes a literal for WebKit's content-rule regex subset.
pub fn escape_regex(literal: &str) -> String {
    let mut escaped = String::with_capacity(literal.len());
    for character in literal.chars() {
        if ".+?^${}()|[]\\*/".contains(character) {
            escaped.push('\\');
        }
        escaped.push(character);
    }
    escaped
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_options() {
        assert_eq!(options_start("||a.com^$script"), Some(8));
        assert_eq!(options_start("||a.com^"), None);
        assert_eq!(options_start("/ad[0-9]$/$script"), Some(10));
        assert_eq!(options_start("@@||a.com^$document"), Some(10));
        assert_eq!(options_start("/ads/x.js$script"), Some(9));
        assert_eq!(options_start("/ad[0-9]$/"), None);
    }

    #[test]
    fn strips_options() {
        assert_eq!(
            without_options("||a.com/x.js$script,redirect=noop.js", &["redirect"]).as_deref(),
            Some("||a.com/x.js$script")
        );
        assert_eq!(
            without_options("*$removeparam=utm_source", &["removeparam"]).as_deref(),
            Some("*")
        );
        assert!(has_option("@@||a.com^$generichide", "generichide"));
        assert!(!has_option("||a.com^$domain=b.com", "document"));
    }

    #[test]
    fn reads_cosmetic_locations() {
        let locations = cosmetic_locations("example.com,~sub.example.com,google.*##.ad");
        assert_eq!(locations.hostnames, ["example.com"]);
        assert_eq!(locations.not_hostnames, ["sub.example.com"]);
        assert_eq!(locations.entities, ["google"]);
        assert_eq!(cosmetic_locations("##.ad"), CosmeticLocations::default());
        let odd = cosmetic_locations("~bing.*,google.co.*##.ad");
        assert!(odd.entities.is_empty());
        assert_eq!(odd.unsupported, 2);
    }
}
