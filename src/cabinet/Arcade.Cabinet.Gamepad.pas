unit Arcade.Cabinet.Gamepad;

///  CABINET - the gamepads plugged into the control panel : XInput, up to 4, polled once per frame.
///  Self-contained (same approach as GS.FMeX.Input.Gamepad, no FMeX dependency) :
///    - xinput1_4 / 1_3 / 9_1_0 loaded dynamically : no XInput at all is not an error, the
///      cabinet plays on the keyboard ;
///    - an empty port is only re-probed every 2 s (XInputGetState on an empty port costs ~0.5 ms) ;
///    - the left stick is folded into the d-pad bits (radial dead zone, 8 directions), the
///      triggers into two spare bits : a pad is one Word of buttons, nothing analog.
///  Windows only.

interface

uses
  Winapi.Windows;

const
  CPadMax = 4;

  // XInput button masks ; LT / RT use the two bits XInput leaves free.
  PAD_UP    = $0001;
  PAD_DOWN  = $0002;
  PAD_LEFT  = $0004;
  PAD_RIGHT = $0008;
  PAD_START = $0010;
  PAD_BACK  = $0020;
  PAD_LS    = $0040;
  PAD_RS    = $0080;
  PAD_LB    = $0100;
  PAD_RB    = $0200;
  PAD_LT    = $0400;
  PAD_RT    = $0800;
  PAD_A     = $1000;
  PAD_B     = $2000;
  PAD_X     = $4000;
  PAD_Y     = $8000;

type
  TCabinetGamepads = class
  private
    FButtons: array[0..CPadMax - 1] of Word;
    FPrev: array[0..CPadMax - 1] of Word;
    FConnected: array[0..CPadMax - 1] of Boolean;
    FRetry: array[0..CPadMax - 1] of Integer;   // frames before re-probing an empty port
  public
    constructor Create;
    /// Once per frame.
    procedure Update;
    function Connected(aPad: Integer): Boolean;
    function ConnectedCount: Integer;
    /// Current buttons (stick folded into the d-pad, triggers into PAD_LT / PAD_RT).
    function Buttons(aPad: Integer): Word;
    /// Rising edges of this frame.
    function Pressed(aPad: Integer): Word;
    class function Available: Boolean; static;
  end;

implementation

type
  TXInputGamepad = record
    wButtons: Word;
    bLeftTrigger, bRightTrigger: Byte;
    sThumbLX, sThumbLY, sThumbRX, sThumbRY: SmallInt;
  end;
  TXInputState = record
    dwPacketNumber: DWORD;
    Gamepad: TXInputGamepad;
  end;
  TXInputGetState = function(dwUserIndex: DWORD; var pState: TXInputState): DWORD; stdcall;

const
  CRetryFrames = 120;
  CStickDead = 7849 / 32767;     // XInput recommended left stick dead zone
  CStickAxis = 0.38;             // ~sin 22.5 deg : 8 equal direction sectors
  CTriggerMin = 30;

var
  GLib: HMODULE = 0;
  GGetState: TXInputGetState = nil;
  GTried: Boolean = False;

procedure EnsureLoaded;
const
  CDlls: array[0..2] of string = ('xinput1_4.dll', 'xinput1_3.dll', 'xinput9_1_0.dll');
var
  i: Integer;
begin
  if GTried then
    Exit;
  GTried := True;
  for i := 0 to High(CDlls) do
  begin
    GLib := LoadLibrary(PChar(CDlls[i]));
    if GLib <> 0 then
      Break;
  end;
  if GLib <> 0 then
    GGetState := GetProcAddress(GLib, 'XInputGetState');
end;

// Radial dead zone, then the direction of the unit vector : no dead cross, exact diagonals.
function StickButtons(aX, aY: SmallInt): Word;
var
  x, y, m: Single;
begin
  Result := 0;
  x := aX / 32767;
  y := aY / 32767;
  m := Sqrt(x * x + y * y);
  if m <= CStickDead then
    Exit;
  x := x / m;
  y := y / m;
  if x > CStickAxis then Result := Result or PAD_RIGHT;
  if x < -CStickAxis then Result := Result or PAD_LEFT;
  if y > CStickAxis then Result := Result or PAD_UP;
  if y < -CStickAxis then Result := Result or PAD_DOWN;
end;

{ TCabinetGamepads }

constructor TCabinetGamepads.Create;
begin
  inherited Create;
  EnsureLoaded;
end;

class function TCabinetGamepads.Available: Boolean;
begin
  EnsureLoaded;
  Result := Assigned(GGetState);
end;

procedure TCabinetGamepads.Update;
var
  i: Integer;
  lState: TXInputState;
  lButtons: Word;
begin
  if not Assigned(GGetState) then
    Exit;
  for i := 0 to CPadMax - 1 do
  begin
    FPrev[i] := FButtons[i];
    if not FConnected[i] then
    begin
      Dec(FRetry[i]);
      if FRetry[i] > 0 then
        Continue;
      FRetry[i] := CRetryFrames;
    end;
    FillChar(lState, SizeOf(lState), 0);
    if GGetState(DWORD(i), lState) <> ERROR_SUCCESS then
    begin
      FConnected[i] := False;
      FButtons[i] := 0;
      FPrev[i] := 0;
      Continue;
    end;
    FConnected[i] := True;
    lButtons := lState.Gamepad.wButtons and not (PAD_LT or PAD_RT);
    lButtons := lButtons or StickButtons(lState.Gamepad.sThumbLX, lState.Gamepad.sThumbLY);
    if lState.Gamepad.bLeftTrigger > CTriggerMin then lButtons := lButtons or PAD_LT;
    if lState.Gamepad.bRightTrigger > CTriggerMin then lButtons := lButtons or PAD_RT;
    FButtons[i] := lButtons;
  end;
end;

function TCabinetGamepads.Connected(aPad: Integer): Boolean;
begin
  Result := (aPad >= 0) and (aPad < CPadMax) and FConnected[aPad];
end;

function TCabinetGamepads.ConnectedCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to CPadMax - 1 do
    if FConnected[i] then
      Inc(Result);
end;

function TCabinetGamepads.Buttons(aPad: Integer): Word;
begin
  if Connected(aPad) then
    Result := FButtons[aPad]
  else
    Result := 0;
end;

function TCabinetGamepads.Pressed(aPad: Integer): Word;
begin
  if Connected(aPad) then
    Result := FButtons[aPad] and not FPrev[aPad]
  else
    Result := 0;
end;

initialization

finalization
  if GLib <> 0 then
    FreeLibrary(GLib);

end.
