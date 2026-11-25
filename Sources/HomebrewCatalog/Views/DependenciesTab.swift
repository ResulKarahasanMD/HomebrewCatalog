import SwiftUI

struct DependenciesTab: View {
    let item: any BrewItem
    @Environment(BrewStore.self) private var store

    @State private var reverseDeps: [String] = []
    @State private var installedReverseDeps: [String] = []
    @State private var isLoadingReverseDeps: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let formula = item as? BrewFormula {
                formulaDependencies(formula)
            } else if let cask = item as? BrewCask {
                caskDependencies(cask)
            }

            // Reverse dependencies
            reverseDependenciesSection

            // Related items
            relatedItemsSection
        }
        .onAppear {
            loadReverseDependencies()
        }
    }

    // MARK: - Formula Dependencies

    @ViewBuilder
    private func formulaDependencies(_ formula: BrewFormula) -> some View {
        if let deps = formula.dependencies, !deps.isEmpty {
            dependencySection(
                title: "Dependencies",
                icon: "link",
                items: deps,
                color: .blue
            )
        }

        if let buildDeps = formula.buildDependencies, !buildDeps.isEmpty {
            dependencySection(
                title: "Build Dependencies",
                icon: "hammer",
                items: buildDeps,
                color: .orange
            )
        }

        if let testDeps = formula.testDependencies, !testDeps.isEmpty {
            dependencySection(
                title: "Test Dependencies",
                icon: "checkmark.circle",
                items: testDeps,
                color: .green
            )
        }

        if let recDeps = formula.recommendedDependencies, !recDeps.isEmpty {
            dependencySection(
                title: "Recommended Dependencies",
                icon: "star",
                items: recDeps,
                color: .yellow
            )
        }

        if let optDeps = formula.optionalDependencies, !optDeps.isEmpty {
            dependencySection(
                title: "Optional Dependencies",
                icon: "questionmark.circle",
                items: optDeps,
                color: .secondary
            )
        }

        if let conflicts = formula.conflictsWith, !conflicts.isEmpty {
            dependencySection(
                title: "Conflicts With",
                icon: "exclamationmark.triangle",
                items: conflicts,
                color: .red
            )
        }
    }

    // MARK: - Cask Dependencies

    @ViewBuilder
    private func caskDependencies(_ cask: BrewCask) -> some View {
        if let deps = cask.dependsOn {
            if let formulaDeps = deps.formula, !formulaDeps.isEmpty {
                dependencySection(
                    title: "Formula Dependencies",
                    icon: "terminal",
                    items: formulaDeps,
                    color: .green
                )
            }
            if let caskDeps = deps.cask, !caskDeps.isEmpty {
                dependencySection(
                    title: "Cask Dependencies",
                    icon: "macwindow",
                    items: caskDeps,
                    color: .blue
                )
            }
        }

        if let conflicts = cask.conflictsWith {
            if let caskConflicts = conflicts.cask, !caskConflicts.isEmpty {
                dependencySection(
                    title: "Conflicts With (Casks)",
                    icon: "exclamationmark.triangle",
                    items: caskConflicts,
                    color: .red
                )
            }
            if let formulaConflicts = conflicts.formula, !formulaConflicts.isEmpty {
                dependencySection(
                    title: "Conflicts With (Formulae)",
                    icon: "exclamationmark.triangle",
                    items: formulaConflicts,
                    color: .red
                )
            }
        }
    }

    // MARK: - Reverse Dependencies

    @ViewBuilder
    private var reverseDependenciesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Reverse Dependencies", systemImage: "arrow.turn.up.left")
                    .font(.subheadline.bold())
                if isLoadingReverseDeps {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !isLoadingReverseDeps {
                if !installedReverseDeps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Used by (installed)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(installedReverseDeps, id: \.self) { dep in
                                DependencyChip(name: dep, color: .purple)
                            }
                        }
                    }
                }

                if !reverseDeps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("All packages that depend on this (\(reverseDeps.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(reverseDeps.prefix(30), id: \.self) { dep in
                                DependencyChip(name: dep, color: .secondary)
                            }
                            if reverseDeps.count > 30 {
                                Text("... and \(reverseDeps.count - 30) more")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                            }
                        }
                    }
                } else if installedReverseDeps.isEmpty {
                    Text("No packages depend on this.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Related Items

    @ViewBuilder
    private var relatedItemsSection: some View {
        let related = store.relatedItems(for: item)
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Related Packages")
                    .font(.subheadline.bold())

                ForEach(related, id: \.id) { relatedItem in
                    RelatedItemRow(item: relatedItem)
                }
            }
        }
    }

    // MARK: - Shared Section Builder

    @ViewBuilder
    private func dependencySection(
        title: String, icon: String, items: [String], color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(color)

            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { dep in
                    DependencyChip(name: dep, color: color)
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadReverseDependencies() {
        guard item.itemType == .formula else { return }
        isLoadingReverseDeps = true
        Task {
            async let allDeps = store.reverseDependencies(for: item.name)
            async let installedDeps = store.reverseDependencies(for: item.name, installedOnly: true)
            self.reverseDeps = await allDeps
            self.installedReverseDeps = await installedDeps
            isLoadingReverseDeps = false
        }
    }
}

// MARK: - Dependency Chip

struct DependencyChip: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Related Item Row

struct RelatedItemRow: View {
    let item: any BrewItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.itemType == .cask ? "macwindow" : "terminal")
                .foregroundStyle(item.itemType == .cask ? .blue : .green)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.caption.weight(.medium))
                if let desc = item.desc {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct LayoutResult {
        let positions: [CGPoint]
        let size: CGSize
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX)
        }

        return LayoutResult(
            positions: positions,
            size: CGSize(width: totalWidth, height: currentY + lineHeight)
        )
    }
}
