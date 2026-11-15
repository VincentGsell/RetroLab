unit Arcade.Cabinet.Controls;

///  CABINET - the control panel : PC keyboard + XInput gamepads -> joysticks, buttons, coin and
///  start switches of both players. Polled once per frame, only while the cabinet window has the focus.
///  The wiring is a table of bindings (several keys / pad buttons per switch), editable from the
///  cabinet's overlay and saved in an INI file next to the exe :
///    [Bindings]
///    P1.Button1=KEY:X, KEY:SPACE, PAD1:A
///  Default wiring :
///    player 1 : arrows, X / Space / Ctrl = button 1, Z / Alt = button 2, C = button 3 ; gamepad 1
///    player 2 : R F D G, A = button 1, S = button 2, Q = button 3 ; gamepad 2
///    5 / 6 coin 1 / 2 (pad Back), 1 / 2 start 1 / 2 (pad Start), F2 service
///  Cabinet keys (M, P, F1, F3, Esc) are reserved : they can't be bound to a switch.
///  Windows only.

interface

uses
  System.SysUtils,
  System.Classes,
  System.IniFiles,
  Winapi.Windows,
  GS.Common.I18n,
  Arcade.Board,
  Arcade.Cabinet.Gamepad;

type
  /// Every switch of the panel ; the order follows TArcadeButton then TArcadeSystem.
  TCabinetAction = (
    caP1Up, caP1Down, caP1Left, caP1Right, caP1Button1, caP1Button2, caP1Button3,
    caP2Up, caP2Down, caP2Left, caP2Right, caP2Button1, caP2Button2, caP2Button3,
    caCoin1, caCoin2, caStart1, caStart2, caService);

  TBindKind = (bkKey, bkPad);

  /// One physical input : a key (virtual key code) or a button of gamepad Pad (0..3, PAD_xx mask).
  TInputBind = record
    Kind: TBindKind;
    Pad: Byte;
    Code: Word;
    class function Key(aVk: Word): TInputBind; static;
    class function PadButton(aPad: Byte; aMask: Word): TInputBind; static;
    function SameAs(const aOther: TInputBind): Boolean;
  end;

  TCabinetControls = class
  public const
    CMaxBinds = 6;
  private
    FPrevKeys: array[0..255] of Boolean;
    FPads: TCabinetGamepads;
    FBinds: array[TCabinetAction] of TArray<TInputBind>;
    function BindDown(const aBind: TInputBind): Boolean;
    function GetBinds(aAction: TCabinetAction): TArray<TInputBind>;
  public
    /// Show the controls overlay when the cabinet is switched on.
    ShowAtStart: Boolean;
    constructor Create;
    destructor Destroy; override;
    /// Once per frame, before anything reads the panel (gamepads).
    procedure Poll;
    function KeyDown(aVk: Integer): Boolean;
    /// Edge-triggered : true once per press (cabinet keys : pause, reset...).
    function KeyPressed(aVk: Integer): Boolean;
    /// Rising edges of every connected gamepad, OR-ed.
    function PadPressed: Word;
    /// Current panel state ; all released when aFocused is false.
    function Read(aFocused: Boolean): TArcadeInputs;
    /// Anything held, keyboard or gamepad (waiting for release before a capture).
    function AnyDown: Boolean;
    /// The first key / pad button currently held that may be bound (reserved keys skipped).
    function CaptureAny(out aBind: TInputBind): Boolean;

    procedure SetDefaults;
    /// Adds aBind to aAction and removes it from every other switch (one input, one switch).
    procedure AddBind(aAction: TCabinetAction; const aBind: TInputBind);
    procedure ClearBinds(aAction: TCabinetAction);
    /// False when the file doesn't exist (defaults kept).
    function LoadFromFile(const aFile: string): Boolean;
    procedure SaveToFile(const aFile: string);

    property Binds[aAction: TCabinetAction]: TArray<TInputBind> read GetBinds;
    property Pads: TCabinetGamepads read FPads;
  end;

