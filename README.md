# SVStudio

**Open-Source Native macOS 2D VTuber Player (`.sat`)** — powered by **Apple Metal**, **Apple Vision**, **AVFoundation**, **CoreAudio**, and **CoreMediaIO**, with **VTube Studio** parameter compatibility and a standalone CLI toolchain (`svstudio-tool`).

> **Open Source (MIT):** SVStudio is released open source under the [MIT License](./LICENSE).
>
> **Avatar Separation Notice:** The bundled **SVStudio.app** and **SVStudio-1.0.0.dmg** ship **without** the Satella (`GothicWitch.sat`) avatar inside the app or disk image (only the lightweight [`Avatars/TestAvatar.sat`](./Avatars/TestAvatar.sat) sample avatar is bundled). For completeness, the standalone Satella avatar is hosted separately in this repository at [`SatellaAvatar/GothicWitch.sat`](./SatellaAvatar/GothicWitch.sat) and on the `v1.0.0` GitHub Release.

---

## Download & Signature Validation

### Ready-to-Run macOS DMG (`SVStudio-1.0.0.dmg`)

| Artifact | Purpose | Size | Location |
|---|---|---|---|
| **SVStudio-1.0.0.dmg** | Signed & verified macOS Disk Image (`SVStudio.app` + `TestAvatar.sat`) | `2,887,969` bytes (`2.8 MB`) | [Download via Release `v1.0.0`](https://github.com/macauleyjustin/SVStudio/releases/download/v1.0.0/SVStudio-1.0.0.dmg) · [Repo File](./SVStudio-1.0.0.dmg) |
| **SVStudio-1.0.0.dmg.sha256** | SHA-256 verification digest | `85` bytes | [Download Checksum](https://github.com/macauleyjustin/SVStudio/releases/download/v1.0.0/SVStudio-1.0.0.dmg.sha256) · [Repo File](./SVStudio-1.0.0.dmg.sha256) |
| **GothicWitch.sat** | Standalone Satella avatar (not inside app/DMG) | `1.9 MB` | [Download Avatar](https://github.com/macauleyjustin/SVStudio/releases/download/v1.0.0/GothicWitch.sat) · [`SatellaAvatar/GothicWitch.sat`](./SatellaAvatar/GothicWitch.sat) |

- **Bundle Identifier:** `dev.svstudio.player`
- **Architecture:** Apple Silicon (`arm64`, Mach-O thin binary)
- **DMG SHA-256:**
  ```text
  1969ce557a873a78bf3d0ae682b481c27b5185077f79917820d0409b0ea91389  SVStudio-1.0.0.dmg
  ```
- **DMG Verified CRC32:** `$5F3647B0` (`hdiutil verify`)

### Verify the Download & Signature Locally

```bash
# 1. Verify SHA-256 digest
shasum -a 256 -c SVStudio-1.0.0.dmg.sha256

# 2. Verify DMG code signature and APFS disk image integrity
codesign --verify --strict --verbose=2 SVStudio-1.0.0.dmg
hdiutil verify SVStudio-1.0.0.dmg

# 3. After dragging SVStudio.app to /Applications, verify the signed bundle
codesign --verify --deep --strict --verbose=2 /Applications/SVStudio.app
```

> **Gatekeeper & Signing Note:** The prebuilt binary and DMG in this release are **ad-hoc code-signed** (`Signature=adhoc`, strictly sealed resources & Designated Requirement verified) and are not notarized with an Apple Developer ID certificate. If macOS Gatekeeper blocks a browser-downloaded copy, clear the download quarantine attribute after verifying the SHA-256 checksum above (`xattr -cr /Applications/SVStudio.app`, or Right-Click -> Open). Maintainers with an Apple Developer ID certificate can pass `SVSTUDIO_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"` to `./Source/Packaging/build_dmg.sh`.

---

## System Requirements & What It Runs On

- **Operating System:** macOS `14.0` or later (`LSMinimumSystemVersion = 14.0`)
- **Processor:** Apple Silicon (`arm64`) for the packaged DMG, or build from source on macOS with **Swift 6** (`swift-tools-version: 6.0`)
- **Graphics & Rendering:**
  - **Apple Metal & MetalKit (`SatellaRender`)** real-time 2D deformed-mesh GPU renderer with premultiplied-alpha safety
  - Studio Dark, Chroma Green (`#00FF00`), White, Checkerboard, Transparent, and Custom canvas backgrounds
  - Declarative particle/ribbon effects (`miasma`, `aura_wisp`, `particles`) with facial exclusion boxes
- **Tracking & Audio:**
  - **Apple Vision & AVFoundation** local on-device webcam face, head rotation/position, eye blink/gaze, eyebrow, mouth, and toggleable facial emotion/expression detection (smoothed with One-Euro & critically damped filters; zero cloud calls)
  - **AVFoundation / CoreAudio / AudioToolbox** real-time microphone lip sync
  - *(Note: Hand tracking controls and webcam hand-gesture options have been removed from the SVStudio player UI while preserving the underlying parameter/IK types inside `SatellaCore` for extensibility.)*
- **Physics & Avatar Reactions:**
  - Symplectic Euler fixed-timestep (`60 Hz`) secondary motion (`pendulum` and `spring2d`) with built-in presets (`light_hair`, `heavy_fabric`, `soft_body`, `accessory`)
  - Optional per-avatar `"category": "breast"` physics intensity scaling and schema-driven canvas drag reactions (only active on avatars that define them)
- **Streaming & Broadcast Outputs:**
  - Dedicated **OBS Clean Feed** borderless output window (`OBSCleanWindow`) with independent Chroma Green / Transparent / Custom background
  - Direct **CoreMediaIO** zero-copy `IOSurface` virtual webcam sink streaming (`VirtualWebcamManager`), plus source for a dedicated `CMIOExtensionProvider` system extension in [`Source/CameraExtension/`](./Source/CameraExtension/)
- **Parameter Compatibility:**
  - Dynamic schema-driven parameter discovery from `rig.json` plus [`VTSParameterCatalog`](./Source/Sources/SatellaCore/Rig/VTSParameterRegistry.swift) mapping standard **VTube Studio** IDs (`FaceAngleX`, `FaceAngleY`, `FaceAngleZ`, `FacePositionX`, `MouthOpen`, `MouthSmile`, `EyeOpenLeft`, `BrowLeftY`, `CheekPuff`, `VoiceVolume`, etc.) and **Live2D Cubism** IDs (`ParamAngleX`, `ParamMouthOpenY`, `ParamMouthForm`, `ParamEyeLOpen`, etc.)

---

## Creating VTubers (`.sat` Avatars) for SVStudio

SVStudio loads self-contained **`.sat` (Satella Avatar Format `1.0.0`)** ZIP archives. Every `.sat` file is validated against strict archive/security rules (`ModelValidator` / `svstudio-tool validate`) before GPU upload — zero scripts or executable code live inside `.sat` packages.

### 1. Package Layout (`YourAvatar/`)

```text
YourAvatar/
├── manifest.json          # Metadata, canvas pixel size, schema "1.0.0", format "satella.avatar", feature flags
├── model.json             # Layer textures, drawable list, drawOrder, blend modes, clip masks
├── rig.json               # Parameters, hierarchical warp/rotation deformers, keyforms, mesh bindings
├── physics.json           # (Optional) Pendulum & 2D spring chains (hair, cloak, accessories, soft body)
├── textures/*.png         # Straight-alpha PNG textures per articulated part
├── meshes/*.json          # 2D triangulated polygon meshes matching texture UV/pixel coordinates
├── expressions/*.json     # (Optional) Additive/override facial expression presets
├── animations/*.json      # (Optional) Looping idle/breathing parameter animations
└── effects/*.json         # (Optional) Behind/above/foreground aura & particle layers
```

All specifications live in the root docs and formal schemas under [`Schemas/`](./Schemas/):

- [`SAT_AVATAR_CREATION_SPEC.md`](./SAT_AVATAR_CREATION_SPEC.md) — 8-step character production guide (artwork separation, seam painting, de-haloing, rigging, QA)
- [`SAT_FORMAT_SPEC.md`](./SAT_FORMAT_SPEC.md) — Package layout, coordinate space, SemVer rules
- [`SAT_RIGGING_SPEC.md`](./SAT_RIGGING_SPEC.md) — Standard parameter dictionary, 9-step frame evaluation order, warp & rotation math
- [`SAT_PHYSICS_SPEC.md`](./SAT_PHYSICS_SPEC.md) — `pendulum` / `spring2d` physics solver & `"category": "breast"` behavior
- [`SAT_EFFECTS_SPEC.md`](./SAT_EFFECTS_SPEC.md) — GPU particle/miasma layers & chroma-key alpha safety
- [`SAT_VALIDATION_SPEC.md`](./SAT_VALIDATION_SPEC.md) — Security limits & schema validation pipeline
- [`AI_AVATAR_GENERATION_PROMPT.md`](./AI_AVATAR_GENERATION_PROMPT.md) — Reusable prompt template for generating `.sat` assets cleanly from character sheets
- [`Schemas/`](./Schemas/) — JSON Schemas (`manifest`, `model`, `rig`, `physics`, `mesh`, `expression`, `animation`, `effects`)

### 2. Step-by-Step Creation Workflow

1. **Separate Layers on a Unified Canvas:** Draw the character facing forward in a neutral pose (`manifest.json` `canvas: { width, height }`) with clean transparent cutouts (`body_torso`, `body_neck`, `face_base`, `mouth_atlas`, eyes, front/back hair, clothing pieces). Paint hidden overlap behind neck/hair/clothing so nothing separates during head or body movement, and strip white fringes with straight-alpha de-haloing.
2. **Generate Contour Delaunay Meshes with `svstudio-tool`:**
   ```bash
   ./Tools/svstudio-tool automesh textures/face_base.png \
     --id mesh_face_base \
     --texture face_base \
     --out meshes/face_base.json
   ```
3. **Define Parameters & Hierarchical Deformers (`rig.json`):** Bind leaf-to-root `rotation` and `warp` deformers to standard IDs such as `ParamAngleX` / `ParamAngleY` / `ParamAngleZ` (or `FaceAngleX/Y/Z`), `ParamMouthOpenY` (`MouthOpen`), `ParamMouthForm` (`MouthSmile`), `ParamBodyAngleX/Y/Z`, and `ParamBreath`, plus any custom physics or drag parameters.
4. **Add Physics, Expressions & Effects:** Declare `pendulum` or `spring2d` groups in `physics.json`, expression presets (`happy`, `sad`, `angry`, `surprised`, etc.) in `expressions/*.json`, and optional particle layers in `effects/*.json`.
5. **Pack, Validate & Inspect Offline Before Opening in SVStudio:**
   ```bash
   # Package folder into a .sat archive
   ./Tools/svstudio-tool pack YourAvatar/ -o Avatars/YourAvatar.sat

   # Run full security + structural + referential integrity validator (require 0 errors)
   ./Tools/svstudio-tool validate Avatars/YourAvatar.sat

   # Inspect summary of parameters, meshes, physics groups, expressions
   ./Tools/svstudio-tool inspect Avatars/YourAvatar.sat

   # Render offline Metal frame against checkerboard / green / black / transparent
   ./Tools/svstudio-tool render Avatars/YourAvatar.sat --out /tmp/preview.png --background checkerboard

   # Run multi-pose QA renders (head turns, mouth shapes, expressions, settled physics)
   ./Tools/svstudio-tool test Avatars/YourAvatar.sat --out-dir /tmp/qa_poses
   ```
6. **Load in SVStudio:** Open `SVStudio.app` and click **Open .sat**, **Import**, or drag and drop `YourAvatar.sat` directly onto the canvas (or place it in `~/Library/Application Support/SVStudio/Avatars/`).

---

## Building From Source & Running Tests

Requirements: macOS 14+ with Xcode / Swift 6 toolchain (`Source/Package.swift`).

```bash
# Build all Swift targets (SatellaCore, SatellaRender, svstudio-tool, SVStudio, satella-tests)
swift build --package-path Source

# Build signed SVStudio.app (bundles TestAvatar.sat only, no Satella/GothicWitch)
./Source/Packaging/build_app.sh

# Build signed & verified SVStudio-1.0.0.dmg + SVStudio-1.0.0.dmg.sha256
./Source/Packaging/build_dmg.sh

# Run full unit, CLI, security, Metal, GUI launch, and DMG verification acceptance suite
zsh ./Tests/run_acceptance_tests.sh
```

---

## Repository Structure

```text
├── README.md                          # Front-page project guide, download, & avatar guide
├── LICENSE                            # MIT open-source license
├── SVStudio-1.0.0.dmg                 # Signed & verified release DMG (without GothicWitch.sat)
├── SVStudio-1.0.0.dmg.sha256          # SHA-256 digest for SVStudio-1.0.0.dmg
├── Avatars/
│   └── TestAvatar.sat                 # Bundled sample avatar ("Starlight Spirit (Test)")
├── SatellaAvatar/
│   └── GothicWitch.sat                # Standalone Satella avatar (kept outside app & DMG)
├── Tools/
│   └── svstudio-tool                  # Prebuilt macOS CLI utility
├── Schemas/                           # JSON Schemas for .sat format components
├── Tests/
│   └── run_acceptance_tests.sh        # End-to-end build, core test, Metal & DMG acceptance suite
└── Source/                            # Swift 6 Package (SatellaCore, SatellaRender, SVStudio, Packaging)
```

---

## License

This project is open-source software licensed under the [MIT License](./LICENSE).
