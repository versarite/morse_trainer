unit uMorseSound;

{ Morse code audio engine: generates dit/dah tones in software and plays
  them through the system's default audio output device via the Windows
  Multimedia API (winmm.dll / waveOut*, exposed here through FPC's
  MMSystem unit). This is the same "generic sound card" approach as the
  original C console version -- it only talks to WAVE_MAPPER (the default
  device), never to specific hardware, so it works with whatever audio
  device Windows already has configured.

  This unit has no LCL/GUI dependency and can be reused as-is by any
  Lazarus form, or by a console program. }

{$mode objfpc}{$H+}

interface

uses
  Windows, MMSystem, SysUtils;

const
  SAMPLE_RATE = 44100;
  AMPLITUDE   = 8000.0;  // headroom below +/-32767 to avoid clipping
  RAMP_MS     = 5.0;     // fade in/out to avoid audible clicks

  // Classic Koch method character order. Levels grow left to right.
  KochOrder: String = 'KMRSUAPTLOWI.NJEF0YVG5Q9ZH38B?427C1D6X';
  KochMaxLevel = 38; // must match Length(KochOrder)

type
  TAudioBuffer = array of SmallInt;

  TTrainerSettings = record
    WPM: Integer;            // character (element) speed
    FarnsworthWPM: Integer;  // effective spacing speed; <= WPM
    Freq: Double;             // sidetone frequency in Hz
  end;

  // A wave-out device kept open across several PlayXxxOnSession calls, so
  // rapid-fire playback (e.g. a 50-group random-text run) only pays the
  // waveOutOpen/Close setup cost once instead of once per group. Using a
  // fresh PlayAudio/PlayText call per group is fine for occasional single
  // characters/lines, but the open/close overhead of each call is enough
  // to make back-to-back groups feel noticeably slower than the timing
  // you actually configured, especially at higher WPM.
  TWaveOutSession = record
    hWaveOut: HWAVEOUT;
    hEvent: THandle;
    IsOpen: Boolean;
  end;

// Returns the Morse pattern ('.'/'-') for a supported character, or '' if
// the character (punctuation etc.) is not in the table. Recognizes the
// German umlauts (Ä/Ö/Ü, either case) as single-byte Latin-1/Windows-1252
// characters (#$C4/#$E4 etc.). For text that may be UTF-8 (the normal
// case for files/LCL controls, where each umlaut is 2 bytes), use
// MorseForAt instead -- it's what BuildMorseAudio actually uses.
function MorseFor(C: Char): String;

// Looks up the Morse code for the character starting at Text[Pos] and
// reports how many bytes it occupied via ConsumedBytes (1 normally; 2 if
// Text[Pos] starts a recognized 2-byte UTF-8 umlaut sequence -- Ä Ö Ü ä ö
// ü). This lets BuildMorseAudio handle UTF-8 text correctly *without*
// rewriting/normalizing the original string -- important because the
// LCL (memos, edits, etc.) expects UTF-8, so converting umlauts down to
// single Latin-1 bytes for lookup purposes would make them display as
// "?" everywhere the text is shown on screen. Falls back to MorseFor on
// the single byte at Pos (which still handles single-byte Latin-1 text).
function MorseForAt(const Text: String; Pos: Integer; out ConsumedBytes: Integer): String;

procedure AppendTone(var Buf: TAudioBuffer; FreqHz, DurMs: Double);
procedure AppendSilence(var Buf: TAudioBuffer; DurMs: Double);

// Builds a complete audio buffer for a line of text (spaces become word
// gaps). Overwrites Buf.
procedure BuildMorseAudio(var Buf: TAudioBuffer; const Text: String;
  const Settings: TTrainerSettings);

// Blocks the calling thread for the duration of playback (same behaviour
// as the original console version). If you need the UI to stay visibly
// responsive during long playback, call Application.ProcessMessages from
// the caller before/after, or run playback on a background thread.
procedure PlayAudio(const Buf: TAudioBuffer);
procedure PlayText(const Text: String; const Settings: TTrainerSettings);

// Open once before a run of several PlayXxxOnSession calls, close once
// when done (Stop button included). See TWaveOutSession above.
function OpenWaveSession(var Session: TWaveOutSession): Boolean;
procedure PlayBufferOnSession(var Session: TWaveOutSession; const Buf: TAudioBuffer);
procedure PlayTextOnSession(var Session: TWaveOutSession; const Text: String;
  const Settings: TTrainerSettings);
procedure CloseWaveSession(var Session: TWaveOutSession);

implementation

