import Foundation

/// Pure, testable decoder for Apple's Continuity proximity-pairing BLE advertisement,
/// which carries unencrypted AirPods/Beats battery + charging state.
///
/// This reimplements, from public reverse-engineering references, the layout of the
/// manufacturer-specific data broadcast under Apple's company id `0x004C`. No private
/// Apple APIs are used. Values are ~10% granular and only broadcast for a short window
/// (typically when the case lid is opened).
enum ContinuityParser {
    static let appleCompanyID: UInt16 = 0x004C
    static let proximityPairingType: UInt8 = 0x07

    /// Parse the raw value of `CBAdvertisementDataManufacturerDataKey`.
    ///
    /// On macOS CoreBluetooth this `Data` begins with the little-endian company id
    /// (`4C 00`); this method also tolerates data that has already had the company id
    /// stripped (as some BLE stacks provide).
    static func parse(manufacturerData: Data) -> AirPodsAdvertisement? {
        var bytes = [UInt8](manufacturerData)

        // Strip the Apple company id prefix if present (little-endian 0x004C).
        if bytes.count >= 2, bytes[0] == 0x4C, bytes[1] == 0x00 {
            bytes.removeFirst(2)
        }

        guard let payload = proximityPayload(in: bytes) else { return nil }
        return decode(payload: payload)
    }

    /// Walk the Continuity TLV segments and return the value of the first proximity
    /// pairing (0x07) segment.
    private static func proximityPayload(in bytes: [UInt8]) -> [UInt8]? {
        var i = 0
        while i + 1 < bytes.count {
            let type = bytes[i]
            let length = Int(bytes[i + 1])
            let start = i + 2
            let end = start + length
            guard end <= bytes.count else { break }
            if type == proximityPairingType {
                return Array(bytes[start..<end])
            }
            i = end
        }
        // Fallback: some inputs are the bare proximity payload (starting with the 0x01 prefix).
        if let first = bytes.first, first == 0x01 { return bytes }
        return nil
    }

    /// Decode a proximity-pairing payload.
    ///
    /// Payload layout (indices relative to the start of the 0x07 value):
    /// - [0]      prefix (0x01)
    /// - [1..2]   device model (little-endian)
    /// - [3]      status flags (bit 0x02 = pods orientation / "flip")
    /// - [4]      pods battery: high nibble & low nibble (each 0...10 => 0...100%, 0x0F = n/a)
    /// - [5]      charging flags (high nibble) + case battery (low nibble)
    /// - [6]      lid open counter
    /// - [7]      device color
    static func decode(payload: [UInt8]) -> AirPodsAdvertisement? {
        guard payload.count >= 6 else { return nil }

        let model = UInt16(payload[1]) | (UInt16(payload[2]) << 8)
        let kind = DeviceKind.fromContinuityModel(model)

        let status = payload[3]
        let podsByte = payload[4]
        let flagsCaseByte = payload[5]
        let lid = payload.count > 6 ? payload[6] : 0

        // "flip" indicates whether the high/low nibbles are left/right or right/left.
        let flip = (status & 0x02) == 0
        let highLevel = decodeNibble(podsByte >> 4)
        let lowLevel = decodeNibble(podsByte & 0x0F)
        let leftLevel = flip ? lowLevel : highLevel
        let rightLevel = flip ? highLevel : lowLevel

        // Charging flags: bit0 = right/primary bud, bit1 = left/secondary bud, bit2 = case.
        let chargeNibble = flagsCaseByte >> 4
        let caseLevel = decodeNibble(flagsCaseByte & 0x0F)
        let rightCharging = (chargeNibble & 0x01) != 0
        let leftCharging = (chargeNibble & 0x02) != 0
        let caseCharging = (chargeNibble & 0x04) != 0

        if kind.isSingleBattery {
            // Over-ear: a single level is reported; prefer whichever nibble is present.
            let level = leftLevel ?? rightLevel
            let charging = leftCharging || rightCharging
            return AirPodsAdvertisement(
                modelValue: model,
                kind: kind,
                left: BatteryComponent(percent: level, isCharging: charging),
                right: nil,
                caseComponent: nil,
                lidCounter: lid
            )
        }

        return AirPodsAdvertisement(
            modelValue: model,
            kind: kind,
            left: BatteryComponent(percent: leftLevel, isCharging: leftCharging),
            right: BatteryComponent(percent: rightLevel, isCharging: rightCharging),
            caseComponent: BatteryComponent(percent: caseLevel, isCharging: caseCharging),
            lidCounter: lid
        )
    }

    /// Decode a 4-bit battery nibble. 0...10 map to 0...100%; 0x0F (and other out-of-range
    /// values) mean the level is unavailable.
    static func decodeNibble(_ nibble: UInt8) -> Int? {
        let n = nibble & 0x0F
        if n == 0x0F { return nil }
        if n > 10 { return nil }
        return Int(n) * 10
    }
}
