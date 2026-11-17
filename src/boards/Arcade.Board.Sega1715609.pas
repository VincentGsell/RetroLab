unit Arcade.Board.Sega1715609;

///  BOARD - Sega Y Board (1988) : top board 171-5609 (837-6565) + bottom board 171-5610 (837-6566).
///
///  What is soldered on it :
///    3 x MC68000 @ 12.5 MHz (50 MHz / 4) : main CPU (the game), sub CPU X (the rotated sprites),
///             sub CPU Y (rotation, System 16B sprites, palette)            -> Arcade.Chip.M68000
///    3 x 315-5248 multiplier + 3 x 315-5249 divider, one pair per 68000  -> Arcade.Chip.SegaMath
///    315-5296 I/O controller (inputs, DIP switches, outputs)             -> Arcade.Chip.Sega315_5296
///    MSM6253 ADC : wheel and pedals, read one bit at a time
///    Z80 @ 4.03 MHz sound CPU : NMI on each sound command, IRQ from the YM2151 -> Arcade.Chip.Z80
///    YM2151 + 315-5218 PCM @ 4.03 MHz                         -> Arcade.Chip.YM2151 / SegaPCM
///    video : Y Board sprites drawn into a 512 x 512 frame buffer that is rotated and tilted
///            line by line, System 16B sprites on top, 8192-colour palette with shadow  -> .Video
///  Timing : 342 x 262 at 60 Hz, 320 x 224 visible, ROT0. IRQ2 on line 170 for one line, IRQ4
///  (vblank) on line 223, on the three 68000s.
///  Controls (cabinet digital panel) : left / right steer, button 1 accelerates, button 2 brakes,
///  button 3 toggles the gear, up = high gear, down = low gear.
///  Force feedback : the vibration and the upright wheel motor drive Rumble[0] ; with the cabinet
///  DIP set to "Moving" (--dip0 EB), the seat's roll position adds a left / right weight.
///  Reference : MAME drivers src/mame/sega/segaybd.cpp, segaic16_m.cpp, 315_5296.cpp. Pure unit : no FMX.

interface

uses
  System.SysUtils,
  System.Classes,
  Arcade.Gfx,
  Arcade.RomSet,
  Arcade.Board,
  Arcade.Chip.M68000,
  Arcade.Chip.Z80,
  Arcade.Chip.YM2151,
  Arcade.Chip.SegaPCM,
  Arcade.Chip.SegaMath,
  Arcade.Chip.Sega315_5296;

const
  C5609_CPU_CLOCK = 12500000;
  C5609_SOUND_CLOCK = 32215900 / 8;
  C5609_LINES = 262;
  C5609_FPS = 60;
  C5609_LINE_RATE = C5609_FPS * C5609_LINES;
  C5609_WIDTH = 320;
  C5609_HEIGHT = 224;
  C5609_PALETTE = 8192;
  C5609_IRQ2_LINE = 170;

  // DIP defaults (MAME) : 1C/1C, upright / sit-down cabinet, demo sounds on, continue, normal
  C5609_COINAGE_DEFAULT = $FF;
  C5609_DSW_DEFAULT = $EA;

  CMain = 0;
  CSubX = 1;
  CSubY = 2;

