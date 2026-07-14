import Foundation

public enum WavFileWriter {
    public static func writeMonoPCM16(samples: [Float], sampleRate: Int, to url: URL) throws {
        var data = Data()
        data.append(wavHeader(sampleRate: sampleRate, dataSize: samples.count * 2))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let value = Int16(clamped * Float(Int16.max))
            data.appendInt16LE(value)
        }

        try data.write(to: url, options: [.atomic])
        try OwnerOnlyFileSecurity.protectFile(url)
    }

    /// Combines PCM WAV checkpoints without loading the whole recording into
    /// memory. Each input must be a mono PCM16 WAV at `sampleRate`.
    public static func mergeMonoPCM16(
        files: [URL],
        sampleRate: Int,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !files.isEmpty else {
            throw WavFileWriterError.noAudioFiles
        }

        try OwnerOnlyFileSecurity.prepareDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".merge-\(UUID().uuidString).wav", isDirectory: false)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        fileManager.createFile(atPath: temporaryURL.path, contents: wavHeader(sampleRate: sampleRate, dataSize: 0))
        let output = try FileHandle(forWritingTo: temporaryURL)
        var dataSize = 0
        do {
            try output.seekToEnd()
            for file in files {
                let data = try Data(contentsOf: file)
                guard data.count >= 44,
                      String(data: data[0..<4], encoding: .ascii) == "RIFF",
                      String(data: data[8..<12], encoding: .ascii) == "WAVE",
                      String(data: data[36..<40], encoding: .ascii) == "data",
                      Self.sampleRate(in: data) == sampleRate else {
                    throw WavFileWriterError.invalidPCM16File(file)
                }
                let payload = data.dropFirst(44)
                dataSize += payload.count
                try output.write(contentsOf: payload)
            }
            try output.seek(toOffset: 0)
            try output.write(contentsOf: wavHeader(sampleRate: sampleRate, dataSize: dataSize))
            try output.synchronize()
            try output.close()
        } catch {
            try? output.close()
            throw error
        }

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: temporaryURL, to: url)
        try OwnerOnlyFileSecurity.protectFile(url, fileManager: fileManager)
    }

    private static func wavHeader(sampleRate: Int, dataSize: Int) -> Data {
        var data = Data()
        let bytesPerSample = 2
        let channels = 1
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample
        let riffSize = 36 + dataSize

        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(riffSize))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(UInt16(channels))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(16)
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(dataSize))
        return data
    }

    private static func sampleRate(in data: Data) -> Int? {
        guard data.count >= 28 else {
            return nil
        }
        return Int(data[24..<28].withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: UInt32.self).littleEndian
        })
    }
}

public enum WavFileWriterError: Error, Equatable, Sendable {
    case noAudioFiles
    case invalidPCM16File(URL)
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(contentsOf: value.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendInt16LE(_ value: Int16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
