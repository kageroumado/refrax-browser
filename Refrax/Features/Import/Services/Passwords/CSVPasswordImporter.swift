import Foundation

/// Imports passwords from CSV files exported by various browsers and password managers.
///
/// This importer supports multiple CSV formats by detecting the column headers
/// and mapping them appropriately. Most browsers use similar column names,
/// but some password managers have unique formats.
///
/// ## Supported Formats
///
/// **Chrome / Chromium browsers**:
/// - Headers: `name,url,username,password`
/// - Alternative: `name,url,username,password,note`
///
/// **Firefox**:
/// - Headers: `url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged`
///
/// **Safari** (Passwords.csv export):
/// - Headers: `Title,URL,Username,Password,Notes,OTPAuth`
///
/// **1Password**:
/// - Headers vary by item type, commonly `Title,Url,Username,Password`
///
/// **Bitwarden**:
/// - Headers: `folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp`
///
/// **LastPass**:
/// - Headers: `url,username,password,totp,extra,name,grouping,fav`
///
/// ## Usage
///
/// ```swift
/// let importer = CSVPasswordImporter()
/// let credentials = try await importer.importPasswords(from: csvURL)
/// ```
final class CSVPasswordImporter: PasswordImporter, Sendable {
    func importPasswords(from fileURL: URL) async throws -> [ImportedCredential] {
        let csvContent = try loadCSVFile(fileURL)
        let lines = parseCSVLines(csvContent)

        guard lines.count > 1 else {
            throw ImportError.noCredentialsFound
        }

        let headers = lines[0]
        let format = detectFormat(from: headers)
        let dataLines = Array(lines.dropFirst())

        var credentials: [ImportedCredential] = []

        for line in dataLines {
            if let credential = parseCredential(from: line, format: format, headers: headers) {
                credentials.append(credential)
            }
        }

        if credentials.isEmpty {
            throw ImportError.noCredentialsFound
        }

        return credentials
    }
}

// MARK: - CSV Format Detection

private extension CSVPasswordImporter {
    enum CSVFormat {
        case chrome
        case firefox
        case safari
        case onePassword
        case bitwarden
        case lastPass
        case generic
    }

    func detectFormat(from headers: [String]) -> CSVFormat {
        let lowercased = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        if lowercased.contains("login_uri") && lowercased.contains("login_username") {
            return .bitwarden
        }

        if lowercased.contains("grouping") && lowercased.contains("fav") {
            return .lastPass
        }

        if lowercased.contains("httprealm") || lowercased.contains("formactionorigin") {
            return .firefox
        }

        if lowercased.contains("otpauth") {
            return .safari
        }

        if lowercased.contains("name"), lowercased.contains("url"), lowercased.contains("username") {
            return .chrome
        }

        if lowercased.contains("title"), lowercased.contains("url") {
            return .onePassword
        }

        return .generic
    }
}

// MARK: - CSV Parsing

private extension CSVPasswordImporter {
    func loadCSVFile(_ url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            do {
                return try String(contentsOf: url, encoding: .isoLatin1)
            } catch {
                throw ImportError.permissionDenied(url.path)
            }
        }
    }

    func parseCSVLines(_ content: String) -> [[String]] {
        var lines: [[String]] = []
        var currentLine: [String] = []
        var currentField = ""
        var insideQuotes = false
        var previousWasQuote = false

        // Iterate over unicode scalars to avoid Swift treating \r\n as a single Character
        for scalar in content.unicodeScalars {
            let char = Character(scalar)

            if char == "\"" {
                if insideQuotes, previousWasQuote {
                    currentField.append("\"")
                    previousWasQuote = false
                } else if insideQuotes {
                    previousWasQuote = true
                } else {
                    insideQuotes = true
                    previousWasQuote = false
                }
            } else {
                if previousWasQuote {
                    insideQuotes = false
                    previousWasQuote = false
                }

                if char == ",", !insideQuotes {
                    currentLine.append(currentField)
                    currentField = ""
                } else if char == "\n" || char == "\r", !insideQuotes {
                    if !currentField.isEmpty || !currentLine.isEmpty {
                        currentLine.append(currentField)
                        if !currentLine.allSatisfy(\.isEmpty) {
                            lines.append(currentLine)
                        }
                        currentLine = []
                        currentField = ""
                    }
                } else {
                    currentField.append(char)
                }
            }
        }

        if !currentField.isEmpty || !currentLine.isEmpty {
            currentLine.append(currentField)
            if !currentLine.allSatisfy(\.isEmpty) {
                lines.append(currentLine)
            }
        }

        return lines
    }
}

