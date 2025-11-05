//
//  DotFieldSimulation.swift
//  HoleDisplacement
//
//  Created by Codex on 2025-02-17.
//

import Foundation
import Metal
import simd

/// Persistent configuration that drives the dot simulation and rendering.
struct DotFieldConfiguration {
    var dotDiameter: Float          // In points
    var spacing: Float              // Grid spacing in points
    var effectRadius: Float         // Touch influence radius in points
    var maxDisplacement: Float      // Max displacement per dot in points
    var stiffness: Float            // Spring stiffness k
    var damping: Float              // Damping coefficient c
    var mass: Float = 1.0           // Mass, fixed to 1 for now
    var targetDotCount: Int = 18_000
    
    mutating func applyIntensityPreset(_ preset: DotFieldIntensityPreset) {
        switch preset {
        case .low:
            maxDisplacement *= 0.65
            stiffness *= 0.65
            damping *= 0.85
        case .default:
            break
        case .high:
            maxDisplacement *= 1.2
            stiffness *= 1.35
            damping *= 1.1
        }
    }
    
    enum DotFieldIntensityPreset {
        case low
        case `default`
        case high
    }
}

struct SimulationDotStateData {
    var offset: SIMD2<Float>
    var velocity: SIMD2<Float>
}

struct SimulationTouchData {
    var position: SIMD2<Float>
    var padding: SIMD2<Float> = .zero
}

struct SimulationUniformsData {
    var timeSpring = SIMD4<Float>(repeating: 0)       // x=dt, y=stiffness, z=damping, w=effectRadius
    var displacementMass = SIMD4<Float>(repeating: 0) // x=maxDisplacement, y=invMass, z=pixelScale, w=unused
    var touchCount: UInt32 = 0
    var dotCount: UInt32 = 0
    var padding0: UInt32 = 0
    var padding1: UInt32 = 0
}

/// Core spring-based simulation for the dot grid. All per-dot integration work is executed on a Metal compute pipeline.
final class DotFieldSimulation {
    
    let device: MTLDevice
    private(set) var configuration: DotFieldConfiguration
    
    private(set) var gridSize: SIMD2<Int> = .zero
    private(set) var canvasSizePoints: SIMD2<Float> = .zero
    private(set) var dotCount: Int = 0
    
    private var restPositionsBuffer: MTLBuffer?
    private var stateBuffer: MTLBuffer?
    
    private let maxTouches = 8
    private var activeTouches: [Int: SIMD2<Float>] = [:]
    private let touchQueue = DispatchQueue(label: "com.snap.dotfield.touches", attributes: .concurrent)
    
    init(device: MTLDevice, configuration: DotFieldConfiguration) {
        self.device = device
        self.configuration = configuration
    }
    
    func updateConfiguration(_ newConfiguration: DotFieldConfiguration) {
        configuration = newConfiguration
    }
    
    func setTouches(_ touches: [Int: SIMD2<Float>]) {
        touchQueue.async(flags: .barrier) {
            self.activeTouches = touches
        }
    }
    
    @discardableResult
    func populateTouches(into pointer: UnsafeMutablePointer<SimulationTouchData>, maxCount: Int) -> Int {
        let snapshot: [SIMD2<Float>] = touchQueue.sync {
            return Array(self.activeTouches.values.prefix(maxCount))
        }
        
        var index = 0
        while index < snapshot.count && index < maxCount {
            pointer.advanced(by: index).pointee = SimulationTouchData(position: snapshot[index])
            index += 1
        }
        while index < maxCount {
            pointer.advanced(by: index).pointee = SimulationTouchData(position: .zero)
            index += 1
        }
        
        return snapshot.count
    }
    
