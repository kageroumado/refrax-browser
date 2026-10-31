// Refrax Shields procedural runner: applies adblock-rust `ProceduralOrActionFilter`s to a page.
//
// Each filter is {selector: [{type, arg}...], action?: {type, arg}}. The first operator selects
// from the document; each later one filters or moves the current set:
//   css-selector       starting with a combinator (" > a", " + a", " ~ a", " a"): query it
//                      relative to each element; otherwise keep the elements it matches
//   has-text           textContent contains the text, or matches /regex/flags
//   matches-attr       an attribute matching name="value" (each side text or /regex/)
//   matches-css[-before|-after]  a computed style property matching "prop: value"
//   matches-path       keep everything when location's path + query matches, else nothing
//   min-text-length    textContent at least that long
//   upward             the nth ancestor (a number) or the closest ancestor matching a selector
//   xpath              the nodes an XPath expression selects from each element
// Actions: none (hide), remove, style (inline declarations), remove-attr, remove-class.
//
// It runs in an isolated world: the page cannot see or patch it. It re-applies on DOM changes,
// at most once per animation frame.
//
// Defines `shieldsApplyProcedural(filters)`; the generated bundle calls it with this host's
// filters.

function shieldsApplyProcedural(filters) {
    'use strict';
    const COMBINATOR = /^\s*[>+~]|^\s+\S/;

    const regexOrText = (text) => {
        const match = /^\/(.+)\/([imsu]*)$/.exec(text);
        if (match) {
            try {
                const regex = new RegExp(match[1], match[2]);
                return (value) => regex.test(value);
            } catch (error) {
                return () => false;
            }
        }
        return (value) => value.includes(text);
    };

    const unquote = (text) => {
        const trimmed = text.trim();
        return /^".*"$/.test(trimmed) ? trimmed.slice(1, -1) : trimmed;
    };

    // A name test: exact for plain text, a match for /regex/.
    const nameMatcher = (text) => (/^\/.+\/[imsu]*$/.test(text) ? regexOrText(text) : (name) => name === text);

    // `name="value"`, either side text or /regex/; the value is optional.
    const attributeMatcher = (arg) => {
        const separator = arg.indexOf('="');
        const nameText = unquote(separator < 0 ? arg : arg.slice(0, separator));
        const name = nameMatcher(nameText);
        const value = separator < 0 ? () => true : regexOrText(unquote(arg.slice(separator + 1)));
        return (element) => Array.from(element.attributes)
            .some((attribute) => name(attribute.name) && value(attribute.value));
    };

    const cssMatcher = (arg, pseudo) => {
        const colon = arg.indexOf(':');
        if (colon < 0) { return () => false; }
        const property = arg.slice(0, colon).trim();
        const value = regexOrText(arg.slice(colon + 1).trim());
        return (element) => value(getComputedStyle(element, pseudo).getPropertyValue(property));
    };

    const operators = {
        'css-selector': (arg) => {
            if (COMBINATOR.test(arg)) {
                return (elements) => elements.flatMap((element) =>
                    Array.from(element.querySelectorAll(`:scope ${arg}`)));
            }
            return (elements) => elements.filter((element) => element.matches(arg));
        },
        'has-text': (arg) => {
            const test = regexOrText(arg);
            return (elements) => elements.filter((element) => test(element.textContent));
        },
        'matches-attr': (arg) => {
            const test = attributeMatcher(arg);
            return (elements) => elements.filter(test);
        },
        'matches-css': (arg) => {
            const test = cssMatcher(arg, null);
            return (elements) => elements.filter(test);
        },
        'matches-css-before': (arg) => {
            const test = cssMatcher(arg, '::before');
            return (elements) => elements.filter(test);
        },
        'matches-css-after': (arg) => {
            const test = cssMatcher(arg, '::after');
            return (elements) => elements.filter(test);
        },
        'matches-path': (arg) => {
            const test = regexOrText(arg);
            return (elements) => (test(location.pathname + location.search) ? elements : []);
        },
        'min-text-length': (arg) => {
            const length = Number(arg) || 0;
            return (elements) => elements.filter((element) => element.textContent.length >= length);
        },
        upward: (arg) => {
            const count = Number(arg);
            if (Number.isInteger(count) && count > 0) {
                return (elements) => elements.flatMap((element) => {
                    let ancestor = element;
                    for (let index = 0; index < count && ancestor; index += 1) {
                        ancestor = ancestor.parentElement;
                    }
                    return ancestor ? [ancestor] : [];
                });
            }
            return (elements) => elements.flatMap((element) => {
                const ancestor = element.parentElement && element.parentElement.closest(arg);
                return ancestor ? [ancestor] : [];
            });
        },
        xpath: (arg) => (elements) => elements.flatMap((element) => {
            const result = document.evaluate(arg, element, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            const nodes = [];
            for (let index = 0; index < result.snapshotLength; index += 1) {
                const node = result.snapshotItem(index);
                if (node instanceof Element) { nodes.push(node); }
            }
            return nodes;
        }),
    };

    const declarations = (style) => style.split(';').map((declaration) => {
        const colon = declaration.indexOf(':');
        return colon < 0 ? null : [declaration.slice(0, colon).trim(), declaration.slice(colon + 1).replace(/!important/i, '').trim()];
    }).filter((pair) => pair && pair[0]);

    const actions = {
        hide: () => (element) => element.style.setProperty('display', 'none', 'important'),
        remove: () => (element) => element.remove(),
        style: (arg) => {
            const pairs = declarations(arg);
            return (element) => {
                for (const [property, value] of pairs) {
                    element.style.setProperty(property, value, 'important');
                }
            };
        },
        'remove-attr': (arg) => {
            const test = nameMatcher(arg);
            return (element) => {
                for (const attribute of Array.from(element.attributes)) {
                    if (test(attribute.name)) { element.removeAttribute(attribute.name); }
                }
            };
        },
        'remove-class': (arg) => {
            const test = nameMatcher(arg);
            return (element) => {
                for (const name of Array.from(element.classList)) {
                    if (test(name)) { element.classList.remove(name); }
                }
            };
        },
    };

    const compiled = [];
    const styleRules = [];
    for (const filter of filters) {
        const steps = filter.selector || [];
        const action = filter.action || { type: 'hide' };
        const isPlainStyle = action.type === 'style' && steps.length === 1 && steps[0].type === 'css-selector';
        if (isPlainStyle) {
            styleRules.push(`${steps[0].arg} { ${action.arg} }`);
            continue;
        }
        if (steps.length === 0 || !actions[action.type]) { continue; }
        try {
            const [first, ...rest] = steps;
            const start = first.type === 'css-selector'
                ? () => Array.from(document.querySelectorAll(first.arg))
                : () => operators[first.type](first.arg)(Array.from(document.querySelectorAll('*')));
            const transforms = rest.map((step) => operators[step.type](step.arg));
            compiled.push({ start, transforms, apply: actions[action.type](action.arg), applied: new WeakSet() });
        } catch (error) {
            // A malformed filter skips itself.
        }
    }

    if (styleRules.length > 0) {
        try {
            const sheet = new CSSStyleSheet();
            sheet.replaceSync(styleRules.join('\n'));
            document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
        } catch (error) {
            // Invalid CSS in one rule invalidates nothing else: the sheet keeps what parsed.
        }
    }
    if (compiled.length === 0) { return; }

    const run = () => {
        for (const filter of compiled) {
            try {
                let elements = filter.start();
                for (const transform of filter.transforms) {
                    if (elements.length === 0) { break; }
                    elements = transform(elements);
                }
                for (const element of elements) {
                    if (!filter.applied.has(element)) {
                        filter.applied.add(element);
                        filter.apply(element);
                    }
                }
            } catch (error) {
                // One failing filter leaves the others running.
            }
        }
    };

    let scheduled = false;
    const schedule = () => {
        if (scheduled) { return; }
        scheduled = true;
        requestAnimationFrame(() => {
            scheduled = false;
            run();
        });
    };
    const observe = () => {
        run();
        new MutationObserver(schedule).observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['class', 'id', 'style'],
        });
    };
    if (document.documentElement) {
        observe();
    } else {
        document.addEventListener('readystatechange', observe, { once: true });
    }
    document.addEventListener('DOMContentLoaded', run, { once: true });
}
