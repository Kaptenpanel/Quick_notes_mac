# Quick Notes

A floating quick-notes window for macOS. Press **⌃⌥N** (Control-Option-N) from any app and a new note opens, ready to type.

- Your notes are listed on the left, and the editor is on the right.
- Click **Pin** above the editor to keep the window on top of other apps; click **Unpin** to stop. To pin a note to the top of the list, right-click it.
- Notes save automatically as you type.
- Closing the window only hides it. The app keeps running, so the shortcut still works. Use ⌘Q to quit.
- Quick Notes opens automatically when you log in, hidden until you press the shortcut.

## Install

Requires macOS 14 or later and Xcode (or the Swift toolchain).

```bash
./scripts/build-app.sh
```

This builds the app, signs it for this Mac, installs it to `/Applications/QuickNotes.app`, and opens it. Run the same command again to update. Your notes are stored separately, so reinstalling never touches them.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌃⌥N | New note from any app (reuses an empty note if one exists) |
| ⇧⌘S | Drag across part of the screen from any app; its text becomes a new note. Esc cancels. Needs Screen Recording permission, which you may have to turn on again after rebuilding |
| ⌘N | New note (while the window is active) |
| ⌘W | Hide the window |
| ⌘M | Minimize |
| Delete | Delete the selected note (while the list is focused) |
| ⌘Q | Quit |

Deleting a note that has text asks you to confirm first. Empty notes are deleted immediately, and are also removed automatically when you leave them.

## Change the shortcut

Edit `HotKeyConfig` in `Sources/QuickNotes/HotKey.swift`, then run `./scripts/build-app.sh` again. Key codes are the `kVK_*` constants, and modifiers are `controlKey`, `optionKey`, `cmdKey` and `shiftKey`.

The shortcut must include Control or Command. macOS 15 and later rejects shortcuts that use only Option or only Option+Shift.

If another app already uses the shortcut, Quick Notes shows a message when it launches.

## Where notes live

- Notes: `~/Library/Application Support/QuickNotes/notes.json`
- Backup of the previous session: `notes.json.bak` in the same folder
- If the notes file is ever damaged, it's moved aside as `notes.corrupt-<date>.json` rather than overwritten, and the last backup is kept as `notes.corrupt-<date>.bak`. You'll see an alert with a "Show in Finder" button.
- If a save fails (for example, the disk is full), a red banner appears in the window and saving keeps retrying. Quitting while notes are unsaved asks you first.
- If the notes file can't be read at all, editing is turned off, so you can't type anything that can't be saved.

## Stop opening at login

Go to System Settings → General → Login Items and turn off Quick Notes. It won't turn itself back on.

If Quick Notes doesn't appear in Login Items after the first launch, add `/Applications/QuickNotes.app` there manually with the + button.

## Development

```bash
swift build                              # debug build
./scripts/build-app.sh --no-install      # build build/QuickNotes.app without installing
```

### Keeping builds fast

Most of a slow (1–2 minute) build is the compiler re-caching Apple's frameworks, not compiling this app. `build-app.sh` keeps that cache in `~/Library/Caches/QuickNotes/ModuleCache`, outside `.build`, so after the first build:

- Don't wipe it. Deleting `.build` is fine: the next build takes about 15 seconds instead of a full cold build. Delete the cache folder only if you want to reset it. Don't copy or move it, because it only works at its original path.
- Expect one slow build after adding a new framework import (for example `import Vision`) or after an Xcode update. That's a one-time cost.
- Plain `swift build`, `swift run` and the editor's indexing each keep their own separate cache, so they pay the same cost again. Let editor indexing finish before running `build-app.sh`, and use the script for app builds.
- Other heavy work on the Mac, such as a virtual machine, can easily double build times.

Quit the installed app before running a development build with `swift run`. Otherwise both copies write the same notes file and compete for the shortcut.