    func rebuildGrid(for canvasSizePoints: SIMD2<Float>) {
        self.canvasSizePoints = canvasSizePoints
        
        let area = max(canvasSizePoints.x * canvasSizePoints.y, 1)
        let baseSpacing = max(configuration.spacing, 1.0)
        var spacing = baseSpacing
        let estimatedCount = max(Int(area / (spacing * spacing)), 1)
        
        if estimatedCount > configuration.targetDotCount {
            let scale = sqrt(Float(estimatedCount) / Float(configuration.targetDotCount))
            spacing = baseSpacing * max(scale, 1.0)
        }
        
        let columns = max(Int(ceil(canvasSizePoints.x / spacing)) + 2, 1)
        let rows = max(Int(ceil(canvasSizePoints.y / spacing)) + 2, 1)
        gridSize = SIMD2<Int>(columns, rows)
        
        var restPositions: [SIMD2<Float>] = []
        restPositions.reserveCapacity(columns * rows)
        
        let origin = SIMD2<Float>(-spacing, -spacing)
        for row in 0..<rows {
            for column in 0..<columns {
                let rest = SIMD2<Float>(
                    origin.x + Float(column) * spacing,
                    origin.y + Float(row) * spacing
                )
                restPositions.append(rest)
            }
        }
        
        dotCount = restPositions.count
        restPositionsBuffer = makeRestPositionsBuffer(from: restPositions)
        stateBuffer = makeStateBuffer(count: dotCount)
    }
    
    func encodeSimulation(on commandBuffer: MTLCommandBuffer,
                          pipeline: MTLComputePipelineState,
                          instanceBuffer: MTLBuffer,
                          instanceOffset: Int,
                          simulationDataBuffer: MTLBuffer,
                          uniformOffset: Int,
                          touchesOffset: Int) {
        guard dotCount > 0,
              let restPositionsBuffer = restPositionsBuffer,
              let stateBuffer = stateBuffer,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        encoder.label = "DotFieldSimulationEncoder"
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(restPositionsBuffer, offset: 0, index: SimulationBufferIndexSwift.restPositions.rawValue)
        encoder.setBuffer(stateBuffer, offset: 0, index: SimulationBufferIndexSwift.states.rawValue)
        encoder.setBuffer(instanceBuffer, offset: instanceOffset, index: SimulationBufferIndexSwift.instances.rawValue)
        encoder.setBuffer(simulationDataBuffer, offset: uniformOffset, index: SimulationBufferIndexSwift.uniforms.rawValue)
        encoder.setBuffer(simulationDataBuffer, offset: touchesOffset, index: SimulationBufferIndexSwift.touches.rawValue)
        
        let maxThreads = pipeline.maxTotalThreadsPerThreadgroup
        let threadWidth = min(maxThreads, 256)
        let threadsPerThreadgroup = MTLSize(width: threadWidth, height: 1, depth: 1)
        let threadgroupCount = MTLSize(width: (dotCount + threadWidth - 1) / threadWidth, height: 1, depth: 1)
        
        encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }
    
    var restBuffer: MTLBuffer? {
        restPositionsBuffer
    }
    
    var stateBufferForDebugging: MTLBuffer? {
        stateBuffer
    }
    
    var maxTouchCapacity: Int {
        maxTouches
    }
    
    // MARK: - Private helpers
    
    private func makeRestPositionsBuffer(from positions: [SIMD2<Float>]) -> MTLBuffer? {
        guard !positions.isEmpty else { return nil }
        let length = positions.count * MemoryLayout<SIMD2<Float>>.stride
        let buffer = device.makeBuffer(bytes: positions,
                                       length: length,
                                       options: .storageModeShared)
        buffer?.label = "RestPositions"
        return buffer
    }
    
    private func makeStateBuffer(count: Int) -> MTLBuffer? {
        guard count > 0 else { return nil }
        let length = count * MemoryLayout<SimulationDotStateData>.stride
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            return nil
        }
        buffer.label = "DotStateBuffer"
        memset(buffer.contents(), 0, length)
        return buffer
    }
}
private enum SimulationBufferIndexSwift: Int {
    case restPositions = 0
    case states = 1
    case instances = 2
    case uniforms = 3
    case touches = 4
}
