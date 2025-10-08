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
    private var assetWriter: AVAssetWriter?
    private var micAudioInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var sessionStartTime: CMTime?
    private var lastOutputFileURL: URL?
    private let audioQueue = DispatchQueue(label: "com.aura.audioQueue")
    
    override init() {
        super.init()
        Task {
            await initialPermissionCheck()
            await findAvailableMics()
        }
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

    @MainActor
    func startCapture(for meeting: Meeting) {
        guard !isRecording, hasMicrophoneAccess, hasScreenCaptureAccess else { return }
        
        let micToUse = self.selectedMicID
        
        Task {
            do {
                self.availableContent = try await SCShareableContent.current
                
                try self.setupAudioSession(for: meeting, micID: micToUse)
                
                try self.micAudioEngine?.start()
                try self.stream?.startCapture { error in
                    if let error = error {
                        print("System capture error: \(error.localizedDescription)")
                        Task { @MainActor in self.stopCapture() }
                    }
                }

                self.isRecording = true
                self.recordingMeetingTitle = meeting.title
                print("--- CAPTURE STARTED for \(meeting.title) ---")
                
            } catch {
                print("ERROR during capture setup: \(error.localizedDescription)")
                self.stopCapture()
            }
        }
    }
    
    private func setupAudioSession(for meeting: Meeting, micID: AudioDeviceID?) throws {
        let outputURL = createFileURL(for: meeting.title)
        assetWriter = try AVAssetWriter(url: outputURL, fileType: .m4a)
        
        try setupMicInput(micID: micID)
        setupSystemAudioInput()
        
        guard let writer = assetWriter, writer.startWriting() else {
            throw NSError(domain: "Aura", code: 99, userInfo: [NSLocalizedDescriptionKey: "AssetWriter could not start writing."])
        }
        
        sessionStartTime = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 1000000)
        writer.startSession(atSourceTime: .zero)
    }

    @MainActor
    func stopCapture() {
        guard isRecording else { return }
        print("--- STOPPING CAPTURE ---")
        
        isRecording = false
        recordingMeetingTitle = nil
        
        micAudioEngine?.stop(); micAudioEngine = nil
        stream?.stopCapture { _ in }
        stream = nil
        
        micAudioInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        
        Task(priority: .userInitiated) {
            await self.assetWriter?.finishWriting()
            guard self.assetWriter?.status == .completed else {
                print("File saving failed: \(self.assetWriter?.error?.localizedDescription ?? "no error")")
                self.assetWriter = nil
                return
            }
            print("File saved successfully locally.")
            await self.uploadRecording()
            self.assetWriter = nil
        }
    }
    
    @MainActor
    private func uploadRecording() async {
        guard let fileURL = lastOutputFileURL else { return }
        print("Starting upload for \(fileURL.lastPathComponent)")
        do {
            let session = try await supabase.auth.session
            let fileData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            print("Uploading to Supabase Storage...")
            _ = try await supabase.storage
                .from("recordings")
                .upload(path: "\(session.user.id)/\(fileName)", file: fileData)
            print("✅ Upload completed successfully!")
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            print("❌ Upload failed: \(error.localizedDescription)")
        }
    }
    
    private func createFileURL(for meetingTitle: String) -> URL {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        let sanitizedTitle = meetingTitle.replacingOccurrences(of: "[^a-zA-Z0-9]+", with: "_", options: .regularExpression)
        let fileName = "Aura-Recording_\(sanitizedTitle)_\(dateString).m4a"
        let url = documentsDirectory.appendingPathComponent(fileName)
        self.lastOutputFileURL = url
        return url
    }

    private func setupMicInput(micID: AudioDeviceID?) throws {
        micAudioEngine = AVAudioEngine()
        let engine = micAudioEngine!
        let inputNode = engine.inputNode
        guard var micToUseID = micID else {
            throw NSError(domain: "Aura", code: 1, userInfo: [NSLocalizedDescriptionKey: "No mic selected."])
        }
        var propertyAddress = AudioObjectPropertyAddress(mSelector: kAudioOutputUnitProperty_CurrentDevice, mScope: kAudioUnitScope_Global, mElement: 0)
        let status = AudioUnitSetProperty(inputNode.audioUnit!, propertyAddress.mSelector, propertyAddress.mScope, propertyAddress.mElement, &micToUseID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw NSError(domain: "Aura", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to set mic with status \(status)."])
        }
        let format = inputNode.outputFormat(forBus: 0)
        let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        micAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        micAudioInput?.expectsMediaDataInRealTime = true
        if let writer = assetWriter, writer.canAdd(micAudioInput!) {
            writer.add(micAudioInput!)
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] (buffer, time) in
            guard let self = self, let micInput = self.micAudioInput, micInput.isReadyForMoreMediaData else { return }
            if let sampleBuffer = self.createSampleBuffer(from: buffer, timestamp: time) {
                self.audioQueue.async { micInput.append(sampleBuffer) }
            }
        }
    }
    
    private func setupSystemAudioInput() {
        guard let display = availableContent?.displays.first else { return }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration(); config.capturesAudio = true; config.excludesCurrentProcessAudio = true
        let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        systemAudioInput?.expectsMediaDataInRealTime = true
        if let writer = assetWriter, writer.canAdd(systemAudioInput!) {
            writer.add(systemAudioInput!)
        }
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        } catch { print("Error setting up system audio stream: \(error.localizedDescription)") }
    }
    
    private func createSampleBuffer(from pcmBuffer: AVAudioPCMBuffer, timestamp: AVAudioTime) -> CMSampleBuffer? {
        var sampleBuffer: CMSampleBuffer?
        var format: CMFormatDescription?
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: pcmBuffer.format.streamDescription, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let presentationTime = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 1000000) - (sessionStartTime ?? CMTime.zero)
        let sampleCount = CMItemCount(pcmBuffer.frameLength)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(pcmBuffer.format.sampleRate)), presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)
        let status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil, formatDescription: format, sampleCount: sampleCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
        guard status == noErr, let buffer = sampleBuffer else { return nil }
        let error = CMSampleBufferSetDataBufferFromAudioBufferList(buffer, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: pcmBuffer.audioBufferList)
        guard error == noErr else { return nil }
        return buffer
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        if let input = self.systemAudioInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("System audio stream stopped with error: \(error.localizedDescription)")
        Task { @MainActor in
            if self.isRecording { self.stopCapture() }
        }
    }
}