type
  TBoardSega1715609 = class(TArcadeBoard)
  private
    FRom: array[0..2] of TBytes;
    FSoundRom: TBytes;
    FMult: array[0..2] of TSega315_5248;
    FDiv: array[0..2] of TSega315_5249;
    FIo: TSega315_5296;
    FYm: TYM2151;
    FPcm: TSegaPCM;
    FDebt: array[0..2] of Double;
    FZ80Debt, FFmDebt: Double;
    FHeld: array[0..2] of Boolean;     // a sub CPU held in reset by the I/O chip
    FSoundHeld: Boolean;
    FSoundLatch: Byte;
    FMisc: Byte;                       // I/O port E
    FAdcShift: Byte;
    FAudioPos: Double;
    FGearPressed, FServiceOn: Boolean;
    FVibration: Integer;
    FWheelMotor: Boolean;
    function MemPtr(aCpu: Integer; aAddr: Cardinal; aWrite: Boolean; out aPalette: Boolean): PByte;
    function IoRead(aCpu: Integer; aAddr: Cardinal): Word;
    procedure IoWrite(aCpu: Integer; aAddr: Cardinal; aValue, aMask: Word);
    function Read16(aCpu: Integer; aAddr: Cardinal): Word;
    function Read8(aCpu: Integer; aAddr: Cardinal): Byte;
    procedure Write16(aCpu: Integer; aAddr: Cardinal; aValue: Word);
    procedure Write8(aCpu: Integer; aAddr: Cardinal; aValue: Byte);
    function MainRead16(aAddr: Cardinal): Word;
    function MainRead8(aAddr: Cardinal): Byte;
    procedure MainWrite16(aAddr: Cardinal; aValue: Word);
    procedure MainWrite8(aAddr: Cardinal; aValue: Byte);
    function SubXRead16(aAddr: Cardinal): Word;
    function SubXRead8(aAddr: Cardinal): Byte;
    procedure SubXWrite16(aAddr: Cardinal; aValue: Word);
    procedure SubXWrite8(aAddr: Cardinal; aValue: Byte);
    function SubYRead16(aAddr: Cardinal): Word;
    function SubYRead8(aAddr: Cardinal): Byte;
    procedure SubYWrite16(aAddr: Cardinal; aValue: Word);
    procedure SubYWrite8(aAddr: Cardinal; aValue: Byte);
    function IoPortIn(aPort: Integer): Byte;
    procedure IoPortOut(aPort: Integer; aValue: Byte);
    procedure SetMisc(aValue: Byte);
    function AnalogInput(aChannel: Integer): Byte;
    procedure PaletteWrite(aOffset: Cardinal);
    function Z80Read(aAddr: Word): Byte;
    procedure Z80Write(aAddr: Word; aValue: Byte);
    function Z80PortIn(aPort: Word): Byte;
    procedure Z80PortOut(aPort: Word; aValue: Byte);
    procedure UpdateControls;
    procedure RunSlice;
    procedure RenderAudio(aCount: Integer);
  protected
    procedure SetAudioRate(aValue: Integer); override;
  public
    Cpu: array[0..2] of TM68000;     // main, sub X, sub Y
    Sound: TZ80;

    MainRam: TBytes;        // 0x10000, main 1F0000
    SharedRam: TBytes;      // 0x10000, the three CPUs at 0C0000
    SubXRam: TBytes;        // 0x8000, sub X 1F8000 (the upper half is the battery-backed RAM)
    YSpriteRam: TBytes;     // 0x10000, sub X 180000
    SubYRam: TBytes;        // 0x10000, sub Y 1F0000
    RotateRam: TBytes;      // 0x800, sub Y 180000
    RotateBuffer: TBytes;   // 0x800, the half the rotation chip draws (swapped on a control read)
    BSpriteRam: TBytes;     // 0x1000, sub Y 188000
    PaletteRam: TBytes;     // 0x4000, sub Y 190000
    SoundRam: array[0..$7FF] of Byte;

    DisplayEnabled: Boolean;
    Coinage, Dsw: Byte;
    Steering, Gas, Brake: Integer;
    HighGear: Boolean;
    /// Moving cabinet roll, from -3 (full left) to +3 (full right).
    BankPosition: Integer;

    Palette: array[0..2 * C5609_PALETTE - 1] of TArgb;   // normal, then shadow / hilight
    YSpriteData: TArray<UInt64>;     // 64-bit words, 16 pixels each
    BSpriteData: TArray<Word>;       // 16-bit words, 4 pixels each

    class function Family: string; override;
    class function Description: string; override;
    constructor Create(aRoms: TRomSetData); override;
    destructor Destroy; override;
    procedure Reset; override;
    procedure RunFrame; override;
    function ScreenInfo: TScreenInfo; override;
    function StateHash: UInt64; override;
    procedure SetServiceMode(aOn: Boolean); override;
    procedure SetDip(aIndex: Integer; aValue: Byte); override;
    function RotateWord(aIndex: Integer): Word; inline;
    function YSpriteWord(aIndex: Integer): Word; inline;
    function BSpriteWord(aIndex: Integer): Word; inline;
  end;

implementation

uses
  Arcade.Board.SegaPalette,
  Arcade.Board.Sega1715609.Video;

function Rd16(const aMem: TBytes; aOfs: Cardinal): Word; inline;
begin
  Result := (Word(aMem[aOfs]) shl 8) or aMem[aOfs + 1];
