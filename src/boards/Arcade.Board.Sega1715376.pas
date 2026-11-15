unit Arcade.Board.Sega1715376;

///  BOARD - Sega Out Run hardware (1986) : CPU board 171-5376-01 + video board 837-6064.
///
///  What is soldered on it :
///    2 x MC68000 @ 10 MHz (40 MHz / 4) : main CPU and sub CPU (road)    -> Arcade.Chip.M68000
///    315-5195 memory mapper : maps the main CPU's 16 MB space in 8 programmable regions, sound
///             latch to the Z80
///    Z80A @ 4 MHz sound CPU, NMI on each sound command                   -> Arcade.Chip.Z80
///    YM2151 @ 4 MHz (FM, stereo)                                         -> Arcade.Chip.YM2151
///    315-5218 PCM @ 4 MHz (16 voices of 8-bit samples)                   -> Arcade.Chip.SegaPCM
///    8255 PPI (display enable, ADC select, sound CPU reset), ADC0804 (wheel, pedals)
///    video : System 16B tilemaps (2 layers of 16 pages + text), road generator (2 roads),
///            zoomed sprites in a double buffer, 4096-colour palette with shadow / hilight -> .Video
///  Timing : 400 x 262 at 6.29 MHz pixel clock, 60.05 Hz, 320 x 224 visible, ROT0.
///  Interrupts : main IRQ2 on lines 65, 129, 193 (hblank), main + sub IRQ4 on line 223 (vblank).
///  Controls (cabinet digital panel) : left / right steer, button 1 accelerates, button 2 brakes,
///  button 3 toggles the gear, up = high gear, down = low gear.
///  Force feedback : the wheel shaker (output port D5) and the moving cabinet's bank motor
///  (8255 port B, deluxe cabinets only) drive Rumble[0].
///  Reference : MAME drivers src/mame/sega/segaorun.cpp, 315_5195.cpp. Pure unit : no FMX.

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
  Arcade.Chip.SegaPCM;

const
  C5376_CPU_CLOCK = 10000000;
  C5376_Z80_CLOCK = 4000000;
  C5376_SOUND_CLOCK = 4000000;
  C5376_PIXEL_CLOCK = 25174800 / 4;
  C5376_LINE_RATE = C5376_PIXEL_CLOCK / 400;
  C5376_LINES = 262;
  C5376_FPS = C5376_LINE_RATE / C5376_LINES;
  C5376_WIDTH = 320;
  C5376_HEIGHT = 224;
  C5376_PALETTE = 4096;

  // DIP defaults (MAME) : 1C/1C, mini up cabinet, demo sounds on, normal time and traffic
  C5376_COINAGE_DEFAULT = $FF;
  C5376_DSW_DEFAULT = $F9;

type
  TMainPageKind = (mpMapper, mpRom, mpRam, mpPalette, mpIo, mpRoad);

  TMainPage = record
    Kind: TMainPageKind;
    Mem: PByte;
    Offset: Cardinal;
  end;

  TBoardSega1715376 = class(TArcadeBoard)
  private
    FMainRom, FSubRom, FSoundRom: TBytes;
    FPages: array[0..4095] of TMainPage;
    FMapper: array[0..31] of Byte;
    FToSound, FFromSound: Byte;
    FMainHeld: Boolean;
    FMainDebt, FSubDebt, FZ80Debt: Double;
    FYm: TYM2151;
    FPcm: TSegaPCM;
    FAudioPos: Double;
    FPpi: array[0..3] of Byte;       // port A, B, C output latches, control
    FAdcValue: Byte;
    FAdcReady: Boolean;
    FAdcBusy: Boolean;
    FAdcDoneAt: Int64;
    FGearPressed: Boolean;
    FServiceOn: Boolean;
    FShakeLevel: Single;             // the game pulses the shaker : smoothed like the motor's inertia
    procedure RebuildMap;
    procedure Install(aIndex: Integer; aOffset, aLength, aMirror: Cardinal; aKind: TMainPageKind;
      aMem: PByte; aMemSize: Cardinal; aRgnOffset: Cardinal);
    function MapperRead(aOffset: Integer): Byte;
    procedure MapperWrite(aOffset: Integer; aValue: Byte);
    function MiscIoRead(aAddr: Cardinal): Word;
    procedure MiscIoWrite(aAddr: Cardinal; aValue, aMask: Word);
    function RoadControlRead: Word;
    procedure RoadControlWrite(aValue, aMask: Word);
    procedure PaletteWrite(aOffset: Cardinal);
    procedure PpiWrite(aPort: Integer; aValue: Byte);
    function PpiRead(aPort: Integer): Byte;
    procedure SetPortC(aValue: Byte);
    procedure AdcPoll;
    function ServicePort: Byte;
    procedure UpdateControls;
    function MainRead16(aAddr: Cardinal): Word;
    function MainRead8(aAddr: Cardinal): Byte;
    procedure MainWrite16(aAddr: Cardinal; aValue: Word);
    procedure MainWrite8(aAddr: Cardinal; aValue: Byte);
    function SubRead16(aAddr: Cardinal): Word;
    function SubRead8(aAddr: Cardinal): Byte;
    procedure SubWrite16(aAddr: Cardinal; aValue: Word);
    procedure SubWrite8(aAddr: Cardinal; aValue: Byte);
    procedure MainResetOut;
    function Z80Read(aAddr: Word): Byte;
    procedure Z80Write(aAddr: Word; aValue: Byte);
    function Z80PortIn(aPort: Word): Byte;
    procedure Z80PortOut(aPort: Word; aValue: Byte);
    procedure RunSlice(aFraction: Double);
    procedure RenderAudio(aCount: Integer);
  protected
    procedure SetAudioRate(aValue: Integer); override;
  public
    Main, Sub: TM68000;
    Sound: TZ80;

    WorkRam: TBytes;        // 0x8000, main CPU
    SubRam: TBytes;         // 0x8000, shared main / sub
    RoadRam: TBytes;        // 0x1000, shared main / sub
    RoadBuffer: TBytes;     // 0x1000, the half the road chip draws (swapped on a control read)
    SpriteRam: TBytes;      // 0x1000
    SpriteBuffer: TBytes;   // 0x1000, the half the sprite chip draws (swapped on a draw write)
    PaletteRam: TBytes;     // 0x2000
    TileRam: TBytes;        // 0x10000, 16 pages of 64 x 32
    TextRam: TBytes;        // 0x1000
    SoundRam: array[0..$7FF] of Byte;

    RoadControl: Byte;
    LatchedPages, LatchedYScroll, LatchedXScroll: array[0..3] of Word;
    DisplayEnabled: Boolean;
    Coinage, Dsw: Byte;
    Steering, Gas, Brake: Integer;   // ADC values 00-FF
    HighGear: Boolean;
    Shaker: Boolean;                 // wheel vibration motor
    BankMotor: Integer;              // moving cabinet : -7 (full left) .. +7 (full right)

    Palette: array[0..2 * C5376_PALETTE - 1] of TArgb;   // normal, then shadow / hilight
    Tiles: TGfxSet;
    SpriteData: TArray<Cardinal>;    // 32-bit words, 8 pixels each
    RoadGfx: TBytes;                 // (256 * 2 + 1) lines of 512 pixels

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
    function TextWord(aIndex: Integer): Word; inline;
    function TileWord(aIndex: Integer): Word; inline;
    function RoadWord(aIndex: Integer): Word; inline;
    function SpriteWord(aIndex: Integer): Word; inline;
  end;

