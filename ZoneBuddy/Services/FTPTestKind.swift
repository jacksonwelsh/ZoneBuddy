import Foundation

/// Which FTP test protocol the workout is running. Determines how the
/// result is calculated (95%×20-min avg vs 75%×best-1-min) and what UI
/// affordances the player shows.
enum FTPTestKind: String, Codable, Equatable, Sendable {
    case twentyMinute
    case ramp
}