/// 'P1.Button1' : the INI name of a switch.
function ActionId(aAction: TCabinetAction): string;
/// 'Button 1' : the switch as shown to the player (translated).
function ActionLabel(aAction: TCabinetAction): string;
/// 'KEY:SPACE', 'PAD1:A' : INI form.
function BindToken(const aBind: TInputBind): string;
function ParseBind(const aToken: string; out aBind: TInputBind): Boolean;
/// 'Space', 'A' : the input as shown to the player, translated (pad number not included).
function BindLabel(const aBind: TInputBind): string;
function IsReservedKey(aVk: Integer): Boolean;

implementation

type
  TKeyName = record
    Vk: Word;
    Token, Caption: string;
  end;
  TPadName = record
    Mask: Word;
    Token, Caption: string;
  end;

const
  CActionIds: array[TCabinetAction] of string = (
    'P1.Up', 'P1.Down', 'P1.Left', 'P1.Right', 'P1.Button1', 'P1.Button2', 'P1.Button3',
    'P2.Up', 'P2.Down', 'P2.Left', 'P2.Right', 'P2.Button1', 'P2.Button2', 'P2.Button3',
    'Coin1', 'Coin2', 'Start1', 'Start2', 'Service');
  CActionLabels: array[TCabinetAction] of string = (
    'Up', 'Down', 'Left', 'Right', 'Button 1', 'Button 2', 'Button 3',
    'Up', 'Down', 'Left', 'Right', 'Button 1', 'Button 2', 'Button 3',
    'Coin 1', 'Coin 2', 'Start 1', 'Start 2', 'Service');
  // translation keys : controls.<id> (P1 and P2 share the labels)
  CActionKeys: array[TCabinetAction] of string = (
    'up', 'down', 'left', 'right', 'button1', 'button2', 'button3',
    'up', 'down', 'left', 'right', 'button1', 'button2', 'button3',
    'coin1', 'coin2', 'start1', 'start2', 'service');

  CKeyNames: array[0..20] of TKeyName = (
    (Vk: VK_UP; Token: 'UP'; Caption: 'Up'),
    (Vk: VK_DOWN; Token: 'DOWN'; Caption: 'Down'),
    (Vk: VK_LEFT; Token: 'LEFT'; Caption: 'Left'),
    (Vk: VK_RIGHT; Token: 'RIGHT'; Caption: 'Right'),
    (Vk: VK_SPACE; Token: 'SPACE'; Caption: 'Space'),
    (Vk: VK_CONTROL; Token: 'CTRL'; Caption: 'Ctrl'),
    (Vk: VK_MENU; Token: 'ALT'; Caption: 'Alt'),
    (Vk: VK_SHIFT; Token: 'SHIFT'; Caption: 'Shift'),
    (Vk: VK_RETURN; Token: 'ENTER'; Caption: 'Enter'),
    (Vk: VK_TAB; Token: 'TAB'; Caption: 'Tab'),
    (Vk: VK_BACK; Token: 'BACKSPACE'; Caption: 'Backspace'),
    (Vk: VK_INSERT; Token: 'INSERT'; Caption: 'Insert'),
    (Vk: VK_DELETE; Token: 'DELETE'; Caption: 'Delete'),
    (Vk: VK_HOME; Token: 'HOME'; Caption: 'Home'),
    (Vk: VK_END; Token: 'END'; Caption: 'End'),
    (Vk: VK_PRIOR; Token: 'PGUP'; Caption: 'PgUp'),
    (Vk: VK_NEXT; Token: 'PGDN'; Caption: 'PgDn'),
    (Vk: VK_LWIN; Token: 'LWIN'; Caption: 'Win'),
    (Vk: VK_CAPITAL; Token: 'CAPSLOCK'; Caption: 'CapsLock'),
    (Vk: VK_ADD; Token: 'NUMPLUS'; Caption: 'Num +'),
    (Vk: VK_SUBTRACT; Token: 'NUMMINUS'; Caption: 'Num -'));

  CPadNames: array[0..15] of TPadName = (
    (Mask: PAD_UP; Token: 'UP'; Caption: 'Up'),
    (Mask: PAD_DOWN; Token: 'DOWN'; Caption: 'Down'),
    (Mask: PAD_LEFT; Token: 'LEFT'; Caption: 'Left'),
    (Mask: PAD_RIGHT; Token: 'RIGHT'; Caption: 'Right'),
    (Mask: PAD_A; Token: 'A'; Caption: 'A'),
    (Mask: PAD_B; Token: 'B'; Caption: 'B'),
    (Mask: PAD_X; Token: 'X'; Caption: 'X'),
    (Mask: PAD_Y; Token: 'Y'; Caption: 'Y'),
    (Mask: PAD_LB; Token: 'LB'; Caption: 'LB'),
    (Mask: PAD_RB; Token: 'RB'; Caption: 'RB'),
    (Mask: PAD_LT; Token: 'LT'; Caption: 'LT'),
    (Mask: PAD_RT; Token: 'RT'; Caption: 'RT'),
    (Mask: PAD_START; Token: 'START'; Caption: 'Start'),
    (Mask: PAD_BACK; Token: 'BACK'; Caption: 'Back'),
    (Mask: PAD_LS; Token: 'LS'; Caption: 'L3'),
    (Mask: PAD_RS; Token: 'RS'; Caption: 'R3'));

  CSection = 'Bindings';