implementation

uses
  Arcade.Board.Sega1715376.Video;

const
  CRegionSize: array[0..3] of Cardinal = ($00FFFF, $01FFFF, $07FFFF, $1FFFFF);

function Rd16(const aMem: TBytes; aOfs: Cardinal): Word; inline;
begin
  Result := (Word(aMem[aOfs]) shl 8) or aMem[aOfs + 1];
end;

procedure Wr16(const aMem: TBytes; aOfs: Cardinal; aValue: Word); inline;
begin
  aMem[aOfs] := aValue shr 8;
  aMem[aOfs + 1] := aValue and $FF;
end;

/// The sprite and road chips swap the contents of their two RAM halves.
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

{ graphics }

function TileLayout(aRegionSize: Integer): TGfxLayout;
var
  lThird, i: Integer;
begin
  Result := Default(TGfxLayout);
  lThird := (aRegionSize * 8) div 3;
  Result.Width := 8;
  Result.Height := 8;
  Result.Planes := 3;
  Result.PlaneOfs[0] := lThird * 2;
  Result.PlaneOfs[1] := lThird;
  Result.PlaneOfs[2] := 0;
  for i := 0 to 7 do
  begin
    Result.XOfs[i] := i;
    Result.YOfs[i] := i * 8;
  end;
  Result.CharInc := 64;
  Result.Count := lThird div 64;
end;

/// MAME segaic16_road_outrun_decode : 2-bit pixels from two planes $4000 apart, stripe area marked.
function DecodeRoad(const aRom: TBytes): TBytes;
var
  x, y, lLen, lSrc: Integer;
  lPix: Byte;
begin
  SetLength(Result, (256 * 2 + 1) * 512);
  lLen := Length(aRom);
  for y := 0 to 256 * 2 - 1 do
  begin
    lSrc := ((y and $FF) * $40 + (y shr 8) * $8000) mod lLen;
    for x := 0 to 511 do
    begin
      lPix := ((aRom[(lSrc + (x shr 3)) mod lLen] shr (not x and 7)) and 1)
        or (((aRom[(lSrc + (x shr 3) + $4000) mod lLen] shr (not x and 7)) and 1) shl 1);
      if (x >= 256 - 8) and (x < 256) and (lPix = 3) then
        lPix := lPix or 4;
      Result[y * 512 + x] := lPix;
    end;
  end;
  FillChar(Result[256 * 2 * 512], 512, 3);
end;

{ palette (MAME sega_16bit_common_base::palette_init : resistor weights, 470 ohm shadow / hilight) }

var
  GPalNormal, GPalShadow, GPalHilight: array[0..31] of Byte;

procedure InitPaletteTables;
const
  CG: array[0..4] of Double = (1 / 3900, 1 / 2000, 1 / 1000, 1 / 500, 1 / 250);
  CG6 = 1 / 470;
