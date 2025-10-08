// CaptureManager.swift

import Foundation
import AVFoundation
import ScreenCaptureKit
import AudioToolbox
import CoreAudio
import Supabase

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

class CaptureManager: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    
    @MainActor @Published var isRecording = false
    @MainActor @Published var hasMicrophoneAccess = false
    @MainActor @Published var hasScreenCaptureAccess = false
    @MainActor @Published var availableMics: [AudioDevice] = []
    @MainActor @Published var selectedMicID: AudioDeviceID?
    @MainActor @Published var recordingMeetingTitle: String?
    
    private var micAudioEngine: AVAudioEngine?
    private var stream: SCStream?
    private var availableContent: SCShareableContent?
    
    // URLs for the two temporary raw audio files
    private var tempMicURL: URL?
    private var tempSystemURL: URL?
    private var finalOutputURL: URL?
    
    // AVAudioFile objects to write the raw audio
    private var micAudioFile: AVAudioFile?
    private var systemAudioFile: AVAudioFile?
    
    private let audioQueue = DispatchQueue(label: "com.aura.audioQueue")
    
    override init() {
        super.init()
        Task {
            await initialPermissionCheck()
            await findAvailableMics()
        }
    }
    
    @MainActor
    func startCapture(for meeting: Meeting) {
        guard !isRecording, hasMicrophoneAccess, hasScreenCaptureAccess else { return }
        let micToUse = self.selectedMicID
        Task {
            do {
                self.availableContent = try await SCShareableContent.current
                try self.setupDualStreamRecording(for: meeting, micID: micToUse)
                
                try self.micAudioEngine?.start()
                try self.stream?.startCapture { error in
                    if let error = error {
                        print("System capture error: \(error.localizedDescription)")
                        Task { @MainActor in self.stopCapture() }
                    }
                }
                self.isRecording = true
                self.recordingMeetingTitle = meeting.title
                print("--- DUAL STREAM CAPTURE STARTED for \(meeting.title) ---")
            } catch {
                print("ERROR during capture setup: \(error.localizedDescription)")
                self.stopCapture()
            }
        }
    }

    @MainActor
    func stopCapture() {
        guard isRecording else { return }
        print("--- STOPPING DUAL STREAM CAPTURE ---")
        isRecording = false
        recordingMeetingTitle = nil
        
        micAudioEngine?.stop(); micAudioEngine = nil
        stream?.stopCapture { _ in }
        stream = nil
        
        micAudioFile = nil
        systemAudioFile = nil
        
        Task(priority: .userInitiated) {
            await mergeConvertAndUpload()
        }
    }
    
    private func setupDualStreamRecording(for meeting: Meeting, micID: AudioDeviceID?) throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let baseName = "Aura-Rec-\(UUID().uuidString)"
        tempMicURL = tempDir.appendingPathComponent(baseName + "-mic.caf")
        tempSystemURL = tempDir.appendingPathComponent(baseName + "-system.caf")
        finalOutputURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(sanitize(meeting.title) + "_\(Date().formatted(.iso8601)).m4a")
        
        // --- Setup Microphone ---
        micAudioEngine = AVAudioEngine()
        let engine = micAudioEngine!
        let inputNode = engine.inputNode
        guard var micToUseID = micID, let audioUnit = inputNode.audioUnit else { throw NSError(domain: "Aura", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mic setup failed."]) }
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioOutputUnitProperty_CurrentDevice, mScope: kAudioUnitScope_Global, mElement: 0)
        let status = AudioUnitSetProperty(audioUnit, propertyAddress.mSelector, propertyAddress.mScope, propertyAddress.mElement, &micToUseID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw NSError(domain: "Aura", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to set mic with status \(status)."]) }
        
        let micFormat = inputNode.outputFormat(forBus: 0)
        micAudioFile = try AVAudioFile(forWriting: tempMicURL!, settings: micFormat.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [weak self] (buffer, time) in
            try? self?.micAudioFile?.write(from: buffer)
        }
        
        // --- Setup System Audio ---
        guard let display = availableContent?.displays.first else { throw NSError(domain: "Aura", code: 3, userInfo: [NSLocalizedDescriptionKey: "No display found."]) }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration(); config.capturesAudio = true; config.excludesCurrentProcessAudio = true
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        let systemAudioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2] as [String : Any]
        let systemAudioFormat = AVAudioFormat(settings: systemAudioSettings)!
        systemAudioFile = try AVAudioFile(forWriting: tempSystemURL!, settings: systemAudioFormat.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
    }
    
    @MainActor
    private func mergeConvertAndUpload() async {
        guard let micURL = tempMicURL, let systemURL = tempSystemURL, let finalURL = finalOutputURL else {
            print("Missing audio URLs for conversion.")
            return
        }
        
        print("Starting merge and conversion...")
        
        let composition = AVMutableComposition()
        
        do {
            let micAsset = AVURLAsset(url: micURL)
            if let micTrack = try await micAsset.loadTracks(withMediaType: .audio).first {
                let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try compositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: await micAsset.load(.duration)), of: micTrack, at: .zero)
            }
            
            let systemAsset = AVURLAsset(url: systemURL)
            if let systemTrack = try await systemAsset.loadTracks(withMediaType: .audio).first {
                let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try compositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: await systemAsset.load(.duration)), of: systemTrack, at: .zero)
            }

            guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { return }
            exportSession.outputURL = finalURL
            exportSession.outputFileType = .m4a
            
            await exportSession.export()
            
            if exportSession.status == .completed {
                print("Merge and conversion successful.")
                await uploadRecording(fileURL: finalURL)
            } else {
                print("Merge/Conversion failed: \(exportSession.error?.localizedDescription ?? "Unknown")")
            }
        } catch {
            print("Error during asset loading/composition: \(error)")
        }
        
        try? FileManager.default.removeItem(at: micURL)
        try? FileManager.default.removeItem(at: systemURL)
    }

    @MainActor
    private func uploadRecording(fileURL: URL) async {
        print("Starting upload for \(fileURL.lastPathComponent)")
        do {
            let session = try await supabase.auth.session
            let fileData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            _ = try await supabase.storage
                .from("recordings")
                .upload(path: "\(session.user.id)/\(fileName)", file: fileData)
            print("✅ Upload completed successfully!")
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            print("❌ Upload failed: \(error.localizedDescription)")
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let pcmBuffer = try? sampleBuffer.toPCMBuffer() else { return }
        try? self.systemAudioFile?.write(from: pcmBuffer)
    }
    
    private func sanitize(_ text: String) -> String {
        return text.replacingOccurrences(of: "[^a-zA-Z0-9]+", with: "_", options: .regularExpression)
    }
    
    @MainActor
    func findAvailableMics() {
        var devices: [AudioDevice] = []
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
        guard status == noErr else { return }
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceIDs)
        guard status == noErr else { return }
        for deviceID in deviceIDs {
            propertyAddress.mSelector = kAudioDevicePropertyStreams
            propertyAddress.mScope = kAudioDevicePropertyScopeInput
            status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
            if status == noErr && propertySize > 0 {
                var name: CFString = "" as CFString
                propertySize = UInt32(MemoryLayout<CFString>.size)
                propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString
                propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
                status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &name)
                if status == noErr {
                    devices.append(AudioDevice(id: deviceID, name: name as String))
                }
            }
        }
        self.availableMics = devices
        if self.selectedMicID == nil, let firstMic = devices.first {
            self.selectedMicID = firstMic.id
        }
    }

    @MainActor
    func initialPermissionCheck() async {
        self.hasMicrophoneAccess = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        do {
            _ = try await SCShareableContent.current
            self.hasScreenCaptureAccess = true
        } catch {
            self.hasScreenCaptureAccess = false
        }
    }
    
    @MainActor
    func requestPermissions() async {
        if !hasMicrophoneAccess {
            self.hasMicrophoneAccess = await AVCaptureDevice.requestAccess(for: .audio)
        }
        do {
            availableContent = try await SCShareableContent.current
            self.hasScreenCaptureAccess = true
        } catch {
            self.hasScreenCaptureAccess = false
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("System audio stream stopped with error: \(error.localizedDescription)")
        Task { @MainActor in
            if self.isRecording { self.stopCapture() }
        }
    }
}

