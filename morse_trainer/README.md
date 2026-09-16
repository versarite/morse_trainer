# Morse Code Trainer

A single-file Windows console app for learning and practicing Morse code.
It generates its own audio (a sine-wave tone with a short fade in/out to
avoid clicks) entirely in software and plays it through your system's
**default audio output device** using the Windows Multimedia API
(`winmm.dll` / `waveOut*`). That's what makes it work with any generic
sound card: it never talks to specific audio hardware, only to whatever
device Windows already has set as default, so if you can hear a YouTube
video, this will work.

> **Note on testing:** this was written and reviewed carefully, but it
> hasn't been compiled in this sandbox — the environment I built it in has
> no Windows toolchain and no network path to install one. Build it with
> the instructions below and let me know if anything doesn't compile; I'm
> happy to fix it.

## Features

- **Copy Practice** — plays random characters (A–Z, 0–9); you type what
  you heard and get live accuracy scoring.
- **Koch Method Trainer** — the well-known adaptive method for learning
  Morse: starts with just two characters (K, M) sent at full target
  speed, and unlocks the next character in the standard Koch order each
  time you clear a 20-character round at ≥90% accuracy. This teaches you
  to recognize characters by sound/rhythm rather than counting dits and
  dahs.
- **Send / Playback Practice** — type any text and hear it played back in
  Morse, with the dot/dash pattern printed alongside so you can connect
  what you see to what you hear.
- **Settings** — adjust character speed (WPM), Farnsworth (effective)
  speed for easier-to-follow spacing while learning, and sidetone
  frequency (300–1200 Hz, default 700 Hz).

## Requirements

- Windows (uses the Win32 API and `winmm.dll`, which ships with every
  version of Windows).
- Any working audio output device — built-in speakers, USB headset,
  HDMI audio, whatever Windows currently uses as default. No special
  drivers needed.
- A C compiler: MinGW-w64 (`gcc`) or MSVC (`cl`).

## Building

**MinGW-w64 (recommended, free):**

```
gcc morse_trainer.c -o morse_trainer.exe -lwinmm -lm -O2
```

**MSVC (Visual Studio "Developer Command Prompt"):**

```
cl morse_trainer.c winmm.lib
```

Either produces `morse_trainer.exe`. No other files or DLLs are needed —
`winmm.dll` is part of every Windows install.

A `Makefile` is included for `mingw32-make` users; just run `mingw32-make`
in this folder.

## Usage

Run `morse_trainer.exe` from a console (double-clicking works too, but a
console window lets you see the menu clearly). You'll get a menu:

```
1. Copy Practice (random characters)
2. Koch Method Trainer (adaptive)
3. Send / Playback Practice
4. Settings
5. Quit
```

In Copy Practice and the Koch Trainer, just press the key for the letter
or digit you heard — no need to press Enter. Press `!` to end a session
early. In Send/Playback Practice, type a line and press Enter; type
`exit` to return to the menu.

Recommended starting point if you're new to Morse: use the **Koch Method
Trainer** at 20 WPM character speed (the default) — the high speed keeps
the *rhythm* of each letter authentic from day one, which is what your
ear actually needs to learn, even though you're only working with 2
characters at first.

## Timing details

Standard Morse timing is derived from the word "PARIS" as a 50-unit
reference: at *W* words per minute, one dit = `1200 / W` ms, a dah is 3
dits, the gap between elements within a character is 1 dit, the gap
between characters is 3 dits, and the gap between words is 7 dits.

Farnsworth timing keeps dits/dahs at full "character speed" (so letters
still sound the way they will at full speed) but stretches the
inter-character and inter-word gaps out to a slower "effective speed" —
useful while you're still recognizing letters. Set the Farnsworth speed
lower than the character speed in Settings to enable this; setting them
equal (the default) disables it.

## Possible extensions

Not included, but straightforward to add if useful:

- Export practice sessions to `.wav` files.
- A real "send" mode that decodes keyboard-key timing (hold spacebar to
  key dits/dahs) instead of only text-to-audio playback.
- Persisting your Koch level and stats to disk between runs.
- A cross-platform port (e.g. via SDL2 or PortAudio) for Linux/macOS.

## Files

- `morse_trainer.c` — the entire program (one file, ~450 lines).
- `Makefile` — convenience build file for `mingw32-make`.
