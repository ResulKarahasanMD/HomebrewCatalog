import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("InstalledFeatureStore")
struct InstalledFeatureStoreTests {
    @Test("refresh populates all listing sources")
    @MainActor
    func refreshPopulatesAllSources() async {
        let service = MockBrewService()
        await service.configureInstalledListings(
            formulas: [
                InstalledFormulaInfo(
                    name: "ripgrep",
                    fullName: "homebrew/core/ripgrep",
                    desc: "Search tool",
                    homepage: nil,
                    license: nil,
                    installedVersion: "13.0.0",
                    latestVersion: "14.1.1",
                    isPinned: true,
                    isOutdated: true,
                    installedOnRequest: true,
                    installedAsDependency: false
                ),
                InstalledFormulaInfo(
                    name: "oniguruma",
                    fullName: "homebrew/core/oniguruma",
                    desc: "Regex library",
                    homepage: nil,
                    license: nil,
                    installedVersion: "6.9.9",
                    latestVersion: "6.9.9",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: false,
                    installedAsDependency: true
                ),
            ],
            casks: [
                InstalledCaskInfo(
                    token: "iterm2",
                    fullToken: "homebrew/cask/iterm2",
                    name: "iTerm2",
                    desc: nil,
                    homepage: nil,
                    installedVersion: "3.5.0",
                    latestVersion: "3.5.0",
                    isOutdated: false,
                    autoUpdates: false
                )
            ],
            outdated: [
                OutdatedInfo(
                    name: "ripgrep",
                    installedVersion: "13.0.0",
                    latestVersion: "14.1.1",
                    isPinned: true,
                    itemType: .formula
                )
            ],
            leaves: ["ripgrep"]
        )

        let store = InstalledFeatureStore(service: service, installedCache: .isolated())
        await store.refresh()

        #expect(store.installedFormulas.count == 2)
        #expect(store.installedCasks.count == 1)
        #expect(store.outdatedPackages.count == 1)
        #expect(store.pinnedNames == ["ripgrep"])
        #expect(store.leafNames == ["ripgrep"])
        #expect(store.installedError == nil)
        #expect(store.installedCount == 3)
        #expect(store.outdatedCount == 1)

        let ripgrep = store.installedFormulas.first { $0.name == "ripgrep" }
        #expect(ripgrep?.isPinned == true)
        #expect(ripgrep?.isOutdated == true)

        let ripgrepLeaf = store.installedFormulas.first { $0.name == "ripgrep" }
        #expect(ripgrepLeaf?.isLeaf == true)

        switch store.installStatusMap[InstalledFeatureStore.statusKey(.formula, "oniguruma")] {
        case .installedAsDependency(let version):
            #expect(version == "6.9.9")
        default:
            Issue.record("Expected installedAsDependency for oniguruma")
        }

        #expect(await service.listInstalledFormulasCount == 1)
        #expect(await service.listInstalledCasksCount == 1)
        #expect(await service.listOutdatedCount == 1)
        #expect(await service.listPinnedCount == 0)
        #expect(await service.listLeavesCount == 1)
    }

    @Test("refresh keeps successful sources when one source fails")
    @MainActor
    func refreshKeepsPartialDataOnSingleSourceFailure() async {
        let service = MockBrewService()
        await service.configureInstalledListings(
            formulas: [
                InstalledFormulaInfo(
                    name: "jq",
                    fullName: "homebrew/core/jq",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "1.7.1",
                    latestVersion: "1.7.1",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: true,
                    installedAsDependency: false
                )
            ]
        )
        await service.configureListingErrors(leaves: BrewProcessError.parseError("leaves failed"))

        let store = InstalledFeatureStore(service: service, installedCache: .isolated())
        await store.refresh()

        #expect(store.installedFormulas.count == 1)
        #expect(store.outdatedPackages.isEmpty)
        #expect(store.installStatusMap[InstalledFeatureStore.statusKey(.formula, "jq")] != nil)
        #expect(store.installedError != nil)
    }

