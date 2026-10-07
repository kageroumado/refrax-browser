import ArgumentParser
import Foundation
import RefraxProtocol

struct CookiesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cookies",
        abstract: "Hand a space's cookies to other tools",
        subcommands: [Export.self],
    )

    struct Export: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "export",
            abstract: "Write named cookies to the Keychain without printing them",
            discussion: """
            Writes each named cookie to the login keychain as a generic password \
            with service <prefix>-<cookie name> and account <domain>, updating the \
            item when it already exists. /usr/bin/security can read new items \
            without a prompt. Values never appear in arguments, output, or logs.

            Needs the space's "Allow command-line tools to read this space's \
            cookies" setting. When a name exists for several subdomains or paths, \
            the most specific cookie is exported.

            Examples:
              refrax-ctl cookies export --space Tools --domain example.com \\
                  --names session_id,csrf --keychain example
              security find-generic-password -s example-session_id -w
            """,
        )

        @Option(name: .long, help: "Space name or ID")
        var space: String

        @Option(name: .long, help: "Domain the cookies belong to (matches subdomains)")
        var domain: String

        @Option(name: .long, help: "Comma-separated cookie names")
        var names: String

        @Option(name: .long, help: "Keychain service prefix")
        var keychain: String

        @Flag(name: .long, help: "Output JSON (names, expiry, and services; never values)")
        var json = false

        func run() async throws {
            let cookieNames = names
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !cookieNames.isEmpty else {
                printError("--names needs at least one cookie name")
                _Exit(1)
            }

            let response = try ControlClient.send(
                .cookiesExport(.init(spaceID: space, domain: domain, names: cookieNames)),
            )
            let cookies: [CTL.CookieInfo]
            switch response {
            case let .cookies(exported):
                cookies = exported
            case let .error(info):
                printError("Error [\(info.code)]: \(info.message)")
                _Exit(1)
            default:
                printError("Unexpected response from Refrax")
                _Exit(1)
            }

            var results: [ExportedCookie] = []
            for cookie in cookies {
                guard let value = cookie.value else {
                    printError("Refrax returned no value for '\(cookie.name)'")
                    _Exit(1)
                }
                let service = "\(keychain)-\(cookie.name)"
                do {
                    try CookieKeychainWriter.store(value, service: service, account: domain)
                } catch {
                    printError(error.localizedDescription)
                    _Exit(1)
                }
                results.append(ExportedCookie(name: cookie.name, expiresDate: cookie.expiresDate, service: service, account: domain))
            }

            try report(results)
        }

        private func report(_ results: [ExportedCookie]) throws {
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(results), as: UTF8.self))
            } else if !CLIConfig.quiet {
                for result in results {
                    print("\(result.name) → \(result.service) (expires \(result.expiresDate ?? "with session"))")
                }
            }
        }
    }

    /// What `cookies export` reports for one cookie. Holds no value.
    private struct ExportedCookie: Encodable {
        let name: String
        let expiresDate: String?
        let service: String
        let account: String
    }
}
