import AppKit
import OpenMarginCore
import SwiftUI

struct InviteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var chosen: [String] = []
    @State private var suggestions: [(name: String, email: String)] = []
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Invite teammates")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Ink.inkSoft)
            }
            Text("They get an email from you. Notes stay on each person's Mac.")
                .font(.callout)
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Add an email", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addDraft)

            if !chosen.isEmpty {
                FlowChips(emails: chosen) { email in
                    chosen.removeAll { $0 == email }
                }
            }

            if !suggestions.isEmpty {
                Text("From Contacts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.inkSoft)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(suggestions, id: \.email) { person in
                        Button {
                            chosen = InviteList.adding(person.email, to: chosen)
                        } label: {
                            HStack(spacing: 8) {
                                Text(String(person.name.prefix(1)).uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Ink.copper, in: Circle())
                                Text(person.name)
                                    .foregroundStyle(Ink.ink)
                                Spacer()
                                Text("Add")
                                    .foregroundStyle(Ink.copper)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(chosen.contains(person.email))
                    }
                }
            }

            if !model.workspace.teammates.isEmpty {
                Text("Already invited: \(model.workspace.teammates.map(\.email).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Ink.inkSoft)
            }

            HStack {
                Button("Copy invitation") { copyInvitation() }
                    .disabled(model.workspace.account == nil)
                Spacer()
                Button("Invite") { send() }
                    .buttonStyle(.borderedProminent)
                    .tint(Ink.copper)
                    .disabled(chosen.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Ink.paper)
        .task {
            suggestions = await model.workspace.suggestions()
        }
    }

    private func addDraft() {
        chosen = InviteList.adding(draft, to: chosen)
        draft = ""
    }

    private func send() {
        addDraft()
        if let error = model.workspace.invite(chosen) {
            message = error
            return
        }
        dismiss()
    }

    private func copyInvitation() {
        guard let account = model.workspace.account else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Workspace.invitation(from: account), forType: .string)
        message = "Copied."
    }
}

private struct FlowChips: View {
    var emails: [String]
    var remove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(emails, id: \.self) { email in
                HStack(spacing: 6) {
                    Text(email)
                        .font(.callout)
                    Button {
                        remove(email)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Ink.paperDeep, in: Capsule())
            }
        }
    }
}
