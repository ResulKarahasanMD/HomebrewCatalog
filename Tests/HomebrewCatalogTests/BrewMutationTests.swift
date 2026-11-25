import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("BrewMutation")
struct BrewMutationTests {
    // Payloads persisted in ActionRecord.mutationPayload. Renaming a case or label
    // breaks decoding, and failed rows written by an older build lose their retry.
    static let persistedPayloads: [(json: String, op: BrewMutation.Op)] = [
        (#"{"id":"6F1C8B7E-2D4A-4F0B-9C3E-1A2B3C4D5E6F","op":{"install":{"name":"jq","isCask":false}}}"#,
         .install(name: "jq", isCask: false)),
        (#"{"id":"6F1C8B7E-2D4A-4F0B-9C3E-1A2B3C4D5E6F","op":{"uninstall":{"name":"iterm2","isCask":true}}}"#,
         .uninstall(name: "iterm2", isCask: true)),
        (#"{"id":"6F1C8B7E-2D4A-4F0B-9C3E-1A2B3C4D5E6F","op":{"upgrade":{"target":{"all":{}}}}}"#,
         .upgrade(target: .all)),
        (#"{"id":"6F1C8B7E-2D4A-4F0B-9C3E-1A2B3C4D5E6F","op":{"upgrade":{"target":{"named":{"name":"rectangle","isCask":true}}}}}"#,
         .upgrade(target: .named(name: "rectangle", isCask: true))),
        (#"{"id":"6F1C8B7E-2D4A-4F0B-9C3E-1A2B3C4D5E6F","op":{"reinstall":{"name":"jq","isCask":false}}}"#,
         .reinstall(name: "jq", isCask: false)),
        (#"{"id":"6F1C8B7E-2D4A-4F0B-9C3E-1A2B3C4D5E6F","op":{"pin":{"name":"jq"}}}"#,
         .pin(name: "jq")),
        (#"{"id":"6F1C8B7E-2D4A-4F0B-9C3E-1A2B3C4D5E6F","op":{"unpin":{"name":"jq"}}}"#,
         .unpin(name: "jq")),
    ]

    @Test("persisted payloads decode to the same operation", arguments: persistedPayloads)
    func persistedPayloadDecodes(json: String, op: BrewMutation.Op) throws {
        let mutation = try JSONDecoder().decode(BrewMutation.self, from: Data(json.utf8))
        #expect(mutation.op == op)
        #expect(mutation.id == UUID(uuidString: "6F1C8B7E-2D4A-4F0B-9C3E-1A2B3C4D5E6F"))
    }

    static let recordShapes: [(op: BrewMutation.Op, command: String, package: String, type: BrewItemType)] = [
        (.install(name: "iterm2", isCask: true), "brew install --cask iterm2", "iterm2", .cask),
        (.uninstall(name: "jq", isCask: false), "brew uninstall jq", "jq", .formula),
        (.upgrade(target: .all), "brew upgrade", "(all)", .formula),
        (.upgrade(target: .named(name: "rectangle", isCask: true)), "brew upgrade --cask rectangle", "rectangle", .cask),
        (.reinstall(name: "jq", isCask: false), "brew reinstall jq", "jq", .formula),
        (.pin(name: "jq"), "brew pin jq", "jq", .formula),
        (.unpin(name: "jq"), "brew unpin jq", "jq", .formula),
    ]

    @Test("a record made from a mutation shows its command and starts pending", arguments: recordShapes)
    func recordFromMutation(op: BrewMutation.Op, command: String, package: String, type: BrewItemType) {
        let record = ActionRecord(mutation: BrewMutation(op))
        #expect(record.displayCommand == command)
        #expect(record.packageName == package)
        #expect(record.packageType == type)
        #expect(record.status == .pending)
    }

    @Test("retrying a recorded mutation reissues the same operation under a new id",
          arguments: recordShapes.map(\.op))
    func retryReissuesSameOperation(op: BrewMutation.Op) throws {
        let original = BrewMutation(op)
        let record = ActionRecord(mutation: original)

        let retry = try #require(record.retryMutation)
        #expect(retry.op == op)
        #expect(retry.id != original.id)
    }

    // Rows written before mutationPayload existed carry only the command string.
    static let legacyRows: [(arguments: String, package: String, type: BrewItemType, op: BrewMutation.Op)] = [
        ("install --cask iterm2", "iterm2", .cask, .install(name: "iterm2", isCask: true)),
        ("uninstall jq", "jq", .formula, .uninstall(name: "jq", isCask: false)),
        ("upgrade wget", "wget", .formula, .upgrade(target: .named(name: "wget", isCask: false))),
        ("reinstall --cask rectangle", "rectangle", .cask, .reinstall(name: "rectangle", isCask: true)),
        ("pin jq", "jq", .formula, .pin(name: "jq")),
        ("unpin jq", "jq", .formula, .unpin(name: "jq")),
    ]

    @Test("a legacy row without a payload still retries its single-package action", arguments: legacyRows)
    func legacyRowRetries(arguments: String, package: String, type: BrewItemType, op: BrewMutation.Op) throws {
        let record = ActionRecord(
            command: "brew", arguments: arguments, packageName: package, packageType: type)

        let retry = try #require(record.retryMutation)
        #expect(retry.op == op)
    }

    // A payload from a newer build, or a damaged one, must not fall back to the command
    // string: for multi-package rows that would retry "brew upgrade jq, wget" as one name.
    @Test("a payload that does not decode is not retried", arguments: [
        #"{"id":"6F1C8B7E-2D4A-4F0B-9C3E-1A2B3C4D5E6F","op":{"upgrade":{"target":{"packages":{"names":["jq","wget"]}}}}}"#,
        "not json",
    ])
    func undecodablePayloadIsNotRetried(payload: String) {
        let record = ActionRecord(
            command: "brew", arguments: "upgrade jq wget", packageName: "jq, wget", packageType: .formula)
        record.mutationPayload = Data(payload.utf8)

        #expect(record.retryMutation == nil)
    }

    @Test("a legacy upgrade-all row stays non-retryable")
    func legacyUpgradeAllIsNotRetryable() {
        let record = ActionRecord(
            command: "brew", arguments: "upgrade", packageName: "(all)", packageType: .formula)
        record.isRetryable = false

        #expect(record.retryMutation == nil)
    }
}
