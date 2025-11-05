
## 1) One-liner
A delightful, full-screen “dotfield” wallpaper/app where thousands of round dots form a uniform grid with a multicolor gradient; when the user touches the screen, dots within a radius spring away from the finger and then settle back.

---

## 2) Goals & Non-Goals
**Goals**
- Feel *buttery* and playful; maintain 120/60 FPS on supported devices.
- Clear, clean visual with round dots and smooth gradient.
- Physical, responsive interaction (spring-based “evade”); supports multi-touch.

**Non-Goals**
- No 3D depth, particles, or complex shaders beyond what’s needed.
- No networking, sign-in, or persistence beyond lightweight settings.

---

## 3) Platforms & Minimums
- **Primary**: iOS 16+ (iPhone), SwiftUI UI layer; Metal-backed rendering path recommended.
- **Nice-to-have** (future): iPad layout; Android (Jetpack Compose + RenderScript/vulkan shader equivalent).
- **Refresh rate**: Respect ProMotion (120Hz) when available.

---

## 4) User Stories
1. As a user, I see a full-screen grid of evenly spaced circular dots with a pleasing gradient.
2. As I touch or drag, dots near my finger move away with a springy feel and smoothly relax back when I lift my finger.
3. As I use multiple fingers, each finger creates its own field; effects combine naturally.
4. As I rotate the phone or open/close the app, the layout stays consistent with no stutter.
5. I can optionally tweak simple settings (dot size, density, gradient preset, animation intensity).

---

## 5) Visual & Layout Spec
- **Dot shape**: perfect circles, no aliasing, equal diameter.
- **Grid**: rectangular lattice aligned to pixel grid; spacing `S` (pt), diameter `D` (pt).
  - Defaults: `D = 4pt`, `S = 10pt` (effective ~ 10k–20k dots for a phone screen; see performance section).
- **Coverage**: Fill *safe area*; optionally allow “edge-to-edge” under home indicator with `ignoresSafeArea()`.
- **Gradient**: smooth multi-stop linear or radial gradient across the canvas.
  - Default preset: diagonal multicolor similar to the reference (purple→pink→blue). Provide 4 presets.
  - Optional subtle time drift (period 30–60s; amplitude small) that must never cause dropped frames.
- **Compositing**: Dots sample gradient color at their current (animated) positions (preferred) or their rest positions for stability.

---

## 6) Interaction & Physics
- **Touch input**: multi-touch; handle `began/changed/ended/cancelled`. Track each active touch with an ID.
- **Effect radius** `R`: default `R = 120pt` per touch (settings: 60–200pt).
- **Max displacement** `Amax`: clamp dot displacement magnitude ≤ `Amax = 24pt`.
- **Falloff**: Smooth radial falloff to 0 at `R`. Recommended kernel:
  - Let `d = |p - t|` (dot position to touch), `u = (p - t) / max(d, ε)`.
  - **Target offset** `Δ* = u * Amax * (1 - smoothstep(0, R, d))`  
    where `smoothstep(a,b,x) = clamp((x-a)/(b-a),0,1)^2 * (3 - 2*clamp(...))`.
- **Spring dynamics** (per dot in influence):
  - State: offset `Δ`, velocity `v` (2D). Target `Δ*` from current active touches (sum and clamp).
  - ODE: `m * d²Δ/dt² + c * dΔ/dt + k * (Δ - Δ*) = 0`.
  - Parameters (defaults): mass `m = 1`, stiffness `k = 28`, damping `c = 14` (ζ≈0.5, under-damped).
  - Integrator: semi-implicit Euler or Verlet on a fixed timestep locked to display refresh; compute 1 step per frame.
- **Multi-touch composition**: compute each touch’s `Δ*` and **sum vectors**, then clamp magnitude to `Amax` before stepping the spring.
- **Release**: when all touches end, `Δ* → 0`, dots spring back to rest.

---

## 7) Performance Budget
- **Frame time**: ≤ 8.3ms on 120Hz devices; ≤ 16.7ms on 60Hz.
- **Dot count**: choose dynamically to meet budget. Start target ~ 12–18k dots on A-series phones; degrade gracefully.
  - Strategy: pick cell size from device class; or switch to instanced GPU drawing.
