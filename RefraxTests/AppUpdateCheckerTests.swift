import Foundation
import Testing

@testable import Refrax

// MARK: - Version Comparison

@Suite("AppUpdateChecker Version Comparison")
struct AppUpdateCheckerVersionTests {
    @Test("Strictly newer versions are detected")
    func newerVersions() {
        #expect(AppUpdateChecker.isNewer("0.28", than: "0.27"))
        #expect(AppUpdateChecker.isNewer("1.0.0", than: "0.99.9"))
        #expect(AppUpdateChecker.isNewer("0.27.1", than: "0.27"))
    }

    @Test("Equal and older versions are rejected")
    func equalAndOlder() {
        #expect(!AppUpdateChecker.isNewer("0.28", than: "0.28"))
        #expect(!AppUpdateChecker.isNewer("0.28.0", than: "0.28"))
        #expect(!AppUpdateChecker.isNewer("0.27", than: "0.28"))
    }
}

// MARK: - Release Parsing

@Suite("AppUpdateChecker GitHub Release Parsing")
struct AppUpdateCheckerParsingTests {
    /// GitHub `releases/latest` shape: download nested in assets[].
    private let githubJSON = Data("""
    {
      "tag_name": "v0.99",
      "body": "Notes",
      "published_at": "2026-08-10T12:00:00Z",
      "prerelease": false,
      "assets": [
        {
          "name": "Refrax-0.99.dmg.sig",
          "size": 89,
          "browser_download_url": "https://github.com/kageroumado/refrax-browser/releases/download/v0.99/Refrax-0.99.dmg.sig"
        },
        {
          "name": "Refrax-0.99.dmg",
          "size": 52428800,
          "browser_download_url": "https://github.com/kageroumado/refrax-browser/releases/download/v0.99/Refrax-0.99.dmg"
        }
      ]
    }
    """.utf8)

    @Test("Selects the .dmg asset and its .sig sibling")
    func parsesAssets() throws {
        let update = try AppUpdateChecker.parseRelease(from: githubJSON, currentVersion: "0.1")
        let parsed = try #require(update)
        #expect(parsed.version == "0.99")
        #expect(parsed.downloadURL.lastPathComponent == "Refrax-0.99.dmg")
        #expect(parsed.signatureURL?.lastPathComponent == "Refrax-0.99.dmg.sig")
        #expect(parsed.downloadSize == 52_428_800)
    }

    @Test("Legacy top-level download_url still parses")
    func parsesLegacyManifest() throws {
        let json = Data("""
        {
          "tag_name": "v0.99",
          "body": "Notes",
          "download_url": "http://localhost:8080/api/releases/download/Refrax-0.99.dmg",
          "published_at": "2026-08-10T12:00:00Z",
          "prerelease": false,
          "size": 1024
        }
        """.utf8)
        let update = try AppUpdateChecker.parseRelease(from: json, currentVersion: "0.1")
        let parsed = try #require(update)
        #expect(parsed.downloadURL.host == "localhost")
        #expect(parsed.signatureURL == nil)
        #expect(parsed.downloadSize == 1024)
    }

    @Test("Release without any download location is ignored")
    func rejectsMissingDownload() throws {
        let json = Data("""
        {"tag_name": "v0.99", "prerelease": false, "assets": []}
        """.utf8)
        #expect(try AppUpdateChecker.parseRelease(from: json, currentVersion: "0.1") == nil)
    }

    @Test("Download on a non-allowlisted host is rejected")
    func rejectsForeignHost() throws {
        let json = Data("""
        {
          "tag_name": "v0.99",
          "prerelease": false,
          "assets": [
            {
              "name": "Refrax-0.99.dmg",
              "size": 1,
              "browser_download_url": "https://evil.example.com/Refrax-0.99.dmg"
            }
          ]
        }
        """.utf8)
        #expect(try AppUpdateChecker.parseRelease(from: json, currentVersion: "0.1") == nil)
    }
}

// MARK: - Download URL Policy

