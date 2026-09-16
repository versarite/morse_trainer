# Morse Code Trainer (Lazarus / Free Pascal port)

This is a Lazarus port of the original C console trainer, rebuilt as a
proper GUI application with five tabs: **Copy Practice**, **Koch
Trainer**, **Send / Playback**, **Random Text**, and **Settings**.

It keeps the exact same audio approach as the C version: tones are
generated in software (sine wave with a short fade in/out to avoid
clicks) and played through the system's **default audio output device**
via the Windows Multimedia API (`winmm.dll`, accessed through FPC's
`MMSystem` unit — `WAVE_MAPPER`/`waveOut*`). That's what makes it work
with any generic sound card without extra drivers: it just uses whatever
device Windows already has set as default.

> **Important — this targets Windows**, same as the original request.
> `Windows`/`MMSystem` are Windows-only units, so this won't compile for
> a Linux or macOS target as-is. If you want a cross-platform Lazarus
> build too, that needs a different audio backend per OS (e.g. SDL2 or
> PortAudio) — say the word and I'll add one.

> **Note on testing:** I wrote and reviewed this carefully, but could not
> compile it in the sandbox I'm working in — it has no Windows/FPC
> toolchain and no network path to install one (same limitation as the
> original C version). The two spots most likely to need a small tweak
> if your Lazarus/FPC version's `MMSystem` unit declares things slightly
> differently are noted with comments in `uMorseSound.pas`, around the
> `waveOutOpen` call. If the compiler flags a type mismatch there, it's
> usually a one-line pointer/type cast fix.

## Files

- `MorseTrainer.lpr` — project/program entry point.
- `uMain.pas` — the main form. All controls (tabs, buttons, edits, memos)
  are created in code rather than via a `.lfm` resource, so there's
  nothing extra to keep in sync — just these `.pas` files.
- `uMorseSound.pas` — the audio engine (Morse table, tone/silence
  generation, timing, playback). No GUI dependency; reusable elsewhere.
- `MorseTrainer.lpi` — a best-effort Lazarus project file. See "Opening
  the project" below if it doesn't load cleanly.

## Troubleshooting: "unit Interfaces not found"

Two separate things can cause this:

1. **Compiling with plain `fpc` instead of `lazbuild`/the IDE.** `Interfaces`,
   `Forms`, `Controls`, etc. are LCL units — plain `fpc MorseTrainer.lpr`
   doesn't know where the LCL lives for your widgetset. Build it with
   `lazbuild MorseTrainer.lpi` from a terminal, or open the project in the
   Lazarus IDE and press F9/Ctrl+F9. Don't invoke `fpc` directly on this
   project.
2. **The project file didn't declare a dependency on the LCL package.**
   This was a bug in the `.lpi` I originally gave you — it was missing a
   `<RequiredPackages>` entry for `LCL`, so even `lazbuild`/the IDE
   couldn't resolve `Interfaces`. It's fixed now; re-download
   `MorseTrainer.lpi` (or just add the block yourself — see below) and
   retry.

If you already have the old copy, add this inside `<ProjectOptions>`,
right after `</RunParams>`:

```xml
<RequiredPackages>
  <Item>
    <PackageName Value="LCL"/>
  </Item>
</RequiredPackages>
```

## Opening the project

**Option A — open the project file directly:**
Open `MorseTrainer.lpi` in Lazarus (File → Open Project). If it loads,
just press Run (F9).

**Option B — safer fallback if the `.lpi` has trouble:**
1. In Lazarus: File → New → Project → Application.
2. Save it as `MorseTrainer` in this folder (let it create its own
   `Project1.lpr`/`Unit1.pas`, then rename/replace as below).
3. Project → Add to Project… and add `uMorseSound.pas` and `uMain.pas`
   from this folder.
4. Open the auto-generated main `.lpr` and replace its contents with
   `MorseTrainer.lpr`'s contents (or just copy the `uses` list and the
   `Application.CreateForm(TForm1, Form1)` line into it).
5. Delete the IDE's auto-generated `Unit1`/`Form1` unit if it created one
   with a `.lfm`, since `uMain.pas` defines its own `TForm1` in code.
6. Build (Ctrl+F9) and Run (F9).

Either way, target the **Win32** or **Win64** platform (Project →
Project Options → Compiler Options → Config and Target).

## Using it

- **Copy Practice** — click Start; it plays a random letter/digit, type
  what you heard into the box and press Enter. Score updates live in the
  log. Click Stop to end the session.
- **Koch Trainer** — click "Start Round" for a 20-character round drawn
  from the currently unlocked character set (shown above the button,
  starting with K and M). Score ≥90% on a round to unlock the next
  character in the standard Koch order.
- **Send / Playback** — type text, click Play to hear it in Morse; the
  dot/dash pattern is shown in the box below so you can connect what you
  see to what you hear.
