unit Cabinet.Window;

///  The cabinet's window : whatever board is plugged in, at its own frame rate, shown as mounted.
///  Loop = Application.OnIdle paced by a stopwatch (no TTimer : starved by a busy loop).
///  Cabinet keys : F1 controls card, M sound, P pause, F3 reset, Esc quit (game keys : wiring of
///  Arcade.Cabinet.Controls, saved in Cabinet.controls.ini next to the exe, edited from the card).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  System.Diagnostics,
  Winapi.Windows,
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.Graphics,
  FMX.Objects,
  FMX.Platform.Win,
  GS.Common.I18n,
  Arcade.Gfx,
  Arcade.Board,
  Arcade.Cabinet.Display,
  Arcade.Cabinet.Sound,
  Arcade.Cabinet.Controls,
  Cabinet.Overlay;

type
  TCabinetWindow = class(TForm)
  private
    FBoard: TArcadeBoard;
    FImage: TImage;
    FControls: TCabinetControls;
    FControlsFile: string;
    FOverlay: TCabinetOverlay;
    FHoldInputs: Boolean;   // back from the card : panel reads as released until everything is
    FWatch: TStopwatch;
    FFramesDone: Int64;
    FPaused: Boolean;
    FRecord: TInputLog;
    FRecordFile: string;
    FSound: TWaveOut;
    FMuted: Boolean;
    FBaseCaption: string;
  public
    /// Shows frame / focus / inputs in the title bar (diagnostics).
    Debug: Boolean;
  private
    function Focused: Boolean;
    procedure OnIdle(Sender: TObject; var Done: Boolean);
    procedure EmulateFrame;
  public
    /// aRecordFile <> '' : every frame's inputs are logged and saved there on close.
    constructor CreateCabinet(aOwner: TComponent; aBoard: TArcadeBoard; const aRecordFile: string;
      aSound: Boolean);
    destructor Destroy; override;
  end;

implementation

const
  CScale = 3;
  CMaxCatchUp = 4;
  CSampleRate = 44100;

{ TCabinetWindow }

constructor TCabinetWindow.CreateCabinet(aOwner: TComponent; aBoard: TArcadeBoard;
  const aRecordFile: string; aSound: Boolean);
var
  lInfo: TScreenInfo;
begin
  inherited CreateNew(aOwner);
  FBoard := aBoard;
  FRecordFile := aRecordFile;
  FRecord := TInputLog.Create;
  FControls := TCabinetControls.Create;
  FControlsFile := ExtractFilePath(ParamStr(0)) + 'Cabinet.controls.ini';
  if not FControls.LoadFromFile(FControlsFile) then
    FControls.SaveToFile(FControlsFile);   // first run : the factory wiring, editable by hand
  if aSound then
  begin
    FSound := TWaveOut.Create(CSampleRate);
    FBoard.AudioRate := CSampleRate;
  end;

  lInfo := FBoard.ScreenInfo;
  FBaseCaption := TrFmt('cabinet.caption', 'Cabinet - %s [%s, %s]  (F1 controls)',
    [FBoard.Roms.Def.Title, FBoard.Roms.Def.Name, FBoard.Family]);
  Caption := FBaseCaption;
  if lInfo.Rotation in [rot90, rot270] then
  begin
    ClientWidth := lInfo.Height * CScale;
    ClientHeight := lInfo.Width * CScale;
  end
  else
  begin
    ClientWidth := lInfo.Width * CScale;
    ClientHeight := lInfo.Height * CScale;
  end;
  Position := TFormPosition.ScreenCenter;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := TAlphaColors.Black;

  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Align := TAlignLayout.Client;
  FImage.WrapMode := TImageWrapMode.Fit;
  FImage.DisableInterpolation := True;
  FImage.HitTest := False;

  FOverlay := TCabinetOverlay.Create(Self, FControls,
    Format('%s [%s]', [FBoard.Roms.Def.Title, FBoard.Roms.Def.Name]));
  if FControls.ShowAtStart then
    FOverlay.Show(True);

  FWatch := TStopwatch.StartNew;
  Application.OnIdle := OnIdle;
end;

destructor TCabinetWindow.Destroy;
begin
  Application.OnIdle := nil;
  if FRecordFile <> '' then
    FRecord.SaveToFile(FRecordFile);
  FRecord.Free;
  FOverlay.Free;
  FControls.Free;
  FBoard.AudioRate := 0;
  FSound.Free;
  inherited;
end;

// An FMX app owns two top-level windows (application + form) : the cabinet has the focus when the
// foreground window, whichever it is, belongs to this process.
function TCabinetWindow.Focused: Boolean;
var
  lPid: DWORD;
begin
  lPid := 0;
  GetWindowThreadProcessId(GetForegroundWindow, @lPid);
  Result := lPid = GetCurrentProcessId;
end;

procedure TCabinetWindow.EmulateFrame;
var
  lBackToGame: Boolean;
begin
  FControls.Poll;
  // the controls card holds the emulation while it is shown
  if Focused and FControls.KeyPressed(VK_F1) then
  begin
    if FOverlay.Visible then
      lBackToGame := True
    else
    begin
      FOverlay.Show(False);
      lBackToGame := False;
    end;
  end
  else
    lBackToGame := FOverlay.Visible and Focused and not FOverlay.Tick;
  if lBackToGame then
  begin
    if FOverlay.Modified then
      FControls.SaveToFile(FControlsFile);
    FOverlay.Hide;
    FHoldInputs := True;
  end;
  if FOverlay.Visible then
    Exit;

  if Focused then
  begin
    if FControls.KeyPressed(VK_F3) then
    begin
      FBoard.Reset;
      FRecord.Clear;   // a replay always starts from power-on
    end;
    if FControls.KeyPressed(Ord('M')) then
      FMuted := not FMuted;
    if FControls.KeyPressed(Ord('P')) then
      FPaused := not FPaused;
    if FControls.KeyPressed(VK_ESCAPE) then
      Close;
  end;
  if FPaused then
    Exit;
  if FHoldInputs then
    FHoldInputs := FControls.AnyDown;   // the key / button that closed the card isn't a game input
  if FHoldInputs then
    FBoard.Inputs := Default(TArcadeInputs)
  else
    FBoard.Inputs := FControls.Read(Focused);
  FRecord.Add(FBoard.Inputs);
  FBoard.RunFrame;
  if Debug and ((FBoard.Frame mod 15) = 0) then
    Caption := Format('frame %d | focus %s | sys %.2x p1 %.2x', [FBoard.Frame,
      BoolToStr(Focused, True), Byte(FBoard.Inputs.System), Byte(FBoard.Inputs.Players[0])]);
  if Assigned(FSound) and not FMuted then
    FSound.Push(FBoard.AudioBuffer, FBoard.AudioCount);
end;

procedure TCabinetWindow.OnIdle(Sender: TObject; var Done: Boolean);
var
  lDue: Int64;
  lRan: Integer;
begin
  Done := False;
  lDue := Trunc(FWatch.Elapsed.TotalSeconds * FBoard.ScreenInfo.FrameRate);
  if lDue - FFramesDone > CMaxCatchUp then
    FFramesDone := lDue - CMaxCatchUp;   // too late (debugger, window drag) : drop, don't spiral
  lRan := 0;
  while FFramesDone < lDue do
  begin
    EmulateFrame;
    Inc(FFramesDone);
    Inc(lRan);
  end;
  if lRan > 0 then
  begin
    ShowBoardScreen(FBoard, FImage.Bitmap);
    FImage.Repaint;
  end
  else
    Sleep(1);
end;

end.
