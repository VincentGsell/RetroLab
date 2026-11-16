unit Cabinet.Menu;

///  The game menu shown when the cabinet starts : the RETROLAB logo, the games of the catalog
///  (ready, or ROM missing), and what to do for the selected one.
///    Up / Down (pad d-pad) or the mouse choose a game, Enter / pad A or Start / a click play it,
///    Esc / pad Back quit.
///  Driven by Tick, once per frame, while no board is plugged in.

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
  Arcade.Catalog,
  Arcade.Cabinet.Gamepad,
  Arcade.Cabinet.Controls,
  Cabinet.Logo;

type
  TCabinetMenu = class
  private
    FControls: TCabinetControls;
    FPanel: TRectangle;
    FRows: TArray<TRectangle>;
    FRowTexts: TArray<TText>;
    FDetail: TText;
    FHelp: TText;
    FRowBox: TRectangle;
    FEntries: TArray<TCatalogEntry>;
    FSelected: Integer;
    FChosen: Integer;
    FWaitRelease: Boolean;
    function AddText(aParent: TFmxObject; aAlign: TAlignLayout; aHeight, aSize: Single;
      aColor: TAlphaColor; aBold: Boolean): TText;
    procedure Refresh;
    procedure RowClick(Sender: TObject);
    procedure RowEnter(Sender: TObject);
    procedure ResetEdges;
    function GetVisible: Boolean;
  public
    constructor Create(aParent: TFmxObject; aControls: TCabinetControls);
    /// aSelect : name of the set to select first ('' : the first one).
    procedure Show(const aEntries: TArray<TCatalogEntry>; const aSelect: string);
    procedure Hide;
    /// One frame : the set to play ('' : none yet). aQuit : the player leaves the cabinet.
    function Tick(out aQuit: Boolean): string;
    property Visible: Boolean read GetVisible;
  end;

implementation

const
  CRowHeight = 34;
  CRowColor = $FF14142A;
  CRowSelected = $FF2A2A55;
  CReady = $FFFFFFFF;
  CMissing = $FF707090;

{ TCabinetMenu }

constructor TCabinetMenu.Create(aParent: TFmxObject; aControls: TCabinetControls);
var
  lLogo: TImage;
  lTagline: TText;
begin
  inherited Create;
  FControls := aControls;
  FChosen := -1;

  FPanel := TRectangle.Create(aParent);
  FPanel.Parent := aParent;
  FPanel.Align := TAlignLayout.Contents;
  FPanel.Fill.Color := $FF0A0A14;
  FPanel.Stroke.Kind := TBrushKind.None;
  FPanel.Visible := False;

  lLogo := TImage.Create(FPanel);
  lLogo.Parent := FPanel;
  lLogo.Align := TAlignLayout.Top;
  lLogo.Height := 64;
  lLogo.Margins.Rect := TRectF.Create(24, 40, 24, 0);
  lLogo.WrapMode := TImageWrapMode.Fit;
  lLogo.DisableInterpolation := True;
  lLogo.HitTest := False;
  DrawLogo(lLogo.Bitmap, CLogoText);

  lTagline := AddText(FPanel, TAlignLayout.Top, 28, 13, $FFFFA010, True);
  lTagline.Position.Y := 900;
  lTagline.Text := CTagline;

  FRowBox := TRectangle.Create(FPanel);
  FRowBox.Parent := FPanel;
  FRowBox.Align := TAlignLayout.Top;
  FRowBox.Position.Y := 950;
  FRowBox.Margins.Rect := TRectF.Create(24, 32, 24, 0);
  FRowBox.Fill.Kind := TBrushKind.None;
  FRowBox.Stroke.Kind := TBrushKind.None;
  FRowBox.HitTest := False;

  FDetail := AddText(FPanel, TAlignLayout.Top, 150, 14, $FF80C8FF, False);
  FDetail.Position.Y := 1000;
  FDetail.Margins.Rect := TRectF.Create(32, 24, 32, 0);
  FDetail.WordWrap := True;
  FDetail.TextSettings.HorzAlign := TTextAlign.Leading;
  FDetail.TextSettings.VertAlign := TTextAlign.Leading;

  FHelp := AddText(FPanel, TAlignLayout.Bottom, 56, 13, $FF9A9AB8, False);
end;

function TCabinetMenu.AddText(aParent: TFmxObject; aAlign: TAlignLayout; aHeight, aSize: Single;
  aColor: TAlphaColor; aBold: Boolean): TText;
begin
  Result := TText.Create(aParent);
  Result.Parent := aParent;
  Result.Align := aAlign;
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

function TCabinetMenu.GetVisible: Boolean;
begin
  Result := FPanel.Visible;
end;

procedure TCabinetMenu.Show(const aEntries: TArray<TCatalogEntry>; const aSelect: string);
var
  i: Integer;
  lRow: TRectangle;
  lText: TText;