    @Test("refresh handles empty listings")
    @MainActor
    func refreshWithNoInstalledPackages() async {
        let service = MockBrewService()
        let store = InstalledFeatureStore(service: service, installedCache: .isolated())

        await store.refresh()

        #expect(store.installedFormulas.isEmpty)
        #expect(store.installedCasks.isEmpty)
        #expect(store.outdatedPackages.isEmpty)
        #expect(store.pinnedNames.isEmpty)
        #expect(store.leafNames.isEmpty)
        #expect(store.installStatusMap.isEmpty)
        #expect(store.installedError == nil)
    }

    @Test("installStatus maps installed, dependency, pinned, outdated and notInstalled")
    @MainActor
    func installStatusMapCoverage() async {
        let service = MockBrewService()
        await service.configureInstalledListings(
            formulas: [
                InstalledFormulaInfo(
                    name: "installed-formula",
                    fullName: "homebrew/core/installed-formula",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "1.0.0",
                    latestVersion: "1.0.0",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: true,
                    installedAsDependency: false
                ),
                InstalledFormulaInfo(
                    name: "dependency-formula",
                    fullName: "homebrew/core/dependency-formula",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "2.0.0",
                    latestVersion: "2.0.0",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: false,
                    installedAsDependency: true
                ),
                InstalledFormulaInfo(
                    name: "pinned-formula",
                    fullName: "homebrew/core/pinned-formula",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "3.0.0",
                    latestVersion: "3.0.0",
                    isPinned: true,
                    isOutdated: false,
                    installedOnRequest: true,
                    installedAsDependency: false
                ),
                InstalledFormulaInfo(
                    name: "outdated-formula",
                    fullName: "homebrew/core/outdated-formula",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "4.0.0",
                    latestVersion: "4.1.0",
                    isPinned: false,
                    isOutdated: true,
                    installedOnRequest: true,
                    installedAsDependency: false
                ),
            ]
        )

        let store = InstalledFeatureStore(service: service, installedCache: .isolated())
        await store.refresh()

        struct BrewItemStub: BrewItem {
            let id: String
            let name: String
            let desc: String?
            let homepage: String?
            let version: String?
            let license: String?
            let itemType: BrewItemType
            let tap: String?
            let deprecated: Bool
            let deprecationDate: String?
            let deprecationReason: String?
            let disabled: Bool
        }

        let installed = BrewItemStub(id: "installed-formula", name: "installed-formula", desc: nil, homepage: nil, version: nil, license: nil, itemType: .formula, tap: nil, deprecated: false, deprecationDate: nil, deprecationReason: nil, disabled: false)
        let dependency = BrewItemStub(id: "dependency-formula", name: "dependency-formula", desc: nil, homepage: nil, version: nil, license: nil, itemType: .formula, tap: nil, deprecated: false, deprecationDate: nil, deprecationReason: nil, disabled: false)
        let pinned = BrewItemStub(id: "pinned-formula", name: "pinned-formula", desc: nil, homepage: nil, version: nil, license: nil, itemType: .formula, tap: nil, deprecated: false, deprecationDate: nil, deprecationReason: nil, disabled: false)
        let outdated = BrewItemStub(id: "outdated-formula", name: "outdated-formula", desc: nil, homepage: nil, version: nil, license: nil, itemType: .formula, tap: nil, deprecated: false, deprecationDate: nil, deprecationReason: nil, disabled: false)
        let missing = BrewItemStub(id: "missing-formula", name: "missing-formula", desc: nil, homepage: nil, version: nil, license: nil, itemType: .formula, tap: nil, deprecated: false, deprecationDate: nil, deprecationReason: nil, disabled: false)

        switch store.installStatus(for: installed) {
        case .installed(let v): #expect(v == "1.0.0")
        default: Issue.record("Expected installed")
        }
        switch store.installStatus(for: dependency) {
        case .installedAsDependency(let v): #expect(v == "2.0.0")
        default: Issue.record("Expected installedAsDependency")
        }
        switch store.installStatus(for: pinned) {
        case .pinned(let v): #expect(v == "3.0.0")
        default: Issue.record("Expected pinned")
        }
        switch store.installStatus(for: outdated) {
        case .outdated(let installedVersion, let latestVersion):
            #expect(installedVersion == "4.0.0")
            #expect(latestVersion == "4.1.0")
        default:
            Issue.record("Expected outdated")
        }
        switch store.installStatus(for: missing) {
        case .notInstalled: #expect(true)
        default: Issue.record("Expected notInstalled")
        }
    }

