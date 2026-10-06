#if os(macOS)
import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search ports, processes or PIDs…", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { focused = true }
    }
}
#endif