function ActionId(aAction: TCabinetAction): string;
begin
  Result := CActionIds[aAction];
end;

function ActionLabel(aAction: TCabinetAction): string;
begin
  Result := Tr('controls.' + CActionKeys[aAction], CActionLabels[aAction]);
end;

function IsReservedKey(aVk: Integer): Boolean;
begin
  Result := (aVk = VK_ESCAPE) or (aVk = VK_F1) or (aVk = VK_F3) or (aVk = Ord('M')) or (aVk = Ord('P'));
end;

// Keys a capture may return : no mouse buttons, generic Shift / Ctrl / Alt only (not their
// left / right twins, which GetAsyncKeyState reports at the same time).
function IsCapturableKey(aVk: Integer): Boolean;
begin
  Result := (aVk >= VK_BACK) and (aVk <= $FE) and not (aVk in [VK_LSHIFT..VK_RMENU])
    and not IsReservedKey(aVk);
end;

function KeyToken(aVk: Word): string;
var
  i: Integer;
begin
  for i := 0 to High(CKeyNames) do
    if CKeyNames[i].Vk = aVk then
      Exit(CKeyNames[i].Token);
  case aVk of
    Ord('A')..Ord('Z'), Ord('0')..Ord('9'): Result := Char(aVk);
    VK_F1..VK_F24: Result := 'F' + IntToStr(aVk - VK_F1 + 1);
    VK_NUMPAD0..VK_NUMPAD9: Result := 'NUM' + IntToStr(aVk - VK_NUMPAD0);
  else
    Result := 'VK' + IntToHex(aVk, 2);
  end;
end;

function KeyCaption(aVk: Word): string;
var
  i: Integer;
  lChar: UINT;
begin
  for i := 0 to High(CKeyNames) do
    if CKeyNames[i].Vk = aVk then
      Exit(Tr('key.' + LowerCase(CKeyNames[i].Token), CKeyNames[i].Caption));
  case aVk of
    Ord('A')..Ord('Z'), Ord('0')..Ord('9'): Result := Char(aVk);
    VK_F1..VK_F24: Result := 'F' + IntToStr(aVk - VK_F1 + 1);
    VK_NUMPAD0..VK_NUMPAD9: Result := TrFmt('key.numpad', 'Num %d', [aVk - VK_NUMPAD0]);
  else
    // punctuation keys : the character printed on the key of the current layout
    lChar := MapVirtualKey(aVk, 2 {MAPVK_VK_TO_CHAR}) and $FFFF;
    if lChar > 32 then
      Result := Char(lChar)
    else
      Result := 'VK' + IntToHex(aVk, 2);
  end;
end;

function BindToken(const aBind: TInputBind): string;
var
  i: Integer;
