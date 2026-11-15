unit Cabinet.Window;

///  The cabinet's window. It starts on the game menu (or straight on a game with --set), plugs in
///  the board of the chosen game and runs it at its own frame rate, shown as mounted ; Esc unplugs it
///  and goes back to the menu. A game whose ROMs can't be loaded never stops the cabinet : the menu
///  says what is missing.
///  Loop = Application.OnIdle paced by a stopwatch (no TTimer : starved by a busy loop).
///  Cabinet keys : F1 controls card, M sound, P pause, F3 reset, Esc back to the menu (game keys :
///  wiring of Arcade.Cabinet.Controls, saved in Cabinet.controls.ini next to the exe).

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
  Arcade.RomSet,
  Arcade.Catalog,
  Arcade.Cabinet.Display,
  Arcade.Cabinet.Sound,
  Arcade.Cabinet.Controls,
  Cabinet.Overlay,
  Cabinet.Menu;

type
  TCabinetOptions = record
    SetName: string;      // '' : start on the menu
    RecordFile: string;   // <> '' : every frame's inputs are logged and saved there when the game ends
    Sound: Boolean;
    Dip0, Dip1: Integer;  // -1 : board default
    Service: Boolean;
  end;

  TCabinetWindow = class(TForm)
  private
    FOptions: TCabinetOptions;
    FRoms: TRomSetData;
    FBoard: TArcadeBoard;
    FLastSet: string;
    FImage: TImage;
    FControls: TCabinetControls;
    FControlsFile: string;
    FOverlay: TCabinetOverlay;
    FMenu: TCabinetMenu;
    FHoldInputs: Boolean;   // back from the card : panel reads as released until everything is
    FWatch: TStopwatch;
    FFramesDone: Int64;
    FSwitched: Boolean;     // a board was plugged in or out during this idle loop
    FPaused: Boolean;
    FRecord: TInputLog;
    FSound: TWaveOut;
    FMuted: Boolean;
  public
    /// Shows frame / focus / inputs in the title bar (diagnostics).
    Debug: Boolean;
  private
    function Focused: Boolean;
    procedure OnIdle(Sender: TObject; var Done: Boolean);
    procedure RestartClock;
    procedure ShowMenu;
    function PlugIn(const aSet: string): Boolean;
    procedure Unplug;
    procedure MenuFrame;
    procedure EmulateFrame;
  public
    constructor CreateCabinet(aOwner: TComponent; const aOptions: TCabinetOptions);
    destructor Destroy; override;
  end;

implementation

const
  CScale = 3;
  CMaxCatchUp = 4;
  CSampleRate = 44100;
  CMenuRate = 60;

{ TCabinetWindow }

constructor TCabinetWindow.CreateCabinet(aOwner: TComponent; const aOptions: TCabinetOptions);
begin
  inherited CreateNew(aOwner);
  FOptions := aOptions;
  FRecord := TInputLog.Create;
  FControls := TCabinetControls.Create;
  FControlsFile := ExtractFilePath(ParamStr(0)) + 'Cabinet.controls.ini';
  if not FControls.LoadFromFile(FControlsFile) then
    FControls.SaveToFile(FControlsFile);   // first run : the factory wiring, editable by hand
  if FOptions.Sound then
    FSound := TWaveOut.Create(CSampleRate);

  ClientWidth := 224 * CScale;   // a vertical monitor, as on every board plugged in so far
  ClientHeight := 256 * CScale;
  Position := TFormPosition.ScreenCenter;
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := TAlphaColors.Black;

  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Align := TAlignLayout.Client;
  FImage.WrapMode := TImageWrapMode.Fit;
  FImage.DisableInterpolation := True;
  FImage.HitTest := False;

  FOverlay := TCabinetOverlay.Create(Self, FControls, '');
  FMenu := TCabinetMenu.Create(Self, FControls);

  FLastSet := FOptions.SetName;
  if (FOptions.SetName = '') or not PlugIn(FOptions.SetName) then
    ShowMenu;
  Application.OnIdle := OnIdle;
