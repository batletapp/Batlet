import Foundation

/// Decoded contents of an Apple Continuity "proximity pairing" (type 0x07) advertisement.
struct AirPodsAdvertisement: Equatable, Sendable {
    var modelValue: UInt16
    var kind: DeviceKind
    var left: BatteryComponent?
    var right: BatteryComponent?
    var caseComponent: BatteryComponent?
    /// Increments each time the case lid is opened; useful for de-duping bursts.
    var lidCounter: UInt8
}