begin
  for lRow in FRows do
    lRow.Free;
  FEntries := aEntries;
  SetLength(FRows, Length(FEntries));
  SetLength(FRowTexts, Length(FEntries));
  FRowBox.Height := Length(FEntries) * CRowHeight + 8;
  for i := 0 to High(FEntries) do
  begin
    lRow := TRectangle.Create(FRowBox);
    lRow.Parent := FRowBox;
    lRow.Align := TAlignLayout.Top;
    lRow.Position.Y := 1000 + i * 1000;   // Top-aligned controls stack in Position.Y order
    lRow.Height := CRowHeight - 4;
    lRow.Margins.Bottom := 4;
    lRow.Stroke.Kind := TBrushKind.None;
    lRow.Cursor := crHandPoint;
    lRow.Tag := i;
    lRow.OnClick := RowClick;
    lRow.OnMouseEnter := RowEnter;
    lText := AddText(lRow, TAlignLayout.Client, CRowHeight, 15, CReady, False);
    lText.Margins.Left := 12;
    lText.TextSettings.HorzAlign := TTextAlign.Leading;
    FRows[i] := lRow;
    FRowTexts[i] := lText;
  end;
  FSelected := 0;
  for i := 0 to High(FEntries) do
    if SameText(FEntries[i].Def.Name, aSelect) then
      FSelected := i;
  FChosen := -1;
  FWaitRelease := True;   // the key that brought the menu back must not act on it
  FPanel.Visible := True;
  FPanel.BringToFront;
  Refresh;
end;

procedure TCabinetMenu.Hide;
begin
  FPanel.Visible := False;
end;

procedure TCabinetMenu.Refresh;
var
  i: Integer;
  lEntry: TCatalogEntry;
  lStatus, lMethod: string;
begin
  for i := 0 to High(FEntries) do
  begin
    lEntry := FEntries[i];
    if lEntry.Available then
      lStatus := Tr('menu.ready', 'READY')
    else
      lStatus := Tr('menu.norom', 'ROM MISSING');
    if lEntry.Method = rmNative then
      lMethod := Tr('menu.native', 'NATIVE BINARY')
    else
      lMethod := Tr('menu.emulated', 'EMULATED');
    FRowTexts[i].Text := Format('%-34s %-12s %-14s %s', [lEntry.Def.Title, lEntry.Def.Maker + ' ' + lEntry.Def.Year,
      lStatus, lMethod]);
    if lEntry.Available then
      FRowTexts[i].TextSettings.FontColor := CReady
    else
      FRowTexts[i].TextSettings.FontColor := CMissing;
    if i = FSelected then
      FRows[i].Fill.Color := CRowSelected
    else
      FRows[i].Fill.Color := CRowColor;
  end;

  if Length(FEntries) = 0 then
    FDetail.Text := ''
  else
  begin
    lEntry := FEntries[FSelected];
    if lEntry.Available then
      FDetail.Text := TrFmt('menu.play', '%s : Enter, A or a click to play.', [lEntry.Def.Title])
    else
      FDetail.Text := TrFmt('menu.howto', 'To play %s, put the MAME set "%s" as %s.zip in :', [lEntry.Def.Title,
        lEntry.Def.Title, lEntry.Def.Name]) + sLineBreak +
        ExtractFilePath(ParamStr(0)) + 'roms\' + sLineBreak + sLineBreak + lEntry.Problem;
  end;
  FHelp.Text := Tr('menu.help', 'Up/Down : choose   Enter, A or click : play   Esc : quit') + sLineBreak +
    Tr('menu.ingame', 'In game : F1 controls, Esc back to this menu');
end;

procedure TCabinetMenu.RowClick(Sender: TObject);
begin
  FSelected := TControl(Sender).Tag;
  if FEntries[FSelected].Available then
    FChosen := FSelected;
  Refresh;
end;

procedure TCabinetMenu.RowEnter(Sender: TObject);
begin
  FSelected := TControl(Sender).Tag;
  Refresh;
end;

// Everything is released : forget the edge state of the navigation keys, so the next press counts.
procedure TCabinetMenu.ResetEdges;
const
  CKeys: array[0..3] of Integer = (VK_UP, VK_DOWN, VK_RETURN, VK_ESCAPE);
var
  lVk: Integer;
begin
  for lVk in CKeys do
    FControls.KeyPressed(lVk);
end;

function TCabinetMenu.Tick(out aQuit: Boolean): string;
var
  lPad: Word;
  lDirty: Boolean;
begin
  aQuit := False;
  Result := '';
  if FChosen >= 0 then
  begin
    Result := FEntries[FChosen].Def.Name;
    FChosen := -1;
    Exit;
  end;
  if Length(FEntries) = 0 then
    Exit;
  if FWaitRelease then
  begin
    if not FControls.AnyDown then
    begin
      FWaitRelease := False;
      ResetEdges;
    end;
    Exit;
  end;

  lDirty := False;
  lPad := FControls.PadPressed;
  if FControls.KeyPressed(VK_UP) or ((lPad and PAD_UP) <> 0) then
  begin
    FSelected := (FSelected + Length(FEntries) - 1) mod Length(FEntries);
    lDirty := True;
  end;
  if FControls.KeyPressed(VK_DOWN) or ((lPad and PAD_DOWN) <> 0) then
  begin
    FSelected := (FSelected + 1) mod Length(FEntries);
    lDirty := True;
  end;
  if FControls.KeyPressed(VK_RETURN) or ((lPad and (PAD_A or PAD_START)) <> 0) then
    if FEntries[FSelected].Available then
      Result := FEntries[FSelected].Def.Name;
  if FControls.KeyPressed(VK_ESCAPE) or ((lPad and PAD_BACK) <> 0) then
    aQuit := True;
  if lDirty then
    Refresh;
end;

end.
