import Foundation
import Speech

/// Turns a recorded recipe into text, on the device, so Grandma's voice
/// becomes something you can read, search and edit.
enum Transcriber {
    static func transcribe(_ audio: Data) async -> String? {
        guard await authorize() else { return nil }
        // Private, always: if this phone can't transcribe on the device, skip
        // it rather than send a family's voices to a server.
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else { return nil }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transcribe-\(UUID().uuidString).m4a")
        do { try audio.write(to: url) } catch { return nil }
        defer { try? FileManager.default.removeItem(at: url) }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true

        return await withCheckedContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    finished = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        }
    }
}
