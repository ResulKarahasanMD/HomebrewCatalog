import Foundation

// MARK: - Installed Formula Info

struct InstalledFormulaInfo: Identifiable, Sendable, Hashable, Codable {
    var id: String { name }
    let name: String
    let fullName: String
    let desc: String?
    let homepage: String?
    let license: String?
    let installedVersion: String
    let latestVersion: String?
    let isPinned: Bool
    let isOutdated: Bool
    let installedOnRequest: Bool
    let installedAsDependency: Bool

    var isLeaf: Bool = false

    var displayVersion: String {
        if let latest = latestVersion, isOutdated {
            return "\(installedVersion) → \(latest)"
        }
        return installedVersion
    }
}

// MARK: - Installed Cask Info

struct InstalledCaskInfo: Identifiable, Sendable, Hashable, Codable {
    var id: String { token }
    let token: String
    let fullToken: String
    let name: String
    let desc: String?
    let homepage: String?
    let installedVersion: String
    let latestVersion: String?
    let isOutdated: Bool
    let autoUpdates: Bool

    var displayVersion: String {
        if let latest = latestVersion, isOutdated {
            return "\(installedVersion) → \(latest)"
        }
        return installedVersion
    }
}

// MARK: - Outdated Info

struct OutdatedInfo: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let installedVersion: String
    let latestVersion: String
    let isPinned: Bool
    let itemType: BrewItemType
}

// MARK: - Install Status (for enriching catalog items)

enum InstallStatus: Sendable {
    case notInstalled
    case installed(version: String)
    case installedAsDependency(version: String)
    case outdated(installedVersion: String, latestVersion: String)
    case pinned(version: String)
}
