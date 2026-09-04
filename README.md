# notch-notes

Durable, per-session notes for [Notch](https://github.com/trobrock/notch).

## Features

- `/note <text>` saves a note in the current Notch session, including while a model response is streaming.
- `/notes` picks a saved note and moves it into the prompt editor.
- `/notes clear` clears pending notes after confirmation.
- Pending notes appear in the fullscreen status and panel.
- Notes survive process restarts and follow fullscreen `/resume`.
- Fullscreen `/new` starts with an empty note list because it creates a new session.

## Requirements

A Notch version with custom session-entry and prompt-editor extension APIs (the change following Notch commit `21ae067`). No Node.js or npm runtime is required; this package is a single Lua extension.

## Install

```sh
notch extensions install github:trobrock/notch-notes
```

Restart Notch after installation.

For local development:

```sh
notch extensions validate .
notch extensions install .
```

## Usage

```text
/note remember to update the release notes
/notes
/notes clear
```

When `/notes` selects a note and the prompt editor already contains text, choose whether to replace it, append the note, or cancel. A note is consumed only after it is placed in the editor.

## Storage

The extension stores append-only records in the active Notch session under the entry kind `trobrock.notch-notes`. It does not create a separate database or notes directory.

## License

MIT
