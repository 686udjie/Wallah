# Wallah

A macOS wallpaper engine that plays video files behind your desktop icons 

## Building

To build the app and generate a `.dmg` installer, run this in the `Wallah` directory:

```bash
xcodebuild -scheme Wallah -configuration Release SYMROOT="$(PWD)/build" && hdiutil create -volname Wallah -srcfolder build/Release/Wallah.app -ov -format UDZO build/Wallah.dmg
```

**FUCK APPLE FOR NOT DOING THIS NATIVELY**