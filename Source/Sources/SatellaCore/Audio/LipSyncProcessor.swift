import Foundation

/// Stateful, thread-safe audio signal processor converting raw PCM frames into a smooth,
/// noise-gated `[0, 1]` mouth-open value with DC/sub-bass rejection and perceptual compression.
public final class LipSyncProcessor: @unchecked Sendable {
    public var noiseFloorRMS: Double = 0.010
    public var gainScale: Double = 1.6

    private var hpfPrevIn: [Double] = []
    private var hpfPrevOut: [Double] = []
    private var hpfSeeded: [Bool] = []
    private var hpfLastSampleRate: Double = 0.0
    private var hpfAlpha: Double = 0.99

    private var isGateOpen: Bool = false
    private var smoothedEnvelope: Double = 0.0
    private var lastRawRMS: Double = 0.0

    public init(noiseFloorRMS: Double = 0.010, gainScale: Double = 1.6) {
        self.noiseFloorRMS = noiseFloorRMS
        self.gainScale = gainScale
    }

    public func configure(noiseFloor: Double, gain: Double) {
        noiseFloorRMS = max(0.001, min(0.25, noiseFloor))
        gainScale = max(0.2, min(6.0, gain))
    }

    public func reset() {
        hpfPrevIn.removeAll(keepingCapacity: true)
        hpfPrevOut.removeAll(keepingCapacity: true)
        hpfSeeded.removeAll(keepingCapacity: true)
        isGateOpen = false
        smoothedEnvelope = 0.0
        lastRawRMS = 0.0
    }

    public func calibrateNoiseFloor() -> Double {
        let updated = max(0.004, min(0.15, lastRawRMS * 1.45 + 0.002))
        noiseFloorRMS = updated
        return updated
    }

    /// Processes decoded floating-point channel buffers (`channels[ch][frame]`),
    /// returning smoothed `[0, 1]` mouth open and post-HPF RMS level.
    public func processChannels(
        _ channels: [[Double]],
        sampleRate: Double,
        dt rawDt: Double
    ) -> (mouthOpen: Double, rms: Double) {
        let chCount = channels.count
        guard chCount > 0 else { return (smoothedEnvelope, lastRawRMS) }
        let frameCount = channels.map(\.count).min() ?? 0
        guard frameCount > 0 else { return (smoothedEnvelope, lastRawRMS) }

        let sr = max(8000.0, sampleRate)
        if abs(sr - hpfLastSampleRate) > 1.0 || hpfPrevIn.count != chCount {
            // ~75 Hz 1-pole high-pass filter removes USB DC bias and low-frequency desk/fan rumble
            let rc = 1.0 / (2.0 * Double.pi * 75.0)
            let dtSample = 1.0 / sr
            hpfAlpha = rc / (rc + dtSample)
            hpfLastSampleRate = sr
            if hpfPrevIn.count != chCount {
                hpfPrevIn = [Double](repeating: 0.0, count: chCount)
                hpfPrevOut = [Double](repeating: 0.0, count: chCount)
                hpfSeeded = [Bool](repeating: false, count: chCount)
            }
        }

        // Take max channel RMS so stereo interfaces where mic sits on Ch1 (or Ch0 only) stay at full sensitivity
        var maxChannelRMS = 0.0
        let alphaHPF = hpfAlpha
        for c in 0..<chCount {
            let buf = channels[c]
            if !hpfSeeded[c] {
                // Seed previous input with the opening sample so USB mic DC offset never triggers a startup pop
                hpfPrevIn[c] = buf[0]
                hpfPrevOut[c] = 0.0
                hpfSeeded[c] = true
            }
            var prevX = hpfPrevIn[c]
            var prevY = hpfPrevOut[c]
            var sumSq = 0.0
            for i in 0..<frameCount {
                let x = buf[i]
                let y = alphaHPF * (prevY + x - prevX)
                prevX = x
                prevY = y
                sumSq += y * y
            }
            hpfPrevIn[c] = prevX
            hpfPrevOut[c] = prevY
            let rms = sqrt(sumSq / Double(frameCount))
            if rms > maxChannelRMS { maxChannelRMS = rms }
        }

        let enterGate = noiseFloorRMS * 1.15 + 0.0015
        let exitGate = noiseFloorRMS * 0.90
        if isGateOpen {
            if maxChannelRMS < exitGate { isGateOpen = false }
        } else {
            if maxChannelRMS > enterGate { isGateOpen = true }
        }

        let targetOpen: Double
        if isGateOpen {
            let excess = max(0.0, maxChannelRMS - noiseFloorRMS * 0.85)
            let drive = min(1.0, excess * gainScale * 9.0)
            targetOpen = drive < 0.025 ? 0.0 : pow(drive, 0.68)
        } else {
            targetOpen = 0.0
        }

        let dt = max(0.002, min(0.15, rawDt > 0 ? rawDt : Double(frameCount) / sr))
        let tau = targetOpen > smoothedEnvelope ? 0.024 : 0.085
        let smoothFactor = 1.0 - exp(-dt / tau)
        smoothedEnvelope += (targetOpen - smoothedEnvelope) * smoothFactor
        if smoothedEnvelope < 0.01 && !isGateOpen {
            smoothedEnvelope = 0.0
        }

        lastRawRMS = maxChannelRMS
        return (smoothedEnvelope, maxChannelRMS)
    }
}
