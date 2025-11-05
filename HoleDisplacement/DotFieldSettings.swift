//
//  DotFieldSettings.swift
//  HoleDisplacement
//
//  Created by Codex on 2025-02-17.
//

import Foundation
import Combine

enum DotSizeOption: Int, CaseIterable, Identifiable, Equatable {
    case small
    case medium
    case large
    
    var id: Int { rawValue }
    
    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    
    var diameter: Float {
        switch self {
        case .small: return 3
        case .medium: return 4
        case .large: return 6
        }
    }
}

enum DensityOption: Int, CaseIterable, Identifiable, Equatable {
    case sparse
    case standard
    case dense
    
    var id: Int { rawValue }
    
    var label: String {
        switch self {
        case .sparse: return "Sparse"
        case .standard: return "Default"
        case .dense: return "Dense"
        }
    }
    
    var spacing: Float {
        switch self {
        case .sparse: return 12
        case .standard: return 10
        case .dense: return 8
        }
    }
    
    var targetDotTarget: Int {
        switch self {
        case .sparse: return 12_000
        case .standard: return 18_000
        case .dense: return 22_000
        }
    }
}

enum IntensityOption: Int, CaseIterable, Identifiable, Equatable {
    case low
    case normal
    case high
    
    var id: Int { rawValue }
    
    var label: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Default"
        case .high: return "High"
        }
    }
    
    var preset: DotFieldConfiguration.DotFieldIntensityPreset {
        switch self {
        case .low: return .low
        case .normal: return .default
        case .high: return .high
        }
    }
    
    var effectRadius: Float {
        switch self {
        case .low: return 90
        case .normal: return 120
        case .high: return 160
        }
    }
}

struct DotFieldSettings: Equatable {
    var dotSize: DotSizeOption = .medium
    var density: DensityOption = .standard
    var intensity: IntensityOption = .normal
    var gradientIndex: Int = 0
    var reduceMotion: Bool = false
    var hapticsEnabled: Bool = false
    
    var intensityPreset: DotFieldConfiguration.DotFieldIntensityPreset {
        intensity.preset
    }
    
    var effectRadius: Float {
        intensity.effectRadius
    }
}

final class DotFieldSettingsStore: ObservableObject {
    @Published var settings: DotFieldSettings
    
    init(settings: DotFieldSettings = DotFieldSettings()) {
        self.settings = settings
    }
}
