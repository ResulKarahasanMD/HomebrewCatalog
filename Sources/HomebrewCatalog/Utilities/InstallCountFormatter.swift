import Foundation

enum InstallCountFormatter {
  private static let grouped: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.maximumFractionDigits = 0
    return formatter
  }()

  private static let abbreviated: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 1
    formatter.minimumFractionDigits = 0
    return formatter
  }()

  static func grouped(_ count: Int) -> String {
    grouped.string(from: NSNumber(value: count)) ?? "\(count)"
  }

  static func abbreviated(_ count: Int) -> String {
    switch count {
    case 1_000_000...:
      formatScaled(Double(count) / 1_000_000, suffix: "M")
    case 1_000...:
      formatScaled(Double(count) / 1_000, suffix: "k")
    default:
      abbreviated.string(from: NSNumber(value: count)) ?? "\(count)"
    }
  }

  private static func formatScaled(_ value: Double, suffix: String) -> String {
    let text = abbreviated.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    return text + suffix
  }
}
