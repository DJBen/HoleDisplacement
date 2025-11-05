// Copyright © 2025 Snap, Inc. All rights reserved.

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

typedef NS_ENUM(EnumBackingType, BufferIndex) {
    BufferIndexVertices     = 0,
    BufferIndexInstances    = 1,
    BufferIndexUniforms     = 2
};

typedef NS_ENUM(EnumBackingType, SimulationBufferIndex) {
    SimulationBufferIndexRestPositions = 0,
    SimulationBufferIndexStates        = 1,
    SimulationBufferIndexInstances     = 2,
    SimulationBufferIndexUniforms      = 3,
    SimulationBufferIndexTouches       = 4
};

typedef struct {
    vector_float2 center;
} DotInstanceUniform;

typedef struct {
    vector_float2 canvasSize;     // Pixels
    float         dotRadius;      // Pixels
    float         smoothing;      // Pixels
    vector_float2 gradientStart;  // Normalized 0-1
    vector_float2 gradientEnd;    // Normalized 0-1
    float         time;           // Seconds
    float         driftStrength;  // Reserved for subtle drift
    uint          gradientStopCount;
    uint          _padding;
    vector_float4 gradientStops;  // Packed stops
    vector_float4 gradientColors[4];
} FrameUniforms;

typedef struct {
    vector_float2 offset;
    vector_float2 velocity;
} SimulationDotState;

typedef struct {
    vector_float4 position;   // xy = position in points
} SimulationTouch;

typedef struct {
    vector_float4 timeSpring;       // x=dt, y=stiffness, z=damping, w=effectRadius
    vector_float4 displacementMass; // x=maxDisplacement, y=invMass, z=pixelScale, w=unused
    uint          touchCount;
    uint          dotCount;
    uint          padding0;
    uint          padding1;
} SimulationUniforms;

#endif /* ShaderTypes_h */
