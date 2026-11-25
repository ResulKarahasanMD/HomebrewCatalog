import SwiftUI

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Select an Item")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose a formula or cask from the list to view details")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}