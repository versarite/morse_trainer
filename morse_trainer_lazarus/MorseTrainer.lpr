program MorseTrainer;

{$mode objfpc}{$H+}

uses
  Interfaces, // this pulls in the LCL widgetset
  Forms,
  uMorseSound,
  uMain;

begin
  Application.Title := 'Morse Code Trainer';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
