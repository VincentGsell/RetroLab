unit Arcade.Board.Capcom85606;

///  BOARD - Capcom PCB 85606 (1985) : CPU / sound board 85606-A + video board 85606-B, 12 MHz crystal.
///
///  What is soldered on it :
///    MC6809 @ 1.5 MHz (E clock of a 6 MHz crystal) main CPU            -> Arcade.Chip.M6809
///    Z80A @ 3 MHz      sound CPU                                       -> Arcade.Chip.Z80
///    2 x YM2203 @ 1.5 MHz (FM + SSG)                                   -> Arcade.Chip.YM2203
///    video : 512x512 background of 16x16 tiles on two priority levels, 128 sprites copied to a
///            buffer, 8x8 text layer, 256-colour RGB444 palette written by the CPU   -> .Video
///  Timing : 384 x 262 at 6 MHz = 96 main CPU cycles per line, 59.64 Hz, visible y 16..239, ROT0.
///  Interrupts : main IRQ at vblank (line 240), held until taken ; 4 sound IRQs per frame.
///  Reference : MAME driver src/mame/capcom/gng.cpp. Pure unit : no FMX.

interface

uses
  System.SysUtils,
  System.Classes,
  Arcade.Gfx,
  Arcade.RomSet,
  Arcade.Board,
  Arcade.Chip.M6809,
  Arcade.Chip.Z80,
  Arcade.Chip.YM2203;

const
  C85606_MAIN_LINE_CYCLES = 96;
  C85606_AUDIO_LINE_CYCLES = 192;
  C85606_LINES = 262;
  C85606_FIRST_VISIBLE = 16;
  C85606_LAST_VISIBLE = 239;
  C85606_WIDTH = 256;
  C85606_HEIGHT = C85606_LAST_VISIBLE - C85606_FIRST_VISIBLE + 1;
  C85606_FPS = 6000000 / (384 * 262);
  C85606_YM_CLOCK = 1500000;

  // DIP defaults (MAME) : 1C/1C, demo sounds on, no flip, 3 lives, upright, 20K 70K+, normal
  C85606_DSW1_DEFAULT = $DF;
  C85606_DSW2_DEFAULT = $FB;

type
  TBoardCapcom85606 = class(TArcadeBoard)
  private
    FMainRom, FAudioRom: TBytes;
    FMainDebt, FAudioDebt: Integer;
    FYm: array[0..1] of TYM2203;
    FAudioPos: Double;
    procedure RenderAudio(aCount: Integer);
    function PortByte(const aButtons: TArcadeButtons): Byte;
    function SystemByte: Byte;
    function MainRead(aAddr: Word): Byte;
    procedure MainWrite(aAddr: Word; aValue: Byte);
    function AudioRead(aAddr: Word): Byte;
    procedure AudioWrite(aAddr: Word; aValue: Byte);
    function NoPortIn(aPort: Word): Byte;
    procedure NoPortOut(aPort: Word; aValue: Byte);
    procedure SetLatch(aBit: Integer; aOn: Boolean);
    procedure SetPaletteEntry(aIndex: Integer);
  protected
    procedure SetAudioRate(aValue: Integer); override;
  public
    Main: TM6809;
    Audio: TZ80;

    MainRam: array[0..$1FFF] of Byte;      // 0000-1FFF (sprite list lives at 1E00-1FFF)
    AudioRam: array[0..$07FF] of Byte;     // C000-C7FF
    FgRam: array[0..$07FF] of Byte;        // 2000-27FF : text codes 000-3FF, attributes 400-7FF
    BgRam: array[0..$07FF] of Byte;        // 2800-2FFF : background codes 000-3FF, attributes 400-7FF
    SpriteBuffer: array[0..$1FF] of Byte;  // copy of 1E00-1FFF, made on a 3C00 write
    PalBase, PalExt: array[0..255] of Byte;  // 3900-39FF (blue), 3800-38FF (red, green)
    ScrollX, ScrollY: array[0..1] of Byte;
    Bank: Integer;                         // 4000-5FFF window : 0-3 = banked ROM, 4 = fixed ROM
    Latch: Byte;                           // LS259 at 3D00-3D07 : b0 flip (inverted), b1 sound run
    SoundLatch: Byte;                      // 3A00 -> sound CPU C800
    Dsw1, Dsw2: Byte;

    Palette: array[0..255] of TArgb;       // tiles 00-3F, sprites 40-7F, text 80-BF
    Chars, Tiles, Sprites: TGfxSet;

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
    function Flipped: Boolean;
    function SoundRunning: Boolean;
  end;

