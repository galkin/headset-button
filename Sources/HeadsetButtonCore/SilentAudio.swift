import Foundation

/// The silent audio that backs the Now Playing slot (ADR 0001: deliberate, not a hack).
public enum SilentAudio {
    /// A mono 16-bit PCM WAV file of digital silence.
    public static func wavData(seconds: Double = 1, sampleRate: Int = 44_100) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let blockAlign = channels * bitsPerSample / 8
        let frameCount = Int(Double(sampleRate) * seconds)
        let dataSize = frameCount * blockAlign

        var data = Data()
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: Int) { withUnsafeBytes(of: UInt16(value).littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF")
        append32(36 + dataSize)
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1) // PCM
        append16(channels)
        append32(sampleRate)
        append32(sampleRate * blockAlign)
        append16(blockAlign)
        append16(bitsPerSample)
        append("data")
        append32(dataSize)
        data.append(Data(count: dataSize))
        return data
    }
}
