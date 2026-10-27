import AVFoundation
import Foundation

/// 마이크 → 16kHz mono 16-bit WAV. 파일은 전사 직후 호출 측에서 지운다(PRD 5.3).
final class MicRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    let url: URL
    /// 버퍼마다 소리 크기(0…1). 오디오 스레드에서 불린다.
    var onLevel: ((Float) -> Void)?
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("rec-\(UUID().uuidString).wav")
    }

    /// 실제 녹음 요청 때만 권한을 묻는다(FR-03, AC-04).
    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    static var permissionLabel: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "허용됨"
        case .denied: return "거부됨"
        case .restricted: return "제한됨"
        case .notDetermined: return "아직 묻지 않음"
        @unknown default: return "알 수 없음"
        }
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw NSError(domain: "JARVIS", code: 1, userInfo: [NSLocalizedDescriptionKey: "오디오 입력 장치가 없습니다"])
        }
        converter = AVAudioConverter(from: format, to: target)
        file = try AVAudioFile(forWriting: url, settings: target.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.write(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        if let onLevel, let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += ch[i] * ch[i] }
            let rms = (sum / Float(buffer.frameLength)).squareRoot()
            // 말소리 RMS는 대략 0.01~0.3 → 로그 눈금으로 0…1에 펼친다(-50dB…0dB)
            let db = 20 * log10(max(rms, 1e-6))
            onLevel(min(max((db + 50) / 50, 0), 1))
        }
        guard let converter, let file else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 { try? file.write(from: out) }
    }

    func stop() -> URL {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil  // 닫기
        return url
    }

    func cancel() {
        _ = stop()
        try? FileManager.default.removeItem(at: url)
    }
}
