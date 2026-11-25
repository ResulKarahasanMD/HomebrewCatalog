import Foundation
import SwiftData

/// The action-history model the app uses: the current schema version's class.
typealias ActionRecord = SchemaV1.ActionRecord

extension SchemaV1 {
    /// Stored shape of an action-history row in version 1. Frozen: a new field belongs in a
    /// new schema version. Behaviour lives in the `ActionRecord` extension below.
    @Model
    final class ActionRecord {
        @Attribute(.unique) var id: String
        var command: String
        var arguments: String
        var packageName: String
        var packageTypeRaw: String
        var statusRaw: String
        var output: String
        var errorOutput: String
        var startedAt: Date
        var completedAt: Date?
        var exitCode: Int32
        var isRetryable: Bool
        /// JSON-encoded `BrewMutation`; nil on rows written before mutations were persisted.
        var mutationPayload: Data?

        init(
            command: String,
            arguments: String,
            packageName: String,
            packageType: BrewItemType,
            status: ActionStatus = .pending
        ) {
            self.id = UUID().uuidString
            self.command = command
            self.arguments = arguments
            self.packageName = packageName
            self.packageTypeRaw = packageType.rawValue
            self.statusRaw = status.rawValue
            self.output = ""
            self.errorOutput = ""
            self.startedAt = Date()
            self.completedAt = nil
            self.exitCode = -1
            self.isRetryable = true
        }
    }
}

extension ActionRecord {
    /// Characters of each output kept in the store; a source build can print megabytes.
    static let storedOutputLimit = 64_000

    /// `text` as it may be stored: its last `storedOutputLimit` characters, since brew prints
    /// its result and errors last, behind a line saying how much was dropped.
    static func storable(_ text: String) -> String {
        let dropped = text.count - storedOutputLimit
        guard dropped > 0 else { return text }
        return "[… \(dropped) earlier characters not kept …]\n" + text.suffix(storedOutputLimit)
    }

    convenience init(mutation: BrewMutation) {
        self.init(
            command: "brew",
            arguments: mutation.op.brewArguments.joined(separator: " "),
            packageName: mutation.op.packageName,
            packageType: mutation.op.packageType
        )
        self.mutationPayload = try? JSONEncoder().encode(mutation)
    }

    /// The operation to run again, under a new id. Rows that predate `mutationPayload` fall
    /// back to parsing their single-package command string.
    var retryMutation: BrewMutation? {
        guard isRetryable else { return nil }
        if let mutationPayload {
            // A payload that does not decode (damaged, or written by a newer build) is not
            // retried: the command string cannot tell which packages, or types, it meant.
            guard let original = try? JSONDecoder().decode(BrewMutation.self, from: mutationPayload) else {
                return nil
            }
            return BrewMutation(original.op)
        }
        guard let verb = arguments.split(separator: " ").first,
            let op = BrewMutation.Op(
                legacyVerb: String(verb), packageName: packageName, packageType: packageType)
        else { return nil }
        return BrewMutation(op)
    }

    var packageType: BrewItemType {
        BrewItemType(rawValue: packageTypeRaw) ?? .formula
    }

    var status: ActionStatus {
        get { ActionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var duration: TimeInterval? {
        guard let completed = completedAt else { return nil }
        return completed.timeIntervalSince(startedAt)
    }

    var formattedDuration: String {
        guard let dur = duration else { return "—" }
        if dur < 1 { return "< 1s" }
        if dur < 60 { return "\(Int(dur))s" }
        let mins = Int(dur) / 60
        let secs = Int(dur) % 60
        return "\(mins)m \(secs)s"
    }

    var displayCommand: String {
        "brew \(arguments)"
    }
}

enum ActionStatus: String, Codable, Sendable {
    case pending
    case running
    case success
    case failed
    case cancelled
}
