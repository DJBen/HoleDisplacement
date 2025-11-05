//
//  Renderer.swift
//  HoleDisplacement
//
//  Created by Codex on 2025-02-17.
//

import Foundation
import Metal
import MetalKit
import simd
import UIKit

enum RendererError: Error {
    case unableToCreatePipeline
}

private enum BufferIndex: Int {
    case vertices = 0
    case instances = 1
    case uniforms = 2
}

private let maxBuffersInFlight = 3
private let bufferAlignment = 0x100

private func alignedSize(_ length: Int) -> Int {
    let clamped = max(length, 1)
    return (clamped + (bufferAlignment - 1)) & -bufferAlignment
}

private struct FrameUniforms {
    var canvasSize: SIMD2<Float> = .zero
    var dotRadius: Float = 0
    var smoothing: Float = 1
    var gradientStart: SIMD2<Float> = SIMD2<Float>(0, 0)
    var gradientEnd: SIMD2<Float> = SIMD2<Float>(1, 1)
    var time: Float = 0
    var driftStrength: Float = 0
    var gradientStopCount: UInt32 = 0
    var padding: UInt32 = 0
    var gradientStops: SIMD4<Float> = SIMD4<Float>(0, 0.33, 0.66, 1)
    var gradientColors0: SIMD4<Float> = SIMD4<Float>(1, 0, 0, 1)
    var gradientColors1: SIMD4<Float> = SIMD4<Float>(0, 1, 0, 1)
    var gradientColors2: SIMD4<Float> = SIMD4<Float>(0, 0, 1, 1)
    var gradientColors3: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
}

struct GradientPreset {
    let name: String
    let colors: [SIMD4<Float>]
    let stops: [Float]
    let start: SIMD2<Float>
    let end: SIMD2<Float>
    let driftAmplitude: Float
    let driftPeriod: Float
    
    static let diagonalAurora = GradientPreset(
        name: "Aurora",
        colors: [
            SIMD4<Float>(0.596, 0.251, 0.925, 1.0),
            SIMD4<Float>(0.956, 0.317, 0.725, 1.0),
            SIMD4<Float>(0.294, 0.556, 0.984, 1.0),
            SIMD4<Float>(0.082, 0.949, 0.894, 1.0)
        ],
        stops: [0.0, 0.35, 0.68, 1.0],
        start: SIMD2<Float>(0.0, 0.0),
        end: SIMD2<Float>(1.0, 1.0),
        driftAmplitude: 0.025,
        driftPeriod: 45.0
    )
    
    static let sunset = GradientPreset(
        name: "Sunset",
        colors: [
            SIMD4<Float>(0.992, 0.549, 0.247, 1.0),
            SIMD4<Float>(0.992, 0.247, 0.435, 1.0),
            SIMD4<Float>(0.600, 0.250, 0.796, 1.0),
            SIMD4<Float>(0.294, 0.388, 0.996, 1.0)
        ],
        stops: [0.0, 0.27, 0.6, 1.0],
        start: SIMD2<Float>(0.1, 0.9),
        end: SIMD2<Float>(0.9, 0.1),
        driftAmplitude: 0.03,
        driftPeriod: 38.0
    )
    
    static let ocean = GradientPreset(
        name: "Ocean",
        colors: [
            SIMD4<Float>(0.000, 0.451, 0.992, 1.0),
            SIMD4<Float>(0.074, 0.713, 0.992, 1.0),
            SIMD4<Float>(0.000, 0.835, 0.623, 1.0),
            SIMD4<Float>(0.000, 0.427, 0.239, 1.0)
        ],
        stops: [0.0, 0.3, 0.65, 1.0],
        start: SIMD2<Float>(0.0, 1.0),
        end: SIMD2<Float>(1.0, 0.0),
        driftAmplitude: 0.02,
        driftPeriod: 52.0
    )
    
