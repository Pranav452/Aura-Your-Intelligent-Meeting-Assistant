// MainView.swift

import SwiftUI
import CoreAudio

struct MainView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var captureManager = CaptureManager()

    var body: some View {
        VStack(alignment: .leading) {
            headerView
            
            micPickerView
            
            if calendarManager.permissionGranted {
                if !captureManager.hasMicrophoneAccess || !captureManager.hasScreenCaptureAccess {
                    audioPermissionRequestView
                }
                
                meetingListView
                
            } else {
                calendarPermissionRequestView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private var headerView: some View {
        HStack {
            Text("Today's Meetings")
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            Button("Sign Out", role: .destructive) {
                Task {
                    await authManager.signOut()
                }
            }
        }
        .padding()
    }
    
    private var calendarPermissionRequestView: some View {
        VStack {
            Spacer()
            Text("Calendar Access Required")
                .font(.title2)
            Text("Please grant calendar access to find and record meetings.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Grant Access") {
                Task {
                    await calendarManager.requestAccess()
                }
            }
            .padding(.top)
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
    }
    
    private var audioPermissionRequestView: some View {
        VStack(alignment: .leading) {
            Text("Ready to Record")
                .font(.headline)
            Text("Aura needs access to your Microphone and Screen Audio to work properly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Enable Audio Permissions") {
                Task {
                    await captureManager.requestPermissions()
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
        .padding([.horizontal, .bottom])

    }
    
    @ViewBuilder
    private var micPickerView: some View {
        if !captureManager.availableMics.isEmpty {
            HStack {
                Text("Microphone:")
                    .font(.headline)
                
                Picker("Select a microphone", selection: $captureManager.selectedMicID) {
                    ForEach(captureManager.availableMics) { mic in
                        Text(mic.name).tag(mic.id as AudioDeviceID?)
                    }
                }
                .labelsHidden()
            }
            .padding([.horizontal, .top])
        }
    }
    
    private var meetingListView: some View {
        List(calendarManager.meetings) { meeting in
            HStack {
                VStack(alignment: .leading) {
                    Text(meeting.title)
                        .font(.headline)
                    Text(meeting.startDate, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if captureManager.isRecording {
                    Button("Stop", role: .destructive) {
                        captureManager.stopCapture()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("Record") {
                        captureManager.startCapture(for: meeting)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!captureManager.hasMicrophoneAccess || !captureManager.hasScreenCaptureAccess)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AuthManager())
}
