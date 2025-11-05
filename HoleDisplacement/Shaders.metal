// Copyright © 2025 Snap, Inc. All rights reserved.

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 local;
    float2 center;
};

static inline float4 smoothGradient(constant FrameUniforms & uniforms, float t) {
    float stops[4] = {
        uniforms.gradientStops.x,
        uniforms.gradientStops.y,
        uniforms.gradientStops.z,
        uniforms.gradientStops.w
    };
    
    float4 colors[4] = {
        uniforms.gradientColors[0],
        uniforms.gradientColors[1],
        uniforms.gradientColors[2],
        uniforms.gradientColors[3]
    };
    
    uint count = max(uniforms.gradientStopCount, (uint)2);
    count = min(count, (uint)4);
    
    if (t <= stops[0]) {
        return colors[0];
    }
    
    for (uint i = 0; i + 1 < count; ++i) {
        float a = stops[i];
        float b = stops[i + 1];
        if (t <= b || i == count - 2) {
            float segmentWidth = max(b - a, 1e-4);
            float f = clamp((t - a) / segmentWidth, 0.0, 1.0);
            return mix(colors[i], colors[i + 1], f);
        }
    }
    
    return colors[count - 1];
}

vertex VertexOut dotVertex(uint vertexID [[vertex_id]],
                           uint instanceID [[instance_id]],
                           constant float2 *unitVertices [[ buffer(BufferIndexVertices) ]],
                           constant DotInstanceUniform *instances [[ buffer(BufferIndexInstances) ]],
                           constant FrameUniforms & uniforms [[ buffer(BufferIndexUniforms) ]]) {
    VertexOut out;
    
    float2 local = unitVertices[vertexID];
    float2 center = instances[instanceID].center;
    float2 pixelPosition = center + local * uniforms.dotRadius;
    
    float2 ndc;
    ndc.x = (pixelPosition.x / uniforms.canvasSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (pixelPosition.y / uniforms.canvasSize.y) * 2.0;
    
    out.position = float4(ndc, 0.0, 1.0);
    out.local = local;
    out.center = center;
    
    return out;
}

fragment float4 dotFragment(VertexOut in [[stage_in]],
                            constant FrameUniforms & uniforms [[ buffer(BufferIndexUniforms) ]]) {
    float feather = uniforms.smoothing / max(uniforms.dotRadius, 0.0001);
    float sdf = length(in.local) - 1.0;
    float alpha = smoothstep(0.0, feather, -sdf);
    
    float2 normalizedPosition = in.center / uniforms.canvasSize;
    float2 gradientVector = uniforms.gradientEnd - uniforms.gradientStart;
    float gradientLength = length(gradientVector);
    float t = 0.0;
    if (gradientLength > 1e-4) {
        float2 dir = gradientVector / gradientLength;
        float projection = dot(normalizedPosition - uniforms.gradientStart, dir);
        t = clamp(projection / gradientLength, 0.0, 1.0);
    }
    
    float4 color = smoothGradient(uniforms, t);
    color.a *= alpha;
    color.rgb *= color.a;
    return color;
}

kernel void updateDots(constant vector_float2 *restPositions [[ buffer(SimulationBufferIndexRestPositions) ]],
                       device SimulationDotState *states [[ buffer(SimulationBufferIndexStates) ]],
                       device DotInstanceUniform *instances [[ buffer(SimulationBufferIndexInstances) ]],
                       constant SimulationUniforms & uniforms [[ buffer(SimulationBufferIndexUniforms) ]],
                       constant SimulationTouch *touches [[ buffer(SimulationBufferIndexTouches) ]],
                       uint id [[thread_position_in_grid]]) {
    if (id >= uniforms.dotCount) {
        return;
    }
    
    float2 rest = float2(restPositions[id]);
    SimulationDotState state = states[id];
    
    float dt = uniforms.timeSpring.x;
    float stiffness = uniforms.timeSpring.y;
    float damping = uniforms.timeSpring.z;
    float effectRadius = uniforms.timeSpring.w;
    
    float maxDisplacement = uniforms.displacementMass.x;
    float invMass = uniforms.displacementMass.y;
    float pixelScale = uniforms.displacementMass.z;
    
    float2 targetOffset = float2(0.0);
    uint touchCount = uniforms.touchCount;
    for (uint i = 0; i < touchCount; ++i) {
        float2 touchPosition = touches[i].position.xy;
        float2 r = rest - touchPosition;
        float distance = length(r);
        if (distance >= effectRadius || distance < 1e-4) {
            continue;
        }
        float2 direction = r / distance;
        float weight = 1.0 - smoothstep(0.0, effectRadius, distance);
        targetOffset += direction * maxDisplacement * weight;
    }
    
    float magnitude = length(targetOffset);
    if (magnitude > maxDisplacement && magnitude > 1e-4) {
        targetOffset = (targetOffset / magnitude) * maxDisplacement;
    }
    
    float2 displacementError = state.offset - targetOffset;
    float2 acceleration = (-stiffness * displacementError - damping * state.velocity) * invMass;
    state.velocity += acceleration * dt;
    state.offset += state.velocity * dt;
    
    float currentMagnitude = length(state.offset);
    if (currentMagnitude > maxDisplacement && currentMagnitude > 1e-4) {
        state.offset = (state.offset / currentMagnitude) * maxDisplacement;
        state.velocity = float2(0.0);
    }
    
    states[id] = state;
    
    float2 pixelCenter = (rest + state.offset) * pixelScale;
    instances[id].center = pixelCenter;
}
