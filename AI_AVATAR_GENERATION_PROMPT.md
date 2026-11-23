# Reusable Prompt Template: External AI Avatar Creation for SVStudio (`.sat`)

Copy and provide this prompt together with a **character reference image**, `SAT_FORMAT_SPEC.md`, `SAT_RIGGING_SPEC.md`, `SAT_PHYSICS_SPEC.md`, `SAT_EFFECTS_SPEC.md`, `SAT_AVATAR_CREATION_SPEC.md`, `Schemas/*.schema.json`, and `./Tools/svstudio-tool`:

---

```markdown
# TASK: CREATE A COMPLETE `.sat` VTUBER AVATAR PACKAGE

You are an external character production agent building a standalone `.sat` avatar compatible with **SVStudio** (`SVStudio.app`). You will NOT modify SVStudio's application source code.

## INPUTS PROVIDED
1. Character reference image(s).
2. The `.sat` Format Specifications (`SAT_FORMAT_SPEC.md`, `SAT_RIGGING_SPEC.md`, `SAT_PHYSICS_SPEC.md`, `SAT_EFFECTS_SPEC.md`, `SAT_AVATAR_CREATION_SPEC.md`) and JSON schemas in `Schemas/`.
3. External CLI utility: `svstudio-tool` (`pack`, `validate`, `inspect`, `render`, `test`, `automesh`).

## OUTPUT DELIVERABLE
A validated, self-contained `<CharacterName>.sat` ZIP archive containing:
- `manifest.json` (`format: "satella.avatar"`, `schemaVersion: "1.0.0"`, canvas dimensions, `features`)
- `model.json` (ordered parts, drawables, straight-alpha PNG texture references)
- `rig.json` (standard parameters + custom physics parameters, acyclic rotation & warp deformer tree, multi-axis keyforms, vertex/mesh bindings)
- `physics.json` (fixed-timestep pendulum / spring2d physics for hair, clothing, accessories, and optional `"category": "breast"` if appropriate)
- `textures/*.png` (alpha-cleaned straight-alpha PNGs with zero white background halos or jagged cutouts; edge-decontaminated against black/green/white/checkerboard)
- `meshes/*.json` (contour-following Delaunay triangle meshes in top-left canvas pixel coords matching every layer's artwork)
- `expressions/*.json` (`neutral`, `happy`, `sad`, `angry`, `surprised`, plus character-specific expressions)
- `animations/idle.json` (smooth looping breathing / idle clip)
- `effects/*.json` (optional declarative GPU aura/miasma/particles with face `exclusionBoxes`)

## MANDATORY TECHNICAL RULES
1. **Coordinate System**: All vertices, pivots, and warp bounds MUST use reference-canvas pixels: origin `(0,0)` at top-left, `+X` right, `+Y` down; UVs `[0, 1]`.
2. **Standard Parameters**: Map tracking parameters using `ParamAngleX`, `ParamAngleY`, `ParamAngleZ`, `ParamMouthOpenY`, `ParamMouthForm`, `ParamBodyAngleX`, `ParamBodyAngleY`, `ParamBodyAngleZ`, `ParamBreath`, and (`ParamEyeLOpen`, `ParamEyeROpen`, `ParamEyeBallX`, `ParamEyeBallY` if eyes are visible; set `features.concealedEyes: true` if veiled/covered).
3. **Zero Double Mouths / Rigid Boxes**: Mouth interior/teeth/tongue/lips MUST stay hidden (`opacity: 0`) at `ParamMouthOpenY = 0` and deform smoothly across `ParamMouthOpenY × ParamMouthForm` with real mesh triangulation (minimum 20+ vertices per deformable limb/hood/hair/cloak panel; finer triangles on face & mouth).
4. **No White Halos**: Decontaminate semi-transparent border RGB before writing PNGs. Never flatten onto a white matte.
5. **Restraint & Physics**: Hair (`light_hair`), heavy garments (`heavy_fabric`), accessories (`accessory`), and optional chest physics (`"category": "breast"`, `soft_body` preset) MUST be damped so everything settles cleanly to `0` at rest.

## VERIFICATION WORKFLOW (DO NOT SKIP)
1. Run `svstudio-tool pack <WorkFolder>/ -o <CharacterName>.sat`.
2. Run `svstudio-tool validate <CharacterName>.sat` and ensure ZERO errors.
3. Run `svstudio-tool render <CharacterName>.sat --out <CharacterName>_green.png --background green` (and `black` / `checkerboard`) to visually inspect alpha cleanliness.
4. Run `svstudio-tool test <CharacterName>.sat --out-dir <QAFolder>/` to verify head turns (`AngleX/Y/Z`), mouth shapes (`MouthOpenY × MouthForm`), expressions, and physics settling.
5. Visually inspect every rendered image and iterate until free of halos, seams, clipped limbs, or distorted anatomy.
```