    static let citrus = GradientPreset(
        name: "Citrus",
        colors: [
            SIMD4<Float>(0.988, 0.941, 0.325, 1.0),
            SIMD4<Float>(0.992, 0.709, 0.239, 1.0),
            SIMD4<Float>(0.941, 0.317, 0.207, 1.0),
            SIMD4<Float>(0.478, 0.184, 0.560, 1.0)
        ],
        stops: [0.0, 0.25, 0.55, 1.0],
        start: SIMD2<Float>(0.0, 0.2),
        end: SIMD2<Float>(1.0, 0.8),
        driftAmplitude: 0.028,
        driftPeriod: 36.0
    )
    
    static let presets: [GradientPreset] = [.diagonalAurora, .sunset, .ocean, .citrus]
}

final class Renderer: NSObject, MTKViewDelegate {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let computePipelineState: MTLComputePipelineState
    private let vertexBuffer: MTLBuffer
    private var instanceBuffer: MTLBuffer
    private var perFrameInstanceLength: Int
    private var instanceBufferOffset: Int = 0
    private var maxInstanceCount: Int = 0
    
    private var uniformBuffer: MTLBuffer
    private var uniformBufferIndex: Int = 0
    private var uniformBufferOffset: Int = 0
    private var uniformsPointer: UnsafeMutablePointer<FrameUniforms>
    
    private var simulationDataBuffer: MTLBuffer
    private var simulationDataStride: Int
    private var simulationDataOffset: Int = 0
    private var simulationUniformPointer: UnsafeMutablePointer<SimulationUniformsData>
    private var simulationTouchPointer: UnsafeMutablePointer<SimulationTouchData>
    private let simulationTouchOffset: Int
    private let maxSimulationTouches: Int
    
    private let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    private weak var metalView: MTKView?
    
    private let defaultConfiguration = DotFieldConfiguration(
        dotDiameter: 5,
        spacing: 10,
        effectRadius: 150,
        maxDisplacement: 24,
        stiffness: 100,
        damping: 14
    )
    private var currentConfiguration: DotFieldConfiguration
    private var systemReduceMotionEnabled: Bool = UIAccessibility.isReduceMotionEnabled
    private var userReduceMotionEnabled: Bool = false
    private var simulation: DotFieldSimulation
    
    private var activeTouches: [Int: SIMD2<Float>] = [:]
    
    private var displayScale: Float = Float(UIScreen.main.scale)
    private var canvasSizePoints: SIMD2<Float> = .zero
    private var canvasSizePixels: SIMD2<Float> = .zero
    
    private var globalTime: Float = 0
    private var lastFrameTimestamp: CFTimeInterval = CACurrentMediaTime()
    
    private var gradientPreset: GradientPreset = .diagonalAurora
    private var currentSettings = DotFieldSettings()
    
    private var reduceMotionActive: Bool {
        systemReduceMotionEnabled || userReduceMotionEnabled
    }
    