end;

procedure SwapContents(const aA, aB: TBytes);
var
  i: Integer;
  lTmp: Byte;
begin
  for i := 0 to High(aA) do
  begin
    lTmp := aA[i];
    aA[i] := aB[i];
    aB[i] := lTmp;
  end;
end;

{ TBoardSega1715609 }

class function TBoardSega1715609.Family: string;
begin
  Result := 'sega1715609';
end;

class function TBoardSega1715609.Description: string;
begin
  Result := 'Sega Y Board 171-5609 : 3 x MC68000 @ 12,5 MHz + Z80, YM2151, PCM 315-5218, sprites tournes et zoomes';
end;

constructor TBoardSega1715609.Create(aRoms: TRomSetData);
var
  lBytes: TBytes;
  i, k: Integer;
  lWord: UInt64;
begin
  inherited Create(aRoms);
  FRom[CMain] := aRoms.Region('maincpu');
  FRom[CSubX] := aRoms.Region('subx');
  FRom[CSubY] := aRoms.Region('suby');
  FSoundRom := aRoms.Region('soundcpu');
  lBytes := aRoms.Region('ysprites');
  SetLength(YSpriteData, Length(lBytes) div 8);
  for i := 0 to High(YSpriteData) do
  begin
    lWord := 0;
    for k := 0 to 7 do
      lWord := (lWord shl 8) or lBytes[i * 8 + k];
    YSpriteData[i] := lWord;
  end;
  lBytes := aRoms.Region('bsprites');
  SetLength(BSpriteData, Length(lBytes) div 2);
  for i := 0 to High(BSpriteData) do
    BSpriteData[i] := (Word(lBytes[i * 2]) shl 8) or lBytes[i * 2 + 1];
  SetLength(MainRam, $10000);
  SetLength(SharedRam, $10000);
  SetLength(SubXRam, $8000);
  SetLength(YSpriteRam, $10000);
  SetLength(SubYRam, $10000);
  SetLength(RotateRam, $800);
  SetLength(RotateBuffer, $800);
  SetLength(BSpriteRam, $1000);
  SetLength(PaletteRam, $4000);

  for i := 0 to 2 do
  begin
    Cpu[i] := TM68000.Create;
    FMult[i] := TSega315_5248.Create;
    FDiv[i] := TSega315_5249.Create;
  end;
  Cpu[CMain].OnRead8 := MainRead8;
  Cpu[CMain].OnRead16 := MainRead16;
  Cpu[CMain].OnWrite8 := MainWrite8;
  Cpu[CMain].OnWrite16 := MainWrite16;
  Cpu[CSubX].OnRead8 := SubXRead8;
  Cpu[CSubX].OnRead16 := SubXRead16;
  Cpu[CSubX].OnWrite8 := SubXWrite8;
  Cpu[CSubX].OnWrite16 := SubXWrite16;
  Cpu[CSubY].OnRead8 := SubYRead8;
  Cpu[CSubY].OnRead16 := SubYRead16;
  Cpu[CSubY].OnWrite8 := SubYWrite8;
  Cpu[CSubY].OnWrite16 := SubYWrite16;
  FIo := TSega315_5296.Create;
  FIo.OnPortIn := IoPortIn;
  FIo.OnPortOut := IoPortOut;
  Sound := TZ80.Create;
  Sound.OnRead := Z80Read;
  Sound.OnWrite := Z80Write;
  Sound.OnPortIn := Z80PortIn;
  Sound.OnPortOut := Z80PortOut;
  FYm := TYM2151.Create(C5609_SOUND_CLOCK);
  FYm.ExternalTimers := True;
  FPcm := TSegaPCM.Create(C5609_SOUND_CLOCK, aRoms.Region('pcm'), 13, $F8);
  Coinage := C5609_COINAGE_DEFAULT;
  Dsw := C5609_DSW_DEFAULT;
  Reset;
end;

destructor TBoardSega1715609.Destroy;
var
  i: Integer;
begin
  for i := 0 to 2 do
  begin
    Cpu[i].Free;
    FMult[i].Free;
    FDiv[i].Free;
  end;
  FIo.Free;
  Sound.Free;
  FYm.Free;
  FPcm.Free;
  inherited;
end;

