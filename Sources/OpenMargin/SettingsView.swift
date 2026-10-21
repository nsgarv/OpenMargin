import OpenMarginCore
import SwiftUI

struct SettingsView: View {
    @State private var key = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Text("Enhance sends the rough note and the transcript to xAI. The audio itself is transcribed on this Mac and is not saved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if KeyStore.environmentKey() != nil {
                    Text("XAI_API_KEY is set in the environment. It wins over a key saved here when OpenMargin is launched from that terminal.")
                        .font(.callout)
                }
                SecureField("xAI API key", text: $key)
                HStack {
                    Button("Save key") { save() }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove saved key") { remove() }
                        .disabled(KeyStore.savedKey() == nil)
                }
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Model")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.top, 8)
    }

    private func save() {
        do {
            try KeyStore.save(key)
            key = ""
            message = "Saved on this Mac."
        } catch {
            message = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try KeyStore.save("")
            message = "Removed the saved key."
        } catch {
            message = error.localizedDescription
        }
    }
}