begin
  if aBind.Kind = bkKey then
    Exit('KEY:' + KeyToken(aBind.Code));
  Result := Format('PAD%d:', [aBind.Pad + 1]);
  for i := 0 to High(CPadNames) do
    if CPadNames[i].Mask = aBind.Code then
      Exit(Result + CPadNames[i].Token);
  Result := Result + IntToHex(aBind.Code, 4);
end;

function BindLabel(const aBind: TInputBind): string;
var
  i: Integer;
begin
  if aBind.Kind = bkKey then
    Exit(KeyCaption(aBind.Code));
  for i := 0 to High(CPadNames) do
    if CPadNames[i].Mask = aBind.Code then
      Exit(Tr('pad.' + LowerCase(CPadNames[i].Token), CPadNames[i].Caption));
  Result := IntToHex(aBind.Code, 4);
end;

function ParseBind(const aToken: string; out aBind: TInputBind): Boolean;
var
  lToken, lName: string;
  i, lPad, lVk: Integer;
begin
  Result := False;
  lToken := UpperCase(Trim(aToken));
  if lToken.StartsWith('KEY:') then
  begin
    lName := Copy(lToken, 5, MaxInt);
    for i := 0 to High(CKeyNames) do
      if CKeyNames[i].Token = lName then
      begin
        aBind := TInputBind.Key(CKeyNames[i].Vk);
        Exit(True);
      end;
    lVk := -1;
    if (Length(lName) = 1) and CharInSet(lName[1], ['A'..'Z', '0'..'9']) then
      lVk := Ord(lName[1])
    else if lName.StartsWith('NUM') then
      lVk := VK_NUMPAD0 + StrToIntDef(Copy(lName, 4, MaxInt), -VK_NUMPAD0 - 1)
    else if (Length(lName) >= 2) and (lName[1] = 'F') then
      lVk := VK_F1 - 1 + StrToIntDef(Copy(lName, 2, MaxInt), -VK_F1)
    else if lName.StartsWith('VK') then
      lVk := StrToIntDef('$' + Copy(lName, 3, MaxInt), -1);
    if (lVk > 0) and (lVk < 256) then
    begin
      aBind := TInputBind.Key(lVk);
      Result := True;
    end;
  end
  else if lToken.StartsWith('PAD') and (Length(lToken) > 5) and (lToken[5] = ':') then
  begin
    lPad := StrToIntDef(lToken[4], 0) - 1;
    if (lPad < 0) or (lPad >= CPadMax) then
      Exit;
    lName := Copy(lToken, 6, MaxInt);
    for i := 0 to High(CPadNames) do
      if CPadNames[i].Token = lName then
      begin
        aBind := TInputBind.PadButton(lPad, CPadNames[i].Mask);
        Exit(True);
      end;
  end;
end;

{ TInputBind }

class function TInputBind.Key(aVk: Word): TInputBind;
begin
  Result.Kind := bkKey;
  Result.Pad := 0;
  Result.Code := aVk;
end;

class function TInputBind.PadButton(aPad: Byte; aMask: Word): TInputBind;
begin
  Result.Kind := bkPad;
  Result.Pad := aPad;
  Result.Code := aMask;
end;

function TInputBind.SameAs(const aOther: TInputBind): Boolean;
begin
  Result := (Kind = aOther.Kind) and (Code = aOther.Code) and ((Kind = bkKey) or (Pad = aOther.Pad));
end;

{ TCabinetControls }

constructor TCabinetControls.Create;
begin
  inherited Create;
  FPads := TCabinetGamepads.Create;
  ShowAtStart := True;
  SetDefaults;
end;

destructor TCabinetControls.Destroy;
begin
  FPads.Free;
  inherited;
end;

procedure TCabinetControls.Poll;
begin
  FPads.Update;
end;

function TCabinetControls.KeyDown(aVk: Integer): Boolean;
begin
  Result := (GetAsyncKeyState(aVk) and $8000) <> 0;
end;

function TCabinetControls.KeyPressed(aVk: Integer): Boolean;
var
  lDown: Boolean;