implementation

uses
  Arcade.Board.Capcom85606.Video;

{ graphics layouts (MAME gng.cpp), offsets in bits }

function CharLayout(aRegionSize: Integer): TGfxLayout;
const
  CX: array[0..7] of Integer = (0, 1, 2, 3, 8 + 0, 8 + 1, 8 + 2, 8 + 3);
var
  i: Integer;
begin
  Result := Default(TGfxLayout);
  Result.Width := 8;
  Result.Height := 8;
  Result.Planes := 2;
  Result.PlaneOfs[0] := 4;
  Result.PlaneOfs[1] := 0;
  for i := 0 to 7 do
  begin
    Result.XOfs[i] := CX[i];
    Result.YOfs[i] := i * 16;
  end;
  Result.CharInc := 16 * 8;
  Result.Count := (aRegionSize * 8) div Result.CharInc;
end;

function TileLayout(aRegionSize: Integer): TGfxLayout;
var
  lThird, i: Integer;
begin
  Result := Default(TGfxLayout);
  lThird := (aRegionSize * 8) div 3;
  Result.Width := 16;
  Result.Height := 16;
  Result.Planes := 3;
  Result.PlaneOfs[0] := lThird * 2;   // RGN_FRAC(2,3)
  Result.PlaneOfs[1] := lThird;       // RGN_FRAC(1,3)
  Result.PlaneOfs[2] := 0;
  for i := 0 to 7 do
  begin
    Result.XOfs[i] := i;
    Result.XOfs[i + 8] := 16 * 8 + i;
  end;
  for i := 0 to 15 do
    Result.YOfs[i] := i * 8;
  Result.CharInc := 32 * 8;
  Result.Count := lThird div Result.CharInc;
end;

function SpriteLayout(aRegionSize: Integer): TGfxLayout;
const
  CX: array[0..15] of Integer = (0, 1, 2, 3, 8 + 0, 8 + 1, 8 + 2, 8 + 3,
    32 * 8 + 0, 32 * 8 + 1, 32 * 8 + 2, 32 * 8 + 3, 33 * 8 + 0, 33 * 8 + 1, 33 * 8 + 2, 33 * 8 + 3);
var
  lHalf, i: Integer;
begin
  Result := Default(TGfxLayout);
  lHalf := (aRegionSize * 8) div 2;
  Result.Width := 16;
  Result.Height := 16;
  Result.Planes := 4;
  Result.PlaneOfs[0] := lHalf + 4;    // RGN_FRAC(1,2)+4
  Result.PlaneOfs[1] := lHalf + 0;
  Result.PlaneOfs[2] := 4;
  Result.PlaneOfs[3] := 0;
  for i := 0 to 15 do
  begin
    Result.XOfs[i] := CX[i];
    Result.YOfs[i] := i * 16;
  end;
  Result.CharInc := 64 * 8;
  Result.Count := lHalf div Result.CharInc;
end;

{ TBoardCapcom85606 }

class function TBoardCapcom85606.Family: string;
begin
  Result := 'capcom85606';
end;

class function TBoardCapcom85606.Description: string;
begin
  Result := 'Capcom PCB 85606 : MC6809 @ 1.5 MHz + Z80 @ 3 MHz, 2 x YM2203, decor 2 niveaux, 128 sprites';
end;