// MARK: - Credential Parsing

private extension CSVPasswordImporter {
    func parseCredential(
        from values: [String],
        format: CSVFormat,
        headers: [String],
    ) -> ImportedCredential? {
        switch format {
        case .chrome:
            parseChromeCredential(values, headers: headers)
        case .firefox:
            parseFirefoxCredential(values, headers: headers)
        case .safari:
            parseSafariCredential(values, headers: headers)
        case .onePassword:
            parseOnePasswordCredential(values, headers: headers)
        case .bitwarden:
            parseBitwardenCredential(values, headers: headers)
        case .lastPass:
            parseLastPassCredential(values, headers: headers)
        case .generic:
            parseGenericCredential(values, headers: headers)
        }
    }

    func parseChromeCredential(_ values: [String], headers: [String]) -> ImportedCredential? {
        let indices = headerIndices(headers)

        guard let urlIndex = indices["url"],
              let usernameIndex = indices["username"],
              let passwordIndex = indices["password"],
              urlIndex < values.count,
              usernameIndex < values.count,
              passwordIndex < values.count
        else {
            return nil
        }

        let urlString = values[urlIndex]
        let username = values[usernameIndex]
        let password = values[passwordIndex]

        guard let domain = extractDomain(from: urlString),
              !username.isEmpty,
              !password.isEmpty
        else {
            return nil
        }

        let notes = indices["note"].flatMap { $0 < values.count ? values[$0] : nil }

        return ImportedCredential(
            domain: domain,
            username: username,
            password: password,
            notes: notes,
        )
    }

    func parseFirefoxCredential(_ values: [String], headers: [String]) -> ImportedCredential? {
        let indices = headerIndices(headers)

        guard let urlIndex = indices["url"],
              let usernameIndex = indices["username"],
              let passwordIndex = indices["password"],
              urlIndex < values.count,
              usernameIndex < values.count,
              passwordIndex < values.count
        else {
            return nil
        }

        let urlString = values[urlIndex]
        let username = values[usernameIndex]
        let password = values[passwordIndex]

        guard let domain = extractDomain(from: urlString),
              !username.isEmpty,
              !password.isEmpty
        else {
            return nil
        }

        var dateCreated: Date?
        var dateLastUsed: Date?

        if let timeCreatedIndex = indices["timecreated"],
           timeCreatedIndex < values.count,
           let timestamp = Int64(values[timeCreatedIndex]) {
            dateCreated = Date(timeIntervalSince1970: Double(timestamp) / 1_000)
        }

        if let timeLastUsedIndex = indices["timelastused"],
           timeLastUsedIndex < values.count,
           let timestamp = Int64(values[timeLastUsedIndex]) {
            dateLastUsed = Date(timeIntervalSince1970: Double(timestamp) / 1_000)
        }

        return ImportedCredential(
            domain: domain,
            username: username,
            password: password,
            dateCreated: dateCreated,
            dateLastUsed: dateLastUsed,
        )
    }

    func parseSafariCredential(_ values: [String], headers: [String]) -> ImportedCredential? {
        let indices = headerIndices(headers)

        guard let urlIndex = indices["url"],
              let usernameIndex = indices["username"],
              let passwordIndex = indices["password"],
              urlIndex < values.count,
              usernameIndex < values.count,
              passwordIndex < values.count
        else {
            return nil
        }

        let urlString = values[urlIndex]
        let username = values[usernameIndex]
        let password = values[passwordIndex]

        guard let domain = extractDomain(from: urlString),
              !username.isEmpty,
              !password.isEmpty
        else {
            return nil
        }

        let notes = indices["notes"].flatMap { $0 < values.count ? values[$0] : nil }

        return ImportedCredential(
            domain: domain,
            username: username,
            password: password,
            notes: notes,
        )
    }

