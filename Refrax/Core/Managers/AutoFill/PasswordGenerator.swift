import Foundation
import NaturalLanguage

// MARK: - Research Notes

//
// ## Password Generation Best Practices (2024-2025)
//
// ### Safari's Approach (WBSPasswordGenerationManager)
// - Format: `xxxxxx-xxxxxx-xxxxxx` (20 chars including dashes)
// - Pronounceable consonant-vowel patterns for memorability
// - Dictionary word filtering via NaturalLanguage framework
// - Website-specific rules from password-manager-resources quirks database
//
// ### Chrome's Approach (password_generator.cc)
// - Default length: 15 characters
// - Excludes visually similar characters: l, I, 1, O, 0, o
// - Symbols: "-_.:!" (limited set for compatibility)
// - Detects "difficult to read" patterns (consecutive dashes/underscores)
// - Shuffles up to 5 times to avoid readability issues
// - Uses cryptographic randomness via base::RandGenerator()
//
// ### 1Password Parser (password-rules-parser)
// - Full spec: minlength, maxlength, required, allowed, max-consecutive
// - Character classes: upper, lower, digit, special, ascii-printable, unicode
// - Custom character sets via [...] syntax with escape handling
// - Multiple `required` rules create AND constraints (all must be satisfied)
//
// ### NIST Guidelines (2024-2025)
// - Minimum 12-16 characters recommended
// - Length > complexity for entropy
// - Passphrases preferred (e.g., "peanut-cliff-orange-wizard")
// - No mandatory periodic rotation unless breach suspected
//
// ### Security Considerations
// - Swift's Int.random(in:) uses SystemRandomNumberGenerator (cryptographically secure)
// - Avoid logging generated passwords
// - Short TTL for temporary storage (we use 5 minutes)
// - Clear on app background/memory pressure
//
// Sources:
// - https://github.com/chromium/chromium/blob/master/components/password_manager/core/browser/generation/password_generator.cc
// - https://github.com/1Password/password-rules-parser
// - https://github.com/apple/password-manager-resources
// - https://www.nist.gov/cybersecurity/how-do-i-create-good-password

/// Generates strong passwords compatible with Safari's format and website requirements.
///
/// ## Default Format
/// Safari-style: `xxxxxx-xxxxxx-xxxxxx`
/// - Three groups of 6 characters separated by dashes (20 total)
/// - Pronounceable consonant-vowel patterns for memorability
/// - At least one uppercase letter and one digit at random positions
/// - Filtered to avoid dictionary words
///
/// ## Custom Generation
/// When website rules require specific constraints (length, character requirements),
/// the generator adapts while maintaining readability and security.
///
/// ## Thread Safety
/// All methods are nonisolated and can be called from any context.
/// Uses Swift's cryptographically secure random number generator.
enum PasswordGenerator {
    // MARK: - Character Sets

    //
    // Chrome excludes visually similar characters to avoid user confusion:
    // - Lowercase 'l' (looks like '1' or 'I')
    // - Uppercase 'I' and 'O' (look like '1' and '0')
    // - Digits '0' and '1' (look like 'O' and 'l')
    // We use pronounceable patterns which naturally avoid most of these.

    /// Consonants for pronounceable generation (excludes 'l' for visual clarity).
    private nonisolated static let consonants = Array("bcdfghjkmnpqrstvwxyz")

    /// Vowels for pronounceable generation.
    private nonisolated static let vowels = Array("aeiou")

    /// Digits excluding visually ambiguous '0' and '1' (Chrome's approach).
    private nonisolated static let digits = Array("23456789")

    /// Special characters for sites requiring them.
    /// Limited set matching Chrome's "-_.:!" for maximum compatibility.
    private nonisolated static let specialCharacters = Array("-_.:!")

    /// Full uppercase set excluding 'I' and 'O' (visually similar to 1 and 0).
    private nonisolated static let uppercaseUnambiguous = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")

