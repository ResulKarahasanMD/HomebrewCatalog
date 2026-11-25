import Foundation
import Observation

@Observable
@MainActor
final class InstalledFeatureStore {
    var installedFormulas: [InstalledFormulaInfo] = []
    var installedCasks: [InstalledCaskInfo] = []
    var outdatedPackages: [OutdatedInfo] = []
    var pinnedNames: [String] = []
    var leafNames: [String] = []
    var isLoadingInstalled: Bool = false
    private(set) var hasCompletedInstalledRefresh = false
    var installedError: String?
    var outdatedError: String?
    var installStatusMap: [String: InstallStatus] = [:]

    var installedCount: Int {
        installedFormulas.count + installedCasks.count
    }

    var outdatedCount: Int {
        outdatedPackages.count
    }

    private let service: any BrewService
    private let installedCache: InstalledStateCache
    private var refreshGeneration: Int = 0

    init(service: any BrewService, installedCache: InstalledStateCache = .shared) {
        self.service = service
        self.installedCache = installedCache
    }

    func hydrate(from snapshot: InstalledStateSnapshot) {
        installedFormulas = snapshot.formulas
        installedCasks = snapshot.casks
        leafNames = snapshot.leafNames
        reconcileAfterMutation()
        let hasUsableData = snapshot.fetchSucceeded && installedCount > 0
        hasCompletedInstalledRefresh = hasUsableData
        if hasUsableData {
            installedError = nil
        }
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isLoadingInstalled = true
        installedError = nil
        outdatedError = nil
        defer {
            if generation == refreshGeneration {
                isLoadingInstalled = false
            }
        }

        async let formulasTask = safe(service.listInstalledFormulas)
        async let casksTask = safe(service.listInstalledCasks)
        async let leavesTask = safe(service.listLeaves)
        async let outdatedTask = safe(service.listOutdated)

        let formulasResult = await formulasTask
        let casksResult = await casksTask
        let leavesResult = await leavesTask
        let outdatedResult = await outdatedTask

        guard generation == refreshGeneration else { return }

        if case .success(let formulas) = formulasResult {
            installedFormulas = formulas
        }
        if case .success(let casks) = casksResult {
            installedCasks = casks
        }
        if case .success(let leaves) = leavesResult {
            leafNames = leaves
        }

        let fetchSucceeded =
            formulasResult.failure == nil || casksResult.failure == nil

        reconcileAfterMutation()

        if case .success(let outdated) = outdatedResult {
            outdatedPackages = outdated
        }

        installedError = aggregateErrorMessage([
            formulasResult.failure,
            casksResult.failure,
            leavesResult.failure,
        ])
        outdatedError = outdatedResult.failure?.localizedDescription
        hasCompletedInstalledRefresh = fetchSucceeded
        if fetchSucceeded {
            await persistSnapshot(fetchSucceeded: true)
        }
    }

    /// Applies a targeted update after a single-package brew action. Returns `false` when a full refresh is needed.
    func applyIncrementalUpdate(action: String, packageName: String, isCask: Bool) async -> Bool {
        switch action {
        case "uninstall":
            removePackage(name: packageName, isCask: isCask)
            await refreshLeavesOnly()
            reconcileAfterMutation()
            await persistSnapshot(fetchSucceeded: true)
            return true

        case "install", "upgrade", "reinstall", "pin", "unpin":
            do {
                if isCask {
                    guard let info = try await service.infoInstalledCask(name: packageName) else {
                        return false
                    }
                    upsertCask(info)
                } else {
                    guard let info = try await service.infoInstalledFormula(name: packageName) else {
                        return false
                    }
                    upsertFormula(info)
                }
                await refreshLeavesOnly()
                reconcileAfterMutation()
                await persistSnapshot(fetchSucceeded: true)
                return true
            } catch {
                return false
            }

        default:
            return false
        }
    }

    func installStatus(for item: any BrewItem) -> InstallStatus {
        // Look up by type + identifier only. A name-first lookup made a cask
        // show the install state of a formula with the same display name.
        installStatusMap[Self.statusKey(for: item)] ?? .notInstalled
    }

    /// Type-qualified key so a cask and a formula sharing a name (e.g. `mpv`) never collide.
    nonisolated static func statusKey(for item: any BrewItem) -> String {
        statusKey(item.itemType, item.id)
    }

    nonisolated static func statusKey(_ type: BrewItemType, _ id: String) -> String {
        type.qualifiedID(id)
    }

