# Refrax Protocol

The shared control protocol for [Refrax](https://refrax.website), a WebKit-based browser for macOS.

RefraxProtocol defines the request/response types used for communication between the Refrax browser and external clients over a Unix domain socket. It enables CLI tools, AI agents, and MCP servers to automate and control Refrax programmatically.

## Overview

The protocol is a simple JSON-over-socket RPC layer. Each request is a flat JSON object with a `type` discriminator, and the server responds with a corresponding JSON object:

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
| **Reference Pane** | Show/hide, add/close/list/activate tabs, move to main |
| **Compound** | Navigate-and-read, click-and-read, fill-form, scroll-and-read |
| **Programs** | Execute multi-step automation programs with security policies |

## Usage

Add RefraxProtocol as a dependency in your `Package.swift`:

```swift
let package = Package(
    dependencies: [
        .package(url: "https://github.com/<owner>/refrax-protocol", from: "1.0.0"),
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