begin
  lDown := KeyDown(aVk);
  Result := lDown and not FPrevKeys[aVk];
  FPrevKeys[aVk] := lDown;
end;

function TCabinetControls.PadPressed: Word;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to CPadMax - 1 do
    Result := Result or FPads.Pressed(i);
end;

function TCabinetControls.BindDown(const aBind: TInputBind): Boolean;
begin
  if aBind.Kind = bkKey then
    Result := KeyDown(aBind.Code)
  else
    Result := (FPads.Buttons(aBind.Pad) and aBind.Code) <> 0;
end;

function TCabinetControls.GetBinds(aAction: TCabinetAction): TArray<TInputBind>;
begin
  Result := FBinds[aAction];
end;

function TCabinetControls.Read(aFocused: Boolean): TArcadeInputs;
var
  lAction: TCabinetAction;
  lBind: TInputBind;
  lDown: Boolean;
begin
  Result := Default(TArcadeInputs);
  if not aFocused then
    Exit;
  for lAction := Low(TCabinetAction) to High(TCabinetAction) do
  begin
    lDown := False;
    for lBind in FBinds[lAction] do
      if BindDown(lBind) then
      begin
        lDown := True;
        Break;
      end;
    if not lDown then
      Continue;
    case lAction of
      caP1Up..caP1Button3: Include(Result.Players[0], TArcadeButton(Ord(lAction) - Ord(caP1Up)));
      caP2Up..caP2Button3: Include(Result.Players[1], TArcadeButton(Ord(lAction) - Ord(caP2Up)));
    else
      Include(Result.System, TArcadeSystem(Ord(lAction) - Ord(caCoin1)));
    end;
  end;
end;

function TCabinetControls.AnyDown: Boolean;
var
  i: Integer;
begin
  for i := VK_BACK to $FE do
    if KeyDown(i) then
      Exit(True);
  for i := 0 to CPadMax - 1 do
    if FPads.Buttons(i) <> 0 then
      Exit(True);
  Result := False;
end;

function TCabinetControls.CaptureAny(out aBind: TInputBind): Boolean;
var
  i, b: Integer;
  lButtons: Word;
begin
  for i := 0 to CPadMax - 1 do
  begin
    lButtons := FPads.Buttons(i);
    if lButtons <> 0 then
      for b := 0 to 15 do
        if (lButtons and (1 shl b)) <> 0 then
        begin
          aBind := TInputBind.PadButton(i, 1 shl b);
          Exit(True);
        end;
  end;
  for i := VK_BACK to $FE do
    if IsCapturableKey(i) and KeyDown(i) then
    begin
      aBind := TInputBind.Key(i);
      Exit(True);
    end;
  Result := False;
end;

procedure TCabinetControls.SetDefaults;

  procedure Keys(aAction: TCabinetAction; const aVks: array of Word);
  var
    lVk: Word;
  begin
    for lVk in aVks do
      AddBind(aAction, TInputBind.Key(lVk));
  end;

var
  lAction: TCabinetAction;
  lPad: Integer;