    @Test("isLoadingInstalled toggles true while refresh runs and false after")
    @MainActor
    func isLoadingLifecycle() async {
        let service = MockBrewService()
        await service.configureListingDelay(nanoseconds: 150_000_000)
        await service.configureInstalledListings(
            formulas: [
                InstalledFormulaInfo(
                    name: "jq",
                    fullName: "homebrew/core/jq",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "1.7.1",
                    latestVersion: "1.7.1",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: true,
                    installedAsDependency: false
                )
            ]
        )

        let store = InstalledFeatureStore(service: service, installedCache: .isolated())
        #expect(store.isLoadingInstalled == false)

        let refreshTask = Task { await store.refresh() }
        await Task.yield()
        #expect(store.isLoadingInstalled == true)
        await refreshTask.value

        #expect(store.isLoadingInstalled == false)
        #expect(store.installedFormulas.count == 1)
    }

    @Test("overlapping refresh calls clear loading when both complete")
    @MainActor
    func overlappingRefreshClearsLoading() async {
        let service = MockBrewService()
        await service.configureListingDelay(nanoseconds: 100_000_000)
        await service.configureInstalledListings(
            formulas: [
                InstalledFormulaInfo(
                    name: "jq",
                    fullName: "homebrew/core/jq",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "1.7.1",
                    latestVersion: "1.7.1",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: true,
                    installedAsDependency: false
                )
            ]
        )

        let store = InstalledFeatureStore(service: service, installedCache: .isolated())
        async let first = store.refresh()
        async let second = store.refresh()
        await first
        await second

        #expect(store.isLoadingInstalled == false)
        #expect(store.hasCompletedInstalledRefresh == true)
    }

    @Test("refresh runs listing calls concurrently with mock delay")
    @MainActor
    func refreshUsesConcurrentListingCalls() async {
        let service = MockBrewService()
        await service.configureListingDelay(nanoseconds: 200_000_000)
        await service.configureInstalledListings(
            formulas: [
                InstalledFormulaInfo(
                    name: "jq",
                    fullName: "homebrew/core/jq",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "1.7.1",
                    latestVersion: "1.7.1",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: true,
                    installedAsDependency: false
                )
            ]
        )

        let store = InstalledFeatureStore(service: service, installedCache: .isolated())
        let start = ContinuousClock.now
        await store.refresh()
        let elapsed = start.duration(to: .now)

        #expect(await service.maxConcurrentListingCalls >= 2)
        #expect(elapsed < .seconds(1))
    }

    @Test("incremental uninstall removes package without full refresh")
    @MainActor
    func incrementalUninstallRemovesPackage() async {
        let service = MockBrewService()
        await service.configureInstalledListings(
            formulas: [
                InstalledFormulaInfo(
                    name: "jq",
                    fullName: "homebrew/core/jq",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "1.7.1",
                    latestVersion: "1.7.1",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: true,
                    installedAsDependency: false
                ),
                InstalledFormulaInfo(
                    name: "ripgrep",
                    fullName: "homebrew/core/ripgrep",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "14.0.0",
                    latestVersion: "14.0.0",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: true,
                    installedAsDependency: false
                ),
            ],
            leaves: ["jq", "ripgrep"]
        )

        let store = InstalledFeatureStore(service: service, installedCache: .isolated())
        await store.refresh()
        let formulasBefore = await service.listInstalledFormulasCount

        let patched = await store.applyIncrementalUpdate(
            action: "uninstall",
            packageName: "jq",
            isCask: false
        )

        #expect(patched == true)
        #expect(store.installedFormulas.count == 1)
        #expect(store.installedFormulas.first?.name == "ripgrep")
        #expect(await service.listInstalledFormulasCount == formulasBefore)
        #expect(store.installStatusMap[InstalledFeatureStore.statusKey(.formula, "jq")] == nil)
    }