- **GPU path** (preferred): Metal render pipeline with **instanced circles** (triangle strip or SDF in fragment) and per-instance offset; gradient sampled in fragment.
- **CPU path** (fallback/dev): SwiftUI `Canvas` with `drawLayer` and a cached dot path; avoid per-dot SwiftUI views.
- **Memory**: ≤ 50MB incremental (positions, velocities, per-instance buffer).

---

## 8) Accessibility & Haptics
- Respect **Reduce Motion**: lower `Amax`, higher damping, and disable gradient drift.
- Optional subtle **haptic tap** on first touch (light impact). Toggle in Settings.

---

## 9) Settings (MVP toggle screen)
- Dot Size: Small / Medium / Large (`D`: 3/4/6pt).
- Density: Sparse / Default / Dense (`S`: 12/10/8pt).
- Intensity: Low / Default / High (`Amax`, `k`, `c` presets).
- Gradient: 4 presets.
- Reduce Motion: On/Off (mirrors system when available).

---

## 10) State & Architecture
- **App state** (`Observable`): device metrics, grid config, list of active touches, frame clock.
- **Renderer**: owns GPU buffers and the simulation step.
- **Simulation**:
  1. Build grid once at layout (store rest positions).
  2. Each frame: compute `Δ*` from touches using spatial partitioning (uniform bins) to visit only nearby dots.
  3. Integrate spring per affected dot; write transformed positions to GPU buffer.
- **Threading**: run simulation on a high-priority background queue; commit render on main/MTL command queue sync.

---

## 11) Telemetry (optional, local only for MVP)
- Frame time rolling average.
- Dot count and percent within budget.
- Toggle through a hidden debug overlay (two-finger triple-tap).

---

## 12) Acceptance Criteria (MVP)
1. Launch shows a dot grid fully covering safe area, with gradient matching selected preset.
2. Single-finger touch causes nearby dots to move away with a springy effect and return when released.
3. Two fingers create two fields that combine; no visual tearing or jumps.
4. 60 FPS sustained on iPhone 12/13; 100+ FPS on ProMotion devices under default density.
5. Orientation changes and app background/foreground keep state without crashes.
6. Reduce Motion enabled leads to visibly calmer animation.
7. No per-dot SwiftUI view allocation; renderer uses Canvas+Metal or pure Metal with instancing.
8. Battery drain under a 2-minute interaction test is within normal bounds (qualitative for MVP).

---

## 13) Risks & Mitigations
- **CPU bottleneck**: Use instanced draw calls, spatial bins, and SIMD math.
- **Shader aliasing**: Render circles as SDFs with smoothstep alpha.
- **Jank on touch begin**: pre-warm pipeline and Metal buffers; avoid allocations in gesture handlers.

---

## 14) Deliverables
- iOS app target with Swift Package for the renderer/simulation.
- Unit tests for kernel math (falloff, spring step).
- Simple Settings view.
- README with build/run notes and performance toggles.

---

## 15) Pseudocode (core loop)

```swift
struct Touch { let id: Int; var pos: SIMD2<Float> }
var touches: [Int: Touch] = [:]

// Grid
struct Dot { let rest: SIMD2<Float>; var delta: SIMD2<Float>; var vel: SIMD2<Float> }
var dots: [Dot] = makeGrid(spacing: S, diameter: D)

func targetOffset(for p: SIMD2<Float>) -> SIMD2<Float> {
    var sum = SIMD2<Float>(0,0)
    for (_, t) in touches {
        let r = p - t.pos
        let d = max(length(r), 1e-4)
        if d < R {
            let u = r / d
            let w = 1 - smoothstep(0, R, d)        // 0..1
            sum += u * Float(Amax) * w
        }
    }
    let m = length(sum)
    return (m > Float(Amax)) ? (normalize(sum) * Float(Amax)) : sum
}

func step(dt: Float) {
    for i in dots.indices {
        let x = dots[i].delta
        let v = dots[i].vel
        let xTarget = targetOffset(for: dots[i].rest)

        // Spring to target: m x¨ + c x˙ + k (x - xTarget) = 0
        let k: Float = 28, c: Float = 14
        let a = -k*(x - xTarget) - c*v             // m=1
        let v2 = v + a*dt
        let x2 = x + v2*dt                         // semi-implicit Euler
        dots[i].vel = v2
        dots[i].delta = clampMagnitude(x2, Float(Amax))
    }
}