import Testing
import Foundation
import CoreLocation
@testable import ZoneBuddy

struct TCXBuilderTests {
    private func sample(
        at t: TimeInterval,
        power: Int? = nil,
        cadence: Double? = nil,
        heartRate: Int? = nil,
        speed: Double? = nil
    ) -> BikeDataSample {
        BikeDataSample(
            timestamp: Date(timeIntervalSince1970: t),
            power: power,
            cadence: cadence,
            heartRate: heartRate,
            speed: speed,
            distance: nil,
            calories: nil
        )
    }

    private func location(at t: TimeInterval, lat: Double, lon: Double, alt: Double = 100) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: alt,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: t)
        )
    }

    private func xmlString(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    @Test
    func producesWellFormedParseableXML() throws {
        let samples = [
            sample(at: 0, power: 150, cadence: 90, heartRate: 130, speed: 30),
            sample(at: 1, power: 160, cadence: 91, heartRate: 132, speed: 31),
        ]
        let data = TCXBuilder.makeTCX(samples: samples, locations: [])
        // XMLParser is the strongest "is this valid XML" assertion available.
        let parser = XMLParser(data: data)
        #expect(parser.parse(), "TCX output should be parseable XML")
        let xml = xmlString(data)
        #expect(xml.contains("<TrainingCenterDatabase"))
        #expect(xml.contains("Sport=\"Biking\""))
    }

    @Test
    func emitsOneTrackpointPerSample() {
        let samples = (0..<5).map { sample(at: Double($0), power: 100, speed: 20) }
        let xml = xmlString(TCXBuilder.makeTCX(samples: samples, locations: []))
        let count = xml.components(separatedBy: "<Trackpoint>").count - 1
        #expect(count == 5)
    }

    @Test
    func embedsPowerViaWattsExtension() {
        let xml = xmlString(TCXBuilder.makeTCX(samples: [sample(at: 0, power: 234)], locations: []))
        #expect(xml.contains("<ns3:Watts>234</ns3:Watts>"))
        #expect(xml.contains("xmlns:ns3=\"http://www.garmin.com/xmlschemas/ActivityExtension/v2\""))
    }

    @Test
    func roundsCadenceToIntegerRPM() {
        let xml = xmlString(TCXBuilder.makeTCX(samples: [sample(at: 0, cadence: 89.6)], locations: []))
        #expect(xml.contains("<Cadence>90</Cadence>"))
    }

    @Test
    func emitsHeartRateOnlyWhenPositive() {
        let withHR = xmlString(TCXBuilder.makeTCX(samples: [sample(at: 0, heartRate: 145)], locations: []))
        #expect(withHR.contains("<HeartRateBpm><Value>145</Value></HeartRateBpm>"))

        let zeroHR = xmlString(TCXBuilder.makeTCX(samples: [sample(at: 0, heartRate: 0)], locations: []))
        #expect(!zeroHR.contains("<HeartRateBpm>"))
    }

    @Test
    func omitsPositionForIndoorRides() {
        let samples = [sample(at: 0, power: 100), sample(at: 1, power: 100)]
        let xml = xmlString(TCXBuilder.makeTCX(samples: samples, locations: []))
        #expect(!xml.contains("<Position>"))
        #expect(!xml.contains("<LatitudeDegrees>"))
    }

    @Test
    func includesPositionForRouteRides() {
        let samples = [sample(at: 0, power: 100, speed: 25), sample(at: 1, power: 100, speed: 25)]
        let locations = [
            location(at: 0, lat: 37.7749, lon: -122.4194, alt: 50),
            location(at: 1, lat: 37.7750, lon: -122.4195, alt: 52),
        ]
        let xml = xmlString(TCXBuilder.makeTCX(samples: samples, locations: locations))
        #expect(xml.contains("<Position>"))
        #expect(xml.contains("<LatitudeDegrees>37.7749000</LatitudeDegrees>"))
        #expect(xml.contains("<AltitudeMeters>50.00</AltitudeMeters>"))
    }

    @Test
    func distanceIsMonotonicAndUsesPointSeparator() {
        // 36 km/h = 10 m/s, held 2s → 20m total. Locale must not turn "." into ",".
        let samples = [
            sample(at: 0, speed: 36),
            sample(at: 1, speed: 36),
            sample(at: 2, speed: 36),
        ]
        let xml = xmlString(TCXBuilder.makeTCX(samples: samples, locations: []))
        #expect(xml.contains("<DistanceMeters>20.00</DistanceMeters>"))
        #expect(!xml.contains("<DistanceMeters>20,00</DistanceMeters>"))
    }

    @Test
    func includesCaloriesWhenProvided() {
        let xml = xmlString(TCXBuilder.makeTCX(samples: [sample(at: 0, power: 100)], locations: [], totalCalories: 420))
        #expect(xml.contains("<Calories>420</Calories>"))
    }

    // MARK: - Synthetic (older rides without captured streams)

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    @Test
    func syntheticAttributesTheProvidedStartTime() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let data = TCXBuilder.makeSyntheticTCX(
            startDate: start, duration: 600, avgPower: 180,
            avgHeartRate: 140, totalDistanceMeters: 6000, totalCalories: 200)
        let xml = xmlString(data)
        // The TCX <Id> / first trackpoint time is what Strava dates the ride by.
        #expect(xml.contains("<Id>\(iso(start))</Id>"))
        #expect(xml.contains("<Time>\(iso(start))</Time>"))
    }

    @Test
    func syntheticReconstructsTotalDistanceAndDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // 10 km over 1000 s.
        let xml = xmlString(TCXBuilder.makeSyntheticTCX(
            startDate: start, duration: 1000, avgPower: 200,
            avgHeartRate: nil, totalDistanceMeters: 10000, totalCalories: nil))
        #expect(xml.contains("<TotalTimeSeconds>1000.00</TotalTimeSeconds>"))
        #expect(xml.contains("<DistanceMeters>10000.00</DistanceMeters>"))
        // Average power is carried onto every synthesized trackpoint.
        #expect(xml.contains("<ns3:Watts>200</ns3:Watts>"))
    }

    @Test
    func syntheticIndoorRideHasNoMap() {
        let xml = xmlString(TCXBuilder.makeSyntheticTCX(
            startDate: Date(timeIntervalSince1970: 1_700_000_000), duration: 300,
            avgPower: 150, avgHeartRate: 130, totalDistanceMeters: 3000, totalCalories: nil))
        #expect(!xml.contains("<Position>"))
    }

    @Test
    func syntheticRouteRideRebuildsMap() {
        let points = [
            RoutePoint(distanceMeters: 0, elevationMeters: 10, gradePercent: 0, latitude: 37.0, longitude: -122.0),
            RoutePoint(distanceMeters: 500, elevationMeters: 30, gradePercent: 4, latitude: 37.01, longitude: -122.01),
            RoutePoint(distanceMeters: 1000, elevationMeters: 20, gradePercent: -2, latitude: 37.02, longitude: -122.0),
        ]
        let xml = xmlString(TCXBuilder.makeSyntheticTCX(
            startDate: Date(timeIntervalSince1970: 1_700_000_000), duration: 600,
            avgPower: 210, avgHeartRate: 150, totalDistanceMeters: 1000, totalCalories: 300,
            routePoints: points))
        #expect(xml.contains("<Position>"))
        #expect(xml.contains("<LatitudeDegrees>37."))
    }

    @Test
    func emptySamplesStillProduceValidDocument() {
        let data = TCXBuilder.makeTCX(samples: [], locations: [])
        let parser = XMLParser(data: data)
        #expect(parser.parse())
        let xml = xmlString(data)
        #expect(!xml.contains("<Trackpoint>"))
    }
}