- **Random Text** — pick one of three sources and click Play for a
  250-character practice run: random letters in groups of 5, random
  numbers in groups of 5, or 250 characters starting at a random spot in
  a text file you load ("Browse..."). The generated/extracted text is
  shown above the log so you can check your copy afterwards. It plays
  group-by-group (word-by-word for a loaded file) so the Stop button
  stays responsive throughout — you don't have to wait for the whole 250
  characters to finish.
- **Settings** — character speed (WPM), Farnsworth (effective) spacing
  speed, and tone frequency (300–1200 Hz, default 700 Hz). Changes apply
  immediately to the next character played.

## German umlauts and extra punctuation

The Morse table (`MorseFor` in `uMorseSound.pas`) now also covers `Ä Ö Ü
ä ö ü` and `! ; -` (`,` and `.` were already supported). These are
available wherever free text is played -- **Random Text's loaded-file
option (c)**, and **Send/Playback** -- but deliberately *not* mixed into
the random letter/number generators for options (a) and (b), which still
draw only from `A-Z`/`0-9` exactly as before.

A text file can be saved as either UTF-8 (each umlaut is 2 bytes) or
single-byte Windows-1252/Latin-1 (each umlaut is 1 byte); both are common
depending on what saved the file, and both are handled -- but not by
rewriting the loaded text. An earlier version of this fix collapsed the
UTF-8 umlaut byte-pairs down to a single Latin-1 byte before storing the
text, which made the *audio* correct but broke *display*: the LCL
(memos, edit boxes) expects UTF-8, and a lone Latin-1 byte isn't valid
UTF-8, so it rendered as `?`. The text is now left exactly as loaded/
typed, and the UTF-8 awareness lives entirely in the audio path instead:
`MorseForAt` (`uMorseSound.pas`) looks at the text position-by-position
and recognizes a 2-byte UTF-8 umlaut sequence as one character (Ä Ö Ü ä
ö ü), consuming both bytes, while everything else -- including a
single-byte Latin-1 umlaut, still supported as a fallback -- is read one
byte at a time as before. `BuildMorseAudio` and the Send/Playback
pattern preview both use it. This is a targeted fix for exactly the
requested characters, not general Unicode support -- other accented
letters (é, ñ, …) are still silently skipped in the audio, same as any
other character outside the Morse table, but they'll at least *display*
correctly now since the text itself is never touched.

## Timing fixes (gaps between groups/words now match your WPM)

If groups in Random Text (or multi-word sentences in Send/Playback) felt
slower than your configured speed, several things fed into that:

1. **Farnsworth spacing is now off by default and structurally can't
   drift out of sync.** The Settings tab used to have two independent
   speed spinners (character speed and Farnsworth/effective spacing
   speed) that could end up set to different values -- e.g. character
   speed raised to 40 WPM while Farnsworth was still sitting at its
   default of 20, so letters played fast but every gap was computed at
   the slower 20 WPM rate. That's almost certainly what you were
   hearing. It's redesigned now: there's a single "Use slower spacing
   between letters/words (Farnsworth method)" checkbox, **unchecked by
   default**. While unchecked, the effective spacing speed is force-set
   equal to character speed on every single settings change -- there is
   no longer a separate stored value that can fall out of sync, so "40
   WPM" now means true 40 WPM everywhere, including the gaps between
   groups. Check the box only if you deliberately want slower,
   beginner-friendly gaps while keeping each letter's own sound
   realistic; a second spinner for that speed becomes enabled only then.
2. **A double-gap bug in the timing engine.** After a character, the
   code always added an inter-character gap *and*, if a space followed,
   the (larger) word gap -- stacking both instead of using just the word
   gap, so every word/group boundary was about 3 dit-units longer than
   it should have been. Fixed in `uMorseSound.pas`'s `BuildMorseAudio`.
3. **Per-group audio device open/close overhead.** Random Text
   previously opened and closed the Windows audio device for every
   single group. That setup cost is small per call but adds up across
   50 groups and was adding noticeable, somewhat unpredictable extra
   silence between groups. Random Text now opens the device once for
   the whole run (`TWaveOutSession` in `uMorseSound.pas`) and only
   closes it when the run finishes or you click Stop.

With these fixed, a 40 WPM run should sound like genuine 40 WPM timing
throughout, including between groups. If it's still not right after
rebuilding, it's worth double-checking on-screen that the Farnsworth
checkbox is actually unchecked and the character-speed spinner reads 40
-- that rules the setting itself out so we can look elsewhere (e.g. the
tone-generation timing math, or something specific to your sound
device/driver).

## Differences from the C console version

- GUI instead of a text menu, with four practice tabs always available
  instead of a top-level menu you navigate in and out of.
- Playback (`PlayAudio`) blocks the calling thread for the duration of
  the tone, exactly like the console version did — for single characters
  this is well under a second, so it won't be noticeable. For very long
  sentences in Send/Playback it could briefly make the window look
  unresponsive; let me know if you'd like that moved to a background
  thread so the UI stays interactive during long playback.
- The Koch level persists only for the lifetime of the running app (same
  as the C version); it resets when you close the program. Persisting it
  to disk between runs is a small addition if you want it.
