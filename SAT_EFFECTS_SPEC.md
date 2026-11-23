# `.sat` Visual Effects Specification (`1.0.0`)

## 1. Purpose
`effects/*.json` defines declarative animated GPU particle/ribbon/aura layers (such as dark purple witch miasma) without executable scripts or shaders embedded in `.sat` packages.

---

## 2. Layer Placement & Ordering
- **`behind_avatar`**: Rendered immediately after the background clear, before the lowest avatar drawable (`drawOrder` back cloak/back hair). Ideal for deep swirling silhouette miasma.
- **`above_cloak`**: Rendered behind the front torso/face drawables or blended softly around peripheral regions.
- **`foreground`**: Rendered after the avatar drawables (subtle floating ember/wisps outside `exclusionBoxes`).

---

## 3. Declarative Parameters (`Schemas/effects.schema.json`)
- **`kind`**:
  - `"miasma"`: Large soft multi-lobed curling smoke billows with slow upward drift and sinusoidal vortex swirl.
  - `"aura_wisp"`: Elongated vertical mystic energy ribbons with soft tip fade.
  - `"particles"`: Crisp drifting spores/motes with twinkle curve.
- **`regions`**: Spawn rectangles `[{ x, y, width, height, weight }]` in canonical canvas space.
- **`exclusionBoxes`**: Rectangles `[x, y, width, height]` (e.g., around `Face_Base` and `Dress_Bodice`) where particle alpha softly attenuates so miasma NEVER obscures facial expressions or core costume detail.
- **`colors`**: Gradient RGBA stops `[r, g, b, a]` over particle normalized age `0 -> 1`.
- **`intensityParam`**: Optional rig parameter (e.g., `ParamMiasmaIntensity`) scaling layer opacity & swirl energy at runtime.
- **`followDeformer`**: Optional deformer ID (e.g. `deformer_body_root`) so aura anchors shift naturally as the avatar leans.

---

## 4. Chroma-Key & Alpha Safety (`chromaSafe: true`)
Naive GPU additive blending (`SRC + DST`) over solid green `#00FF00` pushes semi-transparent purple highlights toward desaturated cyan/white halos during OBS chroma keying.
When `blendMode` is `"alpha"` (or `"additive"` with `chromaSafe: true`), `RenderEngine` renders effects into the avatar's premultiplied offscreen RGBA surface first or uses balanced premultiplied alpha composition (`ONE, ONE_MINUS_SRC_ALPHA`) before compositing over `#00FF00` chroma green or solid `#000000` black, keeping purple miasma rich and chroma-keyable.
