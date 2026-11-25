import Foundation

enum Category: String, CaseIterable, Sendable {
    case developerTools = "Developer Tools"
    case productivity = "Productivity"
    case multimedia = "Multimedia"
    case utilities = "Utilities"
    case entertainment = "Entertainment"
    case design = "Design & Graphics"
    case communication = "Communication"
    case finance = "Finance"
    case education = "Education"
    case science = "Science & Research"
    case networking = "Networking"
    case security = "Security"
    case system = "System & Admin"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .developerTools: return "hammer.fill"
        case .productivity: return "checkmark.seal.fill"
        case .multimedia: return "play.rectangle.fill"
        case .utilities: return "wrench.and.screwdriver.fill"
        case .entertainment: return "gamecontroller.fill"
        case .design: return "paintpalette.fill"
        case .communication: return "bubble.left.and.bubble.right.fill"
        case .finance: return "dollarsign.circle.fill"
        case .education: return "graduationcap.fill"
        case .science: return "atom"
        case .networking: return "network"
        case .security: return "lock.shield.fill"
        case .system: return "gearshape.2.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }
}
