import Foundation
import SwiftUI

enum BikeAnswer: Hashable {
    case yes, no, notSure
}

enum OnboardingStep: Hashable {
    case welcome
    case whatIsThis
    case privacy
    case bikeQuestion
    case bluetooth
    case bikeConnect
    case watchHR
    case ftp
    case done
}

/// State for the first-launch onboarding flow. The `path` is dynamic — answering "no" or
/// "not sure" on the bike question removes the bike-specific steps so the flow stays short
/// for users without a smart bike.
@Observable
final class OnboardingViewModel {
    var path: [OnboardingStep] = [.welcome, .whatIsThis, .privacy, .bikeQuestion, .watchHR, .done]
    var currentIndex: Int = 0

    var bikeAnswer: BikeAnswer? = nil
    var ftpInput: Int = SettingsManager.shared.functionalThresholdPower

    /// Set true when user taps "Take FTP Test Now" on the FTP step. Read by the host
    /// after onboarding dismisses to navigate the user to FTPTestIntroView.
    var routeToFTPTestAfterDismiss: Bool = false

    var currentStep: OnboardingStep {
        guard path.indices.contains(currentIndex) else { return .done }
        return path[currentIndex]
    }

    var progress: (current: Int, total: Int) {
        (currentIndex + 1, path.count)
    }

    var canGoBack: Bool { currentIndex > 0 }

    var isLastStep: Bool { currentIndex >= path.count - 1 }

    func recomputePath() {
        var p: [OnboardingStep] = [.welcome, .whatIsThis, .privacy, .bikeQuestion]
        if bikeAnswer == .yes {
            p.append(.bluetooth)
            p.append(.bikeConnect)
        }
        p.append(.watchHR)
        if bikeAnswer == .yes {
            p.append(.ftp)
        }
        p.append(.done)
        path = p
        if currentIndex >= path.count {
            currentIndex = path.count - 1
        }
    }

    func advance() {
        if currentIndex < path.count - 1 {
            currentIndex += 1
        }
    }

    func goBack() {
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }

    /// Persist any settings the user entered during onboarding and mark it complete.
    func finalize() {
        let clamped = max(50, min(500, ftpInput))
        SettingsManager.shared.functionalThresholdPower = clamped
        SettingsManager.shared.hasCompletedOnboarding = true
    }
}
