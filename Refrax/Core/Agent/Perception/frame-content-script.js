// FrameContentScript.js
// Injected into all frames (including cross-origin) via WKUserScript.
// Extracts interactive elements from the frame's DOM and posts them back
// to the native FrameContentExtractor via webkit.messageHandlers.

(() => {
  'use strict';

  // Only run in subframes — the main frame uses native text extraction.
  if (window === window.top) return;

  const HANDLER_NAME = 'refraxFrameContent';

  // Interactive element selectors
  const INTERACTIVE_SELECTORS = [
    'a[href]',
    'button',
    'input',
    'select',
    'textarea',
    '[role="button"]',
    '[role="link"]',
    '[role="checkbox"]',
    '[role="radio"]',
    '[role="tab"]',
    '[role="menuitem"]',
    '[role="menuitemcheckbox"]',
    '[role="menuitemradio"]',
    '[role="switch"]',
    '[role="combobox"]',
    '[role="listbox"]',
    '[role="option"]',
    '[role="searchbox"]',
    '[role="slider"]',
    '[role="spinbutton"]',
    '[role="treeitem"]',
    '[tabindex]',
    '[onclick]',
    '[contenteditable="true"]',
  ];

  // Check if an element is visible
  function isVisible(el) {
    if (!el || !el.getBoundingClientRect) return false;
    const style = getComputedStyle(el);
    if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  // Get a human-readable label for an element
  function getLabel(el) {
    // aria-label first
    const ariaLabel = el.getAttribute('aria-label');
    if (ariaLabel) return ariaLabel.trim();

    // aria-labelledby
    const labelledBy = el.getAttribute('aria-labelledby');
    if (labelledBy) {
      const labelEl = document.getElementById(labelledBy);
      if (labelEl) return labelEl.textContent.trim().substring(0, 200);
    }

    // For inputs, check associated label
    if (el.id && (el.tagName === 'INPUT' || el.tagName === 'SELECT' || el.tagName === 'TEXTAREA')) {
      const label = document.querySelector(`label[for="${CSS.escape(el.id)}"]`);
      if (label) return label.textContent.trim().substring(0, 200);
    }

    // title attribute
    const title = el.getAttribute('title');
    if (title) return title.trim();

    // Inner text (truncated)
    const text = el.textContent || '';
    return text.trim().substring(0, 200);
  }

  // Get the ARIA role (explicit or implicit)
  function getRole(el) {
    const explicit = el.getAttribute('role');
    if (explicit) return explicit;

    const tag = el.tagName.toLowerCase();
    switch (tag) {
      case 'a': return el.hasAttribute('href') ? 'link' : null;
      case 'button': return 'button';
      case 'input': {
        const type = (el.type || 'text').toLowerCase();
        switch (type) {
          case 'checkbox': return 'checkbox';
          case 'radio': return 'radio';
          case 'submit': case 'reset': case 'button': return 'button';
          case 'range': return 'slider';
          default: return 'textbox';
        }
      }
      case 'select': return 'combobox';
      case 'textarea': return 'textbox';
      default: return null;
    }
  }

  // Extract interactive elements from the frame
  function extractElements() {
    const elements = [];
    const selector = INTERACTIVE_SELECTORS.join(',');
    const nodes = document.querySelectorAll(selector);
    let index = 0;

    for (const el of nodes) {
      if (!isVisible(el)) continue;
      if (index >= 200) break; // Cap to prevent excessive data

      const rect = el.getBoundingClientRect();
      const tag = el.tagName.toLowerCase();
      const role = getRole(el);
      const label = getLabel(el);
      const href = el.getAttribute('href') || null;
      const inputType = el.type || null;
      const value = (tag === 'input' || tag === 'textarea' || tag === 'select')
        ? (el.value || '').substring(0, 100)
        : null;
      const isDisabled = el.disabled === true;
      const isChecked = el.checked === true;

      elements.push({
        index: index,
        tag: tag,
        role: role,
        text: label.substring(0, 200),
        href: href,
        inputType: inputType,
        value: value,
        isDisabled: isDisabled,
        isChecked: isChecked,
        rect: {
          x: Math.round(rect.x),
          y: Math.round(rect.y),
          width: Math.round(rect.width),
          height: Math.round(rect.height),
        },
      });
      index++;
    }

    return elements;
  }

  // Also collect non-interactive text content summary for context
  function extractTextSummary() {
    // Get headings
    const headings = [];
    for (const h of document.querySelectorAll('h1, h2, h3')) {
      const text = h.textContent.trim();
      if (text) headings.push(text.substring(0, 200));
      if (headings.length >= 5) break;
    }

    // Get visible paragraph text (first 500 chars)
    let bodyText = '';
    for (const p of document.querySelectorAll('p, [role="heading"], [role="alert"], [role="status"]')) {
      if (!isVisible(p)) continue;
      const text = p.textContent.trim();
      if (text) {
        bodyText += (bodyText ? ' ' : '') + text;
        if (bodyText.length > 500) break;
      }
    }

    return {
      headings: headings,
      text: bodyText.substring(0, 500),
    };
  }

  // Post extraction results to native handler
  function postResults() {
    try {
      if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers[HANDLER_NAME]) {
        return;
      }

      const elements = extractElements();
      const summary = extractTextSummary();

      window.webkit.messageHandlers[HANDLER_NAME].postMessage({
        frameOrigin: location.origin,
        frameURL: location.href,
        elements: elements,
        summary: summary,
        viewportWidth: document.documentElement.clientWidth || window.innerWidth,
        viewportHeight: document.documentElement.clientHeight || window.innerHeight,
      });
    } catch (e) {
      // Silently fail — CSP or other restrictions may block postMessage
    }
  }

  // Run extraction after the DOM is ready
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(postResults, 100);
  } else {
    document.addEventListener('DOMContentLoaded', () => setTimeout(postResults, 100));
  }

  // Also listen for a re-extraction request from native
  window.__refraxExtractFrameContent = postResults;
})();
