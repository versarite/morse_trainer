unit uMain;

{ Main form for the Morse Code Trainer. All controls are created in code
  (no .lfm resource needed), so this unit is self-contained: drop it plus
  uMorseSound.pas and MorseTrainer.lpr into a Lazarus project and it just
  works. See the five tabs: Copy Practice, Koch Trainer, Send/Playback,
  Random Text, and Settings. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, Spin, Dialogs,
  uMorseSound;

type

  { TForm1 }

  TForm1 = class(TForm)
  private
    Settings: TTrainerSettings;
    KochLevel: Integer;

    PageControl1: TPageControl;
    tsCopy, tsKoch, tsSend, tsRandom, tsSettings: TTabSheet;

    // Copy Practice tab
    lblCopyScore: TLabel;
    edtCopyAnswer: TEdit;
    btnCopyStart, btnCopyStop: TButton;
    memCopyLog: TMemo;
    CopyRunning: Boolean;
    CopyTarget: Char;
    CopyTotal, CopyCorrect: Integer;

    // Koch Trainer tab
    lblKochScore, lblKochChars: TLabel;
    edtKochAnswer: TEdit;
    btnKochStart, btnKochStop: TButton;
    memKochLog: TMemo;
    KochRunning: Boolean;
    KochTarget: Char;
    KochTotal, KochCorrect, KochRoundSize: Integer;

    // Send / Playback tab
    edtSendText: TEdit;
    btnSendPlay: TButton;
    memSendPattern: TMemo;

    // Random Text tab
    rbLetters, rbNumbers, rbFileText: TRadioButton;
    btnBrowseFile: TButton;
    lblFileInfo: TLabel;
    OpenDialog1: TOpenDialog;
    btnRandomPlay, btnRandomStop: TButton;
    lblRandomProgress: TLabel;
    memRandomText: TMemo;
    LoadedFileText, LoadedFileName: String;
    RandomFullText: String;
    RandomRunning, RandomStopRequested: Boolean;

    // Settings tab
    speWPM, speFarnsworth, speFreq: TSpinEdit;
    cbUseFarnsworth: TCheckBox;

    procedure BuildCopyTab;
    procedure BuildKochTab;
    procedure BuildSendTab;
    procedure BuildSettingsTab;

    procedure UpdateCopyScoreLabel;
    procedure UpdateKochScoreLabel;

    procedure CopyStartClick(Sender: TObject);
    procedure CopyStopClick(Sender: TObject);
    procedure CopyAnswerKeyPress(Sender: TObject; var Key: Char);
    procedure CopyPlayNext;

    procedure KochStartClick(Sender: TObject);
    procedure KochStopClick(Sender: TObject);
    procedure KochAnswerKeyPress(Sender: TObject; var Key: Char);
    procedure KochPlayNext;
    procedure FinishKochRound;

    procedure SendPlayClick(Sender: TObject);

    procedure BuildRandomTab;
    procedure RandomModeClick(Sender: TObject);
    procedure BrowseFileClick(Sender: TObject);
    procedure RandomPlayClick(Sender: TObject);
    procedure RandomStopClick(Sender: TObject);

    procedure SettingsChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  Form1: TForm1;

implementation

{ TForm1 }

constructor TForm1.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Randomize;

  Caption := 'Morse Code Trainer';
  Width := 580;
  Height := 440;
  Position := poScreenCenter;

  Settings.WPM := 20;
  Settings.FarnsworthWPM := 20;
  Settings.Freq := 700.0;
  KochLevel := 2;
  KochRoundSize := 20;

  PageControl1 := TPageControl.Create(Self);
  PageControl1.Parent := Self;
  PageControl1.Align := alClient;

  tsCopy := PageControl1.AddTabSheet;
  tsCopy.Caption := 'Copy Practice';
  tsKoch := PageControl1.AddTabSheet;
  tsKoch.Caption := 'Koch Trainer';
  tsSend := PageControl1.AddTabSheet;
  tsSend.Caption := 'Send / Playback';
  tsRandom := PageControl1.AddTabSheet;
  tsRandom.Caption := 'Random Text';
  tsSettings := PageControl1.AddTabSheet;
  tsSettings.Caption := 'Settings';

  BuildCopyTab;
  BuildKochTab;
  BuildSendTab;
  BuildRandomTab;
  BuildSettingsTab;
end;

{ ------------------------------------------------------------------ }
{ Copy Practice tab                                                   }
{ ------------------------------------------------------------------ }

procedure TForm1.BuildCopyTab;
var
  lbl: TLabel;
begin
  lbl := TLabel.Create(Self);
  lbl.Parent := tsCopy;
  lbl.Left := 16; lbl.Top := 16;
  lbl.Caption := 'Click Start, then type the character you hear and press Enter.';

  btnCopyStart := TButton.Create(Self);
  btnCopyStart.Parent := tsCopy;
  btnCopyStart.Left := 16; btnCopyStart.Top := 48; btnCopyStart.Width := 90;
  btnCopyStart.Caption := 'Start';
  btnCopyStart.OnClick := @CopyStartClick;

  btnCopyStop := TButton.Create(Self);
  btnCopyStop.Parent := tsCopy;
  btnCopyStop.Left := 112; btnCopyStop.Top := 48; btnCopyStop.Width := 90;
  btnCopyStop.Caption := 'Stop';
  btnCopyStop.Enabled := False;
  btnCopyStop.OnClick := @CopyStopClick;

  lbl := TLabel.Create(Self);
  lbl.Parent := tsCopy;
  lbl.Left := 16; lbl.Top := 92;
  lbl.Caption := 'Your answer:';

  edtCopyAnswer := TEdit.Create(Self);
  edtCopyAnswer.Parent := tsCopy;
  edtCopyAnswer.Left := 100; edtCopyAnswer.Top := 88; edtCopyAnswer.Width := 50;
  edtCopyAnswer.MaxLength := 1;
  edtCopyAnswer.Enabled := False;
  edtCopyAnswer.OnKeyPress := @CopyAnswerKeyPress;

  lblCopyScore := TLabel.Create(Self);
  lblCopyScore.Parent := tsCopy;
  lblCopyScore.Left := 16; lblCopyScore.Top := 124;
  lblCopyScore.Caption := 'Score: 0/0 (0.0%)';

  memCopyLog := TMemo.Create(Self);
  memCopyLog.Parent := tsCopy;
  memCopyLog.Left := 16; memCopyLog.Top := 152;
  memCopyLog.Width := 520; memCopyLog.Height := 220;
  memCopyLog.ReadOnly := True;
  memCopyLog.ScrollBars := ssVertical;
  memCopyLog.Anchors := [akLeft, akTop, akRight, akBottom];
end;

procedure TForm1.UpdateCopyScoreLabel;
var
  Pct: Double;
begin
  if CopyTotal > 0 then Pct := 100.0 * CopyCorrect / CopyTotal else Pct := 0.0;
  lblCopyScore.Caption := Format('Score: %d/%d (%.1f%%)', [CopyCorrect, CopyTotal, Pct]);
end;

procedure TForm1.CopyStartClick(Sender: TObject);
begin
  CopyRunning := True;
  CopyTotal := 0;
  CopyCorrect := 0;
  memCopyLog.Clear;
  UpdateCopyScoreLabel;
  btnCopyStart.Enabled := False;
  btnCopyStop.Enabled := True;
  edtCopyAnswer.Enabled := True;
  edtCopyAnswer.SetFocus;
  CopyPlayNext;
end;

procedure TForm1.CopyStopClick(Sender: TObject);
begin
  CopyRunning := False;
  btnCopyStart.Enabled := True;
  btnCopyStop.Enabled := False;
  edtCopyAnswer.Enabled := False;
  memCopyLog.Lines.Add('Session stopped.');
end;

procedure TForm1.CopyPlayNext;
const
  CharsetStr = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
begin
  CopyTarget := CharsetStr[1 + Random(Length(CharsetStr))];
  edtCopyAnswer.Text := '';
  PlayText(CopyTarget, Settings);
end;

procedure TForm1.CopyAnswerKeyPress(Sender: TObject; var Key: Char);
var
  Guess: Char;
begin
  if not CopyRunning then Exit;
  if Key <> #13 then Exit;
  Key := #0;
  if edtCopyAnswer.Text = '' then Exit;

  Guess := UpCase(edtCopyAnswer.Text[1]);
  Inc(CopyTotal);
  if Guess = CopyTarget then
  begin
    Inc(CopyCorrect);
    memCopyLog.Lines.Add(Format('%s -> correct', [Guess]));
  end
  else
    memCopyLog.Lines.Add(Format('%s -> wrong (was %s)', [Guess, CopyTarget]));

  UpdateCopyScoreLabel;
  CopyPlayNext;
end;

{ ------------------------------------------------------------------ }
{ Koch Trainer tab                                                    }
{ ------------------------------------------------------------------ }

procedure TForm1.BuildKochTab;
var
  lbl: TLabel;
begin
  lbl := TLabel.Create(Self);
  lbl.Parent := tsKoch;
  lbl.Left := 16; lbl.Top := 16;
  lbl.Caption := 'Adaptive trainer: clear a 20-character round at >=90% to unlock the next character.';

  lblKochChars := TLabel.Create(Self);
  lblKochChars.Parent := tsKoch;
  lblKochChars.Left := 16; lblKochChars.Top := 40;
  lblKochChars.Caption := 'Characters: ' + Copy(KochOrder, 1, KochLevel);

  btnKochStart := TButton.Create(Self);
  btnKochStart.Parent := tsKoch;
  btnKochStart.Left := 16; btnKochStart.Top := 72; btnKochStart.Width := 90;
  btnKochStart.Caption := 'Start Round';
  btnKochStart.OnClick := @KochStartClick;

  btnKochStop := TButton.Create(Self);
  btnKochStop.Parent := tsKoch;
  btnKochStop.Left := 112; btnKochStop.Top := 72; btnKochStop.Width := 90;
  btnKochStop.Caption := 'Stop';
  btnKochStop.Enabled := False;
  btnKochStop.OnClick := @KochStopClick;

  lbl := TLabel.Create(Self);
  lbl.Parent := tsKoch;
  lbl.Left := 16; lbl.Top := 116;
  lbl.Caption := 'Your answer:';

  edtKochAnswer := TEdit.Create(Self);
  edtKochAnswer.Parent := tsKoch;
  edtKochAnswer.Left := 100; edtKochAnswer.Top := 112; edtKochAnswer.Width := 50;
  edtKochAnswer.MaxLength := 1;
  edtKochAnswer.Enabled := False;
  edtKochAnswer.OnKeyPress := @KochAnswerKeyPress;

  lblKochScore := TLabel.Create(Self);
  lblKochScore.Parent := tsKoch;
  lblKochScore.Left := 16; lblKochScore.Top := 148;
  lblKochScore.Caption := 'Score: 0/0 (0.0%)';

  memKochLog := TMemo.Create(Self);
  memKochLog.Parent := tsKoch;
  memKochLog.Left := 16; memKochLog.Top := 176;
  memKochLog.Width := 520; memKochLog.Height := 196;
  memKochLog.ReadOnly := True;
  memKochLog.ScrollBars := ssVertical;
  memKochLog.Anchors := [akLeft, akTop, akRight, akBottom];
end;

procedure TForm1.UpdateKochScoreLabel;
var
  Pct: Double;
begin
  if KochTotal > 0 then Pct := 100.0 * KochCorrect / KochTotal else Pct := 0.0;
  lblKochScore.Caption := Format('Score: %d/%d (%.1f%%)', [KochCorrect, KochTotal, Pct]);
end;

procedure TForm1.KochStartClick(Sender: TObject);
begin
  KochRunning := True;
  KochTotal := 0;
  KochCorrect := 0;
  memKochLog.Clear;
  UpdateKochScoreLabel;
  btnKochStart.Enabled := False;
  btnKochStop.Enabled := True;
  edtKochAnswer.Enabled := True;
  edtKochAnswer.SetFocus;
  KochPlayNext;
end;

procedure TForm1.KochStopClick(Sender: TObject);
begin
  KochRunning := False;
  btnKochStart.Enabled := True;
  btnKochStop.Enabled := False;
  edtKochAnswer.Enabled := False;
  memKochLog.Lines.Add('Round stopped early.');
end;

procedure TForm1.KochPlayNext;
begin
  if KochTotal >= KochRoundSize then
  begin
    FinishKochRound;
    Exit;
  end;
  KochTarget := KochOrder[1 + Random(KochLevel)];
  edtKochAnswer.Text := '';
  PlayText(KochTarget, Settings);
end;

procedure TForm1.KochAnswerKeyPress(Sender: TObject; var Key: Char);
var
  Guess: Char;
begin
  if not KochRunning then Exit;
  if Key <> #13 then Exit;
  Key := #0;
  if edtKochAnswer.Text = '' then Exit;

  Guess := UpCase(edtKochAnswer.Text[1]);
  Inc(KochTotal);
  if Guess = KochTarget then
  begin
    Inc(KochCorrect);
    memKochLog.Lines.Add(Format('[%d/%d] %s -> correct', [KochTotal, KochRoundSize, Guess]));
  end
  else
    memKochLog.Lines.Add(Format('[%d/%d] %s -> wrong (was %s)', [KochTotal, KochRoundSize, Guess, KochTarget]));

  UpdateKochScoreLabel;
  KochPlayNext;
end;

procedure TForm1.FinishKochRound;
var
  Pct: Double;
begin
  KochRunning := False;
  btnKochStart.Enabled := True;
  btnKochStop.Enabled := False;
  edtKochAnswer.Enabled := False;

  if KochTotal > 0 then Pct := 100.0 * KochCorrect / KochTotal else Pct := 0.0;
  memKochLog.Lines.Add(Format('Round complete: %d/%d correct (%.1f%%)', [KochCorrect, KochTotal, Pct]));

  if (Pct >= 90.0) and (KochLevel < KochMaxLevel) then
  begin
    Inc(KochLevel);
    memKochLog.Lines.Add(Format('Level up! Now practicing %d characters: %s',
      [KochLevel, Copy(KochOrder, 1, KochLevel)]));
    lblKochChars.Caption := 'Characters: ' + Copy(KochOrder, 1, KochLevel);
  end
  else if KochLevel >= KochMaxLevel then
    memKochLog.Lines.Add('Full character set unlocked -- keep practicing for speed!')
  else
    memKochLog.Lines.Add('Keep practicing at this level: ' + Copy(KochOrder, 1, KochLevel));
end;

{ ------------------------------------------------------------------ }
{ Send / Playback Practice tab                                        }
{ ------------------------------------------------------------------ }

procedure TForm1.BuildSendTab;
var
  lbl: TLabel;
begin
  lbl := TLabel.Create(Self);
  lbl.Parent := tsSend;
  lbl.Left := 16; lbl.Top := 16;
  lbl.Caption := 'Type text below and click Play to hear it in Morse.';

  edtSendText := TEdit.Create(Self);
  edtSendText.Parent := tsSend;
  edtSendText.Left := 16; edtSendText.Top := 48; edtSendText.Width := 400;

  btnSendPlay := TButton.Create(Self);
  btnSendPlay.Parent := tsSend;
  btnSendPlay.Left := 424; btnSendPlay.Top := 46; btnSendPlay.Width := 90;
  btnSendPlay.Caption := 'Play';
  btnSendPlay.OnClick := @SendPlayClick;

  lbl := TLabel.Create(Self);
  lbl.Parent := tsSend;
  lbl.Left := 16; lbl.Top := 84;
  lbl.Caption := 'Morse pattern:';

  memSendPattern := TMemo.Create(Self);
  memSendPattern.Parent := tsSend;
  memSendPattern.Left := 16; memSendPattern.Top := 108;
  memSendPattern.Width := 520; memSendPattern.Height := 260;
  memSendPattern.ReadOnly := True;
  memSendPattern.ScrollBars := ssVertical;
  memSendPattern.WordWrap := True;
  memSendPattern.Anchors := [akLeft, akTop, akRight, akBottom];
end;

procedure TForm1.SendPlayClick(Sender: TObject);
var
  Txt, PatternStr, Code: String;
  i, Consumed: Integer;
begin
  Txt := edtSendText.Text;
  if Txt = '' then Exit;

  // Uses MorseForAt (not a plain per-byte MorseFor loop) so a UTF-8
  // umlaut -- 2 bytes in Txt -- is read as one character here too,
  // matching what BuildMorseAudio actually plays.
  PatternStr := '';
  i := 1;
  while i <= Length(Txt) do
  begin
    if Txt[i] = ' ' then
    begin
      PatternStr := PatternStr + ' / ';
      Inc(i);
      Continue;
    end;
    Code := MorseForAt(Txt, i, Consumed);
    if Code <> '' then
      PatternStr := PatternStr + Code + ' ';
    Inc(i, Consumed);
  end;
  memSendPattern.Lines.Text := PatternStr;

  PlayText(Txt, Settings);
end;

{ ------------------------------------------------------------------ }
{ Random Text tab                                                     }
{ ------------------------------------------------------------------ }

function NormalizeWhitespace(const S: String): String;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if (Result[i] = #9) or (Result[i] = #10) or (Result[i] = #13) then
      Result[i] := ' ';
end;

function GenerateRandomGroups(const Charset: String; TotalChars, GroupSize: Integer): String;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to TotalChars do
  begin
    Result := Result + Charset[1 + Random(Length(Charset))];
    if (GroupSize > 0) and (i mod GroupSize = 0) and (i < TotalChars) then
      Result := Result + ' ';
  end;
end;

// Takes up to TotalChars characters starting at a random position in
// FullText (or the whole text if it's shorter than TotalChars).
function ExtractFileExcerpt(const FullText: String; TotalChars: Integer): String;
var
  Len, StartPos: Integer;
begin
  Len := Length(FullText);
  if Len = 0 then
  begin
    Result := '';
    Exit;
  end;
  if Len <= TotalChars then
  begin
    Result := FullText;
    Exit;
  end;
  StartPos := 1 + Random(Len - TotalChars + 1);
  Result := Copy(FullText, StartPos, TotalChars);
end;

// Splits on plain spaces without any quote/delimiter interpretation, so
// punctuation from a loaded file (quotes, commas, etc.) can't confuse it
// the way TStrings.DelimitedText sometimes does.
procedure SplitWords(const S: String; List: TStrings);
var
  i, Start: Integer;
begin
  List.Clear;
  Start := 1;
  for i := 1 to Length(S) + 1 do
  begin
    if (i > Length(S)) or (S[i] = ' ') then
    begin
      if i > Start then
        List.Add(Copy(S, Start, i - Start));
      Start := i + 1;
    end;
  end;
end;

procedure TForm1.BuildRandomTab;
var
  lbl: TLabel;
begin
  lbl := TLabel.Create(Self);
  lbl.Parent := tsRandom;
  lbl.Left := 16; lbl.Top := 16;
  lbl.Caption := 'Choose a source, then click Play. Each run uses 250 characters.';

  rbLetters := TRadioButton.Create(Self);
  rbLetters.Parent := tsRandom;
  rbLetters.Left := 16; rbLetters.Top := 44;
  rbLetters.Caption := '250 random letters, in groups of 5';
  rbLetters.Checked := True;
  rbLetters.OnClick := @RandomModeClick;

  rbNumbers := TRadioButton.Create(Self);
  rbNumbers.Parent := tsRandom;
  rbNumbers.Left := 16; rbNumbers.Top := 68;
  rbNumbers.Caption := '250 random numbers, in groups of 5';
  rbNumbers.OnClick := @RandomModeClick;

  rbFileText := TRadioButton.Create(Self);
  rbFileText.Parent := tsRandom;
  rbFileText.Left := 16; rbFileText.Top := 92;
  rbFileText.Caption := 'Load a text file and play 250 characters from a random position';
  rbFileText.OnClick := @RandomModeClick;

  btnBrowseFile := TButton.Create(Self);
  btnBrowseFile.Parent := tsRandom;
  btnBrowseFile.Left := 36; btnBrowseFile.Top := 116; btnBrowseFile.Width := 100;
  btnBrowseFile.Caption := 'Browse...';
  btnBrowseFile.Enabled := False;
  btnBrowseFile.OnClick := @BrowseFileClick;

  lblFileInfo := TLabel.Create(Self);
  lblFileInfo.Parent := tsRandom;
  lblFileInfo.Left := 144; lblFileInfo.Top := 120;
  lblFileInfo.Caption := 'No file loaded.';

  OpenDialog1 := TOpenDialog.Create(Self);
  OpenDialog1.Title := 'Select a text file';
  OpenDialog1.Filter := 'Text files (*.txt)|*.txt|All files|*.*';

  btnRandomPlay := TButton.Create(Self);
  btnRandomPlay.Parent := tsRandom;
  btnRandomPlay.Left := 16; btnRandomPlay.Top := 152; btnRandomPlay.Width := 90;
  btnRandomPlay.Caption := 'Play';
  btnRandomPlay.OnClick := @RandomPlayClick;

  btnRandomStop := TButton.Create(Self);
  btnRandomStop.Parent := tsRandom;
  btnRandomStop.Left := 112; btnRandomStop.Top := 152; btnRandomStop.Width := 90;
  btnRandomStop.Caption := 'Stop';
  btnRandomStop.Enabled := False;
  btnRandomStop.OnClick := @RandomStopClick;

  lblRandomProgress := TLabel.Create(Self);
  lblRandomProgress.Parent := tsRandom;
  lblRandomProgress.Left := 16; lblRandomProgress.Top := 188;
  lblRandomProgress.Caption := '';

  memRandomText := TMemo.Create(Self);
  memRandomText.Parent := tsRandom;
  memRandomText.Left := 16; memRandomText.Top := 212;
  memRandomText.Width := 520; memRandomText.Height := 160;
  memRandomText.ReadOnly := True;
  memRandomText.ScrollBars := ssVertical;
  memRandomText.WordWrap := True;
  memRandomText.Anchors := [akLeft, akTop, akRight, akBottom];
end;

procedure TForm1.RandomModeClick(Sender: TObject);
begin
  btnBrowseFile.Enabled := rbFileText.Checked;
end;

procedure TForm1.BrowseFileClick(Sender: TObject);
var
  SL: TStringList;
begin
  if not OpenDialog1.Execute then Exit;

  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(OpenDialog1.FileName);
      LoadedFileText := NormalizeWhitespace(SL.Text);
      LoadedFileName := OpenDialog1.FileName;
      lblFileInfo.Caption := Format('Loaded "%s" (%d characters).',
        [ExtractFileName(LoadedFileName), Length(LoadedFileText)]);
    except
      on E: Exception do
      begin
        LoadedFileText := '';
        LoadedFileName := '';
        lblFileInfo.Caption := 'Could not read file.';
        ShowMessage('Could not read file: ' + E.Message);
      end;
    end;
  finally
    SL.Free;
  end;
end;

procedure TForm1.RandomPlayClick(Sender: TObject);
var
  Words: TStringList;
  Session: TWaveOutSession;
  i: Integer;
begin
  if rbFileText.Checked and (LoadedFileText = '') then
  begin
    ShowMessage('Please choose a text file first.');
    Exit;
  end;

  if rbLetters.Checked then
    RandomFullText := GenerateRandomGroups('ABCDEFGHIJKLMNOPQRSTUVWXYZ', 250, 5)
  else if rbNumbers.Checked then
    RandomFullText := GenerateRandomGroups('0123456789', 250, 5)
  else
    RandomFullText := ExtractFileExcerpt(LoadedFileText, 250);

  memRandomText.Lines.Text := RandomFullText;

  // Keep one audio device open for the whole run instead of opening and
  // closing it per group -- that per-call setup cost was making the gap
  // between groups noticeably larger than the configured WPM, especially
  // at higher speeds.
  if not OpenWaveSession(Session) then
  begin
    ShowMessage('Could not open an audio output device.');
    Exit;
  end;

  RandomRunning := True;
  RandomStopRequested := False;
  btnRandomPlay.Enabled := False;
  btnRandomStop.Enabled := True;
  rbLetters.Enabled := False;
  rbNumbers.Enabled := False;
  rbFileText.Enabled := False;
  btnBrowseFile.Enabled := False;

  Words := TStringList.Create;
  try
    SplitWords(RandomFullText, Words);
    if Words.Count = 0 then
      lblRandomProgress.Caption := 'Nothing to play.'
    else
      for i := 0 to Words.Count - 1 do
      begin
        if RandomStopRequested then Break;
        lblRandomProgress.Caption := Format('Playing %d of %d...', [i + 1, Words.Count]);
        Application.ProcessMessages;
        if RandomStopRequested then Break;
        PlayTextOnSession(Session, Words[i] + ' ', Settings);
        Application.ProcessMessages;
      end;
  finally
    Words.Free;
    CloseWaveSession(Session);
  end;

  if RandomStopRequested then
    lblRandomProgress.Caption := 'Stopped.'
  else if lblRandomProgress.Caption <> 'Nothing to play.' then
    lblRandomProgress.Caption := 'Done.';

  RandomRunning := False;
  btnRandomPlay.Enabled := True;
  btnRandomStop.Enabled := False;
  rbLetters.Enabled := True;
  rbNumbers.Enabled := True;
  rbFileText.Enabled := True;
  btnBrowseFile.Enabled := rbFileText.Checked;
end;

procedure TForm1.RandomStopClick(Sender: TObject);
begin
  RandomStopRequested := True;
end;

{ ------------------------------------------------------------------ }
{ Settings tab                                                        }
{ ------------------------------------------------------------------ }

procedure TForm1.BuildSettingsTab;
var
  lbl: TLabel;
begin
  lbl := TLabel.Create(Self);
  lbl.Parent := tsSettings;
  lbl.Left := 16; lbl.Top := 20;
  lbl.Caption := 'Character speed (WPM):';

  speWPM := TSpinEdit.Create(Self);
  speWPM.Parent := tsSettings;
  speWPM.Left := 260; speWPM.Top := 16; speWPM.Width := 80;
  speWPM.MinValue := 5; speWPM.MaxValue := 60; speWPM.Value := 20;
  speWPM.OnChange := @SettingsChanged;

  cbUseFarnsworth := TCheckBox.Create(Self);
  cbUseFarnsworth.Parent := tsSettings;
  cbUseFarnsworth.Left := 16; cbUseFarnsworth.Top := 56;
  cbUseFarnsworth.Width := 480;
  cbUseFarnsworth.Caption := 'Use slower spacing between letters/words (Farnsworth method)';
  cbUseFarnsworth.Checked := False;
  cbUseFarnsworth.OnClick := @SettingsChanged;

  lbl := TLabel.Create(Self);
  lbl.Parent := tsSettings;
  lbl.Left := 36; lbl.Top := 88;
  lbl.Caption := 'Effective spacing speed (WPM):';

  speFarnsworth := TSpinEdit.Create(Self);
  speFarnsworth.Parent := tsSettings;
  speFarnsworth.Left := 260; speFarnsworth.Top := 84; speFarnsworth.Width := 80;
  speFarnsworth.MinValue := 5; speFarnsworth.MaxValue := 60; speFarnsworth.Value := 20;
  speFarnsworth.Enabled := False;
  speFarnsworth.OnChange := @SettingsChanged;

  lbl := TLabel.Create(Self);
  lbl.Parent := tsSettings;
  lbl.Left := 16; lbl.Top := 124;
  lbl.Caption := 'Tone frequency (Hz):';

  speFreq := TSpinEdit.Create(Self);
  speFreq.Parent := tsSettings;
  speFreq.Left := 260; speFreq.Top := 120; speFreq.Width := 80;
  speFreq.MinValue := 300; speFreq.MaxValue := 1200; speFreq.Increment := 50;
  speFreq.Value := 700;
  speFreq.OnChange := @SettingsChanged;

  lbl := TLabel.Create(Self);
  lbl.Parent := tsSettings;
  lbl.Left := 16; lbl.Top := 164;
  lbl.Caption := 'With Farnsworth spacing off (the default), every gap -- between ' +
    'letters, between groups/words, everywhere -- runs at the same speed ' +
    'as the letters themselves: true character speed, e.g. real 40 WPM ' +
    'throughout. Turn it on only if you want slower, beginner-friendly ' +
    'gaps while keeping each letter''s own sound realistic.';
  lbl.WordWrap := True;
  lbl.Width := 500;
end;

procedure TForm1.SettingsChanged(Sender: TObject);
begin
  if not cbUseFarnsworth.Checked then
  begin
    // Farnsworth off: spacing is FORCED equal to character speed on every
    // single settings change, full stop. There's no separate stored value
    // that can silently fall out of sync -- this is what guarantees
    // "practice at a real N WPM" actually means N WPM everywhere,
    // including the gaps between groups/words.
    speFarnsworth.Enabled := False;
    speFarnsworth.Value := speWPM.Value;
  end
  else
  begin
    speFarnsworth.Enabled := True;
    if speFarnsworth.Value > speWPM.Value then
      speFarnsworth.Value := speWPM.Value;
  end;

  Settings.WPM := speWPM.Value;
  Settings.FarnsworthWPM := speFarnsworth.Value;
  Settings.Freq := speFreq.Value;
end;

end.
