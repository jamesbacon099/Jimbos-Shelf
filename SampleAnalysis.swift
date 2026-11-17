import Accelerate
import Foundation

struct SampleAnalysis {
    let bpm: Int?
    let key: String?

    static func read(_ url: URL, using ffmpeg: URL) -> Self {
        let process = Process()
        let output = Pipe()
        process.executableURL = ffmpeg
        process.arguments = ["-nostdin", "-v", "error", "-i", url.path, "-t", "240",
                             "-vn", "-ac", "1", "-ar", "11025", "-f", "f32le", "pipe:1"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return Self(bpm: nil, key: nil) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return Self(bpm: nil, key: nil) }
        let samples = data.withUnsafeBytes { raw in
            stride(from: 0, to: raw.count - raw.count % 4, by: 4).map {
                Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt32.self)))
            }
        }
        return estimate(samples)
    }

    static func estimate(_ samples: [Float]) -> Self {
        let size = 4096, step = 256, rate = 11025.0
        let length = vDSP_Length(12)
        guard samples.count >= size,
              let fft = vDSP_create_fftsetup(length, FFTRadix(kFFTRadix2)) else {
            return Self(bpm: nil, key: nil)
        }
        defer { vDSP_destroy_fftsetup(fft) }
        let taper = (0..<size).map { Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(size))) }
        var real = [Float](repeating: 0, count: size / 2)
        var imaginary = real
        var previous = real
        var magnitude = real
        var chroma = [Double](repeating: 0, count: 12)
        var onsets = [Double]()
        for start in stride(from: 0, through: samples.count - size, by: step) {
            for i in real.indices {
                real[i] = samples[start + i * 2] * taper[i * 2]
                imaginary[i] = samples[start + i * 2 + 1] * taper[i * 2 + 1]
            }
            real.withUnsafeMutableBufferPointer { r in
                imaginary.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    vDSP_fft_zrip(fft, &split, 1, length, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &magnitude, 1, vDSP_Length(size / 2))
                }
            }
            var flux = 0.0
            for bin in 12..<950 {
                let power = log1p(magnitude[bin])
                flux += Double(max(0, power - previous[bin])) * (bin < 70 ? 2 : 1)
                previous[bin] = power
                guard start.isMultiple(of: step * 4), bin > 18, bin < 740,
                      magnitude[bin] > 0.04, magnitude[bin] > magnitude[bin - 1],
                      magnitude[bin] > magnitude[bin + 1] else { continue }
                let a = Double(log(magnitude[bin - 1] + 0.0001))
                let b = Double(log(magnitude[bin] + 0.0001))
                let c = Double(log(magnitude[bin + 1] + 0.0001))
                let frequency = (Double(bin) + 0.5 * (a - c) / (a - 2 * b + c)) * rate / Double(size)
                let note = 69 + 12 * log2(frequency / 440)
                let pitch = Int(note.rounded())
                chroma[(pitch % 12 + 12) % 12] += Double(power) / sqrt(frequency)
                    * (1 - abs(note - Double(pitch)))
            }
            onsets.append(start == 0 ? 0 : flux)
        }
        return Self(bpm: tempo(onsets, rate: rate / Double(step)), key: musicalKey(chroma))
    }

    private static func tempo(_ onsets: [Double], rate: Double) -> Int? {
        guard onsets.count > Int(rate * 4) else { return nil }
        let mean = onsets.reduce(0, +) / Double(onsets.count)
        let pulse = onsets.map { max(0, $0 - mean) }
        let energy = pulse.reduce(0) { $0 + $1 * $1 }
        guard energy > 0.01 else { return nil }
        func correlation(_ lag: Int) -> Double {
            guard lag > 0, lag < pulse.count else { return 0 }
            return (lag..<pulse.count).reduce(0) { $0 + pulse[$1] * pulse[$1 - lag] } / energy
        }
        let lags = Int(rate * 60 / 185)...Int(ceil(rate * 60 / 65))
        func score(_ lag: Int) -> Double {
            let bpm = rate * 60 / Double(lag)
            return (correlation(lag) + 0.32 * correlation(lag * 2))
                * (1 - 0.12 * abs(log2(bpm / 115)))
        }
        let scores = lags.map(score)
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[best] > 0.12 else { return nil }
        var lag = Double(lags.lowerBound + best)
        if best > 0, best + 1 < scores.count {
            let a = scores[best - 1], b = scores[best], c = scores[best + 1]
            if a - 2 * b + c < 0 { lag += 0.5 * (a - c) / (a - 2 * b + c) }
        }
        return Int((rate * 60 / lag).rounded())
    }

    private static func musicalKey(_ chroma: [Double]) -> String? {
        let major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        let notes = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        func centered(_ values: [Double]) -> [Double] {
            let mean = values.reduce(0, +) / Double(values.count)
            return values.map { $0 - mean }
        }
        let signal = centered(chroma)
        let energy = signal.reduce(0) { $0 + $1 * $1 }
        guard energy > 0.01 else { return nil }
        var best = (score: 0.35, label: String?.none)
        for (profile, name) in [(major, "major"), (minor, "minor")] {
            let pattern = centered(profile)
            let norm = sqrt(energy * pattern.reduce(0) { $0 + $1 * $1 })
            for root in 0..<12 {
                let score = (0..<12).reduce(0.0) { $0 + signal[($1 + root) % 12] * pattern[$1] } / norm
                if score > best.score { best = (score, "\(notes[root]) \(name)") }
            }
        }
        return best.label
    }
}