var
  v, b: Integer;
  lSum5, lSum6, lAcc: Double;
begin
  lSum5 := 0;
  for b := 0 to 4 do
    lSum5 := lSum5 + CG[b];
  lSum6 := lSum5 + CG6;
  for v := 0 to 31 do
  begin
    lAcc := 0;
    for b := 0 to 4 do
      if (v and (1 shl b)) <> 0 then
        lAcc := lAcc + CG[b];
    GPalNormal[v] := Round(255 * lAcc / lSum5);
    GPalShadow[v] := Round(255 * lAcc / lSum6);
    GPalHilight[v] := Round(255 * (lAcc + CG6) / lSum6);
  end;
end;

{ TBoardSega1715376 }

class function TBoardSega1715376.Family: string;
begin
  Result := 'sega1715376';
end;

class function TBoardSega1715376.Description: string;
begin
  Result := 'Sega 171-5376 (Out Run) : 2 x MC68000 @ 10 MHz + Z80 @ 4 MHz, YM2151, PCM 315-5218, route, sprites zoomes';
end;

constructor TBoardSega1715376.Create(aRoms: TRomSetData);
var
  lSprites: TBytes;
  i: Integer;
begin
  inherited Create(aRoms);
  FMainRom := aRoms.Region('maincpu');
  FSubRom := aRoms.Region('subcpu');
  FSoundRom := aRoms.Region('soundcpu');
  Tiles := DecodeGfx(aRoms.Region('gfx1'), TileLayout(Length(aRoms.Region('gfx1'))));
  lSprites := aRoms.Region('sprites');
  SetLength(SpriteData, Length(lSprites) div 4);
  for i := 0 to High(SpriteData) do
    SpriteData[i] := Cardinal(lSprites[4 * i]) or (Cardinal(lSprites[4 * i + 1]) shl 8)
      or (Cardinal(lSprites[4 * i + 2]) shl 16) or (Cardinal(lSprites[4 * i + 3]) shl 24);
  RoadGfx := DecodeRoad(aRoms.Region('segaic16road'));
  SetLength(WorkRam, $8000);
  SetLength(SubRam, $8000);
  SetLength(RoadRam, $1000);
  SetLength(RoadBuffer, $1000);
  SetLength(SpriteRam, $1000);
  SetLength(SpriteBuffer, $1000);
  SetLength(PaletteRam, $2000);
  SetLength(TileRam, $10000);
  SetLength(TextRam, $1000);

  Main := TM68000.Create;
  Main.OnRead8 := MainRead8;
  Main.OnRead16 := MainRead16;
  Main.OnWrite8 := MainWrite8;
  Main.OnWrite16 := MainWrite16;
  Main.OnResetOut := MainResetOut;
  Sub := TM68000.Create;
  Sub.OnRead8 := SubRead8;
  Sub.OnRead16 := SubRead16;
  Sub.OnWrite8 := SubWrite8;
  Sub.OnWrite16 := SubWrite16;
  Sound := TZ80.Create;
  Sound.OnRead := Z80Read;
  Sound.OnWrite := Z80Write;
  Sound.OnPortIn := Z80PortIn;
  Sound.OnPortOut := Z80PortOut;
  FYm := TYM2151.Create(C5376_SOUND_CLOCK);
  FPcm := TSegaPCM.Create(C5376_SOUND_CLOCK, aRoms.Region('pcm'), 12);
  Coinage := C5376_COINAGE_DEFAULT;
  Dsw := C5376_DSW_DEFAULT;
  Reset;
end;

destructor TBoardSega1715376.Destroy;
begin
  Main.Free;
  Sub.Free;
  Sound.Free;
  FYm.Free;
  FPcm.Free;
  inherited;
end;

function TBoardSega1715376.ScreenInfo: TScreenInfo;
begin
  Result.Width := C5376_WIDTH;
  Result.Height := C5376_HEIGHT;
  Result.Rotation := rot0;
  Result.FrameRate := C5376_FPS;
end;

procedure TBoardSega1715376.SetServiceMode(aOn: Boolean);
begin
  FServiceOn := aOn;
end;

procedure TBoardSega1715376.SetDip(aIndex: Integer; aValue: Byte);
begin
  case aIndex of
    0: Dsw := aValue;
    1: Coinage := aValue;
  end;
end;

function TBoardSega1715376.TextWord(aIndex: Integer): Word;
begin
  Result := Rd16(TextRam, (aIndex and $7FF) * 2);
end;

function TBoardSega1715376.TileWord(aIndex: Integer): Word;
begin
  Result := Rd16(TileRam, (aIndex and $7FFF) * 2);
end;

function TBoardSega1715376.RoadWord(aIndex: Integer): Word;
begin
  Result := Rd16(RoadBuffer, (aIndex and $7FF) * 2);
end;

function TBoardSega1715376.SpriteWord(aIndex: Integer): Word;
begin
  Result := Rd16(SpriteBuffer, (aIndex and $7FF) * 2);
end;

procedure TBoardSega1715376.Reset;
var
  i: Integer;
