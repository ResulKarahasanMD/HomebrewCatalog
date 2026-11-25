import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case discover = "Discover"
    case categories = "Categories"
    case formulas = "Formulae"
    case casks = "Casks"
    case downloads = "Downloads"
    case installed = "Installed"
    case outdated = "Outdated"
    case pinned = "Pinned"
    case leaves = "Leaves"
    case favorites = "Favorites"
    case history = "History"
    case groups = "Groups"
    case actionHistory = "Action History"
    case services = "Services"
    case taps = "Taps"
    case masApps = "Mac App Store"
    case systemHealth = "System Health"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .discover: return "sparkles"
        case .categories: return "square.grid.2x2"
        case .formulas: return "terminal"
        case .casks: return "macwindow"
        case .downloads: return "chart.bar.fill"
        case .installed: return "checkmark.circle.fill"
        case .outdated: return "arrow.triangle.2.circlepath"
        case .pinned: return "pin.fill"
        case .leaves: return "leaf.fill"
        case .favorites: return "heart.fill"
        case .history: return "clock.fill"
        case .groups: return "folder.fill"
        case .actionHistory: return "list.clipboard"
        case .services: return "gearshape.2.fill"
        case .taps: return "spigot.fill"
        case .masApps: return "app.badge.fill"
        case .systemHealth: return "stethoscope"
        case .settings: return "gear"
        }
    }

    @MainActor
    func badgeCount(from store: BrewStore) -> Int? {
        switch self {
        case .outdated:
            let count = store.outdatedCount
            return count > 0 ? count : nil
        case .installed:
            let count = store.installedCount
            return count > 0 ? count : nil
        default:
            return nil
        }
    }
}
