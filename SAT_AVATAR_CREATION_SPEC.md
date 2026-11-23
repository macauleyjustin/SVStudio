# `.sat` Avatar Creation Specification (AI & External Producer Guide)

This document defines the standardized external workflow for creating **`.sat` (Satella Avatar Format)** avatars for **SVStudio** without touching `SVStudio.app` source code.

---

## Step-by-Step Pipeline

### 1. Establish the Master Neutral Illustration
- Fix exact reference canvas pixel dimensions `(W, H)` (top-left origin `(0,0)`, `+X` right, `+Y` down).
- Establish neutral rest pose: head centered facing forward, neutral relaxed expression, arms symmetrical, clear separation between background and silhouette.

### 2. Separate Independent Movable Components
Divide the character cleanly into back-to-front drawables:
- Background effects / rear cloak / rear hair
- Legs / stockings / footwear
- Neck, torso, upper arms, forearms, hands (separate left/right!)
- Bodice / front skirt / hip ornaments
- Head & face base
- Mouth system (`MouthInterior`, `UpperLip`, `LowerLip`, `MouthTeeth`, `MouthTongue`, `MouthLine`, `MouthCover`) — kept **invisible/opacity=0 when closed (`ParamMouthOpenY = 0`)** so zero double mouths appear!
- Eyes (`EyeWhite`, `Iris`, `Highlight`, `UpperEyelid`, `Eyelash`) if visible, OR `concealedEyes: true` + `HoodShadow` if veiled!
- Front hair strands (`HairSideL`, `HairSideR`, `HairBangs`)
- Headgear / hood / crown / accessories / foreground effects

### 3. Reconstruct Hidden Painted Regions
Paint beneath every overlapping seam so deformation never exposes blank gaps:
- Neck beneath chin & collar
- Upper chest beneath hair & throat ornaments
- Inner thigh & back cloak behind stockings & skirt hems
- Mouth skin interior behind `MouthCover` / `Face_Base`
- Forearms & upper arms extending cleanly into sleeves/shoulder joints

### 4. Clean Alpha & Remove Edge Halos (`straight` Alpha)
- Strip all white/black background pixels using floodfill + color decontamination (un-premultiply semi-transparent edge pixels against local background matte RGB so boundary pixels keep true pigment color at low alpha!).
- Inspect every separated layer against **black, green (`#00FF00`), white, and checkerboard** backgrounds. Zero white halos or stray matte islands allowed.

### 5. Build Contour-Following Triangular Meshes
- Never use raw 4-corner quads for bendable organic art (hoods, hair, faces, mouths, cloaks, skirts)!
- Sample tight outer margin points (`4–12px` outside art contour), interior edge ring, and uniform interior lattice -> **Constrained Delaunay Triangulation**, pruning triangles wholly outside the padded alpha envelope.
- Export `meshes/<id>.json` with `vertices` in exact reference-canvas pixels and `uv` in `[0, 1]` matching the layer's texture or atlas placement.

### 6. Build the Hierarchical Rig (`rig.json`)
- Map tracking to standard IDs (`ParamAngleX/Y/Z`, `ParamMouthOpenY`, `ParamMouthForm`, `ParamBodyAngleX/Y/Z`, `ParamBreath`, plus `ParamEyeLOpen`/`ParamEyeROpen` if eyes are visible).
- Author smooth `rotation` deformers at anatomical joints (`body_rot` at pelvis/hips, `head_rot` at neck base, optional arm/shoulder/elbow pivots) and `warp` deformers (`head_warp`, `hood_warp`, `torso_warp`, `hair_*_warp`, `cloak_*_warp`) using multi-point keyforms.
- Author `meshBindings` for delicate facial features (smooth 11+ emotional & speaking mouth shapes across `ParamMouthOpenY × ParamMouthForm`).

### 7. Author Expressions, Animations, Physics & Effects
- Create `expressions/*.json` (`neutral`, `happy`, `sad`, `angry`, `surprised`, etc.).
- Create `animations/idle.json` (looping gentle `ParamBreath` + micro body sway).
- Configure `physics.json` (`light_hair`, `heavy_fabric`, `accessory`, and optional `"category": "breast"` with restrained `soft_body` spring2d damping).
- Optionally configure `effects/*.json` (declarative miasma / aura / particles with `exclusionBoxes` around the face).

### 8. Pack, Validate, Render & QA Externally
Run the headless external CLI:
```bash
./Tools/svstudio-tool pack CharacterFolder/ -o Avatars/Character.sat
./Tools/svstudio-tool validate Avatars/Character.sat
./Tools/svstudio-tool render Avatars/Character.sat --out /tmp/qa.png --background checkerboard
./Tools/svstudio-tool test Avatars/Character.sat --out-dir /tmp/qa_poses
```
Inspect ALL rendered PNGs across backgrounds (`black`, `green`, `white`, `checkerboard`) and parameter extremes (`AngleX/Y/Z`, `MouthOpenY/Form`, expressions, physics, miasma). Fix any visual artifacts BEFORE shipping `.sat` to users!