constructor TBoardCapcom85606.Create(aRoms: TRomSetData);
begin
  inherited Create(aRoms);
  FMainRom := aRoms.Region('maincpu');
  FAudioRom := aRoms.Region('audiocpu');
  Chars := DecodeGfx(aRoms.Region('chars'), CharLayout(Length(aRoms.Region('chars'))));
  Tiles := DecodeGfx(aRoms.Region('tiles'), TileLayout(Length(aRoms.Region('tiles'))));
  Sprites := DecodeGfx(aRoms.Region('sprites'), SpriteLayout(Length(aRoms.Region('sprites'))));

  Main := TM6809.Create;
  Main.OnRead := MainRead;
  Main.OnWrite := MainWrite;
  Audio := TZ80.Create;
  Audio.OnRead := AudioRead;
  Audio.OnWrite := AudioWrite;
  Audio.OnPortIn := NoPortIn;
  Audio.OnPortOut := NoPortOut;
  FYm[0] := TYM2203.Create(C85606_YM_CLOCK);
  FYm[1] := TYM2203.Create(C85606_YM_CLOCK);
  Dsw1 := C85606_DSW1_DEFAULT;
  Dsw2 := C85606_DSW2_DEFAULT;
  Reset;
end;

destructor TBoardCapcom85606.Destroy;
begin
  Main.Free;
  Audio.Free;
  FYm[0].Free;
  FYm[1].Free;
  inherited;
end;

function TBoardCapcom85606.ScreenInfo: TScreenInfo;
begin
  Result.Width := C85606_WIDTH;
  Result.Height := C85606_HEIGHT;
  Result.Rotation := rot0;
  Result.FrameRate := C85606_FPS;
end;

procedure TBoardCapcom85606.SetServiceMode(aOn: Boolean);
begin
  if aOn then
    Dsw1 := Dsw1 and not $40
  else
    Dsw1 := Dsw1 or $40;
end;

procedure TBoardCapcom85606.SetDip(aIndex: Integer; aValue: Byte);
begin
  case aIndex of
    0: Dsw1 := aValue;
    1: Dsw2 := aValue;
  end;
end;

function TBoardCapcom85606.Flipped: Boolean;
begin
  Result := (Latch and 1) = 0;     // LS259 Q0, inverted
end;

function TBoardCapcom85606.SoundRunning: Boolean;
begin
  Result := (Latch and 2) <> 0;    // LS259 Q1 low holds the sound CPU and both YM2203 in reset
end;

procedure TBoardCapcom85606.SetPaletteEntry(aIndex: Integer);
begin
  // RGBx_444, PalExt = high byte (R, G), PalBase = low byte (B, unused)
  Palette[aIndex] := $FF000000
    or (TArgb((PalExt[aIndex] shr 4) * $11) shl 16)
    or (TArgb((PalExt[aIndex] and $0F) * $11) shl 8)
    or TArgb((PalBase[aIndex] shr 4) * $11);
end;

procedure TBoardCapcom85606.Reset;
const
  CPost: array[0..3] of Byte = ($00, $55, $AA, $FF);   // MAME machine_reset : greys until the game writes
var
  i: Integer;
begin
  FillChar(MainRam, SizeOf(MainRam), 0);
  FillChar(AudioRam, SizeOf(AudioRam), 0);
  FillChar(FgRam, SizeOf(FgRam), 0);
  FillChar(BgRam, SizeOf(BgRam), 0);
  FillChar(SpriteBuffer, SizeOf(SpriteBuffer), 0);
  FillChar(ScrollX, SizeOf(ScrollX), 0);
  FillChar(ScrollY, SizeOf(ScrollY), 0);
  for i := 0 to 255 do
  begin
    PalBase[i] := CPost[i and 3];
    PalExt[i] := CPost[i and 3];
    SetPaletteEntry(i);
  end;
  Bank := 0;
  Latch := 0;
  SoundLatch := 0;
  Inputs := Default(TArcadeInputs);
  FMainDebt := 0;
  FAudioDebt := 0;
  FFrame := 0;
  Main.Reset;
  Audio.Reset;
  FYm[0].Reset;
  FYm[1].Reset;
  FAudioPos := 0;
end;

{ Control panel -> input ports (active low) }

function TBoardCapcom85606.PortByte(const aButtons: TArcadeButtons): Byte;
begin
  Result := 0;
  if abRight in aButtons then Result := Result or $01;
  if abLeft in aButtons then Result := Result or $02;
  if abDown in aButtons then Result := Result or $04;
  if abUp in aButtons then Result := Result or $08;
  if abButton1 in aButtons then Result := Result or $10;
  if abButton2 in aButtons then Result := Result or $20;
  Result := not Result;
end;