    init?(metalKitView: MTKView) {
        guard let device = metalKitView.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = queue
        
        let maxFPS = UIScreen.main.maximumFramesPerSecond
        metalKitView.device = device
        metalKitView.colorPixelFormat = .bgra8Unorm_srgb
        metalKitView.depthStencilPixelFormat = .invalid
        metalKitView.sampleCount = 1
        metalKitView.clearColor = MTLClearColorMake(0, 0, 0, 1)
        metalKitView.framebufferOnly = true
        metalKitView.preferredFramesPerSecond = maxFPS >= 120 ? 120 : 60
        metalKitView.isPaused = false
        metalKitView.enableSetNeedsDisplay = false
        self.metalView = metalKitView
        
        let initialReduceMotion = UIAccessibility.isReduceMotionEnabled
        currentConfiguration = defaultConfiguration
        systemReduceMotionEnabled = initialReduceMotion
        userReduceMotionEnabled = false
        currentSettings.reduceMotion = initialReduceMotion
        let effectiveConfig = Renderer.effectiveConfiguration(base: currentConfiguration,
                                                              reduceMotion: initialReduceMotion)
        simulation = DotFieldSimulation(device: device, configuration: effectiveConfig)
        maxSimulationTouches = simulation.maxTouchCapacity
        
        let uniformStride = alignedSize(MemoryLayout<FrameUniforms>.stride)
        guard let uniforms = device.makeBuffer(length: uniformStride * maxBuffersInFlight,
                                               options: .storageModeShared) else {
            return nil
        }
        uniforms.label = "FrameUniforms"
        uniformBuffer = uniforms
        uniformsPointer = uniforms.contents()
            .bindMemory(to: FrameUniforms.self, capacity: 1)
        uniformBufferOffset = 0
        uniformBufferIndex = 0
        
        let simulationUniformSize = MemoryLayout<SimulationUniformsData>.stride
        let touchesSize = maxSimulationTouches * MemoryLayout<SimulationTouchData>.stride
        let simulationUniformAligned = alignedSize(simulationUniformSize)
        simulationTouchOffset = simulationUniformAligned
        let unalignedStride = simulationUniformAligned + touchesSize
        simulationDataStride = alignedSize(unalignedStride)
        guard let simulationBuffer = device.makeBuffer(length: simulationDataStride * maxBuffersInFlight,
                                                       options: .storageModeShared) else {
            return nil
        }
        simulationBuffer.label = "SimulationData"
        simulationDataBuffer = simulationBuffer
        simulationUniformPointer = simulationBuffer.contents()
            .bindMemory(to: SimulationUniformsData.self, capacity: 1)
        simulationTouchPointer = simulationBuffer.contents()
            .advanced(by: simulationTouchOffset)
            .bindMemory(to: SimulationTouchData.self, capacity: maxSimulationTouches)
        for index in 0..<maxSimulationTouches {
            simulationTouchPointer.advanced(by: index).pointee = SimulationTouchData(position: .zero)
        }
        
        let vertexData: [Float] = [
            -1, -1,
             1, -1,
            -1,  1,
             1,  1
        ]
        guard let vertexBuffer = device.makeBuffer(bytes: vertexData,
                                                   length: vertexData.count * MemoryLayout<Float>.stride,
                                                   options: .storageModeShared) else {
            return nil
        }
        self.vertexBuffer = vertexBuffer
        
        perFrameInstanceLength = alignedSize(MemoryLayout<SIMD2<Float>>.stride)
        guard let instanceBuffer = device.makeBuffer(length: perFrameInstanceLength * maxBuffersInFlight,
                                                     options: .storageModeShared) else {
            return nil
        }
        instanceBuffer.label = "DotInstances"
        self.instanceBuffer = instanceBuffer
        
        do {
            pipelineState = try Renderer.makePipeline(device: device,
                                                      pixelFormat: metalKitView.colorPixelFormat)
            computePipelineState = try Renderer.makeComputePipeline(device: device)
        } catch {
            return nil
        }
        
        super.init()
        
        simulation.setTouches(activeTouches)
        metalKitView.delegate = self
        mtkView(metalKitView, drawableSizeWillChange: metalKitView.drawableSize)
    }
    