begin
  FillChar(WorkRam[0], Length(WorkRam), 0);
  FillChar(SubRam[0], Length(SubRam), 0);
  FillChar(RoadRam[0], Length(RoadRam), 0);
  FillChar(RoadBuffer[0], Length(RoadBuffer), 0);
  FillChar(SpriteRam[0], Length(SpriteRam), 0);
  FillChar(SpriteBuffer[0], Length(SpriteBuffer), 0);
  FillChar(PaletteRam[0], Length(PaletteRam), 0);
  FillChar(TileRam[0], Length(TileRam), 0);
  FillChar(TextRam[0], Length(TextRam), 0);
  FillChar(SoundRam, SizeOf(SoundRam), 0);
  for i := 0 to C5376_PALETTE - 1 do
    PaletteWrite(i * 2);
  FillChar(LatchedPages, SizeOf(LatchedPages), 0);
  FillChar(LatchedYScroll, SizeOf(LatchedYScroll), 0);
  FillChar(LatchedXScroll, SizeOf(LatchedXScroll), 0);
  RoadControl := 0;
  FillChar(FMapper, SizeOf(FMapper), 0);
  FToSound := 0;
  FFromSound := 0;
  FMainHeld := False;
  RebuildMap;
  FPpi[0] := 0;
  FPpi[1] := 0;
  FPpi[3] := $9B;
  SetPortC($FF);
  FAdcValue := 0;
  FAdcReady := False;
  FAdcBusy := False;
  FAdcDoneAt := 0;
  Steering := $80;
  Gas := 0;
  Brake := 0;
  HighGear := False;
  FGearPressed := False;
  Shaker := False;
  FShakeLevel := 0;
  BankMotor := 0;
  Rumble[0] := Default(TArcadeRumble);
  Rumble[1] := Default(TArcadeRumble);
  Inputs := Default(TArcadeInputs);
  FMainDebt := 0;
  FSubDebt := 0;
  FZ80Debt := 0;
  FFrame := 0;
  Main.Reset;
  Sub.Reset;
  Sound.Reset;
  FYm.Reset;
  FPcm.Reset;
  FAudioPos := 0;
end;

{ 315-5195 memory mapper }

procedure TBoardSega1715376.Install(aIndex: Integer; aOffset, aLength, aMirror: Cardinal;
  aKind: TMainPageKind; aMem: PByte; aMemSize: Cardinal; aRgnOffset: Cardinal);
var
  lMask, lBase, lMirror, lStart, lEnd, lAddr, lOfs: Cardinal;
  p: Integer;
begin
  lMask := CRegionSize[FMapper[$10 + 2 * aIndex] and 3];
  lBase := (Cardinal(FMapper[$11 + 2 * aIndex]) shl 16) and not lMask;
  lMirror := aMirror and lMask;
  lStart := lBase + (aOffset and lMask);
  if aLength - 1 < lMask then
    lEnd := lStart + aLength - 1
  else
    lEnd := lStart + lMask;
  for p := 0 to 4095 do
  begin
    lAddr := (Cardinal(p) shl 12) and not lMirror;
    if (lAddr >= lStart) and (lAddr <= lEnd) then
    begin
      lOfs := lAddr - lStart + aRgnOffset;
      if (aMem <> nil) and (lOfs + $1000 > aMemSize) then
        Continue;
      FPages[p].Kind := aKind;
      FPages[p].Mem := aMem;
      FPages[p].Offset := lOfs;
    end;
  end;
end;

procedure TBoardSega1715376.RebuildMap;
var
  p, lIndex: Integer;
begin
  for p := 0 to 4095 do
  begin
    FPages[p].Kind := mpMapper;
    FPages[p].Mem := nil;
    FPages[p].Offset := 0;
  end;
  for lIndex := 7 downto 0 do
    case lIndex of
      5:
        begin
          Install(5, $90000, $10000, $F00000, mpRoad, nil, 0, 0);
          Install(5, $80000, $01000, $F0F000, mpRam, @RoadRam[0], Length(RoadRam), 0);
          Install(5, $60000, $08000, $F18000, mpRam, @SubRam[0], Length(SubRam), 0);
          Install(5, $00000, $60000, $F00000, mpRom, @FSubRom[0], Length(FSubRom), 0);
        end;
      4: Install(4, $90000, $10000, $F00000, mpIo, nil, 0, 0);
      3: Install(3, $00000, $01000, $FFF000, mpRam, @SpriteRam[0], Length(SpriteRam), 0);
      2: Install(2, $00000, $02000, $FFE000, mpPalette, @PaletteRam[0], Length(PaletteRam), 0);
      1:
        begin
          Install(1, $00000, $10000, $FE0000, mpRam, @TileRam[0], Length(TileRam), 0);
          Install(1, $10000, $01000, $FEF000, mpRam, @TextRam[0], Length(TextRam), 0);
        end;
      0:
        begin
          Install(0, $60000, $08000, $F98000, mpRam, @WorkRam[0], Length(WorkRam), 0);
          Install(0, $00000, $60000, $F80000, mpRom, @FMainRom[0], Length(FMainRom), 0);
        end;
    end;
end;

function TBoardSega1715376.MapperRead(aOffset: Integer): Byte;
begin
  aOffset := aOffset and $1F;
  case aOffset of
    0, 1: Result := FMapper[aOffset];
    2:
      if (FMapper[2] and 3) = 3 then
        Result := 0
      else
        Result := $0F;
    3: Result := FFromSound;
  else
    Result := $FF;
  end;
