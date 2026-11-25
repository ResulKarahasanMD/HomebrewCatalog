import Foundation
import Observation

/// `brew services`: the list, and start/stop/restart. These finish in seconds, so they
/// report through a short notice instead of an output sheet.
@Observable
@MainActor
final class ServicesFeatureStore {
    struct Notice: Equatable {
        let message: String
        let isError: Bool
    }

    enum Action: Sendable {
        case start, stop, restart

        var verb: String {
            switch self {
            case .start: "start"
            case .stop: "stop"
            case .restart: "restart"
            }
        }

        var pastTense: String {
            switch self {
            case .start: "Started"
            case .stop: "Stopped"
            case .restart: "Restarted"
            }
        }
    }

    private(set) var services: [BrewServiceInfo] = []
    private(set) var isLoading = false
    private(set) var error: String?
    /// Services whose command is running.
    private(set) var busyServices: Set<String> = []
    /// Outcome of the last action.
    private(set) var notice: Notice?

    private let service: any BrewService
    private let redactor = OutputRedactor()
    private var hasLoaded = false

    init(service: any BrewService) {
        self.service = service
    }

    func refreshIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        error = nil
        do {
            services = try await service.listServices()
            hasLoaded = true
        } catch {
            services = []
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func start(_ name: String) async { await perform(.start, on: name) }
    func stop(_ name: String) async { await perform(.stop, on: name) }
    func restart(_ name: String) async { await perform(.restart, on: name) }

    func dismissNotice() {
        notice = nil
    }

    private func perform(_ action: Action, on name: String) async {
        busyServices.insert(name)
        defer { busyServices.remove(name) }

        do {
            let result: ProcessResult
            switch action {
            case .start: result = try await service.startService(name: name)
            case .stop: result = try await service.stopService(name: name)
            case .restart: result = try await service.restartService(name: name)
            }
            if result.exitCode == 0 {
                notice = Notice(message: "\(action.pastTense) \(name)", isError: false)
            } else {
                let detail = redactor.redact(result.stderr.isEmpty ? result.stdout : result.stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                notice = Notice(message: "Could not \(action.verb) \(name): \(detail)", isError: true)
            }
        } catch {
            notice = Notice(
                message: "Could not \(action.verb) \(name): \(redactor.redact(error.localizedDescription))",
                isError: true)
        }
        // The command may have changed the status even when it failed.
        await refresh()
    }
}
