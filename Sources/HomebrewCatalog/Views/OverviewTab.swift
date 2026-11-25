import SwiftUI

struct OverviewTab: View {
    let item: any BrewItem
    @State private var copiedCommand = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Install command section
            VStack(alignment: .leading, spacing: 8) {
                Text("Install Command")
                    .font(.headline)
                
                HStack {
                    Text(item.installCommand)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Button(action: copyCommand) {
                        Image(systemName: copiedCommand ? "checkmark" : "doc.on.doc")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Details section
            VStack(alignment: .leading, spacing: 12) {
                Text("Details")
                    .font(.headline)
                
                DetailRow(label: "Name", value: item.name)
                DetailRow(label: "Type", value: item.itemType.rawValue)
                DetailRow(label: "Version", value: item.version ?? "N/A")
                DetailRow(label: "License", value: item.license ?? "Unknown")
                DetailRow(label: "Homepage", value: item.homepage ?? "N/A")
                
                if let tap = item.tap {
                    DetailRow(label: "Tap", value: tap)
                }
                
                if item.deprecated, let date = item.deprecationDate {
                    DetailRow(label: "Deprecated", value: date)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.vertical)
    }
    
    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.installCommand, forType: .string)
        copiedCommand = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedCommand = false
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.system(size: 13))
                .textSelection(.enabled)
            
            Spacer()
        }
    }
}