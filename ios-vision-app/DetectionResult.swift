//
//  DetectionResult.swift
//  ios-vision-app
//
//  Created by Kosuke Takeda on 2025/05/17.
//

import Foundation
import CoreGraphics

struct DetectionResult: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let rect: CGRect
}
