import Foundation
import SwiftData

enum BrewItemType: String, Codable, CaseIterable, Sendable {
    case formula = "Formula"
    case cask = "Cask"

    /// Type-qualified identity, e.g. "Cask:mpv": a formula and a cask may share a bare id.
    func qualifiedID(_ id: String) -> String {
        "\(rawValue):\(id)"
    }
}

protocol BrewItem: Sendable, Identifiable {
    var id: String { get }
    var name: String { get }
    var desc: String? { get }
    var homepage: String? { get }
    var version: String? { get }
    var license: String? { get }
    var itemType: BrewItemType { get }
    var installCommand: String { get }
    var tap: String? { get }
    var deprecated: Bool { get }
    var deprecationDate: String? { get }
    var deprecationReason: String? { get }
    var disabled: Bool { get }
}

extension BrewItem {
    /// The identifier `brew` expects on the command line: the formula name or the
    /// cask token. Never use `name` for casks — that is the display name
    /// (e.g. "Google Chrome"), which brew does not recognise.
    var brewIdentifier: String { id }

    var installCommand: String {
        switch itemType {
        case .formula:
            return "brew install \(brewIdentifier)"
        case .cask:
            return "brew install --cask \(brewIdentifier)"
        }
    }
}
