import UIKit

/// Resolution of the current device's physical screen corner radius via public APIs:
/// looks up the POSIX `utsname` model identifier in a table of published values, with
/// a safe-area-based fallback for hardware not in the table.
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

    private static func fallbackRadius() -> CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad { return 18 }
        let topInset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 0
        if topInset >= 50 { return 55 }       // Dynamic Island class
        if topInset >= 40 { return 47.33 }    // Notch class
        return 0
    }

    /// Published / community-verified screen corner radii by device model identifier.
    /// Sources: Apple HIG resources, PaintCode device specs, kylebshr/screen-corners.
    private static let cornerRadiusByModel: [String: CGFloat] = [
        // iPhone X / XS / XS Max / 11 Pro / 11 Pro Max
        "iPhone10,3": 39, "iPhone10,6": 39,
        "iPhone11,2": 39, "iPhone11,4": 39, "iPhone11,6": 39,
        "iPhone12,3": 39, "iPhone12,5": 39,

        // iPhone XR / 11
        "iPhone11,8": 41.5,
        "iPhone12,1": 41.5,

        // iPhone 12 mini / 13 mini
        "iPhone13,1": 44,
        "iPhone14,4": 44,

        // iPhone 12 / 12 Pro / 13 / 13 Pro / 14 / 14 Plus
        "iPhone13,2": 47.33, "iPhone13,3": 47.33,
        "iPhone14,5": 47.33, "iPhone14,2": 47.33,
        "iPhone14,7": 47.33, "iPhone14,8": 47.33,

        // iPhone 12 Pro Max / 13 Pro Max
        "iPhone13,4": 53.33,
        "iPhone14,3": 53.33,

        // iPhone 14 Pro / 14 Pro Max — Dynamic Island
        "iPhone15,2": 55, "iPhone15,3": 55,

        // iPhone 15 / 15 Plus / 15 Pro / 15 Pro Max
        "iPhone15,4": 55, "iPhone15,5": 55,
        "iPhone16,1": 55, "iPhone16,2": 55,

        // iPhone 16e (notch, A18)
        "iPhone17,5": 47.33,

        // iPhone 16 / 16 Plus / 16 Pro / 16 Pro Max
        "iPhone17,3": 55, "iPhone17,4": 55,
        "iPhone17,1": 55, "iPhone17,2": 55,

        // iPhone 17 / 17 Plus / 17 Pro / 17 Pro Max
        "iPhone18,3": 55, "iPhone18,4": 55,
        "iPhone18,1": 55, "iPhone18,2": 55,

        // iPad Pro 11" (1st–4th gen) / iPad Pro 12.9" (3rd–6th gen)
        "iPad8,1": 18, "iPad8,2": 18, "iPad8,3": 18, "iPad8,4": 18,
        "iPad8,5": 18, "iPad8,6": 18, "iPad8,7": 18, "iPad8,8": 18,
        "iPad8,9": 18, "iPad8,10": 18, "iPad8,11": 18, "iPad8,12": 18,
        "iPad13,4": 18, "iPad13,5": 18, "iPad13,6": 18, "iPad13,7": 18,
        "iPad13,8": 18, "iPad13,9": 18, "iPad13,10": 18, "iPad13,11": 18,
        "iPad14,3": 18, "iPad14,4": 18, "iPad14,5": 18, "iPad14,6": 18,

        // iPad Pro M4 (11" / 13", 2024)
        "iPad16,3": 18, "iPad16,4": 18, "iPad16,5": 18, "iPad16,6": 18,

        // iPad Air (4th / 5th / M2 / M3)
        "iPad13,1": 18, "iPad13,2": 18,
        "iPad13,16": 18, "iPad13,17": 18,
        "iPad14,8": 18, "iPad14,9": 18, "iPad14,10": 18, "iPad14,11": 18,

        // iPad mini (6th / 7th gen — A15 / A17 Pro)
        "iPad14,1": 21, "iPad14,2": 21,
        "iPad16,1": 21, "iPad16,2": 21,

        // iPad (10th gen — flat-sided, USB-C)
        "iPad13,18": 18, "iPad13,19": 18
    ]
}