function TBoardSega1715609.ScreenInfo: TScreenInfo;
begin
  Result.Width := C5609_WIDTH;
  Result.Height := C5609_HEIGHT;
  Result.Rotation := rot0;
  Result.FrameRate := C5609_FPS;
end;

procedure TBoardSega1715609.SetServiceMode(aOn: Boolean);
begin
  FServiceOn := aOn;
end;

procedure TBoardSega1715609.SetDip(aIndex: Integer; aValue: Byte);
begin
  case aIndex of
    0: Dsw := aValue;
    1: Coinage := aValue;
  end;
end;

function TBoardSega1715609.RotateWord(aIndex: Integer): Word;
begin
  Result := Rd16(RotateBuffer, (aIndex and $3FF) * 2);
end;

function TBoardSega1715609.YSpriteWord(aIndex: Integer): Word;
begin
  Result := Rd16(YSpriteRam, (aIndex and $7FFF) * 2);
end;

function TBoardSega1715609.BSpriteWord(aIndex: Integer): Word;
begin
  Result := Rd16(BSpriteRam, (aIndex and $7FF) * 2);
end;

procedure TBoardSega1715609.Reset;
var
  i: Integer;
begin
  for i := 0 to 2 do
  begin
    FMult[i].Reset;
    FDiv[i].Reset;
    FDebt[i] := 0;
    FHeld[i] := False;
  end;
  FillChar(MainRam[0], Length(MainRam), 0);
  FillChar(SharedRam[0], Length(SharedRam), 0);
  FillChar(SubXRam[0], Length(SubXRam), 0);
  FillChar(YSpriteRam[0], Length(YSpriteRam), 0);
  FillChar(SubYRam[0], Length(SubYRam), 0);
  FillChar(RotateRam[0], Length(RotateRam), 0);
  FillChar(RotateBuffer[0], Length(RotateBuffer), 0);
  FillChar(BSpriteRam[0], Length(BSpriteRam), 0);
  FillChar(PaletteRam[0], Length(PaletteRam), 0);
  FillChar(SoundRam, SizeOf(SoundRam), 0);
  for i := 0 to C5609_PALETTE - 1 do
    PaletteWrite(i * 2);
  FSoundLatch := 0;
  FAdcShift := 0;
  FVibration := 0;
  FWheelMotor := False;
  BankPosition := 0;
  Steering := $80;
  Gas := 0;
  Brake := 0;
  HighGear := False;
  FGearPressed := False;
  Rumble[0] := Default(TArcadeRumble);
  Rumble[1] := Default(TArcadeRumble);
  Inputs := Default(TArcadeInputs);
  FZ80Debt := 0;
  FFmDebt := 0;
  FFrame := 0;
  FIo.Reset;
  for i := 0 to 2 do
    Cpu[i].Reset;
  Sound.Reset;
  FYm.Reset;
  FPcm.Reset;
  FAudioPos := 0;
end;

procedure TBoardSega1715609.PaletteWrite(aOffset: Cardinal);
var
  lIndex: Integer;
begin
  lIndex := (aOffset shr 1) and (C5609_PALETTE - 1);
  SegaColor(Rd16(PaletteRam, lIndex * 2), Palette[lIndex], Palette[C5609_PALETTE + lIndex]);
end;

{ I/O chip : A P1, B general, C limit switches, D motor, E misc, F DSW, G coinage, H lamps }

function TBoardSega1715609.IoPortIn(aPort: Integer): Byte;
begin
  case aPort of
    1:
      begin
        Result := $FF;
        if FServiceOn then Result := Result and not $02;
        if asService in Inputs.System then Result := Result and not $04;
        if asStart1 in Inputs.System then Result := Result and not $08;
        if not HighGear then Result := Result and not $20;
        if asCoin1 in Inputs.System then Result := Result and not $40;
        if asCoin2 in Inputs.System then Result := Result and not $80;
      end;
    2: Result := $E4;       // safety sensors and limit switches off
    5: Result := Dsw;
    6: Result := Coinage;
  else
    Result := $FF;
  end;
end;