    /// Full lowercase set excluding 'l' (visually similar to 1 and I).
    private nonisolated static let lowercaseUnambiguous = Array("abcdefghijkmnopqrstuvwxyz")

    // MARK: - Configuration

    /// Maximum attempts to generate a password without dictionary words.
    private nonisolated static let maxGenerationAttempts = 10

    /// Maximum shuffle attempts to avoid difficult-to-read patterns (Chrome uses 5).
    private nonisolated static let maxShuffleAttempts = 5

    /// Minimum password length enforced regardless of site rules.
    ///
    /// Even if a site claims to accept 4-character passwords, we enforce
    /// a minimum of 8 to prevent weak password generation from malicious
    /// or misconfigured quirks rules. NIST recommends 12-16 minimum.
    private nonisolated static let absoluteMinimumLength = 8

    /// Maximum number of required character sets to prevent DoS.
    ///
    /// A malicious quirks rule could specify hundreds of required sets
    /// to slow down generation. We cap this to a reasonable number.
    private nonisolated static let maxRequiredSets = 8

    // MARK: - Public API

    /// Generates a strong password respecting optional website rules.
    ///
    /// - Parameter rules: Optional password rules from the website's quirks database.
    /// - Returns: A generated password (20 chars for Safari-style, varies for custom).
    nonisolated static func generateStrongPassword(rules: PasswordRules? = nil) -> String {
        for _ in 0 ..< maxGenerationAttempts {
            let password = generateCandidate(rules: rules)
            if !containsDictionaryWords(password), isCompliant(password, rules: rules) {
                return password
            }
        }

        // Fallback: return last attempt even if it might contain words
        return generateCandidate(rules: rules)
    }