end;

destructor TCabinetWindow.Destroy;
begin
  Application.OnIdle := nil;
  Unplug;
  FRecord.Free;
  FMenu.Free;
  FOverlay.Free;
  FControls.Free;
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

procedure TCabinetWindow.RestartClock;
begin
  FWatch := TStopwatch.StartNew;
  FFramesDone := 0;
  FSwitched := True;
end;

procedure TCabinetWindow.ShowMenu;
begin
  Caption := 'RetroLab';
  FMenu.Show(ScanCatalog(ExtractFilePath(ParamStr(0))), FLastSet);
  RestartClock;
end;

function TCabinetWindow.PlugIn(const aSet: string): Boolean;
var
  lInfo: TScreenInfo;
begin
  Result := False;
  FLastSet := aSet;
  try
    FRoms := LoadRomSet(aSet, ExtractFilePath(ParamStr(0)));
    FBoard := CreateBoardForSet(FRoms);
  except
    FreeAndNil(FBoard);
    FreeAndNil(FRoms);
    Exit;
  end;
  if FOptions.Dip0 >= 0 then
    FBoard.SetDip(0, FOptions.Dip0);
  if FOptions.Dip1 >= 0 then
    FBoard.SetDip(1, FOptions.Dip1);
  if FOptions.Service then
    FBoard.SetServiceMode(True);
  if Assigned(FSound) then
    FBoard.AudioRate := CSampleRate;

  lInfo := FBoard.ScreenInfo;
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
  Caption := TrFmt('cabinet.caption', 'Cabinet - %s [%s, %s]  (F1 controls)',
    [FBoard.Roms.Def.Title, FBoard.Roms.Def.Name, FBoard.Family]);

  FMenu.Hide;
  FRecord.Clear;
  FPaused := False;
  FOverlay.Title := Format('%s [%s]', [FBoard.Roms.Def.Title, FBoard.Roms.Def.Name]);
  if FControls.ShowAtStart then
    FOverlay.Show(True);
  RestartClock;
  Result := True;
end;

procedure TCabinetWindow.Unplug;
begin
  if not Assigned(FBoard) then
    Exit;
  if FOptions.RecordFile <> '' then
    FRecord.SaveToFile(FOptions.RecordFile);
  FOverlay.Hide;
  FBoard.AudioRate := 0;
  FreeAndNil(FBoard);
  FreeAndNil(FRoms);
  FImage.Bitmap.SetSize(0, 0);
end;

procedure TCabinetWindow.MenuFrame;
var
  lQuit: Boolean;
  lSet: string;
begin
  FControls.Poll;
  if not Focused then
    Exit;
  lSet := FMenu.Tick(lQuit);
  if lQuit then
    Close
  else if (lSet <> '') and not PlugIn(lSet) then
    ShowMenu;   // the files changed since the menu was shown : show it again, with the reason
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
    begin
      Unplug;
      ShowMenu;
      Exit;
    end;
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
  lRate: Double;
  lRan: Integer;
begin
  Done := False;
  if Assigned(FBoard) then
    lRate := FBoard.ScreenInfo.FrameRate
  else
    lRate := CMenuRate;
  lDue := Trunc(FWatch.Elapsed.TotalSeconds * lRate);
  if lDue - FFramesDone > CMaxCatchUp then
    FFramesDone := lDue - CMaxCatchUp;   // too late (debugger, window drag) : drop, don't spiral
  FSwitched := False;
  lRan := 0;
  while (FFramesDone < lDue) and not FSwitched do
  begin
    if Assigned(FBoard) then
      EmulateFrame
    else
      MenuFrame;
    Inc(FFramesDone);
    Inc(lRan);
  end;
  if (lRan > 0) and Assigned(FBoard) then
  begin
    ShowBoardScreen(FBoard, FImage.Bitmap);
    FImage.Repaint;
  end
  else if lRan = 0 then
    Sleep(1);
end;

end.
