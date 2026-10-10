//
//  Item.swift
//  Cliptate
//
//  Created by 大可 on 2025/8/9.
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
