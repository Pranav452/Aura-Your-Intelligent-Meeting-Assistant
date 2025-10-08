import SwiftUI
import CoreAudio

struct MainView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var captureManager: CaptureManager
    
    @StateObject private var calendarManager = CalendarManager()
    
    @State private var autoRecordMeetingIDs = Set<String>()
    @State private var supervisorTask: Task<Void, Error>?

    var body: some View {
        VStack(alignment: .leading) {
            headerView
            
            if captureManager.isRecording {
                recordingStatusView
            } else {
                micPickerView
                if calendarManager.permissionGranted && (!captureManager.hasMicrophoneAccess || !captureManager.hasScreenCaptureAccess) {
                    audioPermissionRequestView
                }
            }
            
            if calendarManager.permissionGranted {
                meetingListView
            } else {
                calendarPermissionRequestView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear(perform: startSupervisor)
        .onDisappear {
            supervisorTask?.cancel()
        }
    }
    
    private func startSupervisor() {
        supervisorTask?.cancel()
        supervisorTask = Task {
            while !Task.isCancelled {
                let nextAction = findNextAction()
                
                if let (action, meeting, time) = nextAction {
                    let delay = time.timeIntervalSinceNow
                    if delay > 0 {
                        print("Supervisor: Next action '\(action)' for '\(meeting.title)' in \(Int(delay)) seconds.")
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    
                    guard !Task.isCancelled else { break }
                    
                    if action == "start" {
                        captureManager.startCapture(for: meeting)
                    } else {
                        captureManager.stopCapture()
                    }
                    
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } else {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                }
            }
        }
    }

    private func findNextAction() -> (action: String, meeting: Meeting, time: Date)? {
        let now = Date()
        
        if captureManager.isRecording, let title = captureManager.recordingMeetingTitle {
            if let runningMeeting = calendarManager.meetings.first(where: { $0.title == title }) {
                let stopTime = runningMeeting.endDate ?? runningMeeting.startDate.addingTimeInterval(3600)
                if stopTime > now {
                    return ("stop", runningMeeting, stopTime)
                }
            }
        }
        
        let upcomingMeetings = calendarManager.meetings
            .filter { autoRecordMeetingIDs.contains($0.id) && $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
        
        if let nextMeetingToStart = upcomingMeetings.first {
            return ("start", nextMeetingToStart, nextMeetingToStart.startDate)
        }
        
        return nil
    }
    
    private var headerView: some View {
        HStack {
            Text("Today's Meetings").font(.largeTitle).fontWeight(.bold)
            Spacer()
            Button("Sign Out", role: .destructive) { Task { await authManager.signOut() } }
        }.padding()
    }
    
    private var recordingStatusView: some View {
        HStack {
            Image(systemName: "record.circle.fill").foregroundColor(.red).font(.title)
            VStack(alignment: .leading) {
                Text("RECORDING").font(.headline).foregroundColor(.red)
                Text(captureManager.recordingMeetingTitle ?? "Meeting").font(.subheadline)
            }
            Spacer()
            Button("Stop", role: .destructive) {
                captureManager.stopCapture()
            }
            .buttonStyle(.borderedProminent).tint(.red)
        }
        .padding().background(Color.red.opacity(0.1)).cornerRadius(8).padding(.horizontal)
    }

    private var calendarPermissionRequestView: some View {
        VStack {
            Spacer()
            Text("Calendar Access Required").font(.title2)
            Button("Grant Access") { Task { await calendarManager.requestAccess() } }.padding(.top).buttonStyle(.borderedProminent)
            Spacer()
        }
    }
    
    private var audioPermissionRequestView: some View {
        VStack(alignment: .leading) {
            Text("Ready to Record").font(.headline)
            Text("Aura needs access to your Microphone and Screen Audio.").font(.subheadline).foregroundStyle(.secondary)
            Button("Enable Audio Permissions") { Task { await captureManager.requestPermissions() } }.padding(.top, 4)
        }.padding().background(Color(.windowBackgroundColor)).cornerRadius(8).padding([.horizontal, .bottom])
    }
    
    @ViewBuilder
    private var micPickerView: some View {
        if !captureManager.availableMics.isEmpty && !captureManager.isRecording {
            HStack {
                Text("Microphone:").font(.headline)
                Picker("Select a microphone", selection: $captureManager.selectedMicID) {
                    ForEach(captureManager.availableMics) { mic in
                        Text(mic.name).tag(mic.id as AudioDeviceID?)
                    }
                }.labelsHidden()
            }.padding([.horizontal, .top])
        }
    }
    
    private var meetingListView: some View {
        List(calendarManager.meetings) { meeting in
            HStack {
                VStack(alignment: .leading) {
                    Text(meeting.title).font(.headline)
                    Text(meeting.startDate, style: .time).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                
                if captureManager.isRecording && captureManager.recordingMeetingTitle == meeting.title {
                    HStack {
                        Image(systemName: "record.circle.fill").foregroundColor(.red)
                        Text("Recording...").foregroundColor(.red)
                    }
                } else {
                    Toggle("Auto-Record", isOn: Binding(
                        get: { autoRecordMeetingIDs.contains(meeting.id) },
                        set: { shouldAutoRecord in
                            if shouldAutoRecord {
                                autoRecordMeetingIDs.insert(meeting.id)
                            } else {
                                autoRecordMeetingIDs.remove(meeting.id)
                            }
                            supervisorTask?.cancel()
                            startSupervisor()
                        }
                    )).labelsHidden().toggleStyle(.switch)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
