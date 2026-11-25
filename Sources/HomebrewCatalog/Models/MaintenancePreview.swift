import Foundation

/// What `brew cleanup --dry-run` would remove. Line formats follow Homebrew's cleanup.rb.
struct CleanupPreview: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let path: String
        /// Size ("512.3KB", "19 files, 1.4MB") or kind ("broken link", "empty directory").
        let detail: String?
    }

    var items: [Item] = []
    /// Total brew reports it would free, e.g. "1.9MB".
    var freed: String?
    /// Other lines, such as warnings, shown as they are.
    var notes: [String] = []

    var isEmpty: Bool { items.isEmpty }

    init(output: String) {
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if let item = Self.item(from: line) {
                items.append(item)
            } else if let total = Self.freedTotal(from: line) {
                freed = total
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                notes.append(line)
            }
        }
    }

    private static let removePrefix = "Would remove: "
    private static let kindPrefix = "Would remove ("

    private static func item(from line: String) -> Item? {
        if line.hasPrefix(removePrefix) {
            let rest = line.dropFirst(removePrefix.count)
            // "<path> (<size>)": the size is the last parenthesised group.
            if rest.hasSuffix(")"), let open = rest.range(of: " (", options: .backwards) {
                let detail = rest[open.upperBound..<rest.index(before: rest.endIndex)]
                return Item(path: String(rest[..<open.lowerBound]), detail: String(detail))
            }
            return Item(path: String(rest), detail: nil)
        }
        // "Would remove (broken link): <path>"
        if line.hasPrefix(kindPrefix), let close = line.range(of: "): ") {
            let kind = line[line.index(line.startIndex, offsetBy: kindPrefix.count)..<close.lowerBound]
            return Item(path: String(line[close.upperBound...]), detail: String(kind))
        }
        return nil
    }

    private static func freedTotal(from line: String) -> String? {
        let marker = "would free approximately "
        guard let start = line.range(of: marker), let end = line.range(of: " of disk space") else {
            return nil
        }
        return String(line[start.upperBound..<end.lowerBound])
    }
}

/// Formulae `brew autoremove --dry-run` would uninstall.
struct AutoremovePreview: Equatable, Sendable {
    var formulae: [String] = []

    var isEmpty: Bool { formulae.isEmpty }

    /// Output is "==> Would autoremove <n> unneeded formula(e):" then one name per line.
    init(output: String) {
        var inList = false
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if line.contains("Would autoremove") {
                inList = true
            } else if inList, !line.hasPrefix("==>"), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                formulae.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
    }
}
