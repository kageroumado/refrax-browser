// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import CryptoKit
import Foundation

/// The Shields engine the content-blocking tests hand the engine: `engine.dat`, built by
/// shields-datgen from `Engines/Conformance/shields/list0.txt` and `list1.txt`, and
/// `resources.json`, as Refrax writes them, plus the datgen binary that predicts the engine's
/// decisions for the parity test.
struct ShieldsFixture {
    let engine: URL
    let engineSHA256: String
    let resources: URL
    let resourcesSHA256: String
    let datgen: URL?

    /// The adblock-rust version and DAT layout both sides of the contract must share.
    static let format = "adblock-0.13.3;shields-1"

    init?(directory: URL, datgen: URL?) {
        engine = directory.appending(path: "engine.dat")
        resources = directory.appending(path: "resources.json")
        guard let engineData = try? Data(contentsOf: engine), let resourcesData = try? Data(contentsOf: resources) else {
            return nil
        }
        engineSHA256 = Self.sha256(engineData)
        resourcesSHA256 = Self.sha256(resourcesData)
        self.datgen = datgen
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The contract's ContentBlockingPolicy naming these files.
    func policy(enabled: Bool, mode: String, allowlistedHosts: [String], format: String?) -> [String: Any] {
        [
            "isEnabled": enabled,
            "mode": mode,
            "engine": ["path": engine.absoluteString, "sha256": engineSHA256, "format": format ?? Self.format],
            "resources": ["path": resources.absoluteString, "sha256": resourcesSHA256],
            "lists": [["id": "list0", "sourceIndex": 0], ["id": "list1", "sourceIndex": 1]],
            "allowlistedHosts": allowlistedHosts,
        ]
    }

    /// The decisions adblock-rust itself makes for `requests` ({url, source, type}), by url and type.
    func predict(_ requests: [[String: String]]) throws -> [String: String] {
        guard let datgen else {
            throw Skip("no shields-datgen (run with --datgen PATH)")
        }
        let input = FileManager.default.temporaryDirectory.appending(path: "shields-requests-\(UUID().uuidString).json")
        try JSON.data(requests).write(to: input)
        defer { try? FileManager.default.removeItem(at: input) }
        let process = Process()
        process.executableURL = datgen
        process.arguments = ["predict", engine.path, resources.path, input.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure("shields-datgen predict exited \(process.terminationStatus)")
        }
        var decisions: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let decision = JSON.parse(Data(line.utf8)) as? [String: Any],
                  let url = decision["url"] as? String, let type = decision["type"] as? String,
                  let name = decision["decision"] as? String else { continue }
            decisions["\(type) \(url)"] = name
        }
        return decisions
    }
}
