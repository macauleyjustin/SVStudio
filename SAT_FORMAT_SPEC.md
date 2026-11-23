# `.sat` — Satella Avatar Format Specification (`1.0.0`)

## 1. Overview
A `.sat` (**Satella Avatar**) file is a self-contained, platform-independent 2D VTuber model archive packaged as a standard UTF-8 ZIP container (`STORE` or `DEFLATE`). All asset references live inside the archive and describe declarative geometry, rigs, physics, textures, expressions, animations, and visual effects.

`.sat` is designed independently of macOS frameworks (Swift/Metal/AppKit) so Windows and Linux runtimes can parse, deform, simulate, and render identical avatars.

---

## 2. Package Layout
```text
AvatarName.sat (ZIP archive)
├── manifest.json            # Required root descriptor & schema version
├── model.json               # Required textures, parts, and ordered drawables
├── rig.json                 # Required parameters, deformers, and bindings
├── physics.json             # Optional secondary motion solver config
├── textures/
│   └── *.png                # Straight-alpha RGBA PNG textures / atlases
├── meshes/
│   └── *.json               # Per-drawable triangular meshes
├── expressions/
│   └── *.json               # Additive/overwrite/multiply facial presets
├── animations/
│   └── *.json               # Keyframed idle / breathing motion clips
└── effects/
    └── *.json               # Declarative GPU miasma / aura / particle effects
```

---

## 3. Coordinate & Texture Convention
1. **Canvas Space**: Two-dimensional coordinates in **reference-canvas pixels** (`[0, canvas.width] × [0, canvas.height]`).
2. **Origin & Axes**: Top-left `(0, 0)`, `+X` pointing **right**, `+Y` pointing **down**.
3. **Normalized UVs**: `[0, 1] × [0, 1]`, `(0, 0)` at texture top-left, `(1, 1)` at texture bottom-right.
4. **Angle Sign**: Positive rotation degrees rotate **clockwise** in canvas (`+X right, +Y down`) space:
   - `x' = px + (x - px) * cos(θ) - (y - py) * sin(θ)`
   - `y' = py + (x - px) * sin(θ) + (y - py) * cos(θ)`
5. **Alpha Handling**: Textures MUST be stored as clean **straight-alpha RGBA PNG** with no solid matte background contamination. Renderers perform straight-to-premultiplied conversion and edge-bleed clamping so bilinear filtering produces zero white halos on black, green, white, or checkerboard backgrounds.
6. **Draw Order**: Floating-point `drawOrder` sorted ascending (lower draws first / behind; higher draws later / in front). Equal values preserve `model.json` declaration order.

---

## 4. Schema Versioning & Migration Rules
`manifest.json` MUST declare:
```json
{
  "format": "satella.avatar",
  "schemaVersion": "1.0.0"
}
```
- **Major version (`X.y.z`)**: Breaking structural change. Satella `1.x` rejects `major != 1` cleanly with a descriptive error.
- **Minor version (`1.Y.z`)**: Backward-compatible additions with documented defaults. Future `1.1+` runtimes apply explicit in-memory defaults (`alphaMode = "straight"`, missing `clipMasks = []`, missing `physics = null`).
- **Patch version (`1.0.Z`)**: Clarification/errata with identical runtime behavior.
- Deprecated aliases (`v1` without patch) are rejected strictly; always write full `SemVer` `"1.0.0"`.

---

## 5. Binary & Resource Integrity
- All JSON files MUST conform to `Schemas/*.schema.json` and UTF-8 without BOM issues.
- Floating-point arrays MUST contain finite numbers (`!isNaN && !isInfinite`).
- Mesh topology MUST contain `>= 3` vertices (`<= 65,535`), `triangles.count % 3 == 0` (`<= 300,000`), and every triangle index `< vertices.count`.
- `.sat` archives MUST NOT contain executable code, scripts, binaries, symlinks, or path traversal segments (`..` or leading `/`).
