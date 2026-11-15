unit Cabinet.Overlay;

///  The controls card stuck on the cabinet : shown over the screen at power-on and with F1, it
///  lists what every switch is wired to (keyboard, gamepads) and lets the player rewire it :
///    Up / Down (or pad d-pad) choose a switch, Enter (pad A) add a key or pad button,
///    Delete (pad X) clear the switch, F5 factory wiring, Esc / F1 / pad Start back to the game.
///  Driven by Tick, once per frame, while the emulation is held.
///  Header : the RETROLAB logo (Cabinet.Logo), tagline, author and release date,
///  and a blinking "PRESS F1 TO START!".

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  Winapi.Windows,
  FMX.Types,
  FMX.Controls,
  FMX.Objects,
  FMX.Graphics,
  GS.Common.I18n,
  Cabinet.Logo,
  Arcade.Cabinet.Gamepad,
  Arcade.Cabinet.Controls;

const
  CAuthor = 'Vincent Gsell';
  CReleaseDate = '2026-10-24';   // to update at each release

type
  TCabinetOverlay = class
  private
    FControls: TCabinetControls;
    FTitle: string;
    FPanel: TRectangle;
    FLogo: TImage;
    FTagline: TText;
    FByline: TText;
    FStart: TText;
    FText: TText;
    FAtStart: Boolean;
    FBlink: Integer;
    FSelected: TCabinetAction;
    FCapturing: Boolean;
    FArmed: Boolean;          // capture : everything released once, the next press is the one
    FWaitRelease: Boolean;    // after a capture : don't read the captured input as navigation
    FModified: Boolean;
    FLastPads: Integer;
    procedure Refresh;
    procedure ResetEdges;
    function AddLine(aParent: TFmxObject; aHeight, aSize: Single; aColor: TAlphaColor; aBold: Boolean): TText;
    function GetVisible: Boolean;
  public
    constructor Create(aParent: TFmxObject; aControls: TCabinetControls; const aTitle: string);
    /// aAtStart : power-on ("PRESS F1 TO START!"), else back from the game ("PRESS F1 TO RESUME").
    procedure Show(aAtStart: Boolean);
    procedure Hide;
    /// One frame of the overlay ; False when the player went back to the game.
    function Tick: Boolean;
    /// The wiring changed since Show.
    property Modified: Boolean read FModified;
    property Visible: Boolean read GetVisible;
    /// The game shown on the card, set when a board is plugged in.
    property Title: string read FTitle write FTitle;
  end;

implementation

const
  CBindWidth = 26;
  CBlinkFrames = 30;

{ TCabinetOverlay }

constructor TCabinetOverlay.Create(aParent: TFmxObject; aControls: TCabinetControls; const aTitle: string);
begin
  inherited Create;
  FControls := aControls;
  FTitle := aTitle;
  FLastPads := -1;

  FPanel := TRectangle.Create(aParent);
  FPanel.Parent := aParent;
  FPanel.Align := TAlignLayout.Contents;
  FPanel.Fill.Color := $E0000010;
  FPanel.Stroke.Kind := TBrushKind.None;
  FPanel.HitTest := False;
  FPanel.Visible := False;

  FLogo := TImage.Create(FPanel);
  FLogo.Parent := FPanel;
  FLogo.Align := TAlignLayout.Top;
  FLogo.Height := 56;
  FLogo.Margins.Rect := TRectF.Create(16, 16, 16, 0);
  FLogo.WrapMode := TImageWrapMode.Fit;
  FLogo.DisableInterpolation := True;
  FLogo.HitTest := False;
  DrawLogo(FLogo.Bitmap, CLogoText);

  FTagline := AddLine(FPanel, 22, 13, $FFFFA010, True);
  FTagline.Text := CTagline;
  FTagline.Position.Y := 950;
  FByline := AddLine(FPanel, 24, 13, $FF80C8FF, False);
  FByline.Position.Y := 960;
  FStart := AddLine(FPanel, 40, 24, TAlphaColors.White, True);
  FStart.Position.Y := 1000;   // keeps the Top order : logo, byline, start

  FText := TText.Create(FPanel);
  FText.Parent := FPanel;
  FText.Align := TAlignLayout.Client;
  FText.Margins.Rect := TRectF.Create(16, 4, 8, 8);
  FText.HitTest := False;
  FText.WordWrap := False;
  FText.TextSettings.Font.Family := 'Consolas';
  FText.TextSettings.Font.Size := 15;
  FText.TextSettings.FontColor := TAlphaColors.White;
  FText.TextSettings.HorzAlign := TTextAlign.Leading;
  FText.TextSettings.VertAlign := TTextAlign.Leading;
