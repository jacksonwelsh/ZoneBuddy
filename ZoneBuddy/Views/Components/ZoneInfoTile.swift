import SwiftUI

struct ZoneInfoTile: View {
    let zone: PowerZone?
    let ftp: Int
    let foregroundColor: Color

    var body: some View {
        VStack(spacing: 4) {
            if let zone {
                Text(zone.displayName)
                    .font(.headline)
                    .foregroundStyle(foregroundColor)
                Text(zone.zoneName)
                    .font(.subheadline)
                    .foregroundStyle(foregroundColor.opacity(0.7))
                Text(zone.rangeDescription(ftp: ftp))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(foregroundColor.opacity(0.6))
            } else {
                Text("Warmup")
                    .font(.headline)
                    .foregroundStyle(foregroundColor)
            }
        }
    }
}
