# `.sat` Physics Specification (`1.0.0`)

## 1. Overview
`physics.json` specifies frame-rate-independent secondary motion groups so hair, fabric cloaks, skirts, accessories, and optional breast bounce react smoothly to head/body velocity, acceleration, and gravity, then settle cleanly at rest.

---

## 2. Integrator & Stability Guarantee
- Fixed internal integration step (`fixedTimestep`, recommended `0.0166667` = 60 Hz).
- Accumulator clamps large frame hitches (`maxStepsPerFrame = 8`, max accumulated `dt = 0.1s`) so dragging windows or waking from sleep never causes spring explosions.
- Semi-implicit / symplectic Euler with explicit velocity damping guarantees unconditional energy decay toward rest equilibrium (`output -> 0` when inputs stabilize).

---

## 3. Built-in Presets (`preset`)
| Preset | Stiffness (`ω²` scale) | Damping | Inertia | Gravity Scale | Character Behavior |
|---|---|---|---|---|---|
| `light_hair` | `38.0` | `5.8` | `1.15` | `1.0` | Quick, airy hair tip lag & gentle rebound |
| `heavy_fabric` | `16.0` | `4.2` | `0.85` | `1.35` | Slower, weighted velvet/cloak sweep |
| `soft_body` | `46.0` | `8.2` | `0.65` | `0.9` | Subtle, restrained biological damping (`ζ ≈ 0.6`) |
| `accessory` | `52.0` | `6.0` | `1.0` | `1.0` | Crisp rose/star/charm micro-oscillation |

Models MAY override any preset parameter (`stiffness`, `damping`, `inertia`, `gravityScale`, `windWeight`, `maxOutput`) directly in `groups[]`.

---

## 4. Solver Types
### 4.1 `"pendulum"`
Chains `nodes[0..N-1]` anchored to summed `inputs` (positional `x`, `y` + directional `velocityWeight * d(param)/dt` and tilt `angle`).
- Each node integrates angular/cartesian spring restoring force toward gravity-tilted rest vector plus damped momentum, constrained strictly to segment `length`.
- Outputs map node bend angle (`angle`) or displacement (`x`, `y`) × `scale` clamped to `[-maxOutput, +maxOutput]`.

### 4.2 `"spring2d"`
Dedicated 2D damped spring-mass (`pos = (x, y)`, `vel = (vx, vy)`) for soft-body bounce (such as breast physics) and compact secondary bounce:
- Force computes inertial reaction `-inertia * inputAccel + stiffness * (-pos) - damping * vel + wind`.
- Outputs read `pos.x` or `pos.y` × `scale` with hard `[min, max]` displacement saturation and smooth soft-clipping knee at 80% excursion so motion never looks rubbery.

---

## 5. Optional Category Scaling (`breast` Physics)
Groups tagged `"category": "breast"` receive SVStudio's runtime **Breast Physics Intensity** multiplier (`Off = 0.0`, `Subtle = 0.45`, `Normal = 1.0`, `Strong = 1.65`).
- Setting `Off` zeros velocity/displacement cleanly and restores neutral bodice pose.
- Avatars without `"category": "breast"` ignore the slider cleanly.
