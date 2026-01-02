# CoolQuickNote

A lightweight sticky note app for macOS that feels as simple as a real paper sticky note.

## Overview

CoolQuickNote is designed for speed, simplicity, and zero cognitive overhead. Unlike Apple's built-in Sticky Notes app, which can feel overly complicated for quick thoughts, CoolQuickNote gets out of your way—you open it, write something, and you're done.

## Features

- **Single note with auto-save**: One note that's always there when you need it
- **Always-on-top by default**: Optional floating window behavior
- **Font choices**: Switch between regular and handwritten-style fonts
- **Adjustable font size**: 10pt to 32pt range
- **Color options**: Classic yellow plus pink, blue, green, purple, and orange backgrounds
- **Minimal UI**: Clean interface that feels like a physical sticky note

## Requirements

- macOS 13.0 or later

## Building

1. Open `CoolQuickNote.xcodeproj` in Xcode
2. Build and run (⌘R)

## Usage

1. Launch the app—your note is ready
2. Start typing (auto-focuses on launch)
3. Click the gear icon to customize:
   - Font style (Regular/Handwritten)
   - Font size
   - Background color
   - Always-on-top toggle
4. Close the app when done—your note auto-saves

## Design Philosophy

CoolQuickNote embraces simplicity:
- No folders or organization overhead
- No formatting decisions to make
- No login or sync complexity
- Just thoughts in, thoughts saved, brain free again

## Technical Details

Built with SwiftUI for macOS, using:
- `@AppStorage` for automatic persistence
- Custom window styling for sticky note appearance
- Floating window level for always-on-top behavior

## License

Copyright © 2026. All rights reserved.
