# Refrax Protocol

RefraxProtocol defines the Swift requests and responses shared by Refrax and its automation clients. It carries flat JSON messages over a Unix socket to control tabs, page content, and browser state.

## Overview

Each message has a `type` discriminator:

```json
{"type": "ping"}
{"type": "screenshot", "mode": "visible"}
{"type": "click", "ref": "e5"}
```

```json
{"type": "ok", "message": "pong"}
{"type": "screenshot", "data": "...base64..."}
{"type": "error", "code": "not_found", "message": "Tab not found"}
```

### What you can do

| Category | Examples |
|----------|----------|
| **Tabs** | Open, close, activate, pin, duplicate, mute, reorder, move between spaces/groups |
| **Navigation** | Navigate, go back/forward, wait for load, reload |
| **Interaction** | Click, type, scroll, hover, fill forms, dismiss cookie banners |
| **Page** | Screenshot, extract content, execute JavaScript, view source, zoom, find |
| **Spaces & Groups** | List, create, switch, delete spaces; full tab group CRUD |
| **Windows** | Resize, move, center, minimize, fullscreen, set opacity, keep on top |
| **Bookmarks** | List, create, delete, favorite/unfavorite, manage folders |
| **History** | List, search, clear, frequent destinations |
| **Site Settings** | Get/set per-domain settings |
| **Dev Tools** | Inspector, console logs, network log, cookies, storage |
| **Compound** | Navigate-and-read, click-and-read, fill-form, scroll-and-read |
| **Programs** | Execute multi-step automation programs with security policies |

## Usage

Point `Package.swift` at this package in a local Refrax checkout:

```swift
let package = Package(
    dependencies: [
        .package(path: "path/to/refrax/Packages/refrax-protocol"),
    ],
    targets: [
        .target(name: "MyTool", dependencies: [
            .product(name: "RefraxProtocol", package: "refrax-protocol"),
        ]),
    ]
)
```

Then import the module:

```swift
import RefraxProtocol

// Build a request
let request = ControlRequest.tabOpen(.init(url: "https://example.com"))

// Encode to JSON
let data = try JSONEncoder().encode(request)

// Decode a response
let response = try JSONDecoder().decode(ControlResponse.self, from: responseData)

switch response {
case .tabs(let tabs):
    for tab in tabs {
        print("\(tab.title) — \(tab.url ?? "")")
    }
case .error(let error):
    print("Error: \(error.message)")
default:
    break
}
```

## Requirements

- macOS 15+
- Swift 6.0+
