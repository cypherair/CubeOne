import AVFoundation

/// A short synthesized "tick" played on every face turn — no audio
/// asset needed. Filtered noise burst with a faint tone, fast decay.
final class ClickSound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.45
        buffer = Self.makeClickBuffer(format: format)
        try? engine.start()
    }

    func play() {
        guard let buffer, engine.isRunning else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private static func makeClickBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = Float(format.sampleRate)
        let frames = Int(sampleRate * 0.035)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = buffer.floatChannelData![0]
        var lowpass: Float = 0
        for i in 0..<frames {
            let t = Float(i) / Float(frames)
            let envelope = expf(-t * 16) * (1 - t)
            let noise = Float.random(in: -1...1)
            lowpass += 0.3 * (noise - lowpass)
            let tone = sinf(2 * .pi * 1900 * Float(i) / sampleRate)
            samples[i] = (lowpass * 0.75 + tone * 0.25) * envelope * 0.55
        }
        return buffer
    }
}
