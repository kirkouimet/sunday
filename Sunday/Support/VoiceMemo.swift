import AVFoundation
import SwiftUI

/// Records and plays the cook telling a recipe in their own words.
@MainActor
final class VoiceMemo: NSObject, ObservableObject, AVAudioPlayerDelegate {
    /// Long enough for Grandma to finish the story.
    static let maxDuration: TimeInterval = 10 * 60

    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var recorded: Data?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("recipe-memo.m4a")

    func startRecording() async {
        guard await AVAudioApplication.requestRecordPermission() else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.record(forDuration: Self.maxDuration)
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let recorder = self.recorder else { return }
                    self.elapsed = recorder.currentTime
                    if !recorder.isRecording { self.stopRecording() }
                }
            }
        } catch {
            isRecording = false
        }
    }

    func stopRecording() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        recorded = try? Data(contentsOf: url)
    }

    func play(_ data: Data) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            player?.play()
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    func discardRecording() {
        recorded = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
