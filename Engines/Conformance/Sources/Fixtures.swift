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

        "shields-net": shieldsNet,
        "shields-cosmetic": shieldsCosmetic,
        "shields-frame": shieldsFrame,
        // An inline script a $csp rule's policy forbids.
        "csp-page": "<!doctype html><title>csp</title><script>window.__inline = true;</script>",
        "find": """
        <!doctype html><title>find</title>
        <p>One needle here, another needle there.</p><p>And a third NEEDLE.</p>
        """,
        // A looping tone, started by the test with a user gesture.
        "media": """
        <!doctype html><title>media</title>
        <audio id=player src="/asset/tone.wav" loop></audio>
        <audio id=muted src="/asset/tone.wav" loop muted></audio>
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

    /// Requests of every kind Shields decides, and what came of each: `window.done` resolves to
    /// {name: loaded | blocked | open | error | …}. Requests to `localhost` are third-party.
    static let shieldsNet = """
    <!doctype html><title>shields-net</title>
    <script>
    const other = 'http://localhost:' + location.port;
    function image(src) {
      return new Promise(done => {
        const img = new Image();
        img.onload = () => done('loaded');
        img.onerror = () => done('blocked');
        img.src = src;
      });
    }
    function script(src) {
      return new Promise(done => {
        const element = document.createElement('script');
        element.onload = () => done('loaded');
        element.onerror = () => done('blocked');
        element.src = src;
        document.head.append(element);
      });
    }
    function socket(path) {
      return new Promise(done => {
        const ws = new WebSocket('ws://' + location.host + path);
        ws.onopen = () => done('open');
        ws.onerror = () => done('error');
        setTimeout(() => done('timeout'), 3000);
      });
    }
    window.done = (async () => {
      const r = {};
      r.firstParty = await image('/asset/blocked.png');
      r.thirdParty = await image(other + '/asset/blocked.png');
      r.allowed = await image('/asset/allowed.png');
      r.excepted = await image('/asset/excepted.png');
      r.secondList = await image('/asset/second-list.png');
      r.script = await script('/asset/blocked.js');
      r.redirected = await script('/asset/redirected.js');
      r.redirectedTo = window.__redirected === true ? 'stub' : (window.__realRedirected ? 'original' : 'none');
      r.fetch = await fetch('/asset/xhr.json').then(() => 'loaded', () => 'blocked');
      r.echo = await fetch('/echo?tracking=1&keep=2').then(response => response.text(), () => 'failed');
      r.socketBlocked = await socket('/asset/socket-blocked');
      r.socketAllowed = await socket('/asset/socket-allowed');
      return r;
    })();
    </script>
    """

    /// Elements each kind of cosmetic rule acts on, and a cross-site frame with its own.
    static let shieldsCosmetic = """
    <!doctype html><title>shields-cosmetic</title>
    <div class=cosmetic-hidden id=hidden>hidden</div>
    <div class=procedural id=procedural>remove me</div>
    <div class=procedural id=kept>keep me</div>
    <p class=styled id=styled>styled</p>
    <div class=generic-hidden id=generic>generic</div>
    <div id=visible>visible</div>
    <script>
    window.__seenAtStart = (window.__shieldsMarker || []).slice();
    addEventListener('message', e => { window.frameReport = e.data; });
    const frame = document.createElement('iframe');
    frame.src = 'http://frame.localhost:' + location.port + '/html/shields-frame';
    document.body.append(frame);
    </script>
    """

    /// Reports to its parent whether its rules applied before its own script ran.
    static let shieldsFrame = """
    <!doctype html><title>shields-frame</title>
    <div class=cosmetic-hidden id=hidden>frame</div>
    <script>
    parent.postMessage({
      display: getComputedStyle(document.getElementById('hidden')).display,
      marker: window.__shieldsMarker || null,
    }, '*');
    </script>
    """

    /// One second of a 440 Hz tone, 8 kHz 8-bit mono WAV.
    static let tone: Data = {
        let rate = 8000
        let samples = (0 ..< rate).map { UInt8(128 + 100 * sin(Double($0) * 2 * .pi * 440 / Double(rate))) }
        func le32(_ value: Int) -> [UInt8] { (0 ..< 4).map { UInt8((value >> (8 * $0)) & 0xFF) } }
        func le16(_ value: Int) -> [UInt8] { (0 ..< 2).map { UInt8((value >> (8 * $0)) & 0xFF) } }
        var bytes = Array("RIFF".utf8) + le32(36 + samples.count) + Array("WAVEfmt ".utf8)
        bytes += le32(16) + le16(1) + le16(1) + le32(rate) + le32(rate) + le16(1) + le16(8)
        bytes += Array("data".utf8) + le32(samples.count) + samples
        return Data(bytes)
    }()

    /// A 1×1 PNG.
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    static let assets: [String: Asset] = [
        "blocked.png": Asset(type: "image/png", body: png),
        "allowed.png": Asset(type: "image/png", body: png),
        "pic.png": Asset(type: "image/png", body: png),
        "blocked.js": Asset(type: "text/javascript", body: Data("window.__blockedRan = true;".utf8)),
        "xhr.json": Asset(type: "application/json", body: Data("{\"ok\":true}".utf8)),
        "worker.js": Asset(type: "text/javascript", body: Data(worker.utf8)),
        "excepted.png": Asset(type: "image/png", body: png),
        "second-list.png": Asset(type: "image/png", body: png),
        "in-frame.png": Asset(type: "image/png", body: png),
        "redirected.js": Asset(type: "text/javascript", body: Data("window.__realRedirected = true;".utf8)),
        "tone.wav": Asset(type: "audio/wav", body: tone),
    ]
}
