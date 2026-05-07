import SwiftUI

struct ZoneInfoTile: View {
    let zone: PowerZone?
    let ftp: Int
    let foregroundColor: Color

    var body: some View {
        if let zone {
            HStack(spacing: 12) {
                Text(zone.displayName)
                    .font(.headline)
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(zone.zoneName)
                        .font(.subheadline)
                        .foregroundStyle(foregroundColor.opacity(0.7))
                    Text(zone.rangeDescription(ftp: ftp))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(foregroundColor.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Warmup")
                .font(.headline)
                .foregroundStyle(foregroundColor)
        }
    }
}
