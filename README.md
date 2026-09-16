# Morse Code Trainer with classic training formats
# Writen with Claude support

A Windows Morse code training app, in two forms:

- **[`morse_trainer/`](morse_trainer/)** — a single-file C console version.
  Copy Practice, Koch method trainer, Send/Playback, and adjustable
  speed/tone settings. Builds with MinGW-w64 or MSVC.
- **[`morse_trainer_lazarus/`](morse_trainer_lazarus/)** — a Lazarus
  (Free Pascal) GUI port with five tabs: Copy Practice, Koch Trainer,
  Send/Playback, Random Text (letter/number groups or a loaded text
  file with full "umlaut" support), and Settings to set speed and pauses. 
Builds with the Lazarus IDE or `lazbuild`.

Both generate their own audio in software (a sine tone with a short
fade in/out) and play it through the system's default sound device via
the Windows Multimedia API (`winmm.dll`) — no special drivers or
hardware needed, just whatever sound card Windows already has
configured.

Each subfolder has its own `README.md` with full build instructions,
feature notes, and known limitations. Start there for the version you
want to build.

## Which one should I build?

The Lazarus version is the actively developed one — it has the full
feature set (Random Text practice, umlaut/punctuation support, tunable
Farnsworth timing) and a proper GUI. The C console version is the
original, simpler proof of concept; it still works, but new features
have gone into the Lazarus version.

## License

This project is licensed under [Creative Commons
Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/).

You're free to use, copy, modify, and share this project for any
**non-commercial** purpose, as long as you give appropriate credit. See
the [`LICENSE`](LICENSE) file for the full terms.