    /// Checks if a password looks like it was generated by this generator or Safari.
    ///
    /// - Parameter password: The password to check.
    /// - Returns: `true` if the password matches the Safari generated format.
    nonisolated static func looksLikeGeneratedPassword(_ password: String) -> Bool {
        let pattern = #"^[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}$"#
        return password.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Password Generation

    /// Generates a password candidate respecting optional rules.
    private nonisolated static func generateCandidate(rules: PasswordRules?) -> String {
        // Check if rules require special handling
        if let rules, needsCustomGeneration(rules) {
            return generateCustomCandidate(rules: rules)
        }

        // Default Safari-style password
        return generateSafariStyleCandidate()
    }

    /// Checks if rules require custom password generation.
    private nonisolated static func needsCustomGeneration(_ rules: PasswordRules) -> Bool {
        if rules.allowedCharacters != nil {
            return true
        }

        // If max length is too short for Safari format (20 chars)
        if let maxLength = rules.maxLength, maxLength < 20 {
            return true
        }

        // If min length is much longer than Safari format
        if let minLength = rules.minLength, minLength > 20 {
            return true
        }

        // If specific character requirements conflict with Safari format
        if let required = rules.requiredCharacterSets, required.count > 2 {
            return true
        }

        // If max-consecutive is specified (Safari format might violate it)
        if rules.maxConsecutive != nil {
            return true
        }

        return false
    }

    /// Generates Safari-style password: `xxxxxx-xxxxxx-xxxxxx`.
    private nonisolated static func generateSafariStyleCandidate() -> String {
        var groups = [
            generatePronounceable(length: 6),
            generatePronounceable(length: 6),
            generatePronounceable(length: 6),
        ]

        // Insert uppercase at random position
        let uppercaseGroup = Int.random(in: 0 ..< 3)
        let uppercasePos = Int.random(in: 0 ..< 6)
        groups[uppercaseGroup] = replaceCharacter(
            in: groups[uppercaseGroup],
            at: uppercasePos,
            with: { $0.uppercased().first! },
        )

        // Insert digit at random position (different from uppercase if in same group)
        let digitGroup = Int.random(in: 0 ..< 3)
        var digitPos = Int.random(in: 0 ..< 6)

        // Ensure digit doesn't overwrite uppercase
        if digitGroup == uppercaseGroup, digitPos == uppercasePos {
            digitPos = (digitPos + 1) % 6
        }

        groups[digitGroup] = replaceCharacter(
            in: groups[digitGroup],
            at: digitPos,
            with: { _ in digits.randomElement()! },
        )

        return groups.joined(separator: "-")
    }

    /// Generates a password that meets custom site requirements.
    private nonisolated static func generateCustomCandidate(rules: PasswordRules) -> String {
        let length = determineLength(rules: rules)
        var password = generateBasePassword(length: length, rules: rules)

        // Satisfy required character sets
        password = insertRequiredCharacters(password, rules: rules, allowedCharacters: rules.allowedCharacters)

        // Enforce max-consecutive constraint if specified
        if let maxConsec = rules.maxConsecutive, maxConsec > 0 {
            password = enforceMaxConsecutive(password, max: maxConsec, allowedCharacters: rules.allowedCharacters)
        }

        // Add dashes for readability if length permits
        if length >= 12,
           canInsertDashes(rules: rules, passwordLength: password.count) {
            password = insertDashes(password)
        }

        // Chrome's approach: check for difficult-to-read patterns and reshuffle
        for _ in 0 ..< maxShuffleAttempts {
            if !isDifficultToRead(password) {
                break
            }
            password = shufflePassword(password)
        }

        return password
    }

    /// Determines the target password length from rules.
    ///
    /// Enforces security minimums regardless of what the site claims to accept.
    private nonisolated static func determineLength(rules: PasswordRules) -> Int {
        let siteMin = rules.minLength ?? 12
        let siteMax = rules.maxLength ?? 32

        // Enforce our security minimum
        let minLength = max(siteMin, absoluteMinimumLength)
        let maxLength = max(siteMax, absoluteMinimumLength)

        // Aim for 16 chars or midpoint if constrained (NIST recommends 12-16 minimum)
        let targetLength = min(max(minLength, 16), maxLength)
        return targetLength
    }

    /// Inserts required character types at random positions.
    ///
    /// Caps the number of required sets to prevent DoS from malicious rules.
    private nonisolated static func insertRequiredCharacters(
        _ password: String,
        rules: PasswordRules,
        allowedCharacters: Set<Character>?,
    ) -> String {
        var chars = Array(password)
        var usedPositions = Set<Int>()

        // Always ensure at least one uppercase and one digit
        let defaultRequirements: [[Character]] = [
            Array(uppercaseUnambiguous),
            Array(digits),
        ]

        var requirements = rules.requiredCharacterSets ?? defaultRequirements

        if let allowedCharacters {
            requirements = requirements
                .map { $0.filter { allowedCharacters.contains($0) } }
                .filter { !$0.isEmpty }
        }

        // Cap requirements to prevent DoS
        if requirements.count > maxRequiredSets {
            requirements = Array(requirements.prefix(maxRequiredSets))
        }

        // Don't try to insert more characters than we have positions
        let maxInsertions = min(requirements.count, chars.count)

        for i in 0 ..< maxInsertions {
            let charSet = requirements[i]
            guard !charSet.isEmpty else { continue }

            // Find a position that hasn't been used
            var position: Int
            var attempts = 0
            repeat {
                position = Int.random(in: 0 ..< chars.count)
                attempts += 1
                // Prevent infinite loop if somehow all positions are used
                if attempts > chars.count * 2 { break }
            } while usedPositions.contains(position)

            usedPositions.insert(position)
            chars[position] = charSet.randomElement()!
        }

        return String(chars)
    }

    /// Enforces maximum consecutive identical characters.
    ///
    /// Some sites (e.g., aeon.co.jp) limit consecutive identical characters.
    /// This replaces violations with random characters from the same class.
    private nonisolated static func enforceMaxConsecutive(
        _ password: String,
        max: Int,
        allowedCharacters: Set<Character>?,
    ) -> String {
        guard max > 0 else { return password }

        var chars = Array(password)
        var consecutiveCount = 1

        for i in 1 ..< chars.count {
            if chars[i] == chars[i - 1] {
                consecutiveCount += 1
                if consecutiveCount > max {
                    // Replace with a different character
                    let original = chars[i]
                    let replacements = allowedCharacters.map { Array($0) } ?? consonants
                    var replacement: Character
                    repeat {
                        replacement = replacements.randomElement()!
                    } while replacement == original && replacements.count > 1
                    chars[i] = replacement
                    consecutiveCount = 1
                }
            } else {
                consecutiveCount = 1
            }
        }

        return String(chars)
    }

    /// Checks if a password has difficult-to-read patterns.
    ///
    /// Chrome detects consecutive dashes or underscores which "are joined into
    /// long strokes on the screen in many fonts."
    private nonisolated static func isDifficultToRead(_ password: String) -> Bool {
        password.contains("--") || password.contains("__")
    }

    /// Shuffles password characters while preserving dashes.
    private nonisolated static func shufflePassword(_ password: String) -> String {
        let chars = Array(password)
        let dashIndices = chars.indices.filter { chars[$0] == "-" }

        // Extract non-dash characters
        var nonDashChars = chars.filter { $0 != "-" }
        nonDashChars.shuffle()

        // Rebuild with dashes in original positions
        var result: [Character] = []
        var nonDashIndex = 0
        for i in chars.indices {
            if dashIndices.contains(i) {
                result.append("-")
            } else {
                result.append(nonDashChars[nonDashIndex])
                nonDashIndex += 1
            }
        }

        return String(result)
    }

    /// Inserts dashes for readability.
    private nonisolated static func insertDashes(_ password: String) -> String {
        var chars = Array(password)
        let groupSize = chars.count / 3

        if groupSize >= 4 {
            chars.insert("-", at: groupSize * 2)
            chars.insert("-", at: groupSize)
        }

        return String(chars)
    }

    /// Generates a pronounceable string using consonant-vowel patterns.
    private nonisolated static func generatePronounceable(length: Int) -> String {
        var result = ""
        var useConsonant = Bool.random()

        for _ in 0 ..< length {
            if useConsonant {
                result.append(consonants.randomElement()!)
            } else {
                result.append(vowels.randomElement()!)
            }
            useConsonant.toggle()
        }

        return result
    }

    /// Generates a base password using allowed characters when specified.
    private nonisolated static func generateBasePassword(length: Int, rules: PasswordRules) -> String {
        if let allowed = rules.allowedCharacters, !allowed.isEmpty {
            let allowedChars = Array(allowed)
            return String((0 ..< length).map { _ in allowedChars.randomElement()! })
        }

        return generatePronounceable(length: length)
    }

    /// Determines if dashes can be inserted without violating allowed/max length rules.
    private nonisolated static func canInsertDashes(rules: PasswordRules, passwordLength: Int) -> Bool {
        if let allowed = rules.allowedCharacters, !allowed.contains("-") {
            return false
        }

        if let maxLength = rules.maxLength, maxLength >= absoluteMinimumLength {
            return passwordLength + 2 <= maxLength
        }

        return true
    }

    /// Replaces a character at a specific position in a string.
    private nonisolated static func replaceCharacter(
        in string: String,
        at position: Int,
        with transform: (Character) -> Character,
    ) -> String {
        var chars = Array(string)
        chars[position] = transform(chars[position])
        return String(chars)
    }

    // MARK: - Dictionary Word Filtering

    /// Checks if the password contains common dictionary words.
    private nonisolated static func containsDictionaryWords(_ password: String) -> Bool {
        // Check each group individually
        let groups = password.split(separator: "-").map { String($0).lowercased() }

        for group in groups {
            if isLikelyWord(group) {
                return true
            }

            // Check substrings of 4+ characters
            for length in 4 ... min(6, group.count) {
                for start in 0 ... (group.count - length) {
                    let startIndex = group.index(group.startIndex, offsetBy: start)
                    let endIndex = group.index(startIndex, offsetBy: length)
                    let substring = String(group[startIndex ..< endIndex])

                    if isLikelyWord(substring) {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Validates a generated password against the provided rules.
    private nonisolated static func isCompliant(_ password: String, rules: PasswordRules?) -> Bool {
        guard let rules else { return true }

        let length = password.count
        let minimumLength = max(rules.minLength ?? 0, absoluteMinimumLength)
        if length < minimumLength {
            return false
        }

        if let maxLength = rules.maxLength, maxLength >= absoluteMinimumLength, length > maxLength {
            return false
        }

        if let allowed = rules.allowedCharacters,
           !password.allSatisfy({ allowed.contains($0) }) {
            return false
        }

        let requirements = rules.requiredCharacterSets ?? [
            Array(uppercaseUnambiguous),
            Array(digits),
        ]

        if let allowed = rules.allowedCharacters {
            for set in requirements {
                let filtered = set.filter { allowed.contains($0) }
                if !filtered.isEmpty, !password.contains(where: { filtered.contains($0) }) {
                    return false
                }
            }
        } else {
            for set in requirements {
                if !password.contains(where: { set.contains($0) }) {
                    return false
                }
            }
        }

        if let maxConsecutive = rules.maxConsecutive, maxConsecutive > 0 {
            var count = 1
            let chars = Array(password)
            for i in 1 ..< chars.count {
                if chars[i] == chars[i - 1] {
                    count += 1
                    if count > maxConsecutive {
                        return false
                    }
                } else {
                    count = 1
                }
            }
        }

        return true
    }

    /// Checks if a string is likely a dictionary word using NaturalLanguage.
    private nonisolated static func isLikelyWord(_ string: String) -> Bool {
        guard string.count >= 4 else { return false }

        // Common short words to filter out (including inappropriate content)
        let commonWords: Set<String> = [
            "pass", "word", "hack", "porn", "sexy", "drug", "kill", "hate",
            "fuck", "shit", "damn", "cock", "dick", "cunt", "bitch", "nazi",
            "bomb", "dead", "death", "evil", "gore", "rape", "sick", "spam",
            "test", "temp", "admin", "root", "user", "login", "name", "mail",
        ]

        if commonWords.contains(string) {
            return true
        }

        // Use NaturalLanguage to detect if it's a real word
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = string

        var isWord = false
        tagger.enumerateTags(
            in: string.startIndex ..< string.endIndex,
            unit: .word,
            scheme: .lexicalClass,
        ) { tag, _ in
            if tag != nil {
                isWord = true
            }
            return false
        }

        return isWord
    }
}

// MARK: - Password Rules

/// Password rules parsed from website requirements.
///
/// ## Supported Directives (per Apple/1Password spec)
///
/// - `minlength: N` - Minimum password length
/// - `maxlength: N` - Maximum password length
/// - `required: class, class, ...` - Required character classes (AND logic)
/// - `allowed: class, class, ...` - Allowed character classes
/// - `max-consecutive: N` - Maximum consecutive identical characters
///
/// ## Character Classes
///
/// - `upper` - Uppercase letters (A-Z)
/// - `lower` - Lowercase letters (a-z)
/// - `digit` - Digits (0-9)
/// - `special` - Special characters
/// - `ascii-printable` - All printable ASCII
/// - `[abc...]` - Custom character set
///
/// ## References
///
/// - [1Password Parser](https://github.com/1Password/password-rules-parser)
/// - [Apple Password Rules](https://developer.apple.com/password-rules/)
/// - [WHATWG Proposal](https://github.com/nicman23/nicman23.github.io/blob/whatwg-password-rules/passwordrules/index.md)
struct PasswordRules: Sendable, Equatable {
    /// Minimum password length.
    var minLength: Int?

    /// Maximum password length.
    var maxLength: Int?

    /// Allowed character sets.
    var allowedCharacters: Set<Character>?

    /// Required character sets (password must contain at least one from each).
    var requiredCharacterSets: [[Character]]?

    /// Maximum consecutive identical characters allowed.
    ///
    /// Some sites (e.g., aeon.co.jp) restrict consecutive identical characters
    /// to prevent patterns like "aaa" or "111".
    var maxConsecutive: Int?

    /// Parses password rules from a string (e.g., from HTML passwordrules attribute).
    ///
    /// Format: `minlength: 8; maxlength: 20; required: upper, lower, digit; max-consecutive: 3`
    ///
    /// - Parameter rulesString: The rules string to parse.
    /// - Returns: Parsed password rules, or `nil` if parsing fails.
    nonisolated static func parse(_ rulesString: String) -> PasswordRules? {
        var rules = PasswordRules()

        let components = rulesString.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }

        for component in components {
            let parts = component.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }

            let key = parts[0].lowercased()
            let value = parts[1]

            switch key {
            case "minlength":
                rules.minLength = Int(value)
            case "maxlength":
                rules.maxLength = Int(value)
            case "required":
                let newSets = parseCharacterSets(value)
                if rules.requiredCharacterSets == nil {
                    rules.requiredCharacterSets = newSets
                } else {
                    // Multiple required rules create AND constraints (1Password spec)
                    rules.requiredCharacterSets?.append(contentsOf: newSets ?? [])
                }
            case "allowed":
                let allowed = parseAllowedCharacters(value)
                if rules.allowedCharacters == nil {
                    rules.allowedCharacters = allowed
                } else {
                    // Multiple allowed rules extend the set
                    if let allowed {
                        rules.allowedCharacters?.formUnion(allowed)
                    }
                }
            case "max-consecutive":
                rules.maxConsecutive = Int(value)
            default:
                break
            }
        }

        return rules
    }

    /// Parses character class specifications into arrays of characters.
    private nonisolated static func parseCharacterSets(_ value: String) -> [[Character]]? {
        let sets = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var result: [[Character]] = []

        for set in sets {
            if let chars = parseCharacterClass(set) {
                result.append(chars)
            }
        }

        return result.isEmpty ? nil : result
    }

    /// Parses a single character class specification.
    private nonisolated static func parseCharacterClass(_ spec: String) -> [Character]? {
        switch spec {
        case "upper":
            return Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        case "lower":
            return Array("abcdefghijklmnopqrstuvwxyz")
        case "digit":
            return Array("0123456789")
        case "special":
            // Chrome's limited set for compatibility: "-_.:!"
            // Extended set for broader compatibility
            return Array("!@#$%^&*()-_=+[]{}|;:',.<>?/~`")
        case "ascii-printable", "unicode":
            // All printable ASCII (space through tilde)
            // Unicode treated same as ASCII-printable per 1Password spec
            return Array(" !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")
        default:
            // Custom character set: [abc...]
            if spec.hasPrefix("["), spec.hasSuffix("]") {
                let chars = String(spec.dropFirst().dropLast())
                // Filter to printable ASCII only (security: prevent encoding attacks)
                return Array(chars.filter { $0.isASCII && $0.isPrintable })
            }
            return nil
        }
    }

    /// Parses allowed character specifications.
    private nonisolated static func parseAllowedCharacters(_ value: String) -> Set<Character>? {
        let sets = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var result = Set<Character>()

        for set in sets {
            if let chars = parseCharacterClass(set) {
                result.formUnion(chars)
            }
        }

        return result.isEmpty ? nil : result
    }
}

// MARK: - Character Extensions

private extension Character {
    /// Whether this character is printable (not a control character).
    nonisolated var isPrintable: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.value >= 0x20 && scalar.value <= 0x7E
    }
}
