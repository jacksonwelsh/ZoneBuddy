import Foundation

enum WorkoutCoderError: Error {
    case invalidURL
    case invalidPath
    case missingPayload
    case unsupportedVersion
    case decodingFailed
}

enum WorkoutCoder {
    private static let currentVersion: Character = "A"
    private static let host = "zonebuddy.jacksn.dev"

    static func encode(_ workout: Workout) throws -> URL {
        let transfer = WorkoutTransferData(workout: workout)
        let json = try JSONEncoder().encode(transfer)
        let payload = String(currentVersion) + json.base64URLEncodedString()
        guard let url = URL(string: "https://\(host)/workout/\(payload)") else {
            throw WorkoutCoderError.invalidURL
        }
        return url
    }

    static func decode(_ url: URL) throws -> WorkoutTransferData {
        guard url.scheme == "https", url.host() == host else {
            throw WorkoutCoderError.invalidURL
        }

        let pathComponents = url.pathComponents
        guard pathComponents.count == 3, pathComponents[1] == "workout" else {
            throw WorkoutCoderError.invalidPath
        }

        return try decodePayload(pathComponents[2])
    }

    private static func decodePayload(_ payload: String) throws -> WorkoutTransferData {
        guard let firstChar = payload.first else {
            throw WorkoutCoderError.missingPayload
        }
        guard firstChar == currentVersion else {
            throw WorkoutCoderError.unsupportedVersion
        }

        let base64URLString = String(payload.dropFirst())
        guard let data = Data(base64URLEncoded: base64URLString) else {
            throw WorkoutCoderError.decodingFailed
        }

        do {
            return try JSONDecoder().decode(WorkoutTransferData.self, from: data)
        } catch {
            throw WorkoutCoderError.decodingFailed
        }
    }
}
