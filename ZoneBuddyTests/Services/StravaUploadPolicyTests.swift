import Testing
import Foundation
@testable import ZoneBuddy

struct StravaUploadPolicyTests {
    @Test
    func autoUploadRequiresOptIn() {
        #expect(!StravaUploadPolicy.shouldAutoUpload(
            modality: .structured, autoUploadEnabled: false, includeFTPTests: false))
        #expect(StravaUploadPolicy.shouldAutoUpload(
            modality: .structured, autoUploadEnabled: true, includeFTPTests: false))
    }

    @Test
    func freeAndRouteRidesAutoUploadWhenEnabled() {
        #expect(StravaUploadPolicy.shouldAutoUpload(
            modality: .freeRide, autoUploadEnabled: true, includeFTPTests: false))
        #expect(StravaUploadPolicy.shouldAutoUpload(
            modality: .routeRide(routeID: nil, routeName: "Climb", totalElevationGainMeters: 100),
            autoUploadEnabled: true, includeFTPTests: false))
    }

    @Test
    func ftpTestsExcludedUnlessOptedIn() {
        let ftp: SessionModality = .ftpTest(protocol: .twentyMinute, result: nil)
        #expect(!StravaUploadPolicy.shouldAutoUpload(
            modality: ftp, autoUploadEnabled: true, includeFTPTests: false))
        #expect(StravaUploadPolicy.shouldAutoUpload(
            modality: ftp, autoUploadEnabled: true, includeFTPTests: true))
    }

    @Test
    func onlyRouteRidesAreVirtual() {
        #expect(StravaUploadPolicy.isVirtualRide(
            .routeRide(routeID: nil, routeName: "Climb", totalElevationGainMeters: 100)))
        #expect(!StravaUploadPolicy.isVirtualRide(.structured))
        #expect(!StravaUploadPolicy.isVirtualRide(.freeRide))
    }
}