function TBoardCapcom85606.SystemByte: Byte;
begin
  Result := 0;
  if asStart1 in Inputs.System then Result := Result or $01;
  if asStart2 in Inputs.System then Result := Result or $02;
  if asService in Inputs.System then Result := Result or $20;
  if asCoin1 in Inputs.System then Result := Result or $40;
  if asCoin2 in Inputs.System then Result := Result or $80;
  Result := not Result;
end;

{ Memory maps }

function TBoardCapcom85606.NoPortIn(aPort: Word): Byte;
begin
  Result := $FF;
end;

procedure TBoardCapcom85606.NoPortOut(aPort: Word; aValue: Byte);
begin
end;

function TBoardCapcom85606.MainRead(aAddr: Word): Byte;
begin
  case aAddr of
    $0000..$1FFF: Result := MainRam[aAddr];
    $2000..$27FF: Result := FgRam[aAddr - $2000];
    $2800..$2FFF: Result := BgRam[aAddr - $2800];
    $3000: Result := SystemByte;
    $3001: Result := PortByte(Inputs.Players[0]);
    $3002: Result := PortByte(Inputs.Players[1]);
    $3003: Result := Dsw1;
    $3004: Result := Dsw2;
    $4000..$5FFF:
      if Bank = 4 then
        Result := FMainRom[aAddr]
      else
        Result := FMainRom[$10000 + Bank * $2000 + (aAddr - $4000)];
    $6000..$FFFF: Result := FMainRom[aAddr];
  else
    Result := 0;
  end;
end;

