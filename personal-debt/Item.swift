//
//  Item.swift
//  personal-debt
//
//  Created by Mac on 2026/4/25.
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
