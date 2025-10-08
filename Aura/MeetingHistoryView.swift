// MeetingHistoryView.swift

import SwiftUI

struct MeetingHistoryView: View {
    @StateObject private var viewModel = MeetingHistoryViewModel()
    
    var body: some View {
        // NavigationSplitView is the top-level container
        NavigationSplitView {
            // The List is the sidebar content
            List(viewModel.meetings) { meeting in
                NavigationLink(value: meeting) {
                    VStack(alignment: .leading) {
                        Text(meeting.title).font(.headline)
                        Text(meeting.createdAt).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("History")
            .task { await viewModel.fetchMeetings() }
            .refreshable { await viewModel.fetchMeetings() }
            // **THE FIX**: The navigationDestination MUST be placed here,
            // directly on the view that contains the NavigationLinks.
            .navigationDestination(for: CompletedMeeting.self) { meeting in
                MeetingDetailView(meeting: meeting)
            }
            
        } detail: {
            // The detail view placeholder
            Text("Select a meeting to see the details.")
        }
    }
}

// MeetingDetailView is unchanged but included for completeness
struct MeetingDetailView: View {
    let meeting: CompletedMeeting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading) {
                    Text(meeting.title).font(.largeTitle).fontWeight(.bold)
                    Text(meeting.createdAt).font(.title3).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary").font(.title2).fontWeight(.semibold)
                    Text(meeting.summary ?? "No summary available.").textSelection(.enabled)
                }
                
                if let actionItems = meeting.actionItems, !actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action Items").font(.title2).fontWeight(.semibold)
                        ForEach(actionItems) { item in
                            HStack(alignment: .top) {
                                Image(systemName: "square")
                                VStack(alignment: .leading) {
                                    Text(item.task).fontWeight(.medium)
                                    if let assignee = item.assignee, !assignee.isEmpty {
                                        Text("Assignee: \(assignee)").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.bottom, 4)
                        }
                    }
                }
                
                if let transcript = meeting.transcript, !transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcript").font(.title2).fontWeight(.semibold)
                        ForEach(transcript) { utterance in
                            VStack(alignment: .leading) {
                                Text("Speaker \(utterance.speaker ?? "Unknown")")
                                    .font(.caption).bold().foregroundStyle(.secondary)
                                Text(utterance.text)
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .padding()
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
        .navigationTitle(meeting.title)
    }
}