procedure TBoardSega1715609.IoPortOut(aPort: Integer; aValue: Byte);
begin
  case aPort of
    3:
      // motor board (MAME pdrift_output_cb1) : 161 / 162 step the seat right / left, other values
      // carry a roll position in d3-d7 and the vibration in d0-d2 ; $FF is the test menu
      if aValue = 162 then
      begin
        if BankPosition > -3 then Dec(BankPosition);
      end
      else if aValue = 161 then
      begin
        if BankPosition < 3 then Inc(BankPosition);
      end
      else if (aValue <> $FF) and (aValue <> 160) then
      begin
        FVibration := aValue and 7;
        case aValue and $F8 of
          56: BankPosition := -3;
          48: BankPosition := -2;
          40: BankPosition := -1;
          120: BankPosition := 0;
          72: BankPosition := 1;
          80: BankPosition := 2;
          88: BankPosition := 3;
        end;
      end;
    4: SetMisc(aValue);
    7: FWheelMotor := (aValue and 2) <> 0;   // D7 /mute, D2 start lamp, D1 upright wheel motor
  end;
end;

/// Port E : D7 display enable, D5 watchdog, D4 sound CPU run, D3 / D2 hold sub X / sub Y in
/// reset, D1-D0 analog multiplexer.
procedure TBoardSega1715609.SetMisc(aValue: Byte);
var
  lHold: Boolean;
begin
  FMisc := aValue;
  DisplayEnabled := (aValue and $80) <> 0;
  lHold := (aValue and $10) = 0;
  if FSoundHeld and not lHold then
    Sound.Reset;
  FSoundHeld := lHold;
  lHold := (aValue and $08) <> 0;
  if FHeld[CSubX] and not lHold then
    Cpu[CSubX].Reset;
  FHeld[CSubX] := lHold;
  lHold := (aValue and $04) <> 0;
  if FHeld[CSubY] and not lHold then
    Cpu[CSubY].Reset;
  FHeld[CSubY] := lHold;
end;

/// MSM6253 inputs : channels 0-2 are not wired on Power Drift ; channel 3 goes through a
/// 4052 multiplexer to brake, gas or steering.
function TBoardSega1715609.AnalogInput(aChannel: Integer): Byte;
begin
  if aChannel < 3 then
    Exit($80);
  case FMisc and 3 of
    0: Result := Brake;
    1: Result := Gas;
    2: Result := Steering;
  else
    Result := $80;
  end;
end;

{ buses }

function TBoardSega1715609.MemPtr(aCpu: Integer; aAddr: Cardinal; aWrite: Boolean; out aPalette: Boolean): PByte;
begin
  aPalette := False;
  Result := nil;
  aAddr := aAddr and $1FFFFF;
  case aAddr of
    $000000..$07FFFF:
      if not aWrite and (aAddr < Cardinal(Length(FRom[aCpu]))) then
        Result := @FRom[aCpu][aAddr];
    $0C0000..$0CFFFF: Result := @SharedRam[aAddr and $FFFF];
  else
    case aCpu of
      CMain:
        if aAddr >= $1F0000 then
          Result := @MainRam[aAddr and $FFFF];
      CSubX:
        case aAddr of
          $180000..$18FFFF: Result := @YSpriteRam[aAddr and $FFFF];
          $1F8000..$1FFFFF: Result := @SubXRam[aAddr and $7FFF];
        end;
    else
      case aAddr of
        $180000..$187FFF: Result := @RotateRam[aAddr and $7FF];
        $188000..$18FFFF: Result := @BSpriteRam[aAddr and $FFF];
        $190000..$197FFF:
          begin
            Result := @PaletteRam[aAddr and $3FFF];
            aPalette := aWrite;
          end;
        $1F0000..$1FFFFF: Result := @SubYRam[aAddr and $FFFF];
      end;
    end;
  end;
end;

function TBoardSega1715609.IoRead(aCpu: Integer; aAddr: Cardinal): Word;
begin
  aAddr := aAddr and $1FFFFF;
  case aAddr of
    $080000..$081FFF: Result := FMult[aCpu].Read((aAddr shr 1) and 3);
    $084000..$085FFF: Result := FDiv[aCpu].Read((aAddr shr 1) and $F);
  else
    Result := $FFFF;
    if aCpu = CMain then
      case aAddr of
        $100000..$10001F: Result := $FF00 or FIo.Read((aAddr shr 1) and $F);
        $100040..$100047:
          begin
            // MSM6253 : the conversion result comes out one bit at a time on D7
            Result := $FF7F or (Word(FAdcShift and $80));
            FAdcShift := FAdcShift shl 1;
          end;
      end
    else if (aCpu = CSubY) and (aAddr >= $198000) and (aAddr <= $19FFFF) then
      SwapContents(RotateRam, RotateBuffer);
  end;
