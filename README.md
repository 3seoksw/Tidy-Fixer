<p align="center">
  <img src="Design/TidyFixer-icon.png" width="128" alt="Tidy Fixer icon">
</p>

<h1 align="center">Tidy Fixer</h1>

<p align="center">
  A private macOS menu-bar app that fixes grammar and awkward phrasing with small edits, so the message still sounds like you.<br>
  It runs on a local model through <a href="https://ollama.com">Ollama</a>, so your drafts stay on your Mac.
</p>

## Screenshots

### Tidy Fixer Bar

<p align="center">
  <img width="747" height="115" alt="Screenshot 2026-11-15 at 3 46 35 AM" src="https://github.com/user-attachments/assets/58588206-16fd-4fbf-8090-573ff0fe074c" />
  <img width="739" height="120" alt="Screenshot 2026-11-15 at 3 50 24 AM" src="https://github.com/user-attachments/assets/3252d004-922d-45cc-81f1-a8bf025f642d" />
</p>

### Settings

<p align="center">
  <img width="904" height="653" alt="Screenshot 2026-11-15 at 3 51 01 AM" src="https://github.com/user-attachments/assets/4e468b79-b892-4330-9692-a90738ee1f65" />
  <img width="895" height="645" alt="Screenshot 2026-11-15 at 3 51 32 AM" src="https://github.com/user-attachments/assets/437c917c-9905-4d43-a939-16e0f1c7577d" />
</p>


## How it works

1. Press **Option+Space** to open the bar.
2. Type or paste a draft, then press **Return**.
3. Review the diff, then click the copy icon.

- **Profiles:** Email, Work, Chat, and General, each with its own editable prompt. Pick one, or leave it on Auto and Tev1 chooses.
- **Reply context:** text under a `---` line, or a quoted thread ("On … wrote:", "From:"), is read for context but never edited.
- **Memory:** the model loads when you open the bar and unloads after an idle time you set in Settings (⌘,).
- **Privacy:** nothing is sent to the cloud and no messages are stored. Only your profiles are saved, in `~/Library/Application Support/local-writing-fixer/`.

## Requirements

- macOS 13 or later
- Ollama running locally, with a text model (default `qwen3:8b`)
- Optional, for Auto: the Tev1 model (`tev1:4b`)

## Build

```sh
./scripts/bundle.sh    # builds build/Tidy Fixer.app
```

Or open `TidyFixer.xcodeproj` in Xcode and press Cmd+R.
The project is generated from `project.yml`, so run `xcodegen` after adding or removing a source file.

## Notes

- Small models can still over-edit or miss an error, so check the diff before you copy.
- Option+Space may clash with another app's shortcut.
- The app has no Dock icon while it sits in the menu bar.