extension CMSampleBuffer {
    func toPCMBuffer() throws -> AVAudioPCMBuffer {
        guard let blockBuffer = self.dataBuffer else {
            throw NSError(domain: "Aura", code: 8, userInfo: [NSLocalizedDescriptionKey: "Missing data buffer."])
        }

        var audioBufferList = AudioBufferList()
        var blockBufferLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        // Extract audio samples from CMBlockBuffer
        let status = CMBlockBufferGetDataPointer(blockBuffer,
                                                 atOffset: 0,
                                                 lengthAtOffsetOut: nil,
                                                 totalLengthOut: &blockBufferLength,
                                                 dataPointerOut: &dataPointer)
        guard status == noErr, let pointer = dataPointer else {
            throw NSError(domain: "Aura", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to get data pointer."])
        }

        guard let formatDescription = self.formatDescription else {
            throw NSError(domain: "Aura", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to get format description."])
        }

        let audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat,
                                               frameCapacity: AVAudioFrameCount(self.numSamples)) else {
            throw NSError(domain: "Aura", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioPCMBuffer."])
        }

        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        let dst = pcmBuffer.mutableAudioBufferList.pointee.mBuffers
        memcpy(dst.mData, pointer, Int(dst.mDataByteSize))
        return pcmBuffer
    }
}
