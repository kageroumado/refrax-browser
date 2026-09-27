// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// The pages and subresources the fixture server serves.
enum Fixtures {
    struct Asset {
        let type: String
        let body: Data
    }

    static let pages: [String: String] = [
        "notify": notify,
        "basic": "<!doctype html><title>basic</title><p id=p>basic page</p>",
        "other": "<!doctype html><title>other</title><p>other page</p>",
        "links": "<!doctype html><title>links</title><a id=link href=\"/html/other\">other</a>",
        // Requests /asset/js-ran-<host> when the page's own script runs.
        "scripted": "<!doctype html><title>scripted</title><script>new Image().src = '/asset/js-ran-' + location.hostname</script>",
        "excluded": "<!doctype html><title>excluded</title>",

        // Records whether a document-start script ran before the page's first script, and
        // leaves an element at the very end for document-end scripts to find.
        "early": """
        <!doctype html><title>early</title>
        <script>window.__seenEarly = typeof window.__early;</script>
        <p>body</p>
        <div id=late></div>
        """,

        // The child frame reports into its parent whether a script ran in it.
        "frames": "<!doctype html><title>frames</title><iframe src=\"/html/child\"></iframe>",
        "child": """
        <!doctype html><title>child</title>
        <script>parent.__childRan = window.__ran === true; parent.__childLoaded = true;</script>
        """,

        "blocking": """
        <!doctype html><title>blocking</title>
        <script src="/asset/blocked.js"></script>
        <script>
        window.results = {};
        function image(name) {
          return new Promise(done => {
            const img = new Image();
            img.onload = () => done('loaded');
            img.onerror = () => done('blocked');
            img.src = '/asset/' + name;
          });
        }
        window.done = Promise.all([
          image('blocked.png').then(v => results.image = v),
          image('allowed.png').then(v => results.allowed = v),
          fetch('/asset/xhr.json').then(() => results.fetch = 'loaded', () => results.fetch = 'blocked'),
        ]).then(() => { results.script = window.__blockedRan ? 'loaded' : 'blocked'; return results; });
        </script>
        """,

        "spa": spa,
        "download": "<!doctype html><title>download</title><a id=link href=\"/download/payload.bin?bytes=100000\">get</a>",

        // Text to select, an image and a link to drag, a field to type into. A keydown listener
        // swallows ⌘J while window.__swallow is set.
        "input": """
        <!doctype html><title>input</title>
        <style>body{margin:0;font:20px sans-serif} p{margin:20px;width:600px} img{display:block;margin:20px;width:120px;height:120px}</style>
        <p id=text>The quick brown fox jumps over the lazy dog, twice over for good measure.</p>
        <img id=pic src="/asset/pic.png" alt="pic">
        <p><a id=link href="/html/basic">a link to drag</a></p>
        <script>
        window.log = [];
        for (const type of ['dragstart', 'dragend', 'mousedown', 'mouseup'])
          addEventListener(type, () => log.push(type), true);
        window.__swallow = false;
        addEventListener('keydown', e => {
          log.push('keydown:' + (e.metaKey ? 'meta+' : '') + e.key);
          if (window.__swallow && e.metaKey && e.key === 'j') e.preventDefault();
        }, true);
        </script>
        """,
    ]

    /// A single-page app: clicking the button routes to a new URL with pushState and paints new
    /// content, which Chromium counts as a soft navigation.
    static let spa = """
    <!doctype html><title>spa</title>
    <style>button{font-size:24px;margin:40px;width:300px;height:80px}</style>
    <button id=go>next view</button><main id=view><h1>home</h1></main>
    <script>
    window.routes = 0;
    document.getElementById('go').addEventListener('click', () => {
      routes++;
      history.pushState({}, '', '/html/spa?view=' + routes);
      const view = document.getElementById('view');
      view.innerHTML = '<h1>view ' + routes + '</h1>' + '<p>content</p>'.repeat(40);
    });
    </script>
    """

    /// Shows notifications from the page and from a service worker, and logs every event
    /// either reports in window.events.
    static let notify = """
    <!doctype html><title>notify</title>
    <script>
    window.events = [];
    window.show = (title, options) => {
      const n = new Notification(title, options);
      for (const type of ['show', 'click', 'close', 'error'])
        n.addEventListener(type, () => events.push(type + ':' + title));
      window.last = n;
      return true;
    };
    navigator.serviceWorker.onmessage = e => events.push(e.data);
    window.worker = navigator.serviceWorker.register('/asset/worker.js').then(reg => new Promise(done => {
      if (reg.active) return done(reg);
      const installing = reg.installing || reg.waiting;
      installing.addEventListener('statechange', () => { if (installing.state === 'activated') done(reg); });
    }));
    </script>
    """

    /// Tells every window of its origin about the notification events it receives.
    static let worker = """
    self.addEventListener('install', () => self.skipWaiting());
    async function tell(text) {
      for (const client of await clients.matchAll({includeUncontrolled: true, type: 'window'}))
        client.postMessage(text);
    }
    self.addEventListener('notificationclick', e => e.waitUntil(tell('notificationclick:' + e.notification.title)));
    self.addEventListener('notificationclose', e => e.waitUntil(tell('notificationclose:' + e.notification.title)));
    """

    /// A 1×1 PNG.
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    static let assets: [String: Asset] = [
        "blocked.png": Asset(type: "image/png", body: png),
        "allowed.png": Asset(type: "image/png", body: png),
        "pic.png": Asset(type: "image/png", body: png),
        "blocked.js": Asset(type: "text/javascript", body: Data("window.__blockedRan = true;".utf8)),
        "xhr.json": Asset(type: "application/json", body: Data("{\"ok\":true}".utf8)),
        "worker.js": Asset(type: "text/javascript", body: Data(worker.utf8)),
    ]

    /// Rules for the blocking page: an image, a first-party script (through uBlock's `1p`
    /// alias) and a fetch (an `xhr` rule, which the engine must apply to fetch()).
    static let blockingList = """
    ! Title: engine-conformance
    /asset/blocked.png
    /asset/blocked.js$script,1p
    /asset/xhr.json$xhr
    example.com##.cosmetic
    ||tracker.invalid^$removeparam=x
    """
}