end;

procedure TBoardSega1715376.MapperWrite(aOffset: Integer; aValue: Byte);
var
  lOld: Byte;
  lAddr: Cardinal;
  lWord: Word;
begin
  aOffset := aOffset and $1F;
  lOld := FMapper[aOffset];
  FMapper[aOffset] := aValue;
  case aOffset of
    2:
      if ((lOld xor aValue) and 3) <> 0 then
      begin
        if (aValue and 3) = 3 then
          FMainHeld := True
        else if FMainHeld then
        begin
          FMainHeld := False;
          Main.Reset;
        end;
      end;
    3:
      begin
        FToSound := aValue;
        Sound.RaiseNmi;
      end;
    5:
      if aValue = 1 then
      begin
        lAddr := (Cardinal(FMapper[$0A]) shl 17) or (Cardinal(FMapper[$0B]) shl 9) or (Cardinal(FMapper[$0C]) shl 1);
        MainWrite16(lAddr, (Word(FMapper[0]) shl 8) or FMapper[1]);
      end
      else if aValue = 2 then
      begin
        lAddr := (Cardinal(FMapper[$07]) shl 17) or (Cardinal(FMapper[$08]) shl 9) or (Cardinal(FMapper[$09]) shl 1);
        lWord := MainRead16(lAddr);
        FMapper[0] := lWord shr 8;
        FMapper[1] := lWord and $FF;
      end;
    $10..$1F:
      if lOld <> aValue then
        RebuildMap;
  end;
end;

{ palette }

procedure TBoardSega1715376.PaletteWrite(aOffset: Cardinal);
var
  lIndex: Integer;
  lValue: Word;
  r, g, b: Integer;
begin
  lIndex := (aOffset shr 1) and (C5376_PALETTE - 1);
  lValue := Rd16(PaletteRam, lIndex * 2);
  r := ((lValue shr 12) and 1) or ((lValue shl 1) and $1E);
  g := ((lValue shr 13) and 1) or ((lValue shr 3) and $1E);
  b := ((lValue shr 14) and 1) or ((lValue shr 7) and $1E);
  Palette[lIndex] := $FF000000 or (TArgb(GPalNormal[r]) shl 16) or (TArgb(GPalNormal[g]) shl 8) or GPalNormal[b];
  if (lValue and $8000) <> 0 then
    Palette[C5376_PALETTE + lIndex] := $FF000000 or (TArgb(GPalHilight[r]) shl 16) or (TArgb(GPalHilight[g]) shl 8) or GPalHilight[b]
  else
    Palette[C5376_PALETTE + lIndex] := $FF000000 or (TArgb(GPalShadow[r]) shl 16) or (TArgb(GPalShadow[g]) shl 8) or GPalShadow[b];
end;

{ I/O : 8255, inputs, ADC, sprite trigger }

procedure TBoardSega1715376.SetPortC(aValue: Byte);
var
  lOld: Byte;
begin
  lOld := FPpi[2];
  FPpi[2] := aValue;
  DisplayEnabled := (aValue and $20) <> 0;
  // D0 low holds the sound CPU in reset ; it restarts when released
  if ((lOld and 1) = 0) and ((aValue and 1) <> 0) then
    Sound.Reset;
end;

/// ADC0804 : the input is sampled when the conversion ends (73 ADC clocks at 1.05 MHz, about
/// 700 CPU cycles after the start), on the channel selected at that moment.
procedure TBoardSega1715376.AdcPoll;
begin
  if FAdcBusy and (Main.Cycles >= FAdcDoneAt) then
  begin
    FAdcBusy := False;
    case (FPpi[2] shr 2) and 7 of
      0: FAdcValue := Steering;
      1: FAdcValue := Gas;
      2: FAdcValue := Brake;
      3: FAdcValue := $80;
    else
      FAdcValue := $10;
    end;
    FAdcReady := True;
  end;
end;

procedure TBoardSega1715376.PpiWrite(aPort: Integer; aValue: Byte);
var
  lBit: Integer;
begin
  AdcPoll;
  case aPort of
    0: FPpi[0] := aValue;
    1:
      begin
        FPpi[1] := aValue;
        // bank motor : 1-7 left (8 - n), 8 still, 9-F right (n - 8) ; 0 is ignored
        if (aValue and $0F) <> 0 then
          BankMotor := (aValue and $0F) - 8;
      end;
    2: SetPortC(aValue);
  else
    if (aValue and $80) <> 0 then
    begin
      FPpi[3] := aValue;
      FPpi[0] := 0;
      FPpi[1] := 0;
      SetPortC(0);
    end
    else
    begin
      lBit := (aValue shr 1) and 7;
      if (aValue and 1) <> 0 then
        SetPortC(FPpi[2] or (1 shl lBit))
      else
        SetPortC(FPpi[2] and not (1 shl lBit));
    end;
  end;
end;

function TBoardSega1715376.PpiRead(aPort: Integer): Byte;
begin
  AdcPoll;
  case aPort of
    0:
      begin
        // bank motor limit switches (centered) and the ADC end-of-conversion line
        Result := $FF xor $10;
        if FAdcReady then
          Result := Result xor $40;
      end;
    1: Result := 0;
    2: Result := FPpi[2];
  else
    Result := FPpi[3];
  end;
