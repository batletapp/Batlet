import XCTest
@testable import Batlet

final class ContinuityParserTests: XCTestCase {

    /// Builds manufacturer data (company id + a single 0x07 TLV) from a proximity payload.
    private func manufacturerData(payload: [UInt8], includeCompanyID: Bool = true) -> Data {
        var bytes: [UInt8] = []
        if includeCompanyID { bytes += [0x4C, 0x00] }
        bytes += [ContinuityParser.proximityPairingType, UInt8(payload.count)]
        bytes += payload
        return Data(bytes)
    }

    // prefix, model(LE lo,hi), status, podsByte, flagsCaseByte, lid, color
    private func payload(
        modelLo: UInt8, modelHi: UInt8 = 0x20,
        status: UInt8, podsByte: UInt8, flagsCaseByte: UInt8, lid: UInt8 = 0
    ) -> [UInt8] {
        [0x01, modelLo, modelHi, status, podsByte, flagsCaseByte, lid, 0x00]
    }

    func testDecodeNibble() {
        XCTAssertEqual(ContinuityParser.decodeNibble(0x00), 0)
        XCTAssertEqual(ContinuityParser.decodeNibble(0x05), 50)
        XCTAssertEqual(ContinuityParser.decodeNibble(0x0A), 100)
        XCTAssertNil(ContinuityParser.decodeNibble(0x0F))   // unavailable
        XCTAssertNil(ContinuityParser.decodeNibble(0x0B))   // out of range
    }

    func testParsesAirPodsProWithFlip() {
        // status bit 0x02 clear => flip => left = low nibble, right = high nibble.
        // podsByte 0x85 => high 8 (80%), low 5 (50%).
        // flagsCaseByte 0x49 => charge nibble 4 (case charging), case level 9 (90%).
        let data = manufacturerData(payload: payload(
            modelLo: 0x0E, status: 0x00, podsByte: 0x85, flagsCaseByte: 0x49, lid: 0x03
        ))

        let ad = ContinuityParser.parse(manufacturerData: data)
        XCTAssertNotNil(ad)
        XCTAssertEqual(ad?.kind, .airpodsPro)
        XCTAssertEqual(ad?.left?.percent, 50)
        XCTAssertEqual(ad?.right?.percent, 80)
        XCTAssertEqual(ad?.caseComponent?.percent, 90)
        XCTAssertEqual(ad?.caseComponent?.isCharging, true)
        XCTAssertEqual(ad?.left?.isCharging, false)
        XCTAssertEqual(ad?.right?.isCharging, false)
        XCTAssertEqual(ad?.lidCounter, 0x03)
    }

    func testParsesWithoutFlip() {
        // status bit 0x02 set => no flip => left = high nibble, right = low nibble.
        let data = manufacturerData(payload: payload(
            modelLo: 0x0E, status: 0x02, podsByte: 0x85, flagsCaseByte: 0x00
        ))
        let ad = ContinuityParser.parse(manufacturerData: data)
        XCTAssertEqual(ad?.left?.percent, 80)
        XCTAssertEqual(ad?.right?.percent, 50)
    }

    func testChargingFlags() {
        // charge nibble bit0 = right, bit1 = left.
        let data = manufacturerData(payload: payload(
            modelLo: 0x0E, status: 0x00, podsByte: 0xAA, flagsCaseByte: 0x30
        ))
        let ad = ContinuityParser.parse(manufacturerData: data)
        XCTAssertEqual(ad?.left?.isCharging, true)
        XCTAssertEqual(ad?.right?.isCharging, true)
        XCTAssertEqual(ad?.caseComponent?.isCharging, false)
    }

    func testUnavailableCaseBattery() {
        // case low nibble 0x0F => unavailable.
        let data = manufacturerData(payload: payload(
            modelLo: 0x0E, status: 0x00, podsByte: 0x55, flagsCaseByte: 0x0F
        ))
        let ad = ContinuityParser.parse(manufacturerData: data)
        XCTAssertNil(ad?.caseComponent?.percent)
    }

    func testAirPodsMaxIsSingleBattery() {
        let data = manufacturerData(payload: payload(
            modelLo: 0x0A, status: 0x00, podsByte: 0x77, flagsCaseByte: 0x00
        ))
        let ad = ContinuityParser.parse(manufacturerData: data)
        XCTAssertEqual(ad?.kind, .airpodsMax)
        XCTAssertEqual(ad?.left?.percent, 70)
        XCTAssertNil(ad?.right)
        XCTAssertNil(ad?.caseComponent)
    }

    func testIgnoresNonProximityMessage() {
        // Apple company id but a "nearby" message (type 0x10), not proximity pairing.
        let data = Data([0x4C, 0x00, 0x10, 0x02, 0x00, 0x00])
        XCTAssertNil(ContinuityParser.parse(manufacturerData: data))
    }

    func testParsesBarePayloadWithoutCompanyID() {
        let data = manufacturerData(payload: payload(
            modelLo: 0x0E, status: 0x00, podsByte: 0x99, flagsCaseByte: 0x08
        ), includeCompanyID: false)
        // Strip the TLV header too, leaving a bare payload beginning with 0x01.
        let bare = Data(data.dropFirst(2))
        let ad = ContinuityParser.parse(manufacturerData: bare)
        XCTAssertEqual(ad?.left?.percent, 90)
        XCTAssertEqual(ad?.right?.percent, 90)
    }

    func testDeviceOverallPercentIsMinimumOfBuds() {
        let data = manufacturerData(payload: payload(
            modelLo: 0x0E, status: 0x00, podsByte: 0x85, flagsCaseByte: 0x49
        ))
        let ad = ContinuityParser.parse(manufacturerData: data)!
        let device = Device.from(advertisement: ad, id: "test", name: "AirPods Pro")
        XCTAssertEqual(device.overallPercent, 50)
        XCTAssertEqual(device.kind, .airpodsPro)
    }
}
