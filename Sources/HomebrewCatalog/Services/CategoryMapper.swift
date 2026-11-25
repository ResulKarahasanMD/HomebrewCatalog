import Foundation

struct CategoryMapper: Sendable {
    static let shared = CategoryMapper()

    /// Used for tie-breaking when multiple categories share the same keyword score.
    private static let categoryPriority: [Category] = [
        .entertainment,
        .communication,
        .finance,
        .education,
        .science,
        .security,
        .networking,
        .multimedia,
        .design,
        .productivity,
        .utilities,
        .developerTools,
        .system,
    ]

    private let keywordMap: [Category: [String]] = [
        .developerTools: [
            "git", "docker", "kubernetes", "node", "nodejs", "python", "ruby", "swift", "golang", "rust",
            "xcode", "vscode", "intellij", "compiler", "sdk", "framework", "debugger", "debugging",
            "unittest", "cmake", "make", "gradle", "maven", "npm", "yarn", "pip", "cargo",
            "programming", "developer", "development", "linter", "formatter",
        ],
        .productivity: [
            "note", "todo", "task", "calendar", "email", "document", "pdf", "office", "spreadsheet",
            "word", "slide", "markup", "markdown", "viewer", "reader",
        ],
        .multimedia: [
            "video", "audio", "music", "player", "ffmpeg", "vlc", "youtube", "stream", "recording",
            "capture", "photo", "gimp", "blender", "imagemagick", "transcode", "encode", "decode",
        ],
        .utilities: [
            "cleaner", "compress", "zip", "backup", "sync", "clipboard", "timer", "calculator",
            "scanner", "benchmark", "launcher", "shortcut", "automation", "archiver",
        ],
        .entertainment: [
            "game", "steam", "minecraft", "retro", "emulator", "puzzle", "arcade", "board-game",
        ],
        .design: [
            "design", "vector", "draw", "sketch", "figma", "adobe", "illustrator", "photoshop",
            "cad", "rendering", "color", "palette", "font", "typography", "graphics",
        ],
        .communication: [
            "chat", "message", "slack", "discord", "telegram", "whatsapp", "zoom", "meet", "teams",
            "skype", "voip", "irc", "matrix", "signal",
        ],
        .finance: [
            "money", "budget", "bank", "crypto", "bitcoin", "trading", "investment", "expense",
            "invoice", "tax", "accounting", "payment", "wallet",
        ],
        .education: [
            "learn", "course", "quiz", "flashcard", "dictionary", "language", "translate", "math",
            "chemistry", "biology",
        ],
        .science: [
            "matlab", "jupyter", "bioconductor", "genomics", "bioinformatics", "simulation",
            "molecule", "gene", "research", "laboratory", "chemistry", "physics",
        ],
        .networking: [
            "vpn", "openvpn", "wireguard", "tailscale", "ssh", "ftp", "dns", "firewall", "proxy",
            "networking", "wifi", "wireless", "nmap", "curl", "wget", "iperf", "traceroute",
        ],
        .security: [
            "password", "encrypt", "hash", "tor", "certificate", "gpg", "gnupg", "authentication",
            "2fa", "secure", "privacy", "keychain", "vault",
        ],
        .system: [
            "system", "process", "disk", "memory", "cpu", "gpu", "battery", "bluetooth", "driver",
            "kernel", "boot", "recovery", "monitoring", "sysctl",
        ],
    ]

    private init() {}

    func mapItem(_ item: some BrewItem) -> Category {
        let searchText = searchText(for: item)
        let packageName = item.name.lowercased()

        var bestCategory: Category?
        var bestScore = 0

        for category in Self.categoryPriority {
            guard let keywords = keywordMap[category] else { continue }
            let score = keywords.reduce(into: 0) { count, keyword in
                if matches(keyword: keyword, in: searchText, packageName: packageName) {
                    count += 1
                }
            }
            if score > bestScore {
                bestScore = score
                bestCategory = category
            }
        }

        return bestCategory ?? .other
    }

    func mapFormula(_ formula: BrewFormula) -> Category {
        mapItem(formula)
    }

    func mapCask(_ cask: BrewCask) -> Category {
        mapItem(cask)
    }

    private func searchText(for item: some BrewItem) -> String {
        var parts = [item.name]
        if let desc = item.desc, !desc.isEmpty {
            parts.append(desc)
        }
        return parts.joined(separator: " ").lowercased()
    }

    private func matches(keyword: String, in text: String, packageName: String) -> Bool {
        let keyword = keyword.lowercased()
        guard !keyword.isEmpty else { return false }

        if packageName == keyword
            || packageName.hasPrefix("\(keyword)-")
            || packageName.hasPrefix("\(keyword)_")
            || packageName.hasSuffix("-\(keyword)")
            || packageName.contains("-\(keyword)-")
        {
            return true
        }

        if keyword.count <= 4 {
            return containsWholeWord(keyword, in: text)
        }

        return text.contains(keyword)
    }

    private func containsWholeWord(_ word: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = "\\b\(escaped)\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