procedure TBoardCapcom85606.MainWrite(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $0000..$1FFF: MainRam[aAddr] := aValue;
    $2000..$27FF: FgRam[aAddr - $2000] := aValue;
    $2800..$2FFF: BgRam[aAddr - $2800] := aValue;
    $3800..$38FF:
      begin
        PalExt[aAddr - $3800] := aValue;
        SetPaletteEntry(aAddr - $3800);
      end;
    $3900..$39FF:
      begin
        PalBase[aAddr - $3900] := aValue;
        SetPaletteEntry(aAddr - $3900);
      end;
    $3A00: SoundLatch := aValue;
    $3B08: ScrollX[0] := aValue;
    $3B09: ScrollX[1] := aValue;
    $3B0A: ScrollY[0] := aValue;
    $3B0B: ScrollY[1] := aValue;
    $3C00: Move(MainRam[$1E00], SpriteBuffer[0], SizeOf(SpriteBuffer));   // sprite DMA
    $3D00..$3D07: SetLatch(aAddr - $3D00, (aValue and 1) <> 0);
    $3E00:
      if aValue = 4 then
        Bank := 4
      else
        Bank := aValue and 3;
  end;
end;

procedure TBoardCapcom85606.SetLatch(aBit: Integer; aOn: Boolean);
var
  lWasRunning: Boolean;
begin
  lWasRunning := SoundRunning;
  if aOn then
    Latch := Latch or (1 shl aBit)
  else
    Latch := Latch and not (1 shl aBit);
  if lWasRunning and not SoundRunning then
  begin
    Audio.Reset;
    FYm[0].Reset;
    FYm[1].Reset;
    FAudioDebt := 0;
  end;
end;

function TBoardCapcom85606.AudioRead(aAddr: Word): Byte;
begin
  case aAddr of
    $0000..$7FFF: Result := FAudioRom[aAddr];
    $C000..$C7FF: Result := AudioRam[aAddr - $C000];
    $C800: Result := SoundLatch;
  else
    Result := 0;
  end;
end;

procedure TBoardCapcom85606.AudioWrite(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $C000..$C7FF: AudioRam[aAddr - $C000] := aValue;
    $E000, $E001: FYm[0].Write(aAddr and 1, aValue);
    $E002, $E003: FYm[1].Write(aAddr and 1, aValue);
  end;
end;

{ Frame }

procedure TBoardCapcom85606.RunFrame;
var
  lLine, lSamples: Integer;
begin
  FAudioCount := 0;
  for lLine := 0 to C85606_LINES - 1 do
  begin
    if lLine = C85606_LAST_VISIBLE + 1 then
      Main.RaiseIrq;                                  // vblank
    if SoundRunning and (lLine in [0, 66, 131, 197]) then
      Audio.RaiseIrq($FF);                            // 4 x 60 Hz

    Inc(FMainDebt, C85606_MAIN_LINE_CYCLES);
    while FMainDebt > 0 do
      Dec(FMainDebt, Main.Step);

    if SoundRunning then
    begin
      Inc(FAudioDebt, C85606_AUDIO_LINE_CYCLES);
      while FAudioDebt > 0 do
        Dec(FAudioDebt, Audio.Step);
    end;

    if FAudioRate > 0 then
    begin
      FAudioPos := FAudioPos + FAudioRate / (C85606_FPS * C85606_LINES);
      lSamples := Trunc(FAudioPos);
      FAudioPos := FAudioPos - lSamples;
      RenderAudio(lSamples);
    end;

    if (lLine = C85606_LAST_VISIBLE) and RenderEnabled then
      Render85606(Self, FScreen);
  end;
  Inc(FFrame);
end;

procedure TBoardCapcom85606.SetAudioRate(aValue: Integer);
begin
  inherited;
  FAudioPos := 0;
end;

procedure TBoardCapcom85606.RenderAudio(aCount: Integer);
const
  CMix = 0.35;   // same mix as the other two-YM2203 boards
var
  i: Integer;
begin
  if FAudioCount + aCount > Length(FAudioBuffer) then
    aCount := Length(FAudioBuffer) - FAudioCount;
  if aCount <= 0 then
    Exit;
  for i := FAudioCount to FAudioCount + aCount - 1 do
    FAudioBuffer[i] := 0;
  FYm[0].Render(FAudioBuffer, FAudioCount, aCount, FAudioRate);
  FYm[1].Render(FAudioBuffer, FAudioCount, aCount, FAudioRate);
  for i := FAudioCount to FAudioCount + aCount - 1 do
    FAudioBuffer[i] := FAudioBuffer[i] * CMix;
  Inc(FAudioCount, aCount);
end;

function TBoardCapcom85606.StateHash: UInt64;
var
  lHash: UInt64;
  r: Integer;
  lYmRegs: array[0..255] of Byte;

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

begin
  lHash := UInt64($CBF29CE484222325);
  Feed(MainRam, SizeOf(MainRam));
  Feed(AudioRam, SizeOf(AudioRam));
  Feed(FgRam, SizeOf(FgRam));
  Feed(BgRam, SizeOf(BgRam));
  Feed(SpriteBuffer, SizeOf(SpriteBuffer));
  Feed(PalBase, SizeOf(PalBase));
  Feed(PalExt, SizeOf(PalExt));
  Feed(ScrollX, SizeOf(ScrollX));
  Feed(ScrollY, SizeOf(ScrollY));
  Feed(Bank, SizeOf(Bank));
  Feed(Latch, 1);
  Feed(SoundLatch, 1);
  for r := 0 to 255 do
    lYmRegs[r] := FYm[0].Register(r);
  Feed(lYmRegs, SizeOf(lYmRegs));
  for r := 0 to 255 do
    lYmRegs[r] := FYm[1].Register(r);
  Feed(lYmRegs, SizeOf(lYmRegs));
  Feed(Main.A, 1); Feed(Main.B, 1); Feed(Main.DP, 1); Feed(Main.CC, 1);
  Feed(Main.X, 2); Feed(Main.Y, 2); Feed(Main.U, 2); Feed(Main.S, 2); Feed(Main.PC, 2);
  Feed(Audio.AF, 2); Feed(Audio.BC, 2); Feed(Audio.DE, 2); Feed(Audio.HL, 2);
  Feed(Audio.AF2, 2); Feed(Audio.BC2, 2); Feed(Audio.DE2, 2); Feed(Audio.HL2, 2);
  Feed(Audio.IX, 2); Feed(Audio.IY, 2); Feed(Audio.SP, 2); Feed(Audio.PC, 2);
  Feed(Audio.I, 1); Feed(Audio.IFF1, 1); Feed(Audio.IM, 1); Feed(Audio.Halted, 1);
  Result := lHash;
end;

initialization
  RegisterBoard(TBoardCapcom85606);

end.
