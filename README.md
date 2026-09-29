# Quick Notes

A floating quick-notes window for macOS. Press **⌃⌥N** (Control-Option-N) from any app and a new note opens, ready to type.

- Your notes are listed on the left, and the editor is on the right.
- Type in the search field above the list to show only notes containing that text (capitals and accents are ignored). Creating a new note clears the search.
- The window appears on every desktop (Space), so switching desktops never hides your notes.
- The window stays on top of other windows. Click the pin button in the editor's top-right corner to turn that off.
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
| ⌘N | New note (while the window is active) |
| ⌘W | Hide the window |
| ⌘M | Minimize |
| ↑ / ↓ | Move between notes (while the list is focused) |
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
swift test    # core logic tests
swift build   # debug build
```

Quit the installed app before running a development build with `swift run`. Otherwise both copies write the same notes file and compete for the shortcut.

`swift run` has no app bundle, so it shows Courier New instead of Courier Prime and the default icon. Use `./scripts/build-app.sh --no-install` to build `build/QuickNotes.app` with fonts and icon without installing it.

## Fonts and icon

- The interface uses [Courier Prime](https://github.com/quoteunquoteapps/CourierPrime), bundled in `Resources/Fonts` under the SIL Open Font License (`Resources/Fonts/OFL.txt`). The app registers it at launch.
- The app icon is `Resources/AppIcon.icns`, generated from `docs/export/1c-logo/quicknotes-icon-light-160.svg`.
