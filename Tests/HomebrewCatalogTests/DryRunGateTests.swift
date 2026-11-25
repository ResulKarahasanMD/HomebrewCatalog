import Foundation
import Testing
@testable import HomebrewCatalog

private let cleanupDryRun = """
    Would remove: /Users/alice/Library/Caches/Homebrew/downloads/1a2b--jq--1.7.1.arm64_sequoia.bottle.tar.gz (512.3KB)
    ==> This operation would free approximately 512.3KB of disk space.
    """

private let autoremoveDryRun = "==> Would autoremove 1 unneeded formula:\nlibevent\n"

@MainActor
private func makeStore() -> (MockBrewService, MaintenanceFeatureStore) {
    let service = MockBrewService()
    let installed = InstalledFeatureStore(service: service, installedCache: .isolated())
    return (service, MaintenanceFeatureStore(service: service, installed: installed))
}

@Suite("DryRunGate")
@MainActor
struct DryRunGateTests {
    @Test("cleanup does not run without a preview")
    func cleanupNeedsPreview() async {
        let (service, store) = makeStore()

        let ran = await store.runCleanup()

        #expect(!ran)
        #expect(await service.cleanupCalls == 0)
        #expect(store.error != nil)
    }

    @Test("cleanup runs after a preview that found something")
    func cleanupRunsAfterPreview() async {
        let (service, store) = makeStore()
        await service.configureDryRuns(cleanup: cleanupDryRun)

        await store.loadCleanupPreview()
        #expect(store.canRunCleanup)
        let ran = await store.runCleanup()

        #expect(ran)
        #expect(await service.cleanupCalls == 1)
    }

    @Test("a cleanup preview with nothing to remove does not unlock cleanup")
    func emptyPreviewKeepsCleanupLocked() async {
        let (service, store) = makeStore()
        await service.configureDryRuns(cleanup: "")

        await store.loadCleanupPreview()
        let ran = await store.runCleanup()

        #expect(!store.canRunCleanup)
        #expect(!ran)
        #expect(await service.cleanupCalls == 0)
    }

    @Test("each cleanup needs a fresh preview")
    func previewIsSpentByARun() async {
        let (service, store) = makeStore()
        await service.configureDryRuns(cleanup: cleanupDryRun)
        await store.loadCleanupPreview()

        await store.runCleanup()
        let ranAgain = await store.runCleanup()

        #expect(!ranAgain)
        #expect(store.cleanupPreview == nil)
        #expect(await service.cleanupCalls == 1)
    }

    @Test("a failed dry run leaves cleanup locked and reports the error")
    func failedPreviewKeepsCleanupLocked() async {
        let (service, store) = makeStore()
        await service.configureDryRuns(error: BrewProcessError.brewNotFound)

        await store.loadCleanupPreview()
        let ran = await store.runCleanup()

        #expect(!ran)
        #expect(store.cleanupPreview == nil)
        #expect(store.error != nil)
        #expect(await service.cleanupCalls == 0)
    }

    @Test("autoremove does not run without a preview listing formulae")
    func autoremoveNeedsPreview() async {
        let (service, store) = makeStore()
        await service.configureDryRuns(autoremove: "")

        let withoutPreview = await store.runAutoremove()
        await store.loadAutoremovePreview()
        let withEmptyPreview = await store.runAutoremove()

        #expect(!withoutPreview)
        #expect(!withEmptyPreview)
        #expect(await service.autoremoveCalls == 0)
    }

    @Test("autoremove runs once per preview and re-reads installed packages")
    func autoremoveRunsOncePerPreview() async {
        let (service, store) = makeStore()
        await service.configureDryRuns(autoremove: autoremoveDryRun)
        await store.loadAutoremovePreview()
        #expect(store.autoremovePreview?.formulae == ["libevent"])
        let listingsBefore = await service.listInstalledFormulasCount

        let ran = await store.runAutoremove()
        let ranAgain = await store.runAutoremove()

        #expect(ran)
        #expect(!ranAgain)
        #expect(await service.autoremoveCalls == 1)
        #expect(await service.listInstalledFormulasCount == listingsBefore + 1)
    }
}
