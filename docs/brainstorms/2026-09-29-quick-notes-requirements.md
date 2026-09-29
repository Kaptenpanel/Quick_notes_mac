---
date: 2026-09-29
topic: quick-notes
---

# Quick Notes for Mac

## Summary

A native Mac app, built and installed locally, where a global hotkey opens a new note in a single always-on-top window: note list in a left sidebar, editor on the right. Notes autosave and persist; closing the window hides it while the app keeps running so the hotkey stays live.

---

## Problem Frame

The user wants fast note capture on an Intel Mac (macOS 26.3), similar to Windows Sticky Notes / OneNote Quick Note. Attempts so far have failed:

- Plume could not be installed because the Mac App Store is not working on this machine.
- Apple Notes' Quick Note shortcut does nothing when triggered; Notes only creates regular notes inside the full app.

As a result the user currently has no quick-capture habit or place for quick notes at all. The cost is friction: any thought worth jotting requires opening a full app and navigating to a new note, so it doesn't happen.

---

## Requirements

**Capture**
- R1. A global keyboard shortcut, working from any app, creates a new empty note and shows the window with the cursor in that note, ready to type.
- R2. Default shortcut avoids the Globe/Fn key (e.g., ⌥⌘N). Exact default chosen in planning to avoid common conflicts.

**Window**
- R3. The app has one window: note list on the left, editor for the selected note on the right.
- R4. The window floats above other apps' windows by default.
- R5. A pin toggle in the window turns floating on/off; the choice persists across launches.
- R6. The window can be minimized and closed. Closing hides the window; the app keeps running in the background and the hotkey still works.
- R7. Quitting the app (menu or ⌘Q) fully exits it.

**Notes**
- R8. Multiple notes supported. The list shows each note titled by its first line, newest first.
- R9. Selecting a note in the list opens it in the editor.
- R10. Notes are plain text.
- R11. Notes save automatically while typing — no save action — and survive app quit, crash, and reboot.
- R12. A note can be deleted. No undo/trash in v1.

**Install & launch**
- R13. App is built locally and installed into Applications without the App Store.
- R14. App launches automatically at login so the hotkey is always available.

---

## Acceptance Examples

- AE1. **Covers R1, R6.** Given the window is closed and another app is focused, when the user presses the hotkey, the window appears on top with a new empty note, cursor ready.
- AE2. **Covers R1, R6.** Given the window is minimized, when the user presses the hotkey, the window restores and a new note is created.
- AE3. **Covers R4, R5.** Given pin is on, when the user clicks into another app, the notes window stays visible above it. Given pin is off, the other app's window can cover it.
- AE4. **Covers R11.** Given the user types into a note and then quits (or the Mac restarts), when the app reopens, the note text is intact.
- AE5. **Covers R8.** Given a note's first line is "groceries", the list shows "groceries" as its title. Given an empty note, the list shows a placeholder title.

---

## Success Criteria

- User can go from any app to typing a note in under ~2 seconds with one shortcut.
- User actually keeps notes in it day to day — notes accumulate in the list.
- Nothing typed is ever lost.
- Planning can proceed without inventing window, hotkey, save, or close behavior.

---

## Scope Boundaries

- Separate floating sticky window per note (possible later "pop out" feature)
- Colors, rich text formatting, images
- Search
- iCloud sync, iPhone/iPad access
- Import from Apple Notes
- App Store distribution, notarization or signing for other users
- Undo/trash for deleted notes

---

## Key Decisions

- One floating window with sidebar (over sticky windows or menu bar app): matches the user's description and Plume's shape; least complexity.
- Close hides, doesn't quit: hotkey must keep working.
- Hotkey avoids Globe key: Globe-based Quick Note shortcut didn't work for the user.
- Plain text only: smallest version that delivers daily value.
- Launch at login: capture must be available without remembering to open the app.

---

## Dependencies / Assumptions

- Xcode and Swift 6.3 are installed (verified: `/Applications/Xcode.app`), so a native app can be built locally.
- Target machine: Intel (x86_64), macOS 26.3.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R1][Technical] Whether a global hotkey needs a macOS permission prompt (e.g., Accessibility) and how to guide the user through it.
- [Affects R2][Technical] Final default shortcut, checked against common system/app conflicts.
- [Affects R6][Technical] Whether to show a Dock icon, menu bar icon, or both while the window is hidden.
- [Affects R13][Technical] Local signing needed for the app to launch cleanly and keep permissions across rebuilds.