end;

procedure TBoardSega1715609.IoWrite(aCpu: Integer; aAddr: Cardinal; aValue, aMask: Word);
begin
  aAddr := aAddr and $1FFFFF;
  case aAddr of
    $080000..$081FFF: FMult[aCpu].Write((aAddr shr 1) and 3, aValue, aMask);
    $084000..$085FFF: FDiv[aCpu].Write((aAddr shr 1) and $F, aValue, aMask);
  else
    if aCpu = CMain then
      case aAddr of
        $082000..$083FFF:
          if (aMask and $00FF) <> 0 then
          begin
            FSoundLatch := aValue and $FF;
            Sound.RaiseNmi;
          end;
        $100000..$10001F:
          if (aMask and $00FF) <> 0 then
            FIo.Write((aAddr shr 1) and $F, aValue and $FF);
        $100040..$100047:
          if (aMask and $00FF) <> 0 then
            FAdcShift := AnalogInput((aAddr shr 1) and 3);
      end;
  end;
end;

function TBoardSega1715609.Read16(aCpu: Integer; aAddr: Cardinal): Word;
var
  p: PByte;
  lPal: Boolean;
begin
  p := MemPtr(aCpu, aAddr, False, lPal);
  if p <> nil then
    Result := (Word(p^) shl 8) or PByte(p + 1)^
  else
    Result := IoRead(aCpu, aAddr);
end;

function TBoardSega1715609.Read8(aCpu: Integer; aAddr: Cardinal): Byte;
var
  p: PByte;
  lPal: Boolean;
  lWord: Word;
begin
  p := MemPtr(aCpu, aAddr, False, lPal);
  if p <> nil then
    Result := p^
  else
  begin
    lWord := IoRead(aCpu, aAddr and not 1);
    if (aAddr and 1) <> 0 then
      Result := lWord and $FF
    else
      Result := lWord shr 8;
  end;
end;

procedure TBoardSega1715609.Write16(aCpu: Integer; aAddr: Cardinal; aValue: Word);
var
  p: PByte;
  lPal: Boolean;
begin
  p := MemPtr(aCpu, aAddr, True, lPal);
  if p <> nil then
  begin
    p^ := aValue shr 8;
    PByte(p + 1)^ := aValue and $FF;
    if lPal then
      PaletteWrite(aAddr and $3FFF);
  end
  else if (aAddr and $1FFFFF) >= $080000 then
    IoWrite(aCpu, aAddr, aValue, $FFFF);
end;

procedure TBoardSega1715609.Write8(aCpu: Integer; aAddr: Cardinal; aValue: Byte);
var
  p: PByte;
  lPal: Boolean;
begin
  p := MemPtr(aCpu, aAddr, True, lPal);
  if p <> nil then
  begin
    p^ := aValue;
    if lPal then
      PaletteWrite(aAddr and $3FFE);
  end
  else if (aAddr and $1FFFFF) >= $080000 then
  begin
    if (aAddr and 1) <> 0 then
      IoWrite(aCpu, aAddr and not 1, aValue, $00FF)
    else
      IoWrite(aCpu, aAddr, Word(aValue) shl 8, $FF00);
  end;
end;

function TBoardSega1715609.MainRead16(aAddr: Cardinal): Word; begin Result := Read16(CMain, aAddr); end;
function TBoardSega1715609.MainRead8(aAddr: Cardinal): Byte; begin Result := Read8(CMain, aAddr); end;
procedure TBoardSega1715609.MainWrite16(aAddr: Cardinal; aValue: Word); begin Write16(CMain, aAddr, aValue); end;
procedure TBoardSega1715609.MainWrite8(aAddr: Cardinal; aValue: Byte); begin Write8(CMain, aAddr, aValue); end;
function TBoardSega1715609.SubXRead16(aAddr: Cardinal): Word; begin Result := Read16(CSubX, aAddr); end;
function TBoardSega1715609.SubXRead8(aAddr: Cardinal): Byte; begin Result := Read8(CSubX, aAddr); end;
procedure TBoardSega1715609.SubXWrite16(aAddr: Cardinal; aValue: Word); begin Write16(CSubX, aAddr, aValue); end;
procedure TBoardSega1715609.SubXWrite8(aAddr: Cardinal; aValue: Byte); begin Write8(CSubX, aAddr, aValue); end;
function TBoardSega1715609.SubYRead16(aAddr: Cardinal): Word; begin Result := Read16(CSubY, aAddr); end;
function TBoardSega1715609.SubYRead8(aAddr: Cardinal): Byte; begin Result := Read8(CSubY, aAddr); end;
procedure TBoardSega1715609.SubYWrite16(aAddr: Cardinal; aValue: Word); begin Write16(CSubY, aAddr, aValue); end;
procedure TBoardSega1715609.SubYWrite8(aAddr: Cardinal; aValue: Byte); begin Write8(CSubY, aAddr, aValue); end;

