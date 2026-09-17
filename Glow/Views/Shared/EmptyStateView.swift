import SwiftUI

struct EmptyStateView: View {
    let state: EmptyState
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: state.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 70))
                .foregroundStyle(.secondary)
            
            Text(state.title)
                .font(.title2.weight(.semibold))
            
            Text(state.subtitle)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            Button(action: action) {
                state.buttonLabel
            }
            .font(.headline)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}

#Preview {
    EmptyStateView(state: .lights) {}
}
