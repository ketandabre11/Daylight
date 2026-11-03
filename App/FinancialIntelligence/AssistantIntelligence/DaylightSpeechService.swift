import Foundation
import Speech
import AVFoundation

public enum VoiceAssistantState: Equatable, Sendable {
    case idle
    case listening
    case processing
    case responding
    case error(String)
    case permissionDenied
}

@MainActor
@Observable
public final class DaylightSpeechService: NSObject, SFSpeechRecognizerDelegate {
    public static let shared = DaylightSpeechService()

    public var state: VoiceAssistantState = .idle
    public var transcribedText: String = ""
    public var isAudioAvailable: Bool = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-AU"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    public override init() {
        super.init()
        speechRecognizer?.delegate = self
        checkInitialAvailability()
    }

    private func checkInitialAvailability() {
        let auth = SFSpeechRecognizer.authorizationStatus()
        switch auth {
        case .authorized:
            isAudioAvailable = speechRecognizer?.isAvailable ?? false
        case .denied, .restricted:
            isAudioAvailable = false
        case .notDetermined:
            isAudioAvailable = true
        @unknown default:
            isAudioAvailable = false
        }
    }

    public func requestPermissionAndStartListening(
        onFinalTranscription: @escaping (String) -> Void
    ) {
        let auth = SFSpeechRecognizer.authorizationStatus()
        switch auth {
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] newStatus in
                Task { @MainActor [weak self] in
                    if newStatus == .authorized {
                        self?.startListening(onFinalTranscription: onFinalTranscription)
                    } else {
                        self?.state = .permissionDenied
                    }
                }
            }
        case .authorized:
            startListening(onFinalTranscription: onFinalTranscription)
        case .denied, .restricted:
            state = .permissionDenied
        @unknown default:
            state = .error("Speech recognition is not supported on this device.")
        }
    }

    public func startListening(onFinalTranscription: @escaping (String) -> Void) {
        // Reset any existing task
        stopListening()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error("Speech recognition is currently unavailable on this device.")
            return
        }

        do {
            #if canImport(UIKit)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest else {
                state = .error("Unable to create an audio recognition request.")
                return
            }

            // Prefer on-device recognition if supported
            if speechRecognizer.supportsOnDeviceRecognition {
                recognitionRequest.requiresOnDeviceRecognition = true
            }
            recognitionRequest.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            // Check for valid hardware format
            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                state = .error("No microphone hardware input detected.")
                return
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            state = .listening
            transcribedText = ""

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.state = .processing
                        self.stopListening()
                        onFinalTranscription(result.bestTranscription.formattedString)
                    }
                }

                if let error {
                    self.stopListening()
                    // If simulator or cancelled
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 216 {
                        // Request was cancelled or no speech detected
                        self.state = .idle
                    } else {
                        self.state = .error(error.localizedDescription)
                    }
                }
            }
        } catch {
            state = .error(error.localizedDescription)
            stopListening()
        }
    }

    public func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    public func reset() {
        stopListening()
        state = .idle
        transcribedText = ""
    }
}
