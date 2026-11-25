import Foundation

/// A brew command that changes installed state, captured in full so a failed run can be
/// re-issued exactly. It is persisted as JSON in `ActionRecord.mutationPayload`: renaming
/// a case or an associated-value label breaks retry for rows written by older builds.
struct BrewMutation: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let op: Op

    enum Op: Codable, Sendable, Equatable {
        case install(name: String, isCask: Bool)
        case uninstall(name: String, isCask: Bool)
        case upgrade(target: UpgradeTarget)
        case reinstall(name: String, isCask: Bool)
        case pin(name: String)
        case unpin(name: String)
    }

    enum UpgradeTarget: Codable, Sendable, Equatable {
        /// `brew upgrade` with no arguments.
        case all
        /// One package; several are upgraded as a sequence of these, so each keeps its type.
        case named(name: String, isCask: Bool)
    }

    init(_ op: Op, id: UUID = UUID()) {
        self.id = id
        self.op = op
    }
}

extension BrewMutation.Op {
    /// The brew subcommand, e.g. "install".
    var verb: String {
        switch self {
        case .install: "install"
        case .uninstall: "uninstall"
        case .upgrade: "upgrade"
        case .reinstall: "reinstall"
        case .pin: "pin"
        case .unpin: "unpin"
        }
    }

    /// The arguments after `brew`, for display; `BrewProcessService` builds the ones it runs.
    var brewArguments: [String] {
        switch self {
        case .install(let name, let isCask), .uninstall(let name, let isCask), .reinstall(let name, let isCask),
            .upgrade(.named(let name, let isCask)):
            [verb] + (isCask ? ["--cask"] : []) + [name]
        case .upgrade(.all):
            [verb]
        case .pin(let name), .unpin(let name):
            [verb, name]
        }
    }

    var packageName: String {
        switch self {
        case .install(let name, _), .uninstall(let name, _), .reinstall(let name, _),
            .upgrade(.named(let name, _)), .pin(let name), .unpin(let name):
            name
        case .upgrade(.all):
            "(all)"
        }
    }

    var packageType: BrewItemType {
        switch self {
        case .install(_, let isCask), .uninstall(_, let isCask), .reinstall(_, let isCask),
            .upgrade(.named(_, let isCask)):
            isCask ? .cask : .formula
        case .upgrade(.all), .pin, .unpin:
            .formula
        }
    }

    /// Rebuilds the operation of an `ActionRecord` written before mutations were persisted,
    /// which kept only the command string. Only single-package actions can be recovered.
    init?(legacyVerb verb: String, packageName: String, packageType: BrewItemType) {
        let isCask = packageType == .cask
        switch verb {
        case "install": self = .install(name: packageName, isCask: isCask)
        case "uninstall": self = .uninstall(name: packageName, isCask: isCask)
        case "upgrade": self = .upgrade(target: .named(name: packageName, isCask: isCask))
        case "reinstall": self = .reinstall(name: packageName, isCask: isCask)
        case "pin": self = .pin(name: packageName)
        case "unpin": self = .unpin(name: packageName)
        default: return nil
        }
    }
}
