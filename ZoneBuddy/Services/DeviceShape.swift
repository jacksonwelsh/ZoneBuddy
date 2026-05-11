import UIKit

/// Resolution of the current device's physical screen corner radius via public APIs:
/// looks up the POSIX `utsname` model identifier in a table of measured values, with
/// a screen-size + safe-area fallback for hardware not in the table.
enum DeviceShape {
    static let screenCornerRadius: CGFloat = {
        if let exact = cornerRadiusByModel[modelIdentifier()] {
            return exact
        }
        return fallbackRadius()
    }()

    private static func modelIdentifier() -> String {
        if let simID = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simID
        }
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }

    /// Best-effort guess for hardware released after this table was last updated.
    /// Errs on the side of "more rounded" so the EdgeGlowView never has corners
    /// sticking off the physical screen.
    private static func fallbackRadius() -> CGFloat {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        let topInset = keyWindow?.safeAreaInsets.top ?? 0
        let screenWidth = keyWindow?.screen.bounds.width ?? 0

        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            // Modern flat-design iPads sit around 18–30. Default high so glow
            // never overshoots the bezel on unknown new Pros.
            return 30
        case .phone:
            if topInset >= 50 { return 62 }   // Dynamic Island / modern Pro screen
            if topInset >= 40 {                // Notch — Plus/Max bodies use a larger radius
                return screenWidth > 415 ? 53.33 : 47.33
            }
            return 0                            // Home button (SE, etc.)
        default:
            return 0
        }
    }

    /// Screen corner radii by model identifier. Every iOS 26-compatible iPhone and
    /// iPad in this table was measured by reading `UIScreen.displayCornerRadius`
    /// directly from the corresponding simulator runtime; older entries kept for
    /// devices that fell out of iOS 26 support but may still launch the app.
    private static let cornerRadiusByModel: [String: CGFloat] = [

        // MARK: - iPhone (home-button / square corners)

        "iPhone12,8": 0,        // iPhone SE (2nd gen)
        "iPhone14,6": 0,        // iPhone SE (3rd gen)

        // MARK: - iPhone (notch, 39 pt — X / XS / 11 Pro family)

        "iPhone10,3": 39, "iPhone10,6": 39,        // iPhone X
        "iPhone11,2": 39,                          // iPhone XS
        "iPhone11,4": 39, "iPhone11,6": 39,        // iPhone XS Max
        "iPhone12,3": 39, "iPhone12,5": 39,        // iPhone 11 Pro / Pro Max

        // MARK: - iPhone (notch, 41.5 pt — XR / 11)

        "iPhone11,8": 41.5,                        // iPhone XR
        "iPhone12,1": 41.5,                        // iPhone 11

        // MARK: - iPhone (notch, 44 pt — mini)

        "iPhone13,1": 44,                          // iPhone 12 mini
        "iPhone14,4": 44,                          // iPhone 13 mini

        // MARK: - iPhone (notch, 47.33 pt — 12/13/14 standard + 16e/17e)

        "iPhone13,2": 47.33, "iPhone13,3": 47.33,  // iPhone 12 / 12 Pro
        "iPhone14,2": 47.33,                       // iPhone 13 Pro
        "iPhone14,5": 47.33,                       // iPhone 13
        "iPhone14,7": 47.33,                       // iPhone 14
        "iPhone17,5": 47.33,                       // iPhone 16e
        "iPhone18,5": 47.33,                       // iPhone 17e

        // MARK: - iPhone (notch, 53.33 pt — 12/13 Pro Max + 14 Plus)

        "iPhone13,4": 53.33,                       // iPhone 12 Pro Max
        "iPhone14,3": 53.33,                       // iPhone 13 Pro Max
        "iPhone14,8": 53.33,                       // iPhone 14 Plus

        // MARK: - iPhone (Dynamic Island, 55 pt — 14 Pro through 16 Plus)

        "iPhone15,2": 55, "iPhone15,3": 55,        // iPhone 14 Pro / Pro Max
        "iPhone15,4": 55, "iPhone15,5": 55,        // iPhone 15 / 15 Plus
        "iPhone16,1": 55, "iPhone16,2": 55,        // iPhone 15 Pro / Pro Max
        "iPhone17,3": 55, "iPhone17,4": 55,        // iPhone 16 / 16 Plus

        // MARK: - iPhone (Dynamic Island, 62 pt — 16 Pro & all iPhone 17 family)

        "iPhone17,1": 62, "iPhone17,2": 62,        // iPhone 16 Pro / Pro Max
        "iPhone18,1": 62, "iPhone18,2": 62,        // iPhone 17 Pro / Pro Max
        "iPhone18,3": 62,                          // iPhone 17
        "iPhone18,4": 62,                          // iPhone Air

        // MARK: - iPad (home-button / square corners)

        "iPad11,1": 0, "iPad11,2": 0,              // iPad mini 5
        "iPad11,3": 0, "iPad11,4": 0,              // iPad Air 3
        "iPad11,6": 0, "iPad11,7": 0,              // iPad 8
        "iPad12,1": 0, "iPad12,2": 0,              // iPad 9

        // MARK: - iPad (rounded, 18 pt — older Pro + Air 4/5/M2/M3/M4)

        // iPad Pro 11" 1st gen + iPad Pro 12.9" 3rd gen
        "iPad8,1": 18, "iPad8,2": 18, "iPad8,3": 18, "iPad8,4": 18,
        "iPad8,5": 18, "iPad8,6": 18, "iPad8,7": 18, "iPad8,8": 18,
        // iPad Pro 11" 2nd gen + iPad Pro 12.9" 4th gen
        "iPad8,9": 18, "iPad8,10": 18, "iPad8,11": 18, "iPad8,12": 18,
        // iPad Air 4
        "iPad13,1": 18, "iPad13,2": 18,
        // iPad Pro 11" 3rd gen + iPad Pro 12.9" 5th gen
        "iPad13,4": 18, "iPad13,5": 18, "iPad13,6": 18, "iPad13,7": 18,
        "iPad13,8": 18, "iPad13,9": 18, "iPad13,10": 18, "iPad13,11": 18,
        // iPad Air 5
        "iPad13,16": 18, "iPad13,17": 18,
        // iPad Pro 11" 4th gen + iPad Pro 12.9" 6th gen
        "iPad14,3": 18, "iPad14,4": 18, "iPad14,5": 18, "iPad14,6": 18,
        // iPad Air 11" M2 + iPad Air 13" M2
        "iPad14,8": 18, "iPad14,9": 18, "iPad14,10": 18, "iPad14,11": 18,
        // iPad Air 11" M3 + iPad Air 13" M3
        "iPad15,3": 18, "iPad15,4": 18, "iPad15,5": 18, "iPad15,6": 18,
        // iPad Air 11" M4 + iPad Air 13" M4
        "iPad16,9": 18, "iPad16,10": 18, "iPad16,11": 18, "iPad16,12": 18,

        // MARK: - iPad mini (rounded, 21.5 pt — mini 6 / mini A17 Pro)

        "iPad14,1": 21.5, "iPad14,2": 21.5,        // iPad mini 6
        "iPad16,1": 21.5, "iPad16,2": 21.5,        // iPad mini (A17 Pro)

        // MARK: - iPad (rounded, 25 pt — flat-side budget iPads)

        "iPad13,18": 25, "iPad13,19": 25,          // iPad 10
        "iPad15,7": 25, "iPad15,8": 25,            // iPad (A16)

        // MARK: - iPad Pro (rounded, 30 pt — M4 / M5 thin-chassis Pros)

        "iPad16,3": 30, "iPad16,4": 30,            // iPad Pro 11" M4
        "iPad16,5": 30, "iPad16,6": 30,            // iPad Pro 13" M4
        "iPad17,1": 30, "iPad17,2": 30,            // iPad Pro 11" M5
        "iPad17,3": 30, "iPad17,4": 30             // iPad Pro 13" M5
    ]
}
