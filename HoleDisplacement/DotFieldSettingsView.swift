//
//  DotFieldSettingsView.swift
//  HoleDisplacement
//
//  Created by Codex on 2025-02-17.
//

import SwiftUI
import UIKit

struct DotFieldSettingsView: View {
    @ObservedObject var store: DotFieldSettingsStore
    var systemReduceMotionEnabled: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    private var gradientOptions: [(index: Int, preset: GradientPreset)] {
        GradientPreset.presets.enumerated().map { (index: $0.offset, preset: $0.element) }
    }
    
    var body: some View {
        NavigationView {
            List {
                dotSection
                animationSection
                feedbackSection
                if systemReduceMotionEnabled {
                    systemReduceMotionSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var dotSection: some View {
        Section("Dots") {
            Picker("Dot Size", selection: $store.settings.dotSize) {
                ForEach(DotSizeOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            
            Picker("Density", selection: $store.settings.density) {
                ForEach(DensityOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var animationSection: some View {
        Section("Animation") {
            Picker("Intensity", selection: $store.settings.intensity) {
                ForEach(IntensityOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            
            Picker("Gradient", selection: $store.settings.gradientIndex) {
                ForEach(gradientOptions, id: \.index) { entry in
                    Text(entry.preset.name).tag(entry.index)
                }
            }
            
            Toggle(isOn: $store.settings.reduceMotion) {
                Text("Reduce Motion")
            }
        }
    }
    
    private var feedbackSection: some View {
        Section("Feedback") {
            Toggle(isOn: $store.settings.hapticsEnabled) {
                Text("Haptic on First Touch")
            }
        }
    }
    
    private var systemReduceMotionSection: some View {
        Section {
            Label("System Reduce Motion is enabled", systemImage: "exclamationmark.triangle")
                .foregroundColor(.secondary)
                .font(.footnote)
        }
    }
}
