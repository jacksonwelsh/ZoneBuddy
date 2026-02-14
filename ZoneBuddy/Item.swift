//
//  Item.swift
//  ZoneBuddy
//
//  Created by Jackson Welsh on 2/13/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