    private static func makePipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "dotVertex"),
              let fragmentFunction = library.makeFunction(name: "dotFragment") else {
            throw RendererError.unableToCreatePipeline
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "DotFieldPipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private static func makeComputePipeline(device: MTLDevice) throws -> MTLComputePipelineState {
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "updateDots") else {
            throw RendererError.unableToCreatePipeline
        }
        return try device.makeComputePipelineState(function: function)
    }
    
    private static func effectiveConfiguration(base: DotFieldConfiguration,
                                               reduceMotion: Bool) -> DotFieldConfiguration {
        var config = base
        if reduceMotion {
            config.maxDisplacement *= 0.6
            config.stiffness *= 0.8
            config.damping *= 1.2
        }
        return config
    }
    
    func updateTouch(id: Int, location: CGPoint) {
        let position = SIMD2<Float>(Float(location.x), Float(location.y))
        activeTouches[id] = position
        simulation.setTouches(activeTouches)
    }
    
    func endTouch(id: Int) {
        activeTouches.removeValue(forKey: id)
        simulation.setTouches(activeTouches)
    }
    
    func resetTouches() {
        activeTouches.removeAll()
        simulation.setTouches(activeTouches)
    }
    
    func apply(settings: DotFieldSettings) {
        let previousSettings = currentSettings
        currentSettings = settings
        
        userReduceMotionEnabled = settings.reduceMotion
        if settings.gradientIndex >= 0 && settings.gradientIndex < GradientPreset.presets.count {
            gradientPreset = GradientPreset.presets[settings.gradientIndex]
        } else {
            gradientPreset = .diagonalAurora
        }
        
        var newConfig = defaultConfiguration
        newConfig.dotDiameter = settings.dotSize.diameter
        newConfig.spacing = settings.density.spacing
        newConfig.targetDotCount = settings.density.targetDotTarget
        newConfig.effectRadius = settings.effectRadius
        newConfig.applyIntensityPreset(settings.intensityPreset)
        currentConfiguration = newConfig
        
        let requiresGridRebuild = previousSettings.dotSize != settings.dotSize ||
            previousSettings.density != settings.density
        
        updateSimulationConfiguration(forceGridRebuild: requiresGridRebuild)
    }
    
    func systemReduceMotionChanged(_ enabled: Bool) {
        systemReduceMotionEnabled = enabled
        updateSimulationConfiguration(forceGridRebuild: false)
    }
    
    private func rotateBuffers() {
        let uniformStride = alignedSize(MemoryLayout<FrameUniforms>.stride)
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        uniformBufferOffset = uniformStride * uniformBufferIndex
        uniformsPointer = uniformBuffer.contents()
            .advanced(by: uniformBufferOffset)
            .bindMemory(to: FrameUniforms.self, capacity: 1)
        
        instanceBufferOffset = perFrameInstanceLength * uniformBufferIndex
        
        simulationDataOffset = simulationDataStride * uniformBufferIndex
        simulationUniformPointer = simulationDataBuffer.contents()
            .advanced(by: simulationDataOffset)
            .bindMemory(to: SimulationUniformsData.self, capacity: 1)
        simulationTouchPointer = simulationDataBuffer.contents()
            .advanced(by: simulationDataOffset + simulationTouchOffset)
            .bindMemory(to: SimulationTouchData.self, capacity: maxSimulationTouches)
    }
    
    private func updateSimulationConfiguration(forceGridRebuild: Bool) {
        let effectiveConfig = Renderer.effectiveConfiguration(base: currentConfiguration,
                                                              reduceMotion: reduceMotionActive)
        simulation.updateConfiguration(effectiveConfig)
        if forceGridRebuild && canvasSizePoints.x > 0 && canvasSizePoints.y > 0 {
            simulation.rebuildGrid(for: canvasSizePoints)
            prepareInstanceStorage(dotCount: simulation.dotCount)
        }
    }
    
    private func prepareInstanceStorage(dotCount: Int) {
        let requiredPerFrame = alignedSize(dotCount * MemoryLayout<SIMD2<Float>>.stride)
        if requiredPerFrame > instanceBuffer.length / maxBuffersInFlight {
            guard let buffer = device.makeBuffer(length: requiredPerFrame * maxBuffersInFlight,
                                                 options: .storageModeShared) else {
                print("Renderer: unable to allocate instance buffer for \(dotCount) dots")
                return
            }
            buffer.label = "DotInstances"
            instanceBuffer = buffer
        }
        perFrameInstanceLength = max(requiredPerFrame, alignedSize(MemoryLayout<SIMD2<Float>>.stride))
        maxInstanceCount = dotCount
    }
    
    private func populateUniforms() {
        var uniforms = FrameUniforms()
        uniforms.canvasSize = canvasSizePixels
        
        let radiusPixels = max(currentConfiguration.dotDiameter * 0.5 * displayScale, 1.0)
        uniforms.dotRadius = radiusPixels
        uniforms.smoothing = max(1.0, radiusPixels * 0.3)
        uniforms.time = globalTime
        
        var start = gradientPreset.start
        var end = gradientPreset.end
        let amplitude = reduceMotionActive ? 0 : gradientPreset.driftAmplitude
        if amplitude > 0 {
            let period = max(gradientPreset.driftPeriod, 0.1)
            let phase = sin((globalTime / period) * (Float.pi * 2))
            let direction = simd_normalize(end - start)
            let offset = direction * (amplitude * phase)
            start = simd_clamp(start - offset, SIMD2<Float>(repeating: 0), SIMD2<Float>(repeating: 1))
            end = simd_clamp(end + offset, SIMD2<Float>(repeating: 0), SIMD2<Float>(repeating: 1))
        }
        uniforms.gradientStart = start
        uniforms.gradientEnd = end
        uniforms.driftStrength = amplitude
        
        let stops = gradientPreset.stops
        uniforms.gradientStopCount = UInt32(max(2, stops.count))
        var stopVector = SIMD4<Float>(repeating: stops.first ?? 0)
        for i in 0..<min(stops.count, 4) {
            stopVector[i] = stops[i]
        }
        uniforms.gradientStops = stopVector
        
        let colors = gradientPreset.colors
        let defaultColor = SIMD4<Float>(0.5, 0.5, 0.5, 1.0)
        uniforms.gradientColors0 = colors.indices.contains(0) ? colors[0] : defaultColor
        uniforms.gradientColors1 = colors.indices.contains(1) ? colors[1] : uniforms.gradientColors0
        uniforms.gradientColors2 = colors.indices.contains(2) ? colors[2] : uniforms.gradientColors1
        uniforms.gradientColors3 = colors.indices.contains(3) ? colors[3] : uniforms.gradientColors2
        
        uniformsPointer.pointee = uniforms
    }
    
    func draw(in view: MTKView) {
        _ = inFlightSemaphore.wait(timeout: .distantFuture)
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return
        }
        commandBuffer.label = "DotFieldCommandBuffer"
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }
        
        rotateBuffers()
        
        let now = CACurrentMediaTime()
        var delta = Float(now - lastFrameTimestamp)
        lastFrameTimestamp = now
        if !delta.isFinite || delta > 0.1 {
            delta = 1.0 / Float(view.preferredFramesPerSecond)
        }
        
        let touchCount = simulation.populateTouches(into: simulationTouchPointer,
                                                    maxCount: maxSimulationTouches)
        
        if maxInstanceCount > 0 {
            var simulationUniforms = SimulationUniformsData()
            simulationUniforms.timeSpring = SIMD4<Float>(
                delta,
                currentConfiguration.stiffness,
                currentConfiguration.damping,
                currentConfiguration.effectRadius
            )
            let invMass = 1.0 / max(currentConfiguration.mass, 1e-4)
            simulationUniforms.displacementMass = SIMD4<Float>(
                currentConfiguration.maxDisplacement,
                invMass,
                displayScale,
                0
            )
            simulationUniforms.touchCount = UInt32(touchCount)
            simulationUniforms.dotCount = UInt32(maxInstanceCount)
            simulationUniformPointer.pointee = simulationUniforms
            
            simulation.encodeSimulation(on: commandBuffer,
                                        pipeline: computePipelineState,
                                        instanceBuffer: instanceBuffer,
                                        instanceOffset: instanceBufferOffset,
                                        simulationDataBuffer: simulationDataBuffer,
                                        uniformOffset: simulationDataOffset,
                                        touchesOffset: simulationDataOffset + simulationTouchOffset)
        } else {
            simulationUniformPointer.pointee = SimulationUniformsData()
        }
        
        globalTime += delta
        populateUniforms()
        
        guard let renderPass = view.currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            commandBuffer.commit()
            return
        }
        
        encoder.label = "DotFieldEncoder"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: BufferIndex.vertices.rawValue)
        encoder.setVertexBuffer(instanceBuffer, offset: instanceBufferOffset, index: BufferIndex.instances.rawValue)
        encoder.setVertexBuffer(uniformBuffer, offset: uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
        encoder.setFragmentBuffer(uniformBuffer, offset: uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
        
        encoder.drawPrimitives(type: .triangleStrip,
                               vertexStart: 0,
                               vertexCount: 4,
                               instanceCount: maxInstanceCount)
        encoder.endEncoding()
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        displayScale = Float(view.contentScaleFactor)
        canvasSizePixels = SIMD2<Float>(Float(size.width), Float(size.height))
        canvasSizePoints = SIMD2<Float>(Float(size.width) / displayScale,
                                        Float(size.height) / displayScale)
        
        updateSimulationConfiguration(forceGridRebuild: true)
        
        globalTime = 0
        lastFrameTimestamp = CACurrentMediaTime()
    }
}
