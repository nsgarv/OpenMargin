import OpenMarginCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var inviting = false
    @State private var clientID = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Coming up")
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(Ink.ink)
                    Spacer()
                    accountButtons
                    Button("New meeting") { model.newMeeting() }
                        .buttonStyle(.borderedProminent)
                        .tint(Ink.copper)
                }

                if model.workspace.needsClientID {
                    clientIDForm
                } else if let status = model.workspace.status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(Ink.inkSoft)
                }

                if let live = model.apps.live {
                    Button {
                        model.openLiveCall()
                    } label: {
                        HStack {
                            Text("\(live.name) is open")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                            Text("Take notes")
                                .foregroundStyle(Ink.copper)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.ink)
                }

                agenda
                notes
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper)
        .sheet(isPresented: $inviting) {
            InviteSheet()
                .environment(model)
        }
    }

    @ViewBuilder
    private var accountButtons: some View {
        if let account = model.workspace.account {
            Button("Invite") { inviting = true }
            Text(account.email)
                .font(.callout)
                .foregroundStyle(Ink.inkSoft)
                .lineLimit(1)
        } else {
            Button(model.workspace.signingIn ? "Waiting for Google…" : "Sign in with Google") {
                Task { await model.workspace.signIn() }
            }
            .disabled(model.workspace.signingIn)
        }
    }

    private var clientIDForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google needs a desktop client ID before OpenMargin can open the sign-in window. In Google Cloud, create an OAuth client of type Desktop, then paste it here. It stays on this Mac.")
                .font(.callout)
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Desktop client ID", text: $clientID)
                .textFieldStyle(.roundedBorder)
            Button("Save and sign in") {
                do {
                    try model.workspace.saveClientID(clientID)
                    Task { await model.workspace.signIn() }
                } catch {
                    model.workspace.status = error.localizedDescription
                }
            }
            .disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var agenda: some View {
        switch model.agenda.access {
        case .unknown:
            Text("Checking the calendar…")
                .font(.callout)
                .foregroundStyle(Ink.inkSoft)
        case .denied(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        case .granted:
            VStack(alignment: .leading, spacing: 18) {
                ForEach(dayGroups, id: \.day) { group in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(Calendar.current.component(.day, from: group.day))")
                                .font(.system(size: 28, weight: .semibold, design: .serif))
                                .foregroundStyle(Ink.ink)
                            Text(group.day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption)
                                .foregroundStyle(Ink.inkSoft)
                        }
                        .frame(width: 52, alignment: .leading)

                        Rectangle()
                            .fill(group.events.isEmpty ? Ink.rule.opacity(0.5) : Ink.copper)
                            .frame(width: 2)
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 10) {
                            if group.events.isEmpty {
                                Text("Nothing scheduled")
                                    .font(.callout)
                                    .foregroundStyle(Ink.inkSoft)
                                    .padding(.top, 8)
                            } else {
                                ForEach(group.events) { event in
                                    Button {
                                        model.openAgendaItem(event)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.title)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(Ink.ink)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Text(event.rangeLabel)
                                                .font(.callout)
                                                .foregroundStyle(Ink.inkSoft)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notes")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Ink.ink)
            if noteGroups.isEmpty {
                Text("Nothing here yet. A meeting on the calendar opens a note, or start a blank one.")
                    .font(.callout)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(noteGroups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.inkSoft)
                        ForEach(group.meetings) { meeting in
                            Button {
                                model.selectedID = meeting.id
                            } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(meeting.title.isEmpty ? "Untitled" : meeting.title)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Ink.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 12)
                                    Text(meeting.createdAt.formatted(date: .omitted, time: .shortened))
                                        .font(.callout)
                                        .foregroundStyle(Ink.inkSoft)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var dayGroups: [(day: Date, events: [AgendaItem])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var days = Set<Date>([today])
        for event in model.agenda.events {
            days.insert(calendar.startOfDay(for: event.start))
        }
        return days.sorted().map { day in
            (day, model.agenda.events.filter { calendar.isDate($0.start, inSameDayAs: day) })
        }
    }

    private var noteGroups: [(title: String, meetings: [Meeting])] {
        let calendar = Calendar.current
        var buckets: [(Date, [Meeting])] = []
        for meeting in model.meetings.prefix(30) {
            let day = calendar.startOfDay(for: meeting.createdAt)
            if let index = buckets.firstIndex(where: { calendar.isDate($0.0, inSameDayAs: day) }) {
                buckets[index].1.append(meeting)
            } else {
                buckets.append((day, [meeting]))
            }
        }
        return buckets.map { day, meetings in
            (MeetingDate.section(day), meetings)
        }
    }
}