@Suite("AppUpdateChecker Conditional Requests")
struct AppUpdateCheckerCacheTests {
    private let release = Data("""
    {
      "tag_name": "v0.99",
      "published_at": "2026-08-10T12:00:00Z",
      "prerelease": false,
      "assets": [
        {
          "name": "Refrax-0.99.dmg",
          "size": 1,
          "browser_download_url": "https://github.com/kageroumado/refrax-browser/releases/download/v0.99/Refrax-0.99.dmg"
        }
      ]
    }
    """.utf8)

    private func cache() throws -> AppUpdateChecker.ReleaseCache {
        let defaults = try #require(UserDefaults(suiteName: "AppUpdateCheckerCacheTests.\(UUID().uuidString)"))
        return AppUpdateChecker.ReleaseCache(defaults: defaults)
    }

    @Test("An update found on one launch is offered again when the next check says nothing changed")
    func unchangedAnswerOffersTheKeptRelease() throws {
        let cache = try cache()
        let first = try AppUpdateChecker.update(status: 200, data: release, etag: "W/\"a\"", cache: cache, currentVersion: "0.1")
        #expect(first?.version == "0.99")
        #expect(cache.etag == "W/\"a\"")

        let again = try AppUpdateChecker.update(status: 304, data: Data(), etag: nil, cache: cache, currentVersion: "0.1")
        #expect(again?.version == "0.99")
    }

    @Test("An unchanged answer is read against the running version, as the release itself is")
    func unchangedAnswerFollowsTheRunningVersion() throws {
        let cache = try cache()
        _ = try AppUpdateChecker.update(status: 200, data: release, etag: "W/\"a\"", cache: cache, currentVersion: "0.1")
        for version in ["0.1", "0.99", "1.0"] {
            let unchanged = try AppUpdateChecker.update(status: 304, data: Data(), etag: nil, cache: cache, currentVersion: version)
            #expect(try unchanged == AppUpdateChecker.parseRelease(from: release, currentVersion: version))
        }
    }

    @Test("An ETag kept without its release is never sent")
    func loneETagIsNotSent() throws {
        let cache = try cache()
        cache.defaults.set("W/\"old\"", forKey: AppUpdateChecker.ReleaseCache.etagKey)
        #expect(cache.etag == nil)
    }

    @Test("A response without an ETag keeps nothing")
    func responseWithoutETagKeepsNothing() throws {
        let cache = try cache()
        _ = try AppUpdateChecker.update(status: 200, data: release, etag: "W/\"a\"", cache: cache, currentVersion: "0.1")
        _ = try AppUpdateChecker.update(status: 200, data: release, etag: nil, cache: cache, currentVersion: "0.1")
        #expect(cache.release == nil)
        #expect(cache.etag == nil)
    }

    @Test("A refused check throws")
    func refusedCheckThrows() throws {
        let cache = try cache()
        #expect(throws: AppUpdateCheckerError.self) {
            try AppUpdateChecker.update(status: 403, data: Data(), etag: nil, cache: cache, currentVersion: "0.1")
        }
    }
}

@Suite("AppUpdateChecker Download URL Policy")
struct AppUpdateCheckerURLPolicyTests {
    @Test("GitHub asset hosts are allowed over HTTPS")
    func allowsGitHubHosts() throws {
        let releaseAsset = try #require(URL(string: "https://github.com/kageroumado/refrax-browser/releases/download/v1/Refrax.dmg"))
        let objectStore = try #require(URL(string: "https://objects.githubusercontent.com/abc"))
        #expect(AppUpdateChecker.isAllowedDownloadURL(releaseAsset))
        #expect(AppUpdateChecker.isAllowedDownloadURL(objectStore))
    }

    @Test("Foreign hosts and downgraded schemes are rejected")
    func rejectsForeign() throws {
        let foreign = try #require(URL(string: "https://evil.example.com/Refrax.dmg"))
        #expect(!AppUpdateChecker.isAllowedDownloadURL(foreign))
        // http:// on a non-pinned host stays rejected even on the debug
        // channel, whose scheme relaxation exists for localhost only
        let httpGitHub = try #require(URL(string: "http://githubusercontent.com.evil.example.com/x.dmg"))
        #expect(!AppUpdateChecker.isAllowedDownloadURL(httpGitHub))
    }
}
