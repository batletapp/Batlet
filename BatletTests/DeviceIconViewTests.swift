import AppKit
import SwiftUI
import XCTest
@testable import Batlet

final class DeviceIconViewTests: XCTestCase {
    @MainActor
    func testLocalDeviceAssetsRenderAtRowSize() {
        let kinds: [DeviceKind] = [
            .airpods, .headphones, .mac, .macBook, .iphone, .ipad,
            .watch, .magicMouse, .keyboard
        ]

        for kind in kinds {
            guard let assetName = kind.iconAssetName else {
                return XCTFail("Missing asset mapping for \(kind)")
            }
            XCTAssertNotNil(NSImage(named: assetName), "Missing asset \(assetName)")

            let renderer = ImageRenderer(content:
                DeviceIconView(kind: kind, size: 18)
                    .foregroundStyle(.black)
                    .frame(width: 24, height: 24)
                    .background(.white)
            )
            renderer.scale = 2
            guard let cgImage = renderer.cgImage else {
                return XCTFail("Could not render \(kind)")
            }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            let darkPixels = (0..<cgImage.width).reduce(0) { total, x in
                total + (0..<cgImage.height).filter { y in
                    guard let color = bitmap.colorAt(x: x, y: y) else { return false }
                    return color.redComponent < 0.5 && color.greenComponent < 0.5
                }.count
            }
            XCTAssertGreaterThan(darkPixels, 20, "\(assetName) appears blank at row size")
        }

    }
}