begin
  for lAction := Low(TCabinetAction) to High(TCabinetAction) do
    FBinds[lAction] := nil;
  Keys(caP1Up, [VK_UP]);
  Keys(caP1Down, [VK_DOWN]);
  Keys(caP1Left, [VK_LEFT]);
  Keys(caP1Right, [VK_RIGHT]);
  Keys(caP1Button1, [Ord('X'), VK_SPACE, VK_CONTROL]);
  Keys(caP1Button2, [Ord('Z'), VK_MENU]);
  Keys(caP1Button3, [Ord('C')]);
  Keys(caP2Up, [Ord('R')]);
  Keys(caP2Down, [Ord('F')]);
  Keys(caP2Left, [Ord('D')]);
  Keys(caP2Right, [Ord('G')]);
  Keys(caP2Button1, [Ord('A')]);
  Keys(caP2Button2, [Ord('S')]);
  Keys(caP2Button3, [Ord('Q')]);
  Keys(caCoin1, [Ord('5')]);
  Keys(caCoin2, [Ord('6')]);
  Keys(caStart1, [Ord('1')]);
  Keys(caStart2, [Ord('2')]);
  Keys(caService, [VK_F2]);
  // gamepad 1 -> player 1, gamepad 2 -> player 2
  for lPad := 0 to 1 do
  begin
    lAction := TCabinetAction(Ord(caP1Up) + lPad * (Ord(caP2Up) - Ord(caP1Up)));
    AddBind(lAction, TInputBind.PadButton(lPad, PAD_UP));
    AddBind(Succ(lAction), TInputBind.PadButton(lPad, PAD_DOWN));
    AddBind(TCabinetAction(Ord(lAction) + 2), TInputBind.PadButton(lPad, PAD_LEFT));
    AddBind(TCabinetAction(Ord(lAction) + 3), TInputBind.PadButton(lPad, PAD_RIGHT));
    AddBind(TCabinetAction(Ord(lAction) + 4), TInputBind.PadButton(lPad, PAD_A));
    AddBind(TCabinetAction(Ord(lAction) + 5), TInputBind.PadButton(lPad, PAD_B));
    AddBind(TCabinetAction(Ord(lAction) + 6), TInputBind.PadButton(lPad, PAD_X));
    AddBind(TCabinetAction(Ord(caCoin1) + lPad), TInputBind.PadButton(lPad, PAD_BACK));
    AddBind(TCabinetAction(Ord(caStart1) + lPad), TInputBind.PadButton(lPad, PAD_START));
  end;
end;

procedure TCabinetControls.AddBind(aAction: TCabinetAction; const aBind: TInputBind);
var
  lAction: TCabinetAction;
  i: Integer;
begin
  for lAction := Low(TCabinetAction) to High(TCabinetAction) do
    for i := High(FBinds[lAction]) downto 0 do
      if FBinds[lAction][i].SameAs(aBind) then
        Delete(FBinds[lAction], i, 1);
  if Length(FBinds[aAction]) >= CMaxBinds then
    Delete(FBinds[aAction], 0, 1);   // full : the oldest one goes
  FBinds[aAction] := FBinds[aAction] + [aBind];
end;

procedure TCabinetControls.ClearBinds(aAction: TCabinetAction);
begin
  FBinds[aAction] := nil;
end;

function TCabinetControls.LoadFromFile(const aFile: string): Boolean;
var
  lIni: TMemIniFile;
  lAction: TCabinetAction;
  lToken: string;
  lBind: TInputBind;
begin
  Result := FileExists(aFile);
  if not Result then
    Exit;
  lIni := TMemIniFile.Create(aFile, TEncoding.UTF8);
  try
    ShowAtStart := lIni.ReadBool('General', 'ShowAtStart', True);
    for lAction := Low(TCabinetAction) to High(TCabinetAction) do
      if lIni.ValueExists(CSection, ActionId(lAction)) then
      begin
        FBinds[lAction] := nil;
        for lToken in lIni.ReadString(CSection, ActionId(lAction), '').Split([',']) do
          if ParseBind(lToken, lBind) then
            AddBind(lAction, lBind);
      end;
  finally
    lIni.Free;
  end;
end;

procedure TCabinetControls.SaveToFile(const aFile: string);
var
  lIni: TMemIniFile;
  lAction: TCabinetAction;
  lTokens: TStringList;
  lBind: TInputBind;
begin
  lIni := TMemIniFile.Create(aFile, TEncoding.UTF8);
  lTokens := TStringList.Create;
  try
    lIni.WriteBool('General', 'ShowAtStart', ShowAtStart);
    for lAction := Low(TCabinetAction) to High(TCabinetAction) do
    begin
      lTokens.Clear;
      for lBind in FBinds[lAction] do
        lTokens.Add(BindToken(lBind));
      lIni.WriteString(CSection, ActionId(lAction), String.Join(', ', lTokens.ToStringArray));
    end;
    lIni.UpdateFile;
  finally
    lTokens.Free;
    lIni.Free;
  end;
end;

end.
