import Foundation
import Testing
@testable import Refrax

@Suite("Exception recorder", .serialized)
struct ExceptionRecorderTests {
    private func makeLogURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("exception-recorder-\(UUID().uuidString).log")
    }

    private func raise(_ name: String, reason: String) {
        _ = RefraxCatchingNSException {
            NSException(name: NSExceptionName(name), reason: reason).raise()
        }
    }

    @Test
    func `A caught exception is written with its name, reason, and stack`() throws {
        let url = makeLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        RefraxExceptionRecorderInstall(url.path)

        raise("RefraxTestException", reason: "Unable to activate constraint in a test")

        let log = try String(contentsOf: url, encoding: .utf8)
        #expect(log.contains("RefraxTestException: Unable to activate constraint in a test"))
        #expect(log.contains("RefraxCatchingNSException"))
    }

    @Test
    func `The log keeps only the newest four exceptions, newest last`() throws {
        let url = makeLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        RefraxExceptionRecorderInstall(url.path)

        for index in 1 ... 6 {
            raise("RefraxTestException\(index)", reason: "reason \(index)")
        }

        let log = try String(contentsOf: url, encoding: .utf8)
        #expect(!log.contains("RefraxTestException2:"))
        #expect(log.contains("RefraxTestException3:"))
        let fifth = try #require(log.range(of: "RefraxTestException5:"))
        let sixth = try #require(log.range(of: "RefraxTestException6:"))
        #expect(fifth.lowerBound < sixth.lowerBound)
    }
}
