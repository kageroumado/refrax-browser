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
