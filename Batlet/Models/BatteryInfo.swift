import Foundation

/// Battery level + charging state for a single component (a bud, a case, or a whole device).
struct BatteryComponent: Equatable, Sendable {
    /// 0...100, or nil when the level is unknown/unavailable.
    var percent: Int?
    var isCharging: Bool

    init(percent: Int?, isCharging: Bool = false) {
        self.percent = percent.map { min(100, max(0, $0)) }
        self.isCharging = isCharging
    }

    var isAvailable: Bool { percent != nil }
}
