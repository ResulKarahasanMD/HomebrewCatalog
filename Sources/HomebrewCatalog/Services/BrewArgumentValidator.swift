import Foundation

/// Allow-list for every value that reaches brew/mas argv. Rejecting here keeps
/// option-like ("-…") and path-like ("../") values out of the argument array, whatever
/// their source: catalog JSON, a third-party tap's `brew` output, the tap text field or a
/// persisted `ActionRecord`.
enum BrewArgumentValidator {
    enum Kind: String, Sendable { case package, service, tap, masQuery }

    // `\A…\z`, not `^…$`: ICU `$` also matches before a trailing newline.
    // A package is a bare name or a tap-qualified `user/repo/name`.
    private static let packagePattern =
        #"\A(?:[A-Za-z0-9][A-Za-z0-9._-]{0,63}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}/)?[A-Za-z0-9][A-Za-z0-9+._@-]{0,127}\z"#
    private static let tapPattern =
        #"\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}\z"#

    static func isValid(_ value: String, as kind: Kind) -> Bool {
        switch kind {
        case .package, .service:
            return value.range(of: packagePattern, options: .regularExpression) != nil
                && !value.contains("..")
        case .tap:
            return value.range(of: tapPattern, options: .regularExpression) != nil
                && !value.contains("..")
        case .masQuery:
            return !value.isEmpty && value.count <= 100 && !value.hasPrefix("-")
                && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        }
    }

    /// `value` unchanged when it is valid; otherwise throws before anything is spawned.
    static func validated(_ value: String, as kind: Kind) throws -> String {
        guard isValid(value, as: kind) else {
            throw BrewProcessError.invalidArgument(kind: kind.rawValue, value: String(value.prefix(64)))
        }
        return value
    }
}

/// Builds the argument arrays of the brew commands that take a name. Every name is
/// validated, and placed after `--` so brew cannot read it as an option: Homebrew's parser
/// ends option parsing at `--` (`Library/Homebrew/cli/parser.rb`).
enum BrewArguments {
    static func named(
        _ command: [String], options: [String] = [], names: [String],
        as kind: BrewArgumentValidator.Kind = .package
    ) throws -> [String] {
        let checked = try names.map { try BrewArgumentValidator.validated($0, as: kind) }
        // No names (`brew upgrade`): a bare trailing `--` would add nothing.
        return command + options + (checked.isEmpty ? [] : ["--"] + checked)
    }

    static func package(_ verb: String, name: String, isCask: Bool) throws -> [String] {
        try named([verb], options: isCask ? ["--cask"] : [], names: [name])
    }

    static func service(_ action: String, name: String) throws -> [String] {
        try named(["services", action], names: [name], as: .service)
    }

    static func tap(_ verb: String, name: String) throws -> [String] {
        try named([verb], names: [name], as: .tap)
    }
}