end;

function TBoardSega1715376.ServicePort: Byte;
begin
  Result := $FF;
  if FServiceOn then Result := Result and not $02;
  if asService in Inputs.System then Result := Result and not $04;
  if asStart1 in Inputs.System then Result := Result and not $08;
  if not HighGear then Result := Result and not $10;
  if asCoin1 in Inputs.System then Result := Result and not $40;
  if asCoin2 in Inputs.System then Result := Result and not $80;
end;

function TBoardSega1715376.MiscIoRead(aAddr: Cardinal): Word;
var
  lOffset: Integer;
begin
  lOffset := (aAddr shr 1) and $3F;
  case lOffset and $38 of
    $00: Result := $FF00 or PpiRead(lOffset and 3);
    $08:
      case lOffset and 3 of
        0: Result := $FF00 or ServicePort;
        1: Result := $FFFF;
        2: Result := $FF00 or Coinage;
      else
        Result := $FF00 or Dsw;
      end;
    $18:
      begin
        AdcPoll;
        FAdcReady := False;
        Result := $FF00 or FAdcValue;
      end;
  else
    Result := $FFFF;
  end;
end;

procedure TBoardSega1715376.MiscIoWrite(aAddr: Cardinal; aValue, aMask: Word);
var
  lOffset: Integer;
begin
  lOffset := (aAddr shr 1) and $3F;
  case lOffset and $38 of
    $00:
      if (aMask and $00FF) <> 0 then
        PpiWrite(lOffset and 3, aValue and $FF);
    $18:
      begin
        // ADC0804 : start a conversion on the channel selected by the 8255 (port C D4-D2)
        AdcPoll;
        if not FAdcBusy then
        begin
          FAdcReady := False;
          FAdcBusy := True;
          FAdcDoneAt := Main.Cycles + Round(73 * C5376_CPU_CLOCK / (25174800 / 4 / 6));
        end;
      end;
    $10:
      if (aMask and $00FF) <> 0 then
        Shaker := (aValue and $20) <> 0;    // D7 /mute, D5 shaker, D2 start lamp, D1 brake lamp
    $38:
      begin
        // sprite chip : swap the two halves of the double buffer
        SwapContents(SpriteRam, SpriteBuffer);
      end;
  end;
end;

function TBoardSega1715376.RoadControlRead: Word;
begin
  SwapContents(RoadRam, RoadBuffer);
  Result := $FFFF;
end;

procedure TBoardSega1715376.RoadControlWrite(aValue, aMask: Word);
begin
  if (aMask and $00FF) <> 0 then
    RoadControl := aValue and 3;
end;

{ main CPU bus }

function TBoardSega1715376.MainRead16(aAddr: Cardinal): Word;
var
  lPage: ^TMainPage;
  lOfs: Cardinal;
begin
  lPage := @FPages[(aAddr shr 12) and $FFF];
  case lPage.Kind of
    mpRom, mpRam, mpPalette:
      begin
        lOfs := lPage.Offset + (aAddr and $FFE);
        Result := (Word(PByte(lPage.Mem + lOfs)^) shl 8) or PByte(lPage.Mem + lOfs + 1)^;
      end;
    mpIo: Result := MiscIoRead(aAddr);
    mpRoad: Result := RoadControlRead;
  else
    Result := $FF00 or MapperRead((aAddr shr 1) and $1F);
  end;
end;

function TBoardSega1715376.MainRead8(aAddr: Cardinal): Byte;
var
  lPage: ^TMainPage;
  lWord: Word;
begin
  lPage := @FPages[(aAddr shr 12) and $FFF];
  case lPage.Kind of
    mpRom, mpRam, mpPalette:
      Result := PByte(lPage.Mem + lPage.Offset + (aAddr and $FFF))^;
  else
    lWord := MainRead16(aAddr and not 1);
    if (aAddr and 1) <> 0 then
      Result := lWord and $FF
    else
      Result := lWord shr 8;
  end;
end;

procedure TBoardSega1715376.MainWrite16(aAddr: Cardinal; aValue: Word);
var
  lPage: ^TMainPage;
  lOfs: Cardinal;
begin
  lPage := @FPages[(aAddr shr 12) and $FFF];
  case lPage.Kind of
    mpRom: ;
    mpRam, mpPalette:
      begin
        lOfs := lPage.Offset + (aAddr and $FFE);
        PByte(lPage.Mem + lOfs)^ := aValue shr 8;
        PByte(lPage.Mem + lOfs + 1)^ := aValue and $FF;
        if lPage.Kind = mpPalette then
          PaletteWrite(lOfs);
      end;
    mpIo: MiscIoWrite(aAddr, aValue, $FFFF);
    mpRoad: RoadControlWrite(aValue, $FFFF);
  else
    MapperWrite((aAddr shr 1) and $1F, aValue and $FF);
  end;
end;

procedure TBoardSega1715376.MainWrite8(aAddr: Cardinal; aValue: Byte);
var
  lPage: ^TMainPage;
  lOfs: Cardinal;