function MorseFor(C: Char): String;
const
  Chars: array[0..49] of Char = (
    'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q',
    'R','S','T','U','V','W','X','Y','Z',
    '0','1','2','3','4','5','6','7','8','9',
    '.',',','?','/','=',
    '!',';','-',
    #$C4, #$E4,  // Ä, ä
    #$D6, #$F6,  // Ö, ö
    #$DC, #$FC); // Ü, ü
  Codes: array[0..49] of String = (
    '.-','-...','-.-.','-..','.','..-.','--.','....','..','.---','-.-',
    '.-..','--','-.','---','.--.','--.-','.-.','...','-','..-','...-',
    '.--','-..-','-.--','--..',
    '-----','.----','..---','...--','....-','.....','-....','--...',
    '---..','----.',
    '.-.-.-','--..--','..--..','-..-.','-...-',
    '-.-.--','-.-.-.','-....-',
    '.-.-','.-.-',
    '---.','---.',
    '..--','..--');
var
  i: Integer;
  UC: Char;
begin
  Result := '';
  UC := UpCase(C); // no-op for the umlaut bytes above; both cases are listed
  for i := Low(Chars) to High(Chars) do
    if Chars[i] = UC then
    begin
      Result := Codes[i];
      Exit;
    end;
end;

function MorseForAt(const Text: String; Pos: Integer; out ConsumedBytes: Integer): String;
const
  Utf8Second: array[0..5] of Byte = ($84, $96, $9C, $A4, $B6, $BC); // Ä Ö Ü ä ö ü
  Utf8Codes:  array[0..5] of String = ('.-.-', '---.', '..--', '.-.-', '---.', '..--');
var
  k: Integer;
begin
  ConsumedBytes := 1;
  if (Byte(Text[Pos]) = $C3) and (Pos < Length(Text)) then
    for k := 0 to 5 do
      if Byte(Text[Pos + 1]) = Utf8Second[k] then
      begin
        ConsumedBytes := 2;
        Result := Utf8Codes[k];
        Exit;
      end;
  Result := MorseFor(Text[Pos]);
end;

procedure AppendTone(var Buf: TAudioBuffer; FreqHz, DurMs: Double);
var
  N, RampSamples, OldLen, i: Integer;
  Amp, Sample, T: Double;
begin
  N := Round(SAMPLE_RATE * DurMs / 1000.0);
  if N <= 0 then Exit;
  RampSamples := Round(SAMPLE_RATE * RAMP_MS / 1000.0);
  if RampSamples * 2 > N then RampSamples := N div 2;

  OldLen := Length(Buf);
  SetLength(Buf, OldLen + N);
  for i := 0 to N - 1 do
  begin
    T := i / SAMPLE_RATE;
    Amp := AMPLITUDE;
    if RampSamples > 0 then
    begin
      if i < RampSamples then
        Amp := Amp * (i / RampSamples)
      else if i >= N - RampSamples then
        Amp := Amp * ((N - i) / RampSamples);
    end;
    Sample := Amp * Sin(2.0 * Pi * FreqHz * T);
    Buf[OldLen + i] := Round(Sample);
  end;
end;

procedure AppendSilence(var Buf: TAudioBuffer; DurMs: Double);
var
  N, OldLen: Integer;
begin
  N := Round(SAMPLE_RATE * DurMs / 1000.0);
  if N <= 0 then Exit;
  OldLen := Length(Buf);
  SetLength(Buf, OldLen + N);
  FillChar(Buf[OldLen], N * SizeOf(SmallInt), 0);
end;

{ Standard timing: at W words per minute (the word "PARIS" as a 50-unit
  reference), one dit = 1200/W ms, a dah is 3 dits, the gap between
  elements within a character is 1 dit, the gap between characters is 3
  dits, and the gap between words is 7 dits.

  Farnsworth timing keeps dits/dahs at full "character speed" (WPM) so
  each letter's rhythm stays realistic, while stretching the
  inter-character/word gaps out to a slower "effective speed"
  (FarnsworthWPM), which is easier to follow while learning. }
procedure BuildMorseAudio(var Buf: TAudioBuffer; const Text: String;
  const Settings: TTrainerSettings);
var
  DitMs, DahMs, ElementGapMs, SpacingUnitMs, CharGapMs, WordGapMs: Double;
  i, j, Consumed, NextPos: Integer;
  Code: String;
  HasNext: Boolean;
begin
  DitMs := 1200.0 / Settings.WPM;
  DahMs := DitMs * 3.0;
  ElementGapMs := DitMs;
  SpacingUnitMs := 1200.0 / Settings.FarnsworthWPM;
  CharGapMs := SpacingUnitMs * 3.0;
  WordGapMs := SpacingUnitMs * 7.0;

  SetLength(Buf, 0);
  // A while-loop, not for-loop, because a UTF-8 umlaut occupies 2 bytes
  // of Text but counts as a single Morse character (see MorseForAt).
  i := 1;
  while i <= Length(Text) do
  begin
    if Text[i] = ' ' then
    begin
      AppendSilence(Buf, WordGapMs);
      Inc(i);
      Continue;
    end;

    Code := MorseForAt(Text, i, Consumed);
    if Code = '' then
    begin
      Inc(i, Consumed); // skip unsupported character(s) silently
      Continue;
    end;

    for j := 1 to Length(Code) do
    begin
      if Code[j] = '.' then
        AppendTone(Buf, Settings.Freq, DitMs)
      else
        AppendTone(Buf, Settings.Freq, DahMs);
      if j < Length(Code) then
        AppendSilence(Buf, ElementGapMs);
    end;

    // Only add the inter-character gap when another character in the same
    // word follows. If the text ends here, or the next character is a
    // space, that gap is skipped: a following space already supplies the
    // (larger) word gap above, and stacking both made every word/group
    // boundary noticeably longer than the configured speed calls for.
    NextPos := i + Consumed;
    HasNext := NextPos <= Length(Text);
    if HasNext and (Text[NextPos] <> ' ') then
      AppendSilence(Buf, CharGapMs);

    Inc(i, Consumed);
  end;
end;

function OpenWaveSession(var Session: TWaveOutSession): Boolean;
var
  Fmt: TWaveFormatEx;
  Res: MMRESULT;
begin
  Result := False;
  FillChar(Session, SizeOf(Session), 0);

  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.wFormatTag := WAVE_FORMAT_PCM;
  Fmt.nChannels := 1;
  Fmt.nSamplesPerSec := SAMPLE_RATE;
  Fmt.wBitsPerSample := 16;
  Fmt.nBlockAlign := (Fmt.nChannels * Fmt.wBitsPerSample) div 8;
  Fmt.nAvgBytesPerSec := Fmt.nSamplesPerSec * Fmt.nBlockAlign;
  Fmt.cbSize := 0;

  Session.hEvent := CreateEvent(nil, False, False, nil);
  if Session.hEvent = 0 then Exit;

  // WAVE_MAPPER = "whatever the default output device is" -- this is what
  // lets the program work with any generic sound card without needing to
  // know its name or capabilities ahead of time.
  Res := waveOutOpen(@Session.hWaveOut, WAVE_MAPPER, @Fmt, DWORD_PTR(Session.hEvent), 0, CALLBACK_EVENT);
  if Res <> MMSYSERR_NOERROR then
  begin
    CloseHandle(Session.hEvent);
    Exit;
  end;

  Session.IsOpen := True;
  Result := True;
end;

procedure PlayBufferOnSession(var Session: TWaveOutSession; const Buf: TAudioBuffer);
var
  Hdr: TWaveHdr;
begin
  if (not Session.IsOpen) or (Length(Buf) = 0) then Exit;

  FillChar(Hdr, SizeOf(Hdr), 0);
  Hdr.lpData := @Buf[0];
  Hdr.dwBufferLength := Length(Buf) * SizeOf(SmallInt);

  waveOutPrepareHeader(Session.hWaveOut, @Hdr, SizeOf(Hdr));
  waveOutWrite(Session.hWaveOut, @Hdr, SizeOf(Hdr));

  while (Hdr.dwFlags and WHDR_DONE) = 0 do
    WaitForSingleObject(Session.hEvent, INFINITE);

  waveOutUnprepareHeader(Session.hWaveOut, @Hdr, SizeOf(Hdr));
end;

procedure PlayTextOnSession(var Session: TWaveOutSession; const Text: String;
  const Settings: TTrainerSettings);
var
  Buf: TAudioBuffer;
begin
  BuildMorseAudio(Buf, Text, Settings);
  PlayBufferOnSession(Session, Buf);
end;

procedure CloseWaveSession(var Session: TWaveOutSession);
begin
  if Session.IsOpen then
  begin
    waveOutClose(Session.hWaveOut);
    CloseHandle(Session.hEvent);
    Session.IsOpen := False;
  end;
end;

procedure PlayAudio(const Buf: TAudioBuffer);
var
  Session: TWaveOutSession;
begin
  if Length(Buf) = 0 then Exit;
  if not OpenWaveSession(Session) then Exit;
  PlayBufferOnSession(Session, Buf);
  CloseWaveSession(Session);
end;

procedure PlayText(const Text: String; const Settings: TTrainerSettings);
var
  Buf: TAudioBuffer;
begin
  BuildMorseAudio(Buf, Text, Settings);
  PlayAudio(Buf);
end;

end.
