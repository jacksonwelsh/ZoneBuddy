import Foundation
import SwiftUI
import Combine

@Observable
final class SettingsManager {
    static let shared = SettingsManager()
    
    private let store = NSUbiquitousKeyValueStore.default
    
    var transitionWarningDuration: Int {
        didSet {
            store.set(Int64(transitionWarningDuration), forKey: Keys.transitionWarningDuration)
            store.synchronize()
        }
    }
    
    var audioCuesEnabled: Bool {
        didSet {
            store.set(audioCuesEnabled, forKey: Keys.audioCuesEnabled)
            store.synchronize()
        }
    }
    
    private enum Keys {
        static let transitionWarningDuration = "transitionWarningDuration"
        static let audioCuesEnabled = "audioCuesEnabled"
    }
    
    private init() {
        // Initialize from store
        let savedDuration = Int(store.longLong(forKey: Keys.transitionWarningDuration))
        self.transitionWarningDuration = savedDuration == 0 ? 10 : savedDuration
        
        if store.object(forKey: Keys.audioCuesEnabled) == nil {
            self.audioCuesEnabled = true
        } else {
            self.audioCuesEnabled = store.bool(forKey: Keys.audioCuesEnabled)
        }
        
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFromCloud()
        }
    }
    
    private func refreshFromCloud() {
        let savedDuration = Int(store.longLong(forKey: Keys.transitionWarningDuration))
        transitionWarningDuration = savedDuration == 0 ? 10 : savedDuration
        
        if store.object(forKey: Keys.audioCuesEnabled) != nil {
            audioCuesEnabled = store.bool(forKey: Keys.audioCuesEnabled)
        }
    }
}