begin
  lPage := @FPages[(aAddr shr 12) and $FFF];
  case lPage.Kind of
    mpRom: ;
    mpRam, mpPalette:
      begin
        lOfs := lPage.Offset + (aAddr and $FFF);
        PByte(lPage.Mem + lOfs)^ := aValue;
        if lPage.Kind = mpPalette then
          PaletteWrite(lOfs);
      end;
    mpIo:
      if (aAddr and 1) <> 0 then
        MiscIoWrite(aAddr, aValue, $00FF)
      else
        MiscIoWrite(aAddr, Word(aValue) shl 8, $FF00);
    mpRoad:
      if (aAddr and 1) <> 0 then
        RoadControlWrite(aValue, $00FF)
      else
        RoadControlWrite(Word(aValue) shl 8, $FF00);
  else
    if (aAddr and 1) <> 0 then
      MapperWrite((aAddr shr 1) and $1F, aValue);
  end;
end;

procedure TBoardSega1715376.MainResetOut;
begin
  Sub.Reset;
end;

{ sub CPU bus : ROM 00000-5FFFF, RAM 60000-7FFFF, road RAM 80000-8FFFF, road control 90000-9FFFF }

function TBoardSega1715376.SubRead16(aAddr: Cardinal): Word;
begin
  aAddr := aAddr and $FFFFE;
  case aAddr of
    $00000..$5FFFF: Result := Rd16(FSubRom, aAddr);
    $60000..$7FFFF: Result := Rd16(SubRam, aAddr and $7FFF);
    $80000..$8FFFF: Result := Rd16(RoadRam, aAddr and $FFF);
    $90000..$9FFFF: Result := RoadControlRead;
  else
    Result := $FFFF;
  end;
end;

function TBoardSega1715376.SubRead8(aAddr: Cardinal): Byte;
var
  lWord: Word;
begin
  aAddr := aAddr and $FFFFF;
  case aAddr of
    $00000..$5FFFF: Result := FSubRom[aAddr];
    $60000..$7FFFF: Result := SubRam[aAddr and $7FFF];
    $80000..$8FFFF: Result := RoadRam[aAddr and $FFF];
  else
    lWord := SubRead16(aAddr);
    if (aAddr and 1) <> 0 then
      Result := lWord and $FF
    else
      Result := lWord shr 8;
  end;
end;

procedure TBoardSega1715376.SubWrite16(aAddr: Cardinal; aValue: Word);
begin
  aAddr := aAddr and $FFFFE;
  case aAddr of
    $60000..$7FFFF: Wr16(SubRam, aAddr and $7FFF, aValue);
    $80000..$8FFFF: Wr16(RoadRam, aAddr and $FFF, aValue);
    $90000..$9FFFF: RoadControlWrite(aValue, $FFFF);
  end;
end;

procedure TBoardSega1715376.SubWrite8(aAddr: Cardinal; aValue: Byte);
begin
  aAddr := aAddr and $FFFFF;
  case aAddr of
    $60000..$7FFFF: SubRam[aAddr and $7FFF] := aValue;
    $80000..$8FFFF: RoadRam[aAddr and $FFF] := aValue;
    $90000..$9FFFF:
      if (aAddr and 1) <> 0 then
        RoadControlWrite(aValue, $00FF);
  end;
end;

{ sound CPU }

function TBoardSega1715376.Z80Read(aAddr: Word): Byte;
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