end;

function TCabinetOverlay.AddLine(aParent: TFmxObject; aHeight, aSize: Single; aColor: TAlphaColor;
  aBold: Boolean): TText;
begin
  Result := TText.Create(aParent);
  Result.Parent := aParent;
  Result.Align := TAlignLayout.Top;
  Result.Position.Y := 900;
  Result.Height := aHeight;
  Result.HitTest := False;
  Result.WordWrap := False;
  Result.TextSettings.Font.Family := 'Consolas';
  Result.TextSettings.Font.Size := aSize;
  if aBold then
    Result.TextSettings.Font.Style := [TFontStyle.fsBold];
  Result.TextSettings.FontColor := aColor;
  Result.TextSettings.HorzAlign := TTextAlign.Center;
end;

function TCabinetOverlay.GetVisible: Boolean;
begin
  Result := FPanel.Visible;
end;

procedure TCabinetOverlay.Show(aAtStart: Boolean);
begin
  FAtStart := aAtStart;
  FBlink := 0;
  FCapturing := False;
  FWaitRelease := True;   // the key that opened the card must not act on it
  FModified := False;
  FPanel.Visible := True;
  FPanel.BringToFront;
  Refresh;
end;

procedure TCabinetOverlay.Hide;
begin
  FCapturing := False;
  FPanel.Visible := False;
end;

procedure TCabinetOverlay.Refresh;

  function Column(aAction: TCabinetAction; aKind: TBindKind): string;
  var
    lBind: TInputBind;
  begin
    Result := '';
    for lBind in FControls.Binds[aAction] do
      if lBind.Kind = aKind then
      begin
        if Result <> '' then
          Result := Result + ', ';
        if aKind = bkPad then
          Result := Result + Format('%d:%s', [lBind.Pad + 1, BindLabel(lBind)])
        else
          Result := Result + BindLabel(lBind);
      end;
    if Result = '' then
      Result := '-';
    if Length(Result) > CBindWidth - 1 then
      Result := Copy(Result, 1, CBindWidth - 3) + '..';
  end;

  procedure Group(aLines: TStrings; const aName: string; aFrom, aTo: TCabinetAction);
  var
    lAction: TCabinetAction;
    lMark, lPads: string;
  begin
    aLines.Add('');
    aLines.Add(Format('  %-12s%-*s%s', [aName, CBindWidth, Tr('overlay.keyboard', 'KEYBOARD'),
      Tr('overlay.gamepad', 'GAMEPAD')]));
    for lAction := aFrom to aTo do
    begin
      lMark := '  ';
      if lAction = FSelected then
        lMark := '> ';
      if (lAction = FSelected) and FCapturing then
        lPads := Tr('overlay.capture', '<< key or button... (Esc : cancel) >>')
      else
        lPads := Column(lAction, bkKey);
      if (lAction = FSelected) and FCapturing then
        aLines.Add(lMark + Format('%-12s%s', [ActionLabel(lAction), lPads]))
      else
        aLines.Add(lMark + Format('%-12s%-*s%s', [ActionLabel(lAction), CBindWidth, lPads,
          Column(lAction, bkPad)]));
    end;
  end;

var
  lLines: TStringList;
  lPads: string;
