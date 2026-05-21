import Foundation

/// JavaScript content script for Chrome Web Store and Firefox Add-ons integration.
///
/// On CWS: spoofs Chrome environment at document start, waits for CWS to build
/// the DOM, then scrapes extension info and replaces the entire page body with
/// a clean custom page that has a working "Add to Refrax" button.
///
/// On AMO: replaces "Add to Firefox" buttons with "Add to Refrax" buttons.
enum WebStoreIntegrationScript {
    /// Message handler name for receiving install requests from the content script.
    static let messageHandlerName = "refraxWebStoreInstall"

    /// Single script injected at document start. Handles everything:
    /// Chrome API spoofing, page replacement after load, button wiring.
    static let earlyStyleScript = """
    (() => {
      const hostname = location.hostname;
      const isCWS = hostname === 'chromewebstore.google.com';
      const isAMO = hostname === 'addons.mozilla.org';
      if (!isCWS && !isAMO) return;

      // --- Chrome environment spoofing (both CWS and AMO) ---
      try {
        if (!window.chrome) {
          Object.defineProperty(window, 'chrome', {
            value: {
              runtime: { id: undefined, connect: function(){}, sendMessage: function(){},
                onMessage: { addListener: function(){} }, onConnect: { addListener: function(){} } },
              app: { isInstalled: false },
              csi: function() { return {}; },
              loadTimes: function() { return {}; }
            },
            writable: false, configurable: false
          });
        }
        Object.defineProperty(Navigator.prototype, 'vendor', {
          get: function() { return 'Google Inc.'; }, configurable: true
        });
        if (!navigator.userAgentData) {
          Object.defineProperty(Navigator.prototype, 'userAgentData', {
            get: function() {
              return {
                brands: [
                  { brand: 'Not(A:Brand', version: '8' },
                  { brand: 'Chromium', version: '144' },
                  { brand: 'Google Chrome', version: '144' }
                ],
                mobile: false, platform: 'macOS',
                getHighEntropyValues: function() {
                  return Promise.resolve({ brands: this.brands, mobile: false, platform: 'macOS',
                    platformVersion: '15.0.0', architecture: 'arm', model: '', uaFullVersion: '144.0.0.0' });
                }
              };
            },
            configurable: true
          });
        }
      } catch (e) {}

      var _setTimeout = window.setTimeout;
      var _MutationObserver = window.MutationObserver;

      // --- Chrome Web Store: scrape then replace entire page ---
      if (isCWS) {
        function getExtensionID() {
          var match = location.pathname.match(/\\/detail\\/(?:[^\\/]+\\/)?([a-z]{32})/);
          return match ? match[1] : null;
        }

        // Unhide content so CWS JS can build the DOM for us to scrape
        function unhideAll() {
          document.querySelectorAll('[style]').forEach(function(el) {
            if (el.style.display === 'none' && el.tagName !== 'SCRIPT' && el.tagName !== 'STYLE' && el.children.length > 0) {
              el.style.removeProperty('display');
            }
          });
        }

        function scrapeAndReplace() {
          unhideAll();

          var extensionID = getExtensionID();
          if (!extensionID) return;

          // Scrape extension info from the CWS DOM
          var title = document.title.replace(/ - Chrome Web Store$/, '').trim() || 'Extension';
          var descEl = document.querySelector('meta[property="og:description"]');
          var description = descEl ? descEl.content : '';
          var iconEl = document.querySelector('img[alt*="logo"], img[alt*="Item logo"]');
          var iconURL = iconEl ? iconEl.src : '';
          var ratingText = '';
          var userCount = '';
          var category = '';

          // Try to find rating and user count
          document.querySelectorAll('span, div').forEach(function(el) {
            var t = el.textContent.trim();
            if (!ratingText && (t.match(/^\\d+\\.\\d+ out of 5$/) || t.match(/^\\d\\.\\d$/))) ratingText = t;
            if (!userCount && t.match(/^[\\d,]+ users?$/)) userCount = t;
          });

          // Category from links
          var catLinks = document.querySelectorAll('a[href*="/category/"]');
          if (catLinks.length > 0) category = catLinks[catLinks.length - 1].textContent.trim();

          // Screenshots
          var screenshots = [];
          document.querySelectorAll('img[alt*="screenshot"], img[alt*="Item media"]').forEach(function(img) {
            if (img.src && img.naturalWidth > 100) screenshots.push(img.src);
          });

          // Overview text
          var overviewText = '';
          document.querySelectorAll('h2, h3').forEach(function(h) {
            if (h.textContent.trim() === 'Overview' && h.parentElement) {
              h.parentElement.querySelectorAll('p, div').forEach(function(p) {
                var t = p.textContent.trim();
                if (t.length > 20 && !overviewText) overviewText = t;
              });
            }
          });
          if (!overviewText) overviewText = description;

          var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);

          // Unhide and preserve the navigation header
          var navHeader = document.querySelector('header');
          if (navHeader) navHeader.style.setProperty('display', 'flex', 'important');

          // Remove Chrome promo dialogs that live inside or near the header
          document.querySelectorAll('[role="dialog"]').forEach(function(el) { el.remove(); });

          // Measure header height for padding (after removing dialogs that inflate it)
          var headerHeight = navHeader ? navHeader.offsetHeight : 0;

          // Remove everything from body except the header, then add our content
          var keep = [];
          var kids = document.body.children;
          for (var i = 0; i < kids.length; i++) {
            var kid = kids[i];
            if (kid.tagName === 'HEADER') keep.push(kid);
          }
          while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
          keep.forEach(function(el) { document.body.appendChild(el); });

          var mainContent = document.createElement('div');
          document.body.appendChild(mainContent);

          var container = document.createElement('div');
          container.style.cssText = 'max-width: 900px; margin: 0 auto; padding: 40px 24px; padding-top: ' + (headerHeight + 24) + 'px;';

          // Header with icon and info
          var header = document.createElement('div');
          header.style.cssText = 'display: flex; align-items: flex-start; gap: 20px; margin-bottom: 32px;';

          if (iconURL) {
            var icon = document.createElement('img');
            icon.src = iconURL;
            icon.style.cssText = 'width: 96px; height: 96px; border-radius: 16px;';
            header.appendChild(icon);
          }

          var info = document.createElement('div');
          info.style.cssText = 'flex: 1;';

          var h1 = document.createElement('h1');
          h1.textContent = title;
          h1.style.cssText = 'margin: 0 0 8px 0; font-size: 28px; font-weight: 600;';
          info.appendChild(h1);

          var metaDiv = document.createElement('div');
          metaDiv.style.cssText = 'color: #5f6368; font-size: 14px; margin-bottom: 16px;';
          var metaParts = [];
          if (ratingText) metaParts.push(ratingText);
          if (userCount) metaParts.push(userCount);
          if (category) metaParts.push(category);
          metaDiv.textContent = metaParts.join(' \\u00B7 ') || 'Chrome Extension';
          info.appendChild(metaDiv);

          // Install button
          var btn = document.createElement('button');
          btn.textContent = 'Add to Refrax';
          btn.style.cssText = 'background: #1a73e8; color: white; border: none; border-radius: 20px; padding: 10px 28px; font-size: 14px; font-weight: 500; cursor: pointer; font-family: inherit; transition: background 0.15s;';

          btn.onmouseenter = function() { if (!btn.disabled) btn.style.background = '#1557b0'; };
          btn.onmouseleave = function() { if (!btn.disabled) btn.style.background = '#1a73e8'; };

          window.__refraxUpdateInstallButton = function(status) {
            if (status === 'installed') {
              btn.textContent = 'Added to Refrax';
              btn.style.background = '#188038';
              btn.style.opacity = '1';
              btn.style.cursor = 'default';
            } else if (status === 'already_installed') {
              btn.textContent = 'Already Installed';
              btn.style.background = '#5f6368';
              btn.style.opacity = '1';
              btn.style.cursor = 'default';
            } else {
              btn.textContent = 'Install Failed';
              btn.style.background = '#d93025';
              btn.disabled = false;
              btn.style.opacity = '1';
              btn.style.cursor = 'pointer';
            }
          };

          btn.onclick = function() {
            if (!handler) return;
            btn.disabled = true;
            btn.textContent = 'Installing\\u2026';
            btn.style.opacity = '0.7';
            btn.style.cursor = 'default';
            btn.onmouseenter = null;
            btn.onmouseleave = null;

            handler.postMessage({ store: 'chrome', extensionID: extensionID, name: title });
          };

          info.appendChild(btn);
          header.appendChild(info);
          container.appendChild(header);

          // Screenshots
          if (screenshots.length > 0) {
            var gallery = document.createElement('div');
            gallery.style.cssText = 'margin-bottom: 32px; overflow-x: auto; white-space: nowrap; -webkit-overflow-scrolling: touch;';
            screenshots.forEach(function(src) {
              var img = document.createElement('img');
              img.src = src;
              img.style.cssText = 'max-height: 400px; border-radius: 8px; margin-right: 12px; border: 1px solid #e0e0e0;';
              gallery.appendChild(img);
            });
            container.appendChild(gallery);
          }

          // Overview
          if (overviewText) {
            var overviewH = document.createElement('h2');
            overviewH.textContent = 'Overview';
            overviewH.style.cssText = 'font-size: 18px; font-weight: 500; margin: 0 0 12px 0;';
            container.appendChild(overviewH);

            var overviewP = document.createElement('p');
            overviewP.textContent = overviewText;
            overviewP.style.cssText = 'color: #5f6368; font-size: 14px; line-height: 1.6; white-space: pre-wrap;';
            container.appendChild(overviewP);
          }

          // Footer
          var footer = document.createElement('div');
          footer.style.cssText = 'margin-top: 40px; padding-top: 20px; border-top: 1px solid #e0e0e0; color: #5f6368; font-size: 12px;';
          footer.textContent = 'Extension from Chrome Web Store \\u00B7 ID: ' + extensionID;
          container.appendChild(footer);

          mainContent.appendChild(container);
        }

        // Wait for CWS to build the DOM, then scrape and replace
        window.addEventListener('load', function() {
          _setTimeout.call(window, scrapeAndReplace, 200);
        });
        // Fallback if load is slow
        document.addEventListener('DOMContentLoaded', function() {
          _setTimeout.call(window, function() {
            if (!document.body.querySelector('h1')) scrapeAndReplace();
          }, 2000);
        });

        // Force full page navigations instead of SPA routing.
        // CWS uses pushState for internal navigation which breaks our page
        // replacement. By intercepting link clicks and doing location.href
        // instead, our script runs fresh on each page.
        document.addEventListener('click', function(e) {
          var link = e.target.closest('a[href]');
          if (!link) return;
          var href = link.href;
          if (!href || href.indexOf('chromewebstore.google.com') < 0) return;
          e.preventDefault();
          e.stopPropagation();
          window.location.href = href;
        }, true);
      }

      // --- Firefox Add-ons: just replace buttons ---
      if (isAMO) {
        function getAddonSlug() {
          var match = location.pathname.match(/\\/addon\\/([^\\/]+)/);
          return match ? match[1] : null;
        }

        function processFirefoxPage() {
          var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
          if (!handler) return;

          document.querySelectorAll('a, button').forEach(function(btn) {
            var text = (btn.textContent || '').trim();
            if (text.indexOf('Add to Firefox') < 0 && text.indexOf('Add to Refrax') < 0) return;
            if (btn.dataset.refraxPatched) return;

            var slug = getAddonSlug();
            if (!slug) return;

            var newBtn = document.createElement('button');
            newBtn.textContent = 'Add to Refrax';
            newBtn.dataset.refraxPatched = 'true';
            newBtn.style.cssText = 'background: #0060df; color: white; border: none; border-radius: 4px; padding: 8px 16px; font-size: 14px; font-weight: 500; cursor: pointer; font-family: inherit;';

            newBtn.onmouseenter = function() { if (!newBtn.disabled) newBtn.style.background = '#0250bb'; };
            newBtn.onmouseleave = function() { if (!newBtn.disabled) newBtn.style.background = '#0060df'; };

            window.__refraxUpdateInstallButton = function(status) {
              if (status === 'installed') {
                newBtn.textContent = 'Added to Refrax';
                newBtn.style.background = '#188038';
                newBtn.style.opacity = '1';
              } else if (status === 'already_installed') {
                newBtn.textContent = 'Already Installed';
                newBtn.style.background = '#5f6368';
                newBtn.style.opacity = '1';
              } else {
                newBtn.textContent = 'Install Failed';
                newBtn.style.background = '#d93025';
                newBtn.disabled = false;
                newBtn.style.opacity = '1';
                newBtn.style.cursor = 'pointer';
              }
            };

            newBtn.onclick = function() {
              newBtn.disabled = true;
              newBtn.textContent = 'Installing\\u2026';
              newBtn.style.opacity = '0.7';
              newBtn.style.cursor = 'default';

              handler.postMessage({
                store: 'firefox',
                extensionID: slug,
                name: (document.querySelector('h1') || {}).textContent || document.title
              });
            };

            btn.parentNode.replaceChild(newBtn, btn);
          });
        }

        if (document.readyState === 'complete' || document.readyState === 'interactive') {
          processFirefoxPage();
        } else {
          document.addEventListener('DOMContentLoaded', processFirefoxPage);
        }
        new _MutationObserver(processFirefoxPage).observe(document.documentElement, { childList: true, subtree: true });
      }
    })();
    """

    /// Document-end script — no longer needed (everything is in earlyStyleScript).
    static let script = """
    (() => {})();
    """
}