    @Test("incremental install uses infoInstalledFormula")
    @MainActor
    func incrementalInstallFetchesSinglePackage() async {
        let service = MockBrewService()
        let newFormula = InstalledFormulaInfo(
            name: "wget",
            fullName: "homebrew/core/wget",
            desc: nil,
            homepage: nil,
            license: nil,
            installedVersion: "1.25.0",
            latestVersion: "1.25.0",
            isPinned: false,
            isOutdated: false,
            installedOnRequest: true,
            installedAsDependency: false
        )
        await service.configureInstalledListings(formulas: [newFormula], leaves: ["wget"])

        let store = InstalledFeatureStore(service: service, installedCache: .isolated())
        store.installedFormulas = []

        let patched = await store.applyIncrementalUpdate(
            action: "install",
            packageName: "wget",
            isCask: false
        )

        #expect(patched == true)
        #expect(store.installedFormulas.count == 1)
        #expect(store.installedFormulas.first?.name == "wget")
        #expect(await service.infoInstalledFormulaCount == 1)
        #expect(await service.listInstalledFormulasCount == 0)
    }

    @Test("hydrate restores snapshot without calling brew")
    @MainActor
    func hydrateFromSnapshot() async {
        let service = MockBrewService()
        let store = InstalledFeatureStore(service: service, installedCache: .isolated())

        store.hydrate(
            from: InstalledStateSnapshot(
                lastUpdated: Date(),
                formulas: [
                    InstalledFormulaInfo(
                        name: "jq",
                        fullName: "homebrew/core/jq",
                        desc: nil,
                        homepage: nil,
                        license: nil,
                        installedVersion: "1.7.1",
                        latestVersion: "1.7.1",
                        isPinned: false,
                        isOutdated: false,
                        installedOnRequest: true,
                        installedAsDependency: false,
                        isLeaf: true
                    )
                ],
                casks: [],
                leafNames: ["jq"],
                fetchSucceeded: true
            )
        )

        #expect(store.hasCompletedInstalledRefresh == true)
        #expect(store.installedFormulas.count == 1)
        #expect(await service.listInstalledFormulasCount == 0)
    }

    @Test("hydrate from empty failed snapshot does not block future refresh")
    @MainActor
    func hydrateEmptySnapshotDoesNotMarkComplete() async {
        let service = MockBrewService()
        let store = InstalledFeatureStore(service: service, installedCache: .isolated())

        store.hydrate(
            from: InstalledStateSnapshot(
                lastUpdated: Date(),
                formulas: [],
                casks: [],
                leafNames: [],
                fetchSucceeded: false
            )
        )

        #expect(store.hasCompletedInstalledRefresh == false)
        #expect(store.installedCount == 0)
    }

    @Test("failed refresh does not persist poisoned cache")
    @MainActor
    func failedRefreshSkipsPersist() async throws {
        let service = MockBrewService()
        await service.configureListingErrors(
            formulas: BrewProcessError.brewNotFound,
            casks: BrewProcessError.brewNotFound
        )

        let cache = InstalledStateCache.isolated()
        let store = InstalledFeatureStore(service: service, installedCache: cache)
        await store.refresh()

        #expect(store.hasCompletedInstalledRefresh == false)
        #expect(store.installedCount == 0)

        let loaded = try await cache.loadSnapshot(maxAge: .infinity)
        #expect(loaded == nil)
    }

    @Test("refresh calls brew outdated listing")
    @MainActor
    func refreshFetchesOutdatedFromBrew() async {
        let service = MockBrewService()
        await service.configureInstalledListings(
            formulas: [
                InstalledFormulaInfo(
                    name: "wget",
                    fullName: "homebrew/core/wget",
                    desc: nil,
                    homepage: nil,
                    license: nil,
                    installedVersion: "1.25.0",
                    latestVersion: "1.25.0",
                    isPinned: false,
                    isOutdated: false,
                    installedOnRequest: true,
                    installedAsDependency: false
                )
            ],
            outdated: [
                OutdatedInfo(
                    name: "wget",
                    installedVersion: "1.25.0",
                    latestVersion: "1.26.0",
                    isPinned: false,
                    itemType: .formula
                )
            ]
        )

        let store = InstalledFeatureStore(service: service, installedCache: .isolated())
        await store.refresh()

        #expect(await service.listOutdatedCount == 1)
        #expect(store.outdatedPackages.count == 1)
        #expect(store.outdatedPackages.first?.name == "wget")
    }
}
