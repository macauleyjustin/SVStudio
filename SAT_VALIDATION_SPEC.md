# `.sat` Validation & Security Specification (`1.0.0`)

Every `.sat` package is treated as **untrusted external input**. Both `SVStudio.app` (`ModelValidator`) and `svstudio-tool validate` run the same strict validation pipeline before loading GPU assets.

---

## 1. Archive & Path Security Checks
1. Archive size `<= 512 MB`, entry count `<= 4,096`.
2. Every ZIP entry path MUST:
   - Use relative POSIX paths (`manifest.json`, `textures/face.png`).
   - Contain NO leading `/`, NO Windows drive prefixes (`C:`), NO `..` traversal components, NO NUL bytes, and NO symlink external attributes.
   - Contain NO executable extensions (`.sh`, `.py`, `.js`, `.command`, `.dylib`, `.so`, `.exe`, `.app`, `.bin`).
3. Decompression bomb defense:
   - Single entry uncompressed size `<= 128 MB`.
   - Total archive uncompressed size `<= 768 MB`.
   - Entry compressed->uncompressed inflation ratio checked dynamically while streaming (`> 100:1` rejected for entries `> 1 MB`).
4. Zero embedded scripts, plugins, or dynamic code are ever evaluated.

---

## 2. Structural & Schema Checks
- `manifest.json` MUST exist, parse as valid UTF-8 JSON, match `format == "satella.avatar"`, and declare supported `SemVer` major version `1`.
- Referenced `model`, `rig`, `physics`, `expressions`, `animations`, and `effects` paths MUST exist inside the ZIP.
- All JSON files MUST contain zero `NaN` / `Infinity` numeric tokens and strictly valid key types.

---

## 3. Texture Integrity Checks
- Every texture referenced by `model.json` or any `meshes/*.json` MUST exist in the archive, decode as a valid PNG image with real alpha channel or valid color type, match declared width/height (`1 <= width, height <= 8192`), and satisfy `width * height <= 67,108,864`.
- Validator issues warnings if any drawable references an unknown texture ID or exceeds texture UV `[0, 1]` bounds significantly.

---

## 4. Mesh & Topology Checks
- `vertices.count >= 3` and `<= 65,535`; all `[x, y]` coordinates finite.
- `uv.count == vertices.count`; finite UV pairs.
- `triangles.count >= 3`, `triangles.count % 3 == 0`, `triangles.count <= 300,000`.
- Every index `idx` satisfies `0 <= idx < vertices.count`.
- No degenerate self-referencing `clipMasks` loops.

---

## 5. Rig & Physics Referential Integrity
- `rig.parameters` MUST have unique IDs and `min <= default <= max` (with finite bounds).
- Every deformer `parent` MUST exist in `rig.deformers`; parent-child graph MUST be **strictly acyclic** (cycles rejected with exact cycle path in the error report!).
- Every `warp` deformer MUST define `rows >= 1`, `cols >= 1`, positive `bounds`, and `(rows + 1) * (cols + 1)` points per `gridOffsets` keyform.
- Every bound `axes[i].parameter` MUST exist in `rig.parameters`, `axes[i].keys` strictly ascending, and `keyforms.count == Π axes[i].keys.count` (or `1` if unbound).
- Every `meshBindings[k].vertexDeltas` (when present) MUST match `vertices.count` of target `meshId`.
- Every `physics.json` input/output parameter ID MUST resolve cleanly in `rig.parameters`, `fixedTimestep > 0`, `nodes.count >= 2` for pendulums, `stiffness > 0`, `damping >= 0`.