begin
  lLines := TStringList.Create;
  try
    FByline.Text := CAuthor + '  ' + #$00B7 + '  ' + TrFmt('overlay.release', 'release %s', [CReleaseDate]);
    if FAtStart then
      FStart.Text := Tr('overlay.start', 'PRESS F1 TO START!')
    else
      FStart.Text := Tr('overlay.resume', 'PRESS F1 TO RESUME');
    lLines.Add(TrFmt('overlay.title', 'CONTROLS - %s', [FTitle]));
    if not TCabinetGamepads.Available then
      lPads := Tr('overlay.noxinput', 'XInput missing : keyboard only')
    else if FControls.Pads.ConnectedCount = 0 then
      lPads := Tr('overlay.nopad', 'no gamepad connected')
    else
      lPads := TrFmt('overlay.pads', '%d gamepad(s) connected - d-pad and left stick = directions',
        [FControls.Pads.ConnectedCount]);
    lLines.Add(lPads);
    Group(lLines, Tr('overlay.player1', 'PLAYER 1'), caP1Up, caP1Button3);
    Group(lLines, Tr('overlay.player2', 'PLAYER 2'), caP2Up, caP2Button3);
    Group(lLines, Tr('overlay.cabinet', 'CABINET'), caCoin1, caService);
    lLines.Add('');
    lLines.Add(Tr('overlay.help1', 'Up/Down select   Enter (A) add   Del (X) clear'));
    lLines.Add(Tr('overlay.help2', 'F5 factory wiring   Esc / F1 / Start : PLAY'));
    lLines.Add('');
    lLines.Add(Tr('overlay.help3', 'In game : F1 controls, M sound, P pause, F3 reset, Esc game menu'));
    FText.Text := lLines.Text;
  finally
    lLines.Free;
  end;
end;

// Everything is released : forget the edge state of the navigation keys, so the next press counts.
procedure TCabinetOverlay.ResetEdges;
const
  CKeys: array[0..5] of Integer = (VK_UP, VK_DOWN, VK_RETURN, VK_DELETE, VK_F5, VK_ESCAPE);
var
  lVk: Integer;
begin
  for lVk in CKeys do
    FControls.KeyPressed(lVk);
  FControls.PadPressed;
end;

function TCabinetOverlay.Tick: Boolean;
var
  lBind: TInputBind;
  lPad: Word;
  lDirty: Boolean;
begin
  Result := True;
  Inc(FBlink);
  FStart.Opacity := Ord((FBlink div CBlinkFrames) mod 2 = 0);
  lDirty := FControls.Pads.ConnectedCount <> FLastPads;
  FLastPads := FControls.Pads.ConnectedCount;

  if FCapturing then
  begin
    if not FArmed then
      FArmed := not FControls.AnyDown
    else if FControls.KeyDown(VK_ESCAPE) then
    begin
      FCapturing := False;
      FWaitRelease := True;
      lDirty := True;
    end
    else if FControls.CaptureAny(lBind) then
    begin
      FControls.AddBind(FSelected, lBind);
      FModified := True;
      FCapturing := False;
      FWaitRelease := True;
      lDirty := True;
    end;
  end
  else if FWaitRelease then
  begin
    if not FControls.AnyDown then
    begin
      FWaitRelease := False;
      ResetEdges;
    end;
  end
  else
  begin
    // read every edge each frame : KeyPressed only sees a press if it's asked about it
    lPad := FControls.PadPressed;
    if FControls.KeyPressed(VK_UP) or ((lPad and PAD_UP) <> 0) then
    begin
      if FSelected = Low(TCabinetAction) then
        FSelected := High(TCabinetAction)
      else
        FSelected := Pred(FSelected);
      lDirty := True;
    end;
    if FControls.KeyPressed(VK_DOWN) or ((lPad and PAD_DOWN) <> 0) then
    begin
      if FSelected = High(TCabinetAction) then
        FSelected := Low(TCabinetAction)
      else
        FSelected := Succ(FSelected);
      lDirty := True;
    end;
    if FControls.KeyPressed(VK_RETURN) or ((lPad and PAD_A) <> 0) then
    begin
      FCapturing := True;
      FArmed := False;
      lDirty := True;
    end;
    if FControls.KeyPressed(VK_DELETE) or ((lPad and PAD_X) <> 0) then
    begin
      FControls.ClearBinds(FSelected);
      FModified := True;
      lDirty := True;
    end;
    if FControls.KeyPressed(VK_F5) then
    begin
      FControls.SetDefaults;
      FModified := True;
      lDirty := True;
    end;
    if FControls.KeyPressed(VK_ESCAPE) or ((lPad and PAD_START) <> 0) then
      Result := False;
  end;
  if lDirty and Result then
    Refresh;
end;

end.
