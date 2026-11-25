import SwiftUI

struct ServicesView: View {
    @Environment(BrewStore.self) private var store

    private var feature: ServicesFeatureStore { store.servicesFeature }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(feature.services.count) services")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await feature.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(feature.isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let notice = feature.notice {
                noticeBanner(notice)
            }

            Divider()

            if let error = feature.error {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "Could Not Load Services",
                    message: error
                )
            } else if feature.isLoading && feature.services.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading services...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if feature.services.isEmpty {
                EmptyStateView(
                    icon: "gearshape.2",
                    title: "No Services Found",
                    message: "Homebrew services will appear here when installed packages provide background services."
                )
            } else {
                servicesList
            }
        }
        .navigationTitle("Services")
        .task {
            await feature.refreshIfNeeded()
        }
        .refreshable {
            await feature.refresh()
        }
        .task(id: feature.notice) {
            // Confirmations fade on their own; errors stay until dismissed.
            guard feature.notice?.isError == false else { return }
            try? await Task.sleep(for: .seconds(4))
            feature.dismissNotice()
        }
    }

    private func noticeBanner(_ notice: ServicesFeatureStore.Notice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? .red : .green)
            Text(notice.message)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                feature.dismissNotice()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background((notice.isError ? Color.red : Color.green).opacity(0.1))
    }

    @ViewBuilder
    private var servicesList: some View {
        List {
            ForEach(feature.services) { service in
                let isBusy = feature.busyServices.contains(service.name)
                HStack(spacing: 12) {
                    Group {
                        if isBusy {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Circle()
                                .fill(statusColor(service.status))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.name)
                            .font(.body.weight(.medium))
                        HStack(spacing: 8) {
                            Text(service.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(statusColor(service.status))
                            if let exitCode = service.exitCode {
                                Text("Exit code \(exitCode)")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            if let user = service.user {
                                Text("User: \(user)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()

                    primaryActions(for: service)
                        .disabled(isBusy)
                }
                .padding(.vertical, 4)
                .contextMenu {
                    Button("Start", systemImage: "play.fill") {
                        Task { await feature.start(service.name) }
                    }
                    .disabled(isBusy || service.status == .started)
                    Button("Stop", systemImage: "stop.fill") {
                        Task { await feature.stop(service.name) }
                    }
                    .disabled(isBusy || service.status != .started)
                    Button("Restart", systemImage: "arrow.clockwise") {
                        Task { await feature.restart(service.name) }
                    }
                    .disabled(isBusy)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func primaryActions(for service: BrewServiceInfo) -> some View {
        HStack(spacing: 6) {
            switch service.status {
            case .started:
                Button {
                    Task { await feature.stop(service.name) }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await feature.restart(service.name) }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

            case .stopped, .unknown:
                Button {
                    Task { await feature.start(service.name) }
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            case .error:
                Button {
                    Task { await feature.restart(service.name) }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }

    private func statusColor(_ status: BrewServiceInfo.Status) -> Color {
        switch status {
        case .started: return .green
        case .stopped: return .secondary
        case .error: return .red
        case .unknown: return .yellow
        }
    }
}
