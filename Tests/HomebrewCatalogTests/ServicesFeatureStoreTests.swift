import Foundation
import Testing
@testable import HomebrewCatalog

private let redis = BrewServiceInfo(
    name: "redis", status: .stopped, user: nil, file: "/opt/homebrew/opt/redis/homebrew.mxcl.redis.plist",
    exitCode: nil)

@MainActor
private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

@Suite("ServicesFeatureStore")
@MainActor
struct ServicesFeatureStoreTests {
    enum Action: String, CaseIterable, Sendable {
        case start, stop, restart
    }

    @Test("each action calls the matching brew services command and re-reads the list",
          arguments: Action.allCases)
    func actionRoutes(action: Action) async {
        let service = MockBrewService()
        await service.configureServices([redis])
        let store = ServicesFeatureStore(service: service)
        await store.refresh()
        let listsBefore = await service.listServicesCount

        switch action {
        case .start: await store.start("redis")
        case .stop: await store.stop("redis")
        case .restart: await store.restart("redis")
        }

        #expect(await service.serviceStartCalls == (action == .start ? ["redis"] : []))
        #expect(await service.serviceStopCalls == (action == .stop ? ["redis"] : []))
        #expect(await service.serviceRestartCalls == (action == .restart ? ["redis"] : []))
        #expect(await service.listServicesCount == listsBefore + 1)
    }

    @Test("a service is marked busy while its command runs")
    func serviceIsBusyDuringAction() async {
        let service = MockBrewService()
        await service.configureServices([redis])
        await service.configureMutations(hold: true)
        let store = ServicesFeatureStore(service: service)

        let action = Task { await store.start("redis") }
        #expect(await eventually { await service.heldMutationCount == 1 })
        #expect(store.busyServices == ["redis"])
        await service.releaseHeldMutation()
        await action.value

        #expect(store.busyServices.isEmpty)
    }

    @Test("a non-zero exit shows brew's error in the notice")
    func failureIsReported() async {
        let service = MockBrewService()
        await service.configureMutations(result: ProcessResult(
            stdout: "", stderr: "Error: Failure while executing; `/bin/launchctl bootstrap gui/501` exited with 5.",
            exitCode: 1, command: "brew services start redis"))
        let store = ServicesFeatureStore(service: service)

        await store.start("redis")

        #expect(store.notice?.isError == true)
        #expect(store.notice?.message.contains("exited with 5") == true)
    }

    @Test("a thrown error is reported and the service is no longer busy")
    func thrownErrorIsReported() async {
        let service = MockBrewService()
        await service.configureMutations(error: BrewProcessError.timeout)
        let store = ServicesFeatureStore(service: service)

        await store.restart("redis")

        #expect(store.notice?.isError == true)
        #expect(store.busyServices.isEmpty)
    }

    @Test("a successful action replaces an earlier error with a confirmation")
    func successClearsError() async {
        let service = MockBrewService()
        await service.configureMutations(error: BrewProcessError.timeout)
        let store = ServicesFeatureStore(service: service)
        await store.start("redis")
        await service.configureMutations(result: ProcessResult(
            stdout: "==> Successfully started `redis` (label: homebrew.mxcl.redis)", stderr: "", exitCode: 0,
            command: "brew services start redis"), error: nil)

        await store.start("redis")

        #expect(store.notice?.isError == false)
        #expect(store.notice?.message == "Started redis")
    }
}
