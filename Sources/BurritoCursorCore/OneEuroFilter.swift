import Foundation

/// One Euro Filter — Casiez, Roussel, Vogel 2012.
/// Adaptive low-pass filter: smooths slow motion heavily, lets fast motion through with low latency.
public struct OneEuroFilter {
    private let minCutoff: Double
    private let beta: Double
    private let dCutoff: Double = 1.0

    private var prevValue: Double?
    private var prevDerivative: Double = 0.0
    private var prevTimestamp: Double?

    public init(minCutoff: Double, beta: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    public mutating func filter(_ x: Double, timestampSec t: Double) -> Double {
        guard let prevT = prevTimestamp, let prevX = prevValue else {
            prevValue = x
            prevTimestamp = t
            return x
        }
        let dt = max(t - prevT, 1e-6)
        let dx = (x - prevX) / dt
        let edx = lowpass(dx, prev: prevDerivative, alpha: smoothingAlpha(cutoff: dCutoff, dt: dt))
        let cutoff = minCutoff + beta * abs(edx)
        let ex = lowpass(x, prev: prevX, alpha: smoothingAlpha(cutoff: cutoff, dt: dt))

        prevValue = ex
        prevDerivative = edx
        prevTimestamp = t
        return ex
    }

    private func smoothingAlpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    private func lowpass(_ x: Double, prev: Double, alpha: Double) -> Double {
        return alpha * x + (1.0 - alpha) * prev
    }
}
