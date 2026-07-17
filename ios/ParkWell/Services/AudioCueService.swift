import AVFoundation
import Foundation

/// Plays the segment-change cue: a short tone, a brief spoken status, or both.
///
/// Ducking, not interruption: the session uses `.duckOthers` so the driver's
/// music/podcast dips under the cue and comes right back — it is never paused.
final class AudioCueService: NSObject {
    enum CueStyle: String, CaseIterable, Identifiable {
        case spoken
        case tone
        case toneAndSpoken = "tone_and_spoken"
        case off

        var id: String { rawValue }
        var label: String {
            switch self {
            case .spoken: return "Spoken status"
            case .tone: return "Tone only"
            case .toneAndSpoken: return "Tone + spoken"
            case .off: return "Off"
            }
        }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private var activeCues = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func announce(_ verdict: Verdict, style: CueStyle) {
        guard style != .off else { return }
        activateSession()

        if style == .tone || style == .toneAndSpoken {
            playTone(for: verdict.level)
        }
        if style == .spoken || style == .toneAndSpoken {
            var text = verdict.spoken
            if verdict.isStale { text += " Data may be out of date." }
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.preUtteranceDelay = style == .toneAndSpoken ? 0.35 : 0
            activeCues += 1
            synthesizer.speak(utterance)
        } else {
            // Tone-only: release the session shortly after the tone ends.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.deactivateSessionIfIdle()
            }
        }
    }

    // MARK: - Session

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt,
                                 options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    private func deactivateSessionIfIdle() {
        guard activeCues == 0, !synthesizer.isSpeaking else { return }
        // notifyOthersOnDeactivation restores the ducked app's volume.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Tone

    /// Distinct pitches per level so the meaning lands without words:
    /// green = high, yellow = mid, red = low double-pulse.
    private func playTone(for level: StatusLevel) {
        let frequency: Double
        let pulses: Int
        switch level {
        case .green: frequency = 880; pulses = 1
        case .yellow: frequency = 660; pulses = 1
        case .red: frequency = 440; pulses = 2
        case .unknown: frequency = 550; pulses = 1
        }

        let sampleRate = 44_100.0
        let pulseDuration = 0.18
        let gapDuration = 0.08
        var samples: [Float] = []
        for pulse in 0..<pulses {
            if pulse > 0 {
                samples.append(contentsOf: [Float](repeating: 0, count: Int(sampleRate * gapDuration)))
            }
            let count = Int(sampleRate * pulseDuration)
            for i in 0..<count {
                let t = Double(i) / sampleRate
                // Short fade in/out to avoid clicks.
                let envelope = min(1, min(t, pulseDuration - t) / 0.02)
                samples.append(Float(sin(2 * .pi * frequency * t) * envelope * 0.5))
            }
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try? engine.start()
        player.scheduleBuffer(buffer) { [weak self, weak player] in
            DispatchQueue.main.async {
                if let player { self?.engine.detach(player) }
            }
        }
        player.play()
    }
}

extension AudioCueService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        activeCues = max(0, activeCues - 1)
        deactivateSessionIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        activeCues = max(0, activeCues - 1)
        deactivateSessionIfIdle()
    }
}