    private func removePackage(name: String, isCask: Bool) {
        if isCask {
            installedCasks.removeAll { $0.token == name || $0.name == name }
        } else {
            installedFormulas.removeAll { $0.name == name }
            leafNames.removeAll { $0 == name }
        }
    }

    private func upsertFormula(_ info: InstalledFormulaInfo) {
        if let index = installedFormulas.firstIndex(where: { $0.name == info.name }) {
            installedFormulas[index] = info
        } else {
            installedFormulas.append(info)
        }
    }

    private func upsertCask(_ info: InstalledCaskInfo) {
        if let index = installedCasks.firstIndex(where: { $0.token == info.token }) {
            installedCasks[index] = info
        } else {
            installedCasks.append(info)
        }
    }

    private func refreshLeavesOnly() async {
        guard case .success(let leaves) = await safe(service.listLeaves) else { return }
        leafNames = leaves
    }

    private func reconcileAfterMutation() {
        deriveOutdatedAndPinnedFromInstalled()
        applyFormulaDecorations()
        rebuildInstallStatusMap()
    }

    private func persistSnapshot(fetchSucceeded: Bool) async {
        let snapshot = InstalledStateSnapshot(
            lastUpdated: Date(),
            formulas: installedFormulas,
            casks: installedCasks,
            leafNames: leafNames,
            fetchSucceeded: fetchSucceeded
        )
        try? await installedCache.saveSnapshot(snapshot)
    }

    private func deriveOutdatedAndPinnedFromInstalled() {
        pinnedNames = installedFormulas.filter(\.isPinned).map(\.name)

        var outdated: [OutdatedInfo] = []
        for formula in installedFormulas where formula.isOutdated {
            outdated.append(
                OutdatedInfo(
                    name: formula.name,
                    installedVersion: formula.installedVersion,
                    latestVersion: formula.latestVersion ?? "unknown",
                    isPinned: formula.isPinned,
                    itemType: .formula
                )
            )
        }
        for cask in installedCasks where cask.isOutdated {
            outdated.append(
                OutdatedInfo(
                    name: cask.token,
                    installedVersion: cask.installedVersion,
                    latestVersion: cask.latestVersion ?? "unknown",
                    isPinned: false,
                    itemType: .cask
                )
            )
        }
        outdatedPackages = outdated
    }

    private func applyFormulaDecorations() {
        let leavesSet = Set(leafNames)

        installedFormulas = installedFormulas.map { formula in
            InstalledFormulaInfo(
                name: formula.name,
                fullName: formula.fullName,
                desc: formula.desc,
                homepage: formula.homepage,
                license: formula.license,
                installedVersion: formula.installedVersion,
                latestVersion: formula.latestVersion,
                isPinned: formula.isPinned,
                isOutdated: formula.isOutdated,
                installedOnRequest: formula.installedOnRequest,
                installedAsDependency: formula.installedAsDependency,
                isLeaf: leavesSet.contains(formula.name)
            )
        }
    }

    private func rebuildInstallStatusMap() {
        var map: [String: InstallStatus] = [:]

        for formula in installedFormulas {
            let key = Self.statusKey(.formula, formula.name)
            if formula.isPinned {
                map[key] = .pinned(version: formula.installedVersion)
            } else if formula.isOutdated {
                map[key] = .outdated(
                    installedVersion: formula.installedVersion,
                    latestVersion: formula.latestVersion ?? "unknown"
                )
            } else if formula.installedAsDependency {
                map[key] = .installedAsDependency(version: formula.installedVersion)
            } else {
                map[key] = .installed(version: formula.installedVersion)
            }
        }

        for cask in installedCasks {
            let key = Self.statusKey(.cask, cask.token)
            if cask.isOutdated {
                map[key] = .outdated(
                    installedVersion: cask.installedVersion,
                    latestVersion: cask.latestVersion ?? "unknown"
                )
            } else {
                map[key] = .installed(version: cask.installedVersion)
            }
        }

        installStatusMap = map
    }

    private func safe<T>(_ operation: @Sendable @escaping () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func aggregateErrorMessage(_ errors: [Error?]) -> String? {
        let descriptions = errors.compactMap { $0?.localizedDescription }

        guard !descriptions.isEmpty else { return nil }
        let unique = Array(Set(descriptions)).sorted()
        return unique.joined(separator: "\n")
    }
}

private extension Result {
    var failure: Error? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