procedure TBoardSega1715376.Z80Write(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $F000..$F7FF: FPcm.Write(aAddr and $FF, aValue);
    $F800..$FFFF: SoundRam[aAddr and $7FF] := aValue;
  end;
end;

function TBoardSega1715376.Z80PortIn(aPort: Word): Byte;
begin
  case aPort and $C0 of
    $00: Result := FYm.Read(aPort and 1);
    $40: Result := FToSound;
  else
    Result := $FF;
  end;
end;

procedure TBoardSega1715376.Z80PortOut(aPort: Word; aValue: Byte);
begin
  if (aPort and $C0) = 0 then
    FYm.Write(aPort and 1, aValue);
end;

{ controls : the digital panel drives the wheel and pedals }

procedure TBoardSega1715376.UpdateControls;
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
  if abButton1 in lPad then
    Gas := Gas + 32
  else
    Gas := Gas - 48;
  if Gas > $FF then Gas := $FF;
  if Gas < 0 then Gas := 0;
  if abButton2 in lPad then
    Brake := Brake + 48
  else
    Brake := Brake - 64;
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

procedure TBoardSega1715376.RunSlice(aFraction: Double);
begin
  FMainDebt := FMainDebt + C5376_CPU_CLOCK / C5376_LINE_RATE * aFraction;
  if FMainHeld then
    FMainDebt := 0
  else
    while FMainDebt > 0 do
      FMainDebt := FMainDebt - Main.Step;
  FSubDebt := FSubDebt + C5376_CPU_CLOCK / C5376_LINE_RATE * aFraction;
  while FSubDebt > 0 do
    FSubDebt := FSubDebt - Sub.Step;
  FZ80Debt := FZ80Debt + C5376_Z80_CLOCK / C5376_LINE_RATE * aFraction;
  if (FPpi[2] and 1) = 0 then
    FZ80Debt := 0
  else
    while FZ80Debt > 0 do
      FZ80Debt := FZ80Debt - Sound.Step;
end;

procedure TBoardSega1715376.RunFrame;
var
  lLine, lSamples, i: Integer;
begin
  FAudioCount := 0;
  UpdateControls;
  for lLine := 0 to C5376_LINES - 1 do
  begin
    if lLine = 223 then
    begin
      Main.SetIrq(4);
      Sub.SetIrq(4);
    end
    else
    begin
      Main.SetIrq(0);
      Sub.SetIrq(0);
    end;
    if lLine in [65, 129, 193] then
    begin
      // IRQ2 rises at the hblank of these lines (pixel 320 of 400) and drops at the next line
      RunSlice(320 / 400);
      Main.SetIrq(2);
      RunSlice(80 / 400);
    end
    else
      RunSlice(1);
    if FAudioRate > 0 then
    begin
      FAudioPos := FAudioPos + FAudioRate / C5376_LINE_RATE;
      lSamples := Trunc(FAudioPos);
      FAudioPos := FAudioPos - lSamples;
      RenderAudio(lSamples);
    end;
    if (lLine = C5376_HEIGHT - 1) and RenderEnabled then
      Render1715376(Self, FScreen);
    if lLine = 261 then
      for i := 0 to 3 do
      begin
        LatchedPages[i] := TextWord($E80 div 2 + i);
        LatchedYScroll[i] := TextWord($E90 div 2 + i);
        LatchedXScroll[i] := TextWord($E98 div 2 + i);
      end;
  end;
  if Shaker then
    FShakeLevel := 1
  else if FShakeLevel > 0.2 then
    FShakeLevel := FShakeLevel - 0.2
  else
    FShakeLevel := 0;
  Rumble[0].Heavy := 0.8 * FShakeLevel;
  Rumble[0].Light := 0.5 * FShakeLevel;
  if BankMotor < 0 then
    Rumble[0].Heavy := Rumble[0].Heavy + 0.35 * -BankMotor / 7
  else if BankMotor > 0 then
    Rumble[0].Light := Rumble[0].Light + 0.5 * BankMotor / 7;
  Inc(FFrame);
end;

procedure TBoardSega1715376.SetAudioRate(aValue: Integer);
begin
  inherited;
  FAudioPos := 0;
end;

procedure TBoardSega1715376.RenderAudio(aCount: Integer);
const
  CYmMix = 0.30 * 2;
  CPcmMix = 0.70 * 2;
var
  i: Integer;
begin
  if FAudioCount + aCount > Length(FAudioBuffer) then
    aCount := Length(FAudioBuffer) - FAudioCount;
  if aCount <= 0 then
    Exit;
  for i := FAudioCount to FAudioCount + aCount - 1 do
    FAudioBuffer[i] := 0;
  FYm.FmGain := CYmMix;
  FPcm.Gain := CPcmMix;
  FYm.Render(FAudioBuffer, FAudioCount, aCount, FAudioRate);
  FPcm.Render(FAudioBuffer, FAudioCount, aCount, FAudioRate);
  Inc(FAudioCount, aCount);
end;

function TBoardSega1715376.StateHash: UInt64;
var
  lHash: UInt64;
  lRegs: array[0..255] of Byte;
  r: Integer;

  procedure Feed(const aData; aSize: Integer);
  var
    i: Integer;
    p: PByte;
  begin
    p := @aData;
    for i := 0 to aSize - 1 do
    begin
      lHash := (lHash xor p^) * UInt64($100000001B3);
      Inc(p);
    end;
  end;

  procedure FeedCpu(aCpu: TM68000);
  var
    lSR: Word;
    lPC: Cardinal;
  begin
    Feed(aCpu.D, SizeOf(aCpu.D));
    Feed(aCpu.A, SizeOf(aCpu.A));
    lSR := aCpu.SR;
    lPC := aCpu.PC;
    Feed(lSR, SizeOf(lSR));
    Feed(lPC, SizeOf(lPC));
  end;

begin
  lHash := UInt64($CBF29CE484222325);
  Feed(WorkRam[0], Length(WorkRam));
  Feed(SubRam[0], Length(SubRam));
  Feed(RoadRam[0], Length(RoadRam));
  Feed(RoadBuffer[0], Length(RoadBuffer));
  Feed(SpriteRam[0], Length(SpriteRam));
  Feed(SpriteBuffer[0], Length(SpriteBuffer));
  Feed(PaletteRam[0], Length(PaletteRam));
  Feed(TileRam[0], Length(TileRam));
  Feed(TextRam[0], Length(TextRam));
  Feed(SoundRam, SizeOf(SoundRam));
  Feed(FMapper, SizeOf(FMapper));
  Feed(FPpi, SizeOf(FPpi));
  FeedCpu(Main);
  FeedCpu(Sub);
  Feed(Sound.PC, SizeOf(Sound.PC));
  for r := 0 to 255 do
    lRegs[r] := FYm.Register(r);
  Feed(lRegs, SizeOf(lRegs));
  Result := lHash;
end;

initialization
  InitPaletteTables;
  RegisterBoard(TBoardSega1715376);

end.
