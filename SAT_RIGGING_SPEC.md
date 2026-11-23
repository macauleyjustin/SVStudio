# `.sat` Rigging & Deformation Specification (`1.0.0`)

## 1. Purpose
`rig.json` defines every parameter, hierarchical deformer (`rotation` and `warp`), parameter keyform, and per-mesh binding so every runtime evaluates identical vertex-level deformations.

---

## 2. Standard Parameter Dictionary
Runtimes drive tracking, lip sync, expressions, and breathing through these standardized IDs (all custom parameters are also supported natively):

| Parameter ID | Group | Range (`min .. def .. max`) | Meaning |
|---|---|---|---|
| `ParamAngleX` | Face | `-30 .. 0 .. 30` | Head yaw (negative = left, positive = right) |
| `ParamAngleY` | Face | `-30 .. 0 .. 30` | Head pitch (negative = down, positive = up) |
| `ParamAngleZ` | Face | `-30 .. 0 .. 30` | Head roll clockwise |
| `ParamMouthOpenY` | Mouth | `0 .. 0 .. 1` | Mouth vertical opening (`0` = closed, `1` = full) |
| `ParamMouthForm` | Mouth | `-1 .. 0 .. 1` | Smile/frown curve (`-1` = frown, `+1` = smile) |
| `ParamBodyAngleX` | Body | `-10 .. 0 .. 10` | Upper body lean/turn left-right |
| `ParamBodyAngleY` | Body | `-10 .. 0 .. 10` | Upper body pitch/bob |
| `ParamBodyAngleZ` | Body | `-10 .. 0 .. 10` | Upper body roll tilt |
| `ParamBreath` | Body | `0 .. 0 .. 1` | Breathing chest/shoulder rise cycle |
| `ParamEyeLOpen` / `ParamEyeROpen` | Eyes | `0 .. 1 .. 1` | Optional blink (`concealedEyes: true` skips) |
| `ParamEyeBallX` / `ParamEyeBallY` | Eyes | `-1 .. 0 .. 1` | Optional gaze (`concealedEyes: true` skips) |

Avatars may define arbitrary custom parameters (`ParamHairLeft`, `ParamCloakLeft`, `ParamBustBounceL_Y`, `ParamBustBounceR_Y`, `ParamMiasmaIntensity`, etc.). SVStudio discovers parameters purely from `rig.json` without hardcoding any avatar ID.

---

## 3. Deterministic 9-Step Frame Evaluation Order
Every runtime MUST execute these steps in exact sequence per frame:
1. **Receive Inputs**: Sample face tracking landmarks, microphone audio amplitude, and frame `dt`.
2. **Normalize & Smooth**: Map tracking into standard parameter units; apply configured smoothing, sensitivity, calibration offset, and return-to-neutral decay on signal loss.
3. **Evaluate Animations & Expressions**: Advance active animation clips (`Idle` / `Breathing`) and fade active expression layers.
4. **Resolve Priorities & Blend**: Combine tracking + animation + expression (`overwrite`, `add`, `multiply`), applying Lip Sync / Face Tracking / Hybrid priority rules for mouth parameters, then clamp to `[min, max]`.
5. **Evaluate Keyforms (Pass 1)**: Interpolate `rig.deformers` and `rig.meshBindings` keyforms for all non-physics-driven state.
6. **Advance Physics Simulation**: Step `PhysicsEngine` at `fixedTimestep` using current parameter values + parameter velocities/accelerations. Write simulated outputs back into destination physics parameters (clamped `[min, max]`).
7. **Apply Physics Re-Evaluation (Pass 2)**: Re-evaluate deformers & bindings driven by physics outputs so secondary deformation happens cleanly in the same frame.
8. **Hierarchical Transform Walk**: For each mesh vertex, apply direct `meshBindings` (`vertexDeltas`, `translate`, `scale`), then walk up its `parent` deformer chain leaf-to-root, applying each `warp` grid or `rotation` pivot transform.
9. **Sort & Render**: Resolve final `opacity` and `drawOrder` (`baseDrawOrder + drawOrderOffset`), sort drawables ascending, evaluate clipping masks and effects, and submit vertex/index buffers to GPU.

---

## 4. Keyform Indexing & Mathematical Interpolation
- Every bound object declares `axes: [{ parameter, keys }]` where `keys` are strictly ascending floats.
- `keyforms` is stored as a flat row-major Cartesian product with **`axes[0]` varying fastest** and `axes[k-1]` varying slowest:
  - Total keyforms = `Π axes[i].keys.count` (or `1` when `axes` is empty).
- **1D Piecewise Linear**: Given clamped `v` between `keys[i]` and `keys[i+1]`, `t = (v - keys[i]) / (keys[i+1] - keys[i])`, `val = lerp(k_i, k_{i+1}, t)`.
- **N-D Multilinear / 2D Bilinear**: Locate bracketing `(lo_i, hi_i, t_i)` on every axis `i`; evaluate tensor-product multilinear blend across all `2^N` corner keyforms.

---

## 5. Deformer Math
### 5.1 Warp Deformer
Defines rest canvas rectangle `bounds { x, y, width, height }` and lattice dimensions `(rows, cols)` yielding `(rows + 1) * (cols + 1)` rest control points:
`P_rest(r, c) = (x + width * c / cols, y + height * r / rows)`.
Keyform stores `gridOffsets[(rows+1)*(cols+1)]` = `[dx, dy]` per control point in canvas pixels (`P(r,c) = P_rest(r,c) + offset(r,c)`).
Given incoming point `p`:
- Compute normalized coordinates `u = (p.x - bounds.x) / bounds.width`, `v = (p.y - bounds.y) / bounds.height`.
- Inside `[0, 1] × [0, 1]`, locate cell `(c, r)` with local fraction `(fu, fv)` and apply smooth **bilinear patch interpolation** over `(P(r,c), P(r,c+1), P(r+1,c), P(r+1,c+1))`.
- Outside `[0, 1]`, smoothly extrapolate using boundary tangent cell + clamped affine remainder so edges never fold or snap.

### 5.2 Rotation Deformer
Defines rest pivot `pivot = [px, py]` in canvas pixels and interpolated `{ angleDeg, translate: [tx, ty], scale: [sx, sy] }`:
1. `(dx, dy) = ((p.x - px) * sx, (p.y - py) * sy)`
2. Rotate by `angleDeg` radians clockwise (`x' = dx cos θ - dy sin θ`, `y' = dx sin θ + dy cos θ`)
3. Result: `(px + tx + x', py + ty + y')`

### 5.3 Leaf-to-Root Composition
Because every mesh vertex and every deformer `pivot` / `bounds` are defined in the same rest canvas coordinate space, evaluating `meshBinding -> parentDeformer -> grandparentDeformer -> ... -> root` composes naturally without cumulative numeric skew.
