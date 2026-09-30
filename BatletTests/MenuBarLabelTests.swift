import XCTest
import SwiftUI
@testable import Batlet

final class MenuBarLabelTests: XCTestCase {
    @MainActor
    func testBadgeArtworkRendersAsOneImage() {
        let plain = ImageRenderer(content: MenuBarIconArtwork(count: 0, colorScheme: .dark)).nsImage
        let badged = ImageRenderer(content: MenuBarIconArtwork(count: 27, colorScheme: .dark)).nsImage

        XCTAssertEqual(plain?.size, NSSize(width: 17, height: 17))
        XCTAssertEqual(badged?.size, NSSize(width: 27, height: 18))
    }

    @MainActor
    func testBadgeNumberCutsThroughTheRenderedImage() {
        for scheme in [ColorScheme.dark, .light] {
            let renderer = ImageRenderer(content: MenuBarIconArtwork(count: 8, colorScheme: scheme))
            renderer.scale = 2
            guard let image = renderer.cgImage else { return XCTFail("Badge image did not render") }
            let bitmap = NSBitmapImageRep(cgImage: image)

            let numberRegion = (28..<40).flatMap { x in
                (16..<32).compactMap { y in bitmap.colorAt(x: x, y: y)?.alphaComponent }
            }
            XCTAssertTrue(numberRegion.contains { $0 < 0.05 }, "The badge number should be transparent")
            XCTAssertGreaterThan(bitmap.colorAt(x: 24, y: 24)?.alphaComponent ?? 0, 0.9,
                                 "The badge background should stay opaque")
        }
    }

    func testBadgeCountsConnectedVisibleDevicesIncludingPinnedRows() {
        let suiteName = "MenuBarLabelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.hiddenDeviceIDs = ["hidden"]

        let mac = Device(id: "mac", name: "Mac", kind: .macBook,
                         source: .systemPower, isConnected: true)
        let pinned = Device(id: "pinned", name: "Headphones", kind: .headphones,
                            source: .systemProfiler, isConnected: true, isPinned: true)
        let hidden = Device(id: "hidden", name: "Mouse", kind: .mouse,
                            source: .systemProfiler, isConnected: true)
        let disconnected = Device(id: "disconnected", name: "Keyboard", kind: .keyboard,
                                  source: .systemProfiler, isConnected: false)

        XCTAssertEqual(settings.visibleConnectedDeviceCount(in: [mac, pinned, hidden, disconnected]), 2)

        var newlyDisconnected = pinned
        newlyDisconnected.isConnected = false
        XCTAssertEqual(settings.visibleConnectedDeviceCount(in: [mac, newlyDisconnected, hidden, disconnected]), 1)

        settings.hiddenDeviceIDs.insert("mac")
        XCTAssertEqual(settings.visibleConnectedDeviceCount(in: [mac, newlyDisconnected, hidden, disconnected]), 0)
    }

    func testBadgeCountToggleHidesCountAndPersists() {
        let suiteName = "MenuBarBadgeCountTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let device = Device(id: "headphones", name: "Headphones", kind: .headphones,
                            source: .systemProfiler, isConnected: true)

        XCTAssertTrue(settings.showMenuBarBadgeCount)
        XCTAssertEqual(settings.menuBarBadgeCount(in: [device]), 1)

        settings.showMenuBarBadgeCount = false
        XCTAssertEqual(settings.menuBarBadgeCount(in: [device]), 0)
        XCTAssertFalse(AppSettings(defaults: defaults).showMenuBarBadgeCount)
    }

    func testRemovedIconPreferencesFallBackToBatlet() {
        let suiteName = "MenuBarIconMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for removedStyle in ["none", "macBattery"] {
            defaults.set(removedStyle, forKey: "menuBarIconStyle")
            XCTAssertEqual(AppSettings(defaults: defaults).menuBarIconStyle, .appIcon)
        }
    }

    @MainActor
    func testEveryIconStyleRendersWithConnectedDeviceBadge() {
        for style in MenuBarIconStyle.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: style.symbolName, accessibilityDescription: nil))
            let image = ImageRenderer(content: MenuBarIconArtwork(style: style, count: 3, colorScheme: .dark)).nsImage
            XCTAssertEqual(image?.size, NSSize(width: 23, height: 18), style.label)
        }
    }

    @MainActor
    func testLargerBadgeCountsKeepTheSameMenuBarHeight() {
        for (count, width) in [(27, 27), (120, 32)] {
            let image = ImageRenderer(content: MenuBarIconArtwork(count: count, colorScheme: .dark)).nsImage
            XCTAssertEqual(image?.size, NSSize(width: width, height: 18))
        }
    }
}
