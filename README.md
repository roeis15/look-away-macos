# LookAway

A lightweight native macOS menu-bar utility built with **SwiftUI** and **AppKit** to encourage scheduled screen breaks and reduce eye and screen fatigue without heavy system overhead.

> **Platform Note:** Built specifically for **macOS** (uses `AppKit`, `NSWorkspace`, and `SMAppService`).

## Overview
LookAway runs as a background accessory in the macOS menu bar and presents a full-screen break screen at the configured interval, with controls for focus/break durations, pause/resume, launch at login, and quick dismissal (`ESC`).

## Key Capabilities
- **Menu-Bar Accessory:** Runs as an accessory app (`NSApp.setActivationPolicy(.accessory)`) with a status bar item (`NSStatusItem`) and settings window.
- **Full-Screen Break Overlay:** Displays a borderless `NSWindow` configured at `.screenSaver` level across spaces, with a countdown timer and keyboard handling (`ESC`).
- **System State Awareness:** Observes `NSWorkspace` sleep and wake notifications to reset/manage timers accurately when the Mac sleeps or wakes.
- **Login Item Support:** Uses `SMAppService.mainApp` to register or unregister launch-at-login behavior.
- **Local Notifications:** Requests notification permissions via `UserNotifications` to send a 15-second warning before break time starts.

## Tech Stack
- **Swift**
- **SwiftUI** & **AppKit**
- **Combine** & **ServiceManagement** (`SMAppService`)
- **UserNotifications**

## Repository Structure
- `LookAway XCODE/LookAway/LookAwayApp.swift` – App entry point, `AppDelegate`, window/overlay management, and `TimerManager`.
- `LookAway XCODE/LookAway/ContentView.swift` – Views/components in the Xcode project.
- `LookAway XCODE/LookAway/Assets.xcassets/` – App icons and visual assets.

## Running Locally
1. Clone the repository:
   ```bash
   git clone [https://github.com/roeis15/look-away-macos.git](https://github.com/roeis15/look-away-macos.git)
   cd look-away-macos
