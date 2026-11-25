import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class BrewStore {
    // MARK: - Catalog State (from API)
    var formulas: [BrewFormula] = []
    var casks: [BrewCask] = []
    var searchText: String = ""
    var selectedSidebarSection: SidebarSection = .discover
    var selectedCategory: Category?
    var selectedItem: (any BrewItem)?

    var catalogSortOption: CatalogSortOption = .default
    var analyticsPeriod: AnalyticsTimePeriod = .oneYear
    private(set) var formulaInstallCounts: [String: Int] = [:]
    private(set) var caskInstallCounts: [String: Int] = [:]
    var isLoadingAnalytics: Bool = false
    var analyticsError: String?
    private var loadedAnalyticsPeriod: HomebrewAPIService.AnalyticsPeriod?

    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var errorMessage: String?
    var lastUpdated: Date?

    // MARK: - Installed Feature Slice
    let installedFeature: InstalledFeatureStore

    // MARK: - System Feature Slices
    let servicesFeature: ServicesFeatureStore
    let tapsFeature: TapsFeatureStore
    /// brew doctor, and cleanup/autoremove behind their dry-run previews.
    let maintenance: MaintenanceFeatureStore

    // MARK: - MAS State
    var masApps: [MASAppInfo] = []
    var masOutdated: [MASAppInfo] = []
    var isMASAvailable: Bool = false
    var isLoadingMAS: Bool = false
    var masError: String?

    // MARK: - Environment
    var brewEnvironment: BrewEnvironmentInfo?

    // MARK: - Mutations
    /// Runs install/uninstall/upgrade/reinstall/pin/unpin, one at a time.
    let mutations: MutationCoordinator
    var isExecutingAction: Bool { mutations.isRunning }

    // MARK: - Catalog derived cache
    // Rebuilt once per catalog load instead of on every view update: mapping
    // ~16k items on each render blocked the main thread.
    private var cachedFeatured: [any BrewItem] = []
    private var cachedCategories: [Category] = []
    private(set) var categoryItemCounts: [Category: Int] = [:]
    /// Items per category, sorted by name.
    private(set) var categoryIndex: [Category: [any BrewItem]] = [:]
    /// Category per item, keyed by `InstalledFeatureStore.statusKey(for:)`.
    private var itemCategories: [String: Category] = [:]

    // MARK: - Download rankings cache
    private(set) var formulaDownloadRows: [DownloadRankRow] = []
    private(set) var caskDownloadRows: [DownloadRankRow] = []
    private(set) var combinedDownloadRows: [DownloadRankRow] = []
    private var analyticsOnlyFormulas: [String: BrewFormula] = [:]
    private var analyticsOnlyCasks: [String: BrewCask] = [:]

    private var catalogCacheMaxAge: TimeInterval {
        let days = UserDefaults.standard.object(forKey: "cacheDurationDays") as? Int ?? 1
        return TimeInterval(max(days, 1)) * 86_400
    }

    private var installedSnapshotMaxAge: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: "autoRefreshInterval")
        if minutes > 0 {
            return TimeInterval(minutes * 60)
        }
        return InstalledStateCache.defaultMaxAge
    }

    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var filteredFormulas: [BrewFormula] {
        let filtered = filterFormulas(formulas)
        return sortFormulas(filtered)
    }

    var filteredCasks: [BrewCask] {
        let filtered = filterCasks(casks)
        return sortCasks(filtered)
    }

    var hasInstallAnalytics: Bool {
        !formulaInstallCounts.isEmpty || !caskInstallCounts.isEmpty
    }

    // Plain reads: rebuilding here mutated observed state during view updates.
    var featuredItems: [any BrewItem] { cachedFeatured }

    var categories: [Category] { cachedCategories }

    func itemCount(for category: Category) -> Int {
        categoryItemCounts[category] ?? 0
    }

    func category(for item: any BrewItem) -> Category {
        itemCategories[InstalledFeatureStore.statusKey(for: item)] ?? .other
    }

    var installedFormulas: [InstalledFormulaInfo] { installedFeature.installedFormulas }
    var installedCasks: [InstalledCaskInfo] { installedFeature.installedCasks }
    var outdatedPackages: [OutdatedInfo] { installedFeature.outdatedPackages }
    var pinnedNames: [String] { installedFeature.pinnedNames }
    var leafNames: [String] { installedFeature.leafNames }
    var isLoadingInstalled: Bool { installedFeature.isLoadingInstalled }
    var hasCompletedInstalledRefresh: Bool { installedFeature.hasCompletedInstalledRefresh }
    var installedError: String? { installedFeature.installedError }
    var outdatedError: String? { installedFeature.outdatedError }
    var installStatusMap: [String: InstallStatus] { installedFeature.installStatusMap }
    var installedCount: Int { installedFeature.installedCount }
    var outdatedCount: Int { installedFeature.outdatedCount }

    // MARK: - Dependencies
    private let apiService = HomebrewAPIService.shared
    private let cache = CatalogCache.shared
    private let brewService: any BrewService

    // MARK: - Lifecycle
    init(service: any BrewService = BrewProcessService.shared) {
        self.brewService = service
        self.installedFeature = InstalledFeatureStore(service: service)
        self.mutations = MutationCoordinator(service: service, installed: installedFeature)
        self.servicesFeature = ServicesFeatureStore(service: service)
        self.tapsFeature = TapsFeatureStore(
            service: service, fetcher: GitHubService.shared, settings: UserDefaultsTapHealthSettings())
        self.maintenance = MaintenanceFeatureStore(service: service, installed: installedFeature)
        Task {
            await loadInitialData()
        }
    }

    // MARK: - Data Loading

    func loadInitialData() async {
        async let catalogLoad: Void = loadCatalogFromCacheOrNetwork()
        async let installedLoad: Void = loadInstalledPackagesInBackground()
        _ = await (catalogLoad, installedLoad)
    }

    private func loadCatalogFromCacheOrNetwork() async {
        if let snapshot = try? await cache.loadCatalogSnapshot(maxAge: catalogCacheMaxAge) {
            applyCatalog(
                formulas: snapshot.formulas,
                casks: snapshot.casks,
                lastUpdated: snapshot.metadata.lastUpdated
            )
            loadingProgress = 1.0
            await loadAnalyticsFromCacheOrNetwork()
            return
        }

        await refreshCatalog()
    }

    private func loadInstalledPackagesInBackground() async {
        if let snapshot = try? await InstalledStateCache.shared.loadSnapshot(maxAge: .infinity) {
            installedFeature.hydrate(from: snapshot)
        }

        let hasFreshSnapshot: Bool
        if let snapshot = try? await InstalledStateCache.shared.loadSnapshot(
            maxAge: installedSnapshotMaxAge
        ) {
            hasFreshSnapshot = snapshot.fetchSucceeded
        } else {
            hasFreshSnapshot = false
        }
        if !hasFreshSnapshot {
            await loadInstalledPackages()
        }
    }

    func refreshCatalog() async {
        isLoading = true
        loadingProgress = 0
        errorMessage = nil

        do {
            // Reuse ETags only while the stored catalog matches the current schema;
            // otherwise a 304 would leave nothing valid to load.
            let previous = try? await cache.loadMetadata()
            let reuseETags = previous?.appVersion == CatalogCache.schemaVersion
            async let catalogTask = apiService.fetchCatalog(
                formulaETag: reuseETags ? previous?.formulaETag : nil,
                caskETag: reuseETags ? previous?.caskETag : nil
            )
            async let analyticsTask = apiService.fetchAnalyticsBundle(period: analyticsPeriod.apiPeriod)
            var catalog = try await catalogTask

            self.loadingProgress = 0.5

            // A 304 list is unchanged: keep the copy in memory or on disk rather than
            // replacing it with nothing (BUG-01). If neither is available, refetch
            // both lists without ETags.
            var fetchedFormulae: [BrewFormula]
            var fetchedCasks: [BrewCask]
            do {
                if let formulae = catalog.formulae {
                    fetchedFormulae = formulae
                } else {
                    fetchedFormulae = try await unchangedFormulas()
                }
                if let casks = catalog.casks {
                    fetchedCasks = casks
                } else {
                    fetchedCasks = try await unchangedCasks()
                }
            } catch {
                catalog = try await apiService.fetchCatalog()
                fetchedFormulae = catalog.formulae ?? []
                fetchedCasks = catalog.casks ?? []
            }

            let metadata = CatalogMetadata(
                lastUpdated: catalog.timestamp,
                formulaCount: fetchedFormulae.count,
                caskCount: fetchedCasks.count,
                appVersion: CatalogCache.schemaVersion,
                formulaETag: catalog.formulaETag,
                caskETag: catalog.caskETag
            )
            if catalog.formulae != nil {
                try await cache.saveFormulas(fetchedFormulae)
            }
            if catalog.casks != nil {
                try await cache.saveCasks(fetchedCasks)
            }
            try await cache.saveMetadata(metadata)

            applyCatalog(
                formulas: fetchedFormulae,
                casks: fetchedCasks,
                lastUpdated: catalog.timestamp
            )

            self.loadingProgress = 0.7

            if let bundle = try? await analyticsTask {
                try? await cache.saveAnalytics(bundle)
                applyAnalytics(bundle)
            } else {
                await loadAnalyticsFromCacheOrNetwork()
            }

            loadingProgress = 1.0
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func unchangedFormulas() async throws -> [BrewFormula] {
        formulas.isEmpty ? try await cache.loadFormulas() : formulas
    }

    private func unchangedCasks() async throws -> [BrewCask] {
        casks.isEmpty ? try await cache.loadCasks() : casks
    }

    private func applyCatalog(formulas: [BrewFormula], casks: [BrewCask], lastUpdated: Date?) {
        self.formulas = formulas
        self.casks = casks
        self.lastUpdated = lastUpdated
        rebuildCategoryIndex()
        rebuildCatalogDerivedCache()
        rebuildDownloadRankings()
    }

    /// Maps every item to its category once per catalog load; filters and category
    /// views read this index instead of re-running CategoryMapper on each render.
    private func rebuildCategoryIndex() {
        var index: [Category: [any BrewItem]] = [:]
        var lookup: [String: Category] = [:]
        for item in (formulas as [any BrewItem]) + (casks as [any BrewItem]) {
            let category = CategoryMapper.shared.mapItem(item)
            lookup[InstalledFeatureStore.statusKey(for: item)] = category
            index[category, default: []].append(item)
        }
        for category in index.keys {
            index[category]?.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
        categoryIndex = index
        itemCategories = lookup
        categoryItemCounts = index.mapValues(\.count)
        cachedCategories = Array(index.keys).sorted { $0.rawValue < $1.rawValue }
    }

    /// Featured depends on install analytics, so it is also rebuilt when those arrive.
    private func rebuildCatalogDerivedCache() {
        cachedFeatured = buildFeaturedItems()
    }

    private func buildFeaturedItems() -> [any BrewItem] {
        if hasInstallAnalytics {
            let topFormulas: [any BrewItem] = formulas
                .filter { !$0.deprecated && !$0.disabled }
                .sorted { installCount(for: $0) > installCount(for: $1) }
                .prefix(10)
                .map { $0 }
            let topCasks: [any BrewItem] = casks
                .filter { !$0.deprecated && !$0.disabled }
                .sorted { installCount(for: $0) > installCount(for: $1) }
                .prefix(10)
                .map { $0 }
            return interleaveFeatured(topFormulas, topCasks).prefix(20).map { $0 }
        }

        let dayBucket = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let eligible = (formulas as [any BrewItem] + casks as [any BrewItem])
            .filter { !$0.deprecated && !$0.disabled }
        return eligible
            .sorted { lhs, rhs in
                let lhsScore = stableFeaturedScore(for: lhs, dayBucket: dayBucket)
                let rhsScore = stableFeaturedScore(for: rhs, dayBucket: dayBucket)
                if lhsScore != rhsScore { return lhsScore < rhsScore }
                return lhs.name < rhs.name
            }
            .prefix(20)
            .map { $0 }
    }

    private func interleaveFeatured(_ formulas: [any BrewItem], _ casks: [any BrewItem]) -> [any BrewItem] {
        var result: [any BrewItem] = []
        let count = max(formulas.count, casks.count)
        result.reserveCapacity(count * 2)
        for index in 0..<count {
            if index < formulas.count { result.append(formulas[index]) }
            if index < casks.count { result.append(casks[index]) }
        }
        return result
    }

    private func stableFeaturedScore(for item: any BrewItem, dayBucket: Int) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(item.id)
        hasher.combine(dayBucket)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    func updateAutoRefreshSchedule() {
        autoRefreshTask?.cancel()
        let minutes = UserDefaults.standard.integer(forKey: "autoRefreshInterval")
        guard minutes > 0 else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(minutes * 60))
                guard let self, !Task.isCancelled else { break }
                await self.refreshCatalog()
                await self.loadInstalledPackages()
            }
        }
    }

    // MARK: - Installed Packages

    func loadInstalledPackages() async {
        await installedFeature.refresh()
    }

    func loadInstalledPackagesIfNeeded() async {
        guard !hasCompletedInstalledRefresh || installedCount == 0 else { return }
        await loadInstalledPackages()
    }

    func installStatus(for item: any BrewItem) -> InstallStatus {
        installedFeature.installStatus(for: item)
    }

    func isInstalled(_ item: any BrewItem) -> Bool {
        switch installStatus(for: item) {
        case .notInstalled: return false
        default: return true
        }
    }

    // MARK: - MAS (Mac App Store)

    func loadMASApps() async {
        isLoadingMAS = true
        let masService = MASService.shared
        self.isMASAvailable = await masService.isAvailable()

        guard isMASAvailable else {
            isLoadingMAS = false
            return
        }

        // Load the two lists independently so a failing `mas outdated` doesn't wipe
        // the installed list that already loaded.
        var problems: [String] = []
        do {
            self.masApps = try await masService.listInstalled()
        } catch {
            self.masApps = []
            problems.append("Installed: \(error.localizedDescription)")
        }
        do {
            self.masOutdated = try await masService.listOutdated()
        } catch {
            self.masOutdated = []
            problems.append("Outdated: \(error.localizedDescription)")
        }
        masError = problems.isEmpty ? nil : problems.joined(separator: "\n")
        isLoadingMAS = false
    }

    // MARK: - Environment

    func loadBrewEnvironment() async {
        do {
            self.brewEnvironment = try await brewService.brewInfo()
        } catch {
            self.brewEnvironment = nil
        }
    }

    func refreshSystemHealth() async {
        async let environment: Void = loadBrewEnvironment()
        async let installed: Void = loadInstalledPackages()
        _ = await (environment, installed)
    }

    // MARK: - Reverse Dependencies

    func reverseDependencies(for name: String, installedOnly: Bool = false) async -> [String] {
        do {
            return try await brewService.reverseDependencies(
                name: name, installed: installedOnly)
        } catch {
            return []
        }
    }

    // MARK: - Analytics

    func installCount(for item: any BrewItem) -> Int {
        switch item.itemType {
        case .formula:
            formulaInstallCounts[item.id] ?? 0
        case .cask:
            caskInstallCounts[item.id] ?? 0
        }
    }

    func installCountLabel(for item: any BrewItem) -> String? {
        let count = installCount(for: item)
        guard count > 0 else { return nil }
        let formatted = InstallCountFormatter.abbreviated(count)
        return "\(formatted) \(analyticsPeriod.installCountLabel)"
    }

    func setCatalogSortOption(_ option: CatalogSortOption) {
        catalogSortOption = option
        if option == .mostDownloaded {
            Task { await loadAnalyticsIfNeeded() }
        }
    }

    func setAnalyticsPeriod(_ period: AnalyticsTimePeriod) {
        guard analyticsPeriod != period else { return }
        analyticsPeriod = period
        Task { await loadAnalytics(period: period.apiPeriod, force: true) }
    }

    private func applyAnalytics(_ bundle: AnalyticsBundle) {
        formulaInstallCounts = InstallAnalyticsRankBuilder.formulaCounts(from: bundle.formula)
        caskInstallCounts = InstallAnalyticsRankBuilder.caskCounts(from: bundle.cask)
        loadedAnalyticsPeriod = bundle.period
        analyticsError = nil
        rebuildCatalogDerivedCache()
        rebuildDownloadRankings()
    }

    // MARK: - Download Rankings

    func downloadRankRows(filter: DownloadRankFilter) -> [DownloadRankRow] {
        let base: [DownloadRankRow]
        switch filter {
        case .all:
            base = combinedDownloadRows
        case .formulae:
            base = formulaDownloadRows
        case .casks:
            base = caskDownloadRows
        }
        guard !searchText.isEmpty else { return base }
        let query = searchText.lowercased()
        return base.filter { $0.name.lowercased().contains(query) }
    }

    private func rebuildDownloadRankings() {
        let formulaEntries = DownloadRankBuilder.buildFormulaEntries(
            formulas: formulas,
            installCounts: formulaInstallCounts
        )
        let caskEntries = DownloadRankBuilder.buildCaskEntries(
            casks: casks,
            installCounts: caskInstallCounts
        )

        formulaDownloadRows = DownloadRankBuilder.rankedRows(from: formulaEntries)
        caskDownloadRows = DownloadRankBuilder.rankedRows(from: caskEntries)
        combinedDownloadRows = DownloadRankBuilder.combinedRankedRows(
            formulaRows: formulaDownloadRows,
            caskRows: caskDownloadRows
        )

        var stubsFormulas: [String: BrewFormula] = [:]
        var stubsCasks: [String: BrewCask] = [:]
        for row in formulaDownloadRows where !row.isCatalogItem {
            stubsFormulas[row.packageID] = BrewFormula(analyticsStubName: row.name)
        }
        for row in caskDownloadRows where !row.isCatalogItem {
            stubsCasks[row.packageID] = BrewCask(analyticsStubToken: row.packageID)
        }
        analyticsOnlyFormulas = stubsFormulas
        analyticsOnlyCasks = stubsCasks
    }

    private func loadAnalyticsFromCacheOrNetwork() async {
        let period = analyticsPeriod.apiPeriod
        if let cached = try? await cache.loadAnalytics(period: period, maxAge: catalogCacheMaxAge) {
            applyAnalytics(cached)
            return
        }
        await loadAnalytics(period: period, force: false)
    }

    func loadAnalyticsIfNeeded() async {
        let period = analyticsPeriod.apiPeriod
        if loadedAnalyticsPeriod == period, hasInstallAnalytics { return }
        await loadAnalytics(period: period, force: false)
    }

    private func loadAnalytics(period: HomebrewAPIService.AnalyticsPeriod, force: Bool) async {
        if !force,
           loadedAnalyticsPeriod == period,
           hasInstallAnalytics
        {
            return
        }

        if let cached = try? await cache.loadAnalytics(period: period, maxAge: catalogCacheMaxAge),
           !force
        {
            applyAnalytics(cached)
            return
        }

        isLoadingAnalytics = true
        analyticsError = nil
        defer { isLoadingAnalytics = false }

        do {
            let bundle = try await apiService.fetchAnalyticsBundle(period: period)
            try? await cache.saveAnalytics(bundle)
            applyAnalytics(bundle)
        } catch {
            analyticsError = error.localizedDescription
            if !hasInstallAnalytics {
                rebuildCatalogDerivedCache()
                rebuildDownloadRankings()
            }
        }
    }

    func categoryItems(for category: Category) -> [any BrewItem] {
        let indexed = categoryIndex[category] ?? []
        let matchingFormulas: [any BrewItem] = filterFormulas(
            indexed.compactMap { $0 as? BrewFormula }
        )
        let matchingCasks: [any BrewItem] = filterCasks(
            indexed.compactMap { $0 as? BrewCask }
        )
        let combined = matchingFormulas + matchingCasks
        return sortCatalogItems(combined, defaultSortByName: true)
    }

    private func filterFormulas(_ base: [BrewFormula]) -> [BrewFormula] {
        let categoryFiltered = selectedCategory.map { cat in
            base.filter { category(for: $0) == cat }
        } ?? base

        if searchText.isEmpty { return categoryFiltered }
        let lowercased = searchText.lowercased()
        return categoryFiltered.filter {
            $0.name.lowercased().contains(lowercased)
                || ($0.desc?.lowercased().contains(lowercased) ?? false)
        }
    }

    private func filterCasks(_ base: [BrewCask]) -> [BrewCask] {
        let categoryFiltered = selectedCategory.map { cat in
            base.filter { category(for: $0) == cat }
        } ?? base

        if searchText.isEmpty { return categoryFiltered }
        let lowercased = searchText.lowercased()
        return categoryFiltered.filter {
            $0.name.lowercased().contains(lowercased)
                || $0.token.lowercased().contains(lowercased)
                || ($0.desc?.lowercased().contains(lowercased) ?? false)
        }
    }

    private func sortFormulas(_ items: [BrewFormula]) -> [BrewFormula] {
        guard catalogSortOption == .mostDownloaded else { return items }
        return items.sorted { lhs, rhs in
            let left = formulaInstallCounts[lhs.name] ?? 0
            let right = formulaInstallCounts[rhs.name] ?? 0
            if left != right { return left > right }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func sortCasks(_ items: [BrewCask]) -> [BrewCask] {
        guard catalogSortOption == .mostDownloaded else { return items }
        return items.sorted { lhs, rhs in
            let left = caskInstallCounts[lhs.token] ?? 0
            let right = caskInstallCounts[rhs.token] ?? 0
            if left != right { return left > right }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func sortCatalogItems(_ items: [any BrewItem], defaultSortByName: Bool) -> [any BrewItem] {
        if catalogSortOption == .mostDownloaded {
            return items.sorted { lhs, rhs in
                let left = installCount(for: lhs)
                let right = installCount(for: rhs)
                if left != right { return left > right }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        if defaultSortByName {
            return items.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        return items
    }

    // MARK: - Search & Filter

    func search(_ query: String) {
        searchText = query
    }

    func selectCategory(_ category: Category?) {
        selectedCategory = category
    }

    func selectItem(_ item: (any BrewItem)?) {
        selectedItem = item
        if let item = item {
            PersistenceController.shared.recordHistory(
                id: item.id,
                name: item.name,
                itemType: item.itemType
            )
        }
    }

    // MARK: - Item Details

    /// Accepts a bare id (formula first, as before) or a type-qualified id from
    /// `BrewItemType.qualifiedID(_:)`, which picks the right item when a formula
    /// and a cask share an id.
    func itemByID(_ id: String) -> (any BrewItem)? {
        for type in BrewItemType.allCases {
            let prefix = type.qualifiedID("")
            guard id.hasPrefix(prefix) else { continue }
            return item(ofType: type, id: String(id.dropFirst(prefix.count)))
        }
        if let formula = formulas.first(where: { $0.id == id }) {
            return formula
        }
        if let cask = casks.first(where: { $0.id == id }) {
            return cask
        }
        return analyticsOnlyFormulas[id] ?? analyticsOnlyCasks[id]
    }

    private func item(ofType type: BrewItemType, id: String) -> (any BrewItem)? {
        switch type {
        case .formula:
            return formulas.first(where: { $0.id == id }) ?? analyticsOnlyFormulas[id]
        case .cask:
            return casks.first(where: { $0.id == id }) ?? analyticsOnlyCasks[id]
        }
    }

    func relatedItems(for item: any BrewItem) -> [any BrewItem] {
        var related: [any BrewItem] = []

        if let formula = item as? BrewFormula {
            if let deps = formula.dependencies {
                for dep in deps {
                    if let match = self.formulas.first(where: { $0.name == dep }) {
                        related.append(match)
                    }
                }
            }
            if let conflicts = formula.conflictsWith {
                for conflict in conflicts {
                    if let match = self.formulas.first(where: { $0.name == conflict }) {
                        related.append(match)
                    }
                }
            }
        } else if let cask = item as? BrewCask {
            if let deps = cask.dependsOn?.formula {
                for dep in deps {
                    if let match = self.formulas.first(where: { $0.name == dep }) {
                        related.append(match)
                    }
                }
            }
            if let conflicts = cask.conflictsWith?.cask {
                for conflict in conflicts {
                    if let match = self.casks.first(where: { $0.token == conflict }) {
                        related.append(match)
                    }
                }
            }
        }

        return related.sorted { $0.name < $1.name }
    }
}
