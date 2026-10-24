import Foundation
import AVFoundation

// MARK: - 后台保活：运行时生成静音 PCM 循环播放

enum CGKeepAlive {
    private static var player: AVAudioPlayer?

    static func start() {
        guard player == nil else {
            player?.play()
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            let url = silentWAVURL()
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            // 音频失败不影响主流程，忽略
        }
    }

    static func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: 生成 2 秒静音 WAV（44.1k 单声道 16bit）
    private static func silentWAVURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("cg_keepalive.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let sampleRate = 44100
        let samples = sampleRate * 2
        var data = Data()
        var header = Data()
        func u32(_ v: Int) -> Data {
            var x = UInt32(v).littleEndian
            return withUnsafeBytes(of: &x) { Data($0) }
        }
        func u16(_ v: Int) -> Data {
            var x = UInt16(v).littleEndian
            return withUnsafeBytes(of: &x) { Data($0) }
        }
        header.append("RIFF".data(using: .ascii)!)
        header.append(u32(36 + samples * 2))
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(u32(16))
        header.append(u16(1))
        header.append(u16(1))
        header.append(u32(sampleRate))
        header.append(u32(sampleRate * 2))
        header.append(u16(2))
        header.append(u16(16))
        header.append("data".data(using: .ascii)!)
        header.append(u32(samples * 2))
        data.append(header)
        data.append(Data(count: samples * 2))
        try? data.write(to: url)
        return url
    }
}
