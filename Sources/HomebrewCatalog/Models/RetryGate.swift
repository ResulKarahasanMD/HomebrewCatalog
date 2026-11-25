import Foundation

/// Holds the mutation a history "Retry" asked for until the user has seen its command and
/// confirmed it. The mutation is rebuilt from a stored `ActionRecord`, so it is checked
/// like any other outside input and nothing runs on the first click.
struct RetryGate: Equatable {
    /// The mutation waiting for confirmation.
    private(set) var pending: BrewMutation?
    /// Why the last request was refused; shown instead of the confirmation.
    private(set) var refusal: String?

    /// The command line shown to the user before confirming.
    var command: String? {
        pending.map { (["brew"] + $0.op.brewArguments).joined(separator: " ") }
    }

    /// Stages `mutation` for confirmation. Returns false, staging nothing, when there is no
    /// mutation or its package name is not one brew could have been given by this app.
    @discardableResult
    mutating func request(_ mutation: BrewMutation?) -> Bool {
        pending = nil
        refusal = nil
        guard let mutation else { return false }
        guard mutation.op.hasValidPackageName else {
            refusal = "This action cannot be retried: its stored package name is not valid."
            return false
        }
        pending = mutation
        return true
    }

    /// The staged mutation, handed over once: a second confirm has nothing to run.
    mutating func confirm() -> BrewMutation? {
        defer { pending = nil }
        return pending
    }

    mutating func cancel() {
        pending = nil
        refusal = nil
    }
}

extension BrewMutation.Op {
    /// False when the package name would be refused by `BrewArgumentValidator`.
    var hasValidPackageName: Bool {
        switch self {
        case .upgrade(.all):
            true
        case .install(let name, _), .uninstall(let name, _), .reinstall(let name, _),
            .upgrade(.named(let name, _)), .pin(let name), .unpin(let name):
            BrewArgumentValidator.isValid(name, as: .package)
        }
    }
}
