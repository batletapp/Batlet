import SwiftUI

/// Consistent outline device artwork for rows and detail headers.
struct DeviceIconView: View {
    let kind: DeviceKind
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let assetName = kind.iconAssetName {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: kind.symbolName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
