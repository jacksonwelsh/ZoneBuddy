import Testing
import Foundation
@testable import ZoneBuddy

@MainActor
struct GPXParserTests {

    // MARK: - XML parsing

    private static let sampleGPX = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="test">
      <trk>
        <name>Test Track</name>
        <trkseg>
          <trkpt lat="40.0000" lon="-105.0000"><ele>1600.0</ele></trkpt>
          <trkpt lat="40.0010" lon="-105.0000"><ele>1602.0</ele></trkpt>
          <trkpt lat="40.0020" lon="-105.0000"><ele>1610.0</ele></trkpt>
          <trkpt lat="40.0030" lon="-105.0000"><ele>1605.0</ele></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    @Test
    func parsesTrackPointsInOrder() throws {
        let data = Data(Self.sampleGPX.utf8)
        let points = try GPXParser.parseRawPoints(from: data)

        #expect(points.count == 4)
        #expect(points[0].lat == 40.0)
        #expect(points[0].lon == -105.0)
        #expect(points[0].ele == 1600.0)
        #expect(points[3].ele == 1605.0)
    }

    @Test
    func rejectsEmptyData() {
        #expect(throws: GPXParseError.unreadable) {
            try GPXParser.parseRawPoints(from: Data())
        }
    }

    @Test
    func rejectsFileWithNoTrackPoints() throws {
        let onlyWaypoint = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><wpt lat="40" lon="-105"><ele>1000</ele></wpt></gpx>
        """
        #expect(throws: GPXParseError.noTrackPoints) {
            try GPXParser.parseRawPoints(from: Data(onlyWaypoint.utf8))
        }
    }

    @Test
    func ignoresRoutePointsOutsideTrkseg() throws {
        // <rtept> and <wpt> aren't track points; the resample relies on
        // strictly time-ordered <trkpt> data and would otherwise drift.
        let mixed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <wpt lat="40" lon="-105"><ele>9999</ele></wpt>
          <rte><rtept lat="41" lon="-104"><ele>9999</ele></rtept></rte>
          <trk><trkseg>
            <trkpt lat="40.0" lon="-105.0"><ele>1000</ele></trkpt>
            <trkpt lat="40.001" lon="-105.0"><ele>1010</ele></trkpt>
          </trkseg></trk>
        </gpx>
        """
        let points = try GPXParser.parseRawPoints(from: Data(mixed.utf8))
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.ele < 5000 })
    }

    @Test
    func rejectsFilesAboveSizeCap() {
        let bytes = GPXParser.maxBytes + 1
        let oversized = Data(repeating: 0x20, count: bytes)
        #expect(throws: GPXParseError.tooLarge(bytes: bytes)) {
            try GPXParser.parseRawPoints(from: oversized)
        }
    }

    @Test
    func rejectsMalformedXML() {
        let bad = Data("<gpx><trkseg><trkpt lat=".utf8)
        #expect(throws: (any Error).self) {
            try GPXParser.parseRawPoints(from: bad)
        }
    }

    // MARK: - Haversine

    @Test
    func haversineDistanceMatchesKnownPair() {
        // 0.001° of latitude ≈ 111.2 m anywhere on Earth.
        let d = GPXParser.haversineMeters(
            lat1: 40.0, lon1: -105.0,
            lat2: 40.001, lon2: -105.0
        )
        #expect(d > 110 && d < 113)
    }

    // MARK: - Resample + smooth

    /// Build raw points along a meridian (so each lat step has a known distance)
    /// with a known three-segment elevation profile: flat, climb, descent.
    private func buildSyntheticRaw(
        flatMeters: Double, climbMeters: Double, descentMeters: Double,
        climbGain: Double, descentLoss: Double,
        sampleSpacingMeters: Double = 2.0
    ) -> [GPXParser.RawPoint] {
        let total = flatMeters + climbMeters + descentMeters
        let metersPerDegLat = 111_320.0
        let stepLat = sampleSpacingMeters / metersPerDegLat
        let count = Int(total / sampleSpacingMeters) + 1
        var points: [GPXParser.RawPoint] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            let dist = Double(i) * sampleSpacingMeters
            let baseEle = 1000.0
            let ele: Double
            if dist < flatMeters {
                ele = baseEle
            } else if dist < flatMeters + climbMeters {
                let t = (dist - flatMeters) / climbMeters
                ele = baseEle + climbGain * t
            } else {
                let t = (dist - flatMeters - climbMeters) / descentMeters
                ele = baseEle + climbGain - descentLoss * t
            }
            points.append(GPXParser.RawPoint(
                lat: 40.0 + Double(i) * stepLat,
                lon: -105.0,
                ele: ele
            ))
        }
        return points
    }

    @Test
    func resampleProducesExpectedTotalDistance() {
        let raw = buildSyntheticRaw(
            flatMeters: 300, climbMeters: 400, descentMeters: 300,
            climbGain: 20, descentLoss: 9
        )
        let points = GPXParser.resampleAndSmooth(raw)

        #expect(!points.isEmpty)
        let total = points.last!.distanceMeters
        // Should be ~1000m; allow 2% for Haversine vs flat-earth and resample
        // rounding.
        #expect(total > 980 && total < 1020)
    }

    @Test
    func resampleUsesUniformStepSpacing() {
        let raw = buildSyntheticRaw(
            flatMeters: 100, climbMeters: 100, descentMeters: 100,
            climbGain: 5, descentLoss: 5
        )
        let points = GPXParser.resampleAndSmooth(raw)

        // All consecutive points (except possibly the final tail) are spaced
        // by `resampleStepMeters`.
        for i in 1..<(points.count - 1) {
            let delta = points[i].distanceMeters - points[i - 1].distanceMeters
            #expect(abs(delta - GPXParser.resampleStepMeters) < 0.001)
        }
    }

    @Test
    func gradeIsPositiveOnClimbAndNegativeOnDescent() {
        let raw = buildSyntheticRaw(
            flatMeters: 200, climbMeters: 400, descentMeters: 200,
            climbGain: 40, descentLoss: 20
        )
        let points = GPXParser.resampleAndSmooth(raw)
        // Mid-climb (around 400m) should read positive grade close to 10%
        // (40m gain over 400m), modulo the smoothing window's averaging.
        let mid = points.first { $0.distanceMeters >= 400 }!
        #expect(mid.gradePercent > 5 && mid.gradePercent < 12)

        // Mid-descent (around 700m) should read negative grade.
        let descent = points.first { $0.distanceMeters >= 700 }!
        #expect(descent.gradePercent < 0)
    }

    @Test
    func gradeIsClampedToTwentyPercent() {
        // Ridiculous 100% climb: 100m of rise over 100m of distance.
        let raw = buildSyntheticRaw(
            flatMeters: 50, climbMeters: 100, descentMeters: 50,
            climbGain: 100, descentLoss: 100
        )
        let points = GPXParser.resampleAndSmooth(raw)
        for p in points {
            #expect(p.gradePercent <= GPXParser.maxGradePercent + 0.0001)
            #expect(p.gradePercent >= -GPXParser.maxGradePercent - 0.0001)
        }
    }

    // MARK: - End-to-end

    @Test
    func makeRouteBuildsCompletePopulatedRoute() throws {
        let data = Data(Self.sampleGPX.utf8)
        let route = try GPXParser.makeRoute(name: "Sample", from: data)

        #expect(route.name == "Sample")
        #expect(route.points.count >= 2)
        #expect(route.totalDistanceMeters > 0)
        #expect(route.rawGPX != nil)
    }
}