{ sound CPU }

function TBoardSega1715609.Z80Read(aAddr: Word): Byte;
begin
  case aAddr of
    $0000..$EFFF:
      if aAddr < Length(FSoundRom) then
        Result := FSoundRom[aAddr]
      else
        Result := $FF;
    $F000..$F7FF: Result := FPcm.Read(aAddr and $FF);
  else
    Result := SoundRam[aAddr and $7FF];
  end;
end;

procedure TBoardSega1715609.Z80Write(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $F000..$F7FF: FPcm.Write(aAddr and $FF, aValue);
    $F800..$FFFF: SoundRam[aAddr and $7FF] := aValue;
  end;
end;

function TBoardSega1715609.Z80PortIn(aPort: Word): Byte;
begin
  case aPort and $C0 of
    $00: Result := FYm.Read(aPort and 1);
    $40: Result := FSoundLatch;
  else
    Result := $FF;
  end;
end;

procedure TBoardSega1715609.Z80PortOut(aPort: Word; aValue: Byte);
begin
  if (aPort and $C0) = 0 then
    FYm.Write(aPort and 1, aValue);
end;

{ controls }

procedure TBoardSega1715609.UpdateControls;
var
  lPad: TArcadeButtons;
  lTarget: Integer;
begin
  lPad := Inputs.Players[0];
  if abLeft in lPad then
    lTarget := $20
  else if abRight in lPad then
    lTarget := $E0
  else
    lTarget := $80;
  if Steering < lTarget then
    Steering := Steering + 8
  else if Steering > lTarget then
    Steering := Steering - 8;
  if Abs(Steering - lTarget) < 8 then
    Steering := lTarget;
  if abButton1 in lPad then Gas := Gas + 32 else Gas := Gas - 48;
  if Gas > $FF then Gas := $FF;
  if Gas < 0 then Gas := 0;
  if abButton2 in lPad then Brake := Brake + 48 else Brake := Brake - 64;
  if Brake > $FF then Brake := $FF;
  if Brake < 0 then Brake := 0;
  if (abButton3 in lPad) and not FGearPressed then
    HighGear := not HighGear;
  FGearPressed := abButton3 in lPad;
  if abUp in lPad then
    HighGear := True
  else if abDown in lPad then
    HighGear := False;
end;

{ frame }

procedure TBoardSega1715609.RunSlice;
var
  i: Integer;
begin
  for i := 0 to 2 do
  begin
    FDebt[i] := FDebt[i] + C5609_CPU_CLOCK / C5609_LINE_RATE;
    if FHeld[i] then
      FDebt[i] := 0
    else
      while FDebt[i] > 0 do
        FDebt[i] := FDebt[i] - Cpu[i].Step;
  end;
  FFmDebt := FFmDebt + C5609_SOUND_CLOCK / 64 / C5609_LINE_RATE;
  FYm.AdvanceTimers(Trunc(FFmDebt));
  FFmDebt := FFmDebt - Trunc(FFmDebt);
  FZ80Debt := FZ80Debt + C5609_SOUND_CLOCK / C5609_LINE_RATE;
  if FSoundHeld then
    FZ80Debt := 0
  else
    while FZ80Debt > 0 do
    begin
      if FYm.IrqActive then
      begin
        if not Sound.IrqPending then
          Sound.RaiseIrq($FF);
      end
      else if Sound.IrqPending then
        Sound.ClearIrq;
      FZ80Debt := FZ80Debt - Sound.Step;
    end;
end;

procedure TBoardSega1715609.RunFrame;
var
  lLine, lSamples, i, lLevel: Integer;
begin
  FAudioCount := 0;
  UpdateControls;
  for lLine := 0 to C5609_LINES - 1 do
  begin
    lLevel := 0;
    if lLine = C5609_IRQ2_LINE then
      lLevel := 2;
    if lLine = 223 then
      lLevel := 4;
    for i := 0 to 2 do
      Cpu[i].SetIrq(lLevel);
    RunSlice;
    if FAudioRate > 0 then
    begin
      FAudioPos := FAudioPos + FAudioRate / C5609_LINE_RATE;
      lSamples := Trunc(FAudioPos);
      FAudioPos := FAudioPos - lSamples;
      RenderAudio(lSamples);
    end;
    if (lLine = C5609_HEIGHT - 1) and RenderEnabled then
      Render1715609(Self, FScreen);
  end;
  Rumble[0].Heavy := FVibration / 7;
  Rumble[0].Light := FVibration / 14;
  if FWheelMotor then
  begin
    Rumble[0].Heavy := Rumble[0].Heavy + 0.6;
    Rumble[0].Light := Rumble[0].Light + 0.4;
  end;
  // the seat leaning left weighs on the left grip (heavy motor), right on the right grip
  if BankPosition < 0 then
    Rumble[0].Heavy := Rumble[0].Heavy + 0.15 * -BankPosition
  else if BankPosition > 0 then
    Rumble[0].Light := Rumble[0].Light + 0.2 * BankPosition;
  Inc(FFrame);
end;

procedure TBoardSega1715609.SetAudioRate(aValue: Integer);
begin
  inherited;
  FAudioPos := 0;
end;

procedure TBoardSega1715609.RenderAudio(aCount: Integer);
var
  i: Integer;
begin
  if FAudioCount + aCount > Length(FAudioBuffer) then
    aCount := Length(FAudioBuffer) - FAudioCount;
  if aCount <= 0 then
    Exit;
  for i := FAudioCount to FAudioCount + aCount - 1 do
    FAudioBuffer[i] := 0;
  FYm.FmGain := 0.30 * 2;
  FPcm.Gain := 0.70 * 2;
  FYm.Render(FAudioBuffer, FAudioCount, aCount, FAudioRate);
  FPcm.Render(FAudioBuffer, FAudioCount, aCount, FAudioRate);
  Inc(FAudioCount, aCount);
end;

function TBoardSega1715609.StateHash: UInt64;
var
  lHash: UInt64;
  lRegs: array[0..255] of Byte;
  r, i: Integer;
  lSR: Word;
  lPC: Cardinal;

  procedure Feed(const aData; aSize: Integer);
  var
    k: Integer;
    p: PByte;
  begin
    p := @aData;
    for k := 0 to aSize - 1 do
    begin
      lHash := (lHash xor p^) * UInt64($100000001B3);
      Inc(p);
    end;
  end;

begin
  lHash := UInt64($CBF29CE484222325);
  Feed(MainRam[0], Length(MainRam));
  Feed(SharedRam[0], Length(SharedRam));
  Feed(SubXRam[0], Length(SubXRam));
  Feed(YSpriteRam[0], Length(YSpriteRam));
  Feed(SubYRam[0], Length(SubYRam));
  Feed(RotateRam[0], Length(RotateRam));
  Feed(RotateBuffer[0], Length(RotateBuffer));
  Feed(BSpriteRam[0], Length(BSpriteRam));
  Feed(PaletteRam[0], Length(PaletteRam));
  Feed(SoundRam, SizeOf(SoundRam));
  for i := 0 to 2 do
  begin
    Feed(Cpu[i].D, SizeOf(Cpu[i].D));
    Feed(Cpu[i].A, SizeOf(Cpu[i].A));
    lSR := Cpu[i].SR;
    lPC := Cpu[i].PC;
    Feed(lSR, SizeOf(lSR));
    Feed(lPC, SizeOf(lPC));
  end;
  Feed(Sound.PC, SizeOf(Sound.PC));
  Feed(FMisc, 1);
  for r := 0 to 255 do
    lRegs[r] := FYm.Register(r);
  Feed(lRegs, SizeOf(lRegs));
  Result := lHash;
end;

initialization
  RegisterBoard(TBoardSega1715609);

end.
