# Satella Virtual Camera Extension (`CMIOExtensionProvider`)

This folder contains the complete native Swift `CMIOExtensionProvider` system extension source (`SatellaCameraProvider.swift` + `Info.plist`) enabling **"Satella Virtual Camera"** across Zoom, Chrome, Discord, FaceTime, and Photo Booth.

## How Satella Virtual Webcam Works in `Satella.app`

1. **Direct CoreMediaIO Sink Streaming (Works Out-of-the-Box Today):**
   Inside `Satella.app` (**Output -> Virtual Webcam**), `VirtualWebcamManager` uses Apple's documented CoreMediaIO Sink APIs (`CMIODeviceStartStream`, `CMIOStreamCopyBufferQueue`, `CMSimpleQueueEnqueue` with zero-copy `IOSurface`-backed `CVPixelBuffer`s) to push live Metal frames straight into any enabled macOS Virtual Camera Extension on your Mac (for example **OBS Virtual Camera** once enabled under *System Settings -> General -> Login Items & Extensions -> Camera Extensions* — OBS Studio itself does not need to stay running or screen-capture a window once the extension is enabled!).

2. **Dedicated `"Satella Virtual Camera"` Extension (Developer ID Build):**
   Because macOS System Integrity Protection (`sysextd`) strictly requires an Apple Developer Team provisioning profile with `com.apple.developer.system-extension.install`, an ad-hoc build cannot activate its own `.systemextension` without a Developer ID certificate. With an Apple Developer ID + Team identifier (`TEAM_ID`):
   - Compile `SatellaCameraProvider.swift` against `CoreMediaIO.framework`, `CoreMedia.framework`, `CoreVideo.framework`, `IOKit.framework` into `dev.satella.camera.extension.systemextension`.
   - Embed under `Satella.app/Contents/Library/SystemExtensions/` and sign both host app (`com.apple.developer.system-extension.install`) and extension (`com.apple.security.app-sandbox`) with your Apple provisioning profile.