    func parseOnePasswordCredential(_ values: [String], headers: [String]) -> ImportedCredential? {
        let indices = headerIndices(headers)

        let urlIndex = indices["url"] ?? indices["website"]
        let usernameIndex = indices["username"]
        let passwordIndex = indices["password"]

        guard let urlIdx = urlIndex,
              let usernameIdx = usernameIndex,
              let passwordIdx = passwordIndex,
              urlIdx < values.count,
              usernameIdx < values.count,
              passwordIdx < values.count
        else {
            return nil
        }

        let urlString = values[urlIdx]
        let username = values[usernameIdx]
        let password = values[passwordIdx]

        guard let domain = extractDomain(from: urlString),
              !username.isEmpty,
              !password.isEmpty
        else {
            return nil
        }

        return ImportedCredential(
            domain: domain,
            username: username,
            password: password,
        )
    }

    func parseBitwardenCredential(_ values: [String], headers: [String]) -> ImportedCredential? {
        let indices = headerIndices(headers)

        guard let urlIndex = indices["login_uri"],
              let usernameIndex = indices["login_username"],
              let passwordIndex = indices["login_password"],
              urlIndex < values.count,
              usernameIndex < values.count,
              passwordIndex < values.count
        else {
            return nil
        }

        let urlString = values[urlIndex]
        let username = values[usernameIndex]
        let password = values[passwordIndex]

        guard let domain = extractDomain(from: urlString),
              !username.isEmpty,
              !password.isEmpty
        else {
            return nil
        }

        let notes = indices["notes"].flatMap { $0 < values.count ? values[$0] : nil }

        return ImportedCredential(
            domain: domain,
            username: username,
            password: password,
            notes: notes,
        )
    }

    func parseLastPassCredential(_ values: [String], headers: [String]) -> ImportedCredential? {
        let indices = headerIndices(headers)

        guard let urlIndex = indices["url"],
              let usernameIndex = indices["username"],
              let passwordIndex = indices["password"],
              urlIndex < values.count,
              usernameIndex < values.count,
              passwordIndex < values.count
        else {
            return nil
        }

        let urlString = values[urlIndex]
        let username = values[usernameIndex]
        let password = values[passwordIndex]

        guard let domain = extractDomain(from: urlString),
              !username.isEmpty,
              !password.isEmpty
        else {
            return nil
        }

        let notes = indices["extra"].flatMap { $0 < values.count ? values[$0] : nil }

        return ImportedCredential(
            domain: domain,
            username: username,
            password: password,
            notes: notes,
        )
    }

    func parseGenericCredential(_ values: [String], headers: [String]) -> ImportedCredential? {
        let indices = headerIndices(headers)

        let urlIndex = indices["url"] ?? indices["website"] ?? indices["site"] ?? indices["domain"]
        let usernameIndex = indices["username"] ?? indices["user"] ?? indices["login"] ?? indices["email"]
        let passwordIndex = indices["password"] ?? indices["pass"]

        guard let urlIdx = urlIndex ?? (!values.isEmpty ? 0 : nil),
              let usernameIdx = usernameIndex ?? (values.count > 1 ? 1 : nil),
              let passwordIdx = passwordIndex ?? (values.count > 2 ? 2 : nil),
              urlIdx < values.count,
              usernameIdx < values.count,
              passwordIdx < values.count
        else {
            return nil
        }

        let urlString = values[urlIdx]
        let username = values[usernameIdx]
        let password = values[passwordIdx]

        guard let domain = extractDomain(from: urlString),
              !username.isEmpty,
              !password.isEmpty
        else {
            return nil
        }

        return ImportedCredential(
            domain: domain,
            username: username,
            password: password,
        )
    }
}

// MARK: - Helpers

private extension CSVPasswordImporter {
    func headerIndices(_ headers: [String]) -> [String: Int] {
        var indices: [String: Int] = [:]
        for (index, header) in headers.enumerated() {
            let normalized = header.lowercased().trimmingCharacters(in: .whitespaces)
            indices[normalized] = index
        }
        return indices
    }

    func extractDomain(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return nil
        }

        if let url = URL(string: trimmed), let host = url.host {
            return host
        }

        let withScheme = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        if let url = URL(string: withScheme), let host = url.host {
            return host
        }

        if !trimmed.contains("/"), !trimmed.contains(" ") {
            return trimmed
        }

        return nil
    }
}
