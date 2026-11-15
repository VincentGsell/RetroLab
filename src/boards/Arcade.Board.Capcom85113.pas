unit Arcade.Board.Capcom85113;

///  BOARD - Capcom PCB 85113 (1985) : 85113-A-1 main board + 85113-B-3 video board. 12 MHz crystal.
///
///  What is soldered on it :
///    Z80A #1 @ 3 MHz   main CPU, 4 x 16K program banks at 8000-BFFF        -> Arcade.Chip.Z80
///    Z80A #2 @ 3 MHz   sound CPU (inside a Capcom 85H001 custom)            -> Arcade.Chip.Z80
///    2 x YM2203 @ 1.5 MHz                                                   -> Arcade.Chip.YM2203
///    video : background = a 2048 x 8 map of 32x32 tiles read from ROM (no background RAM),
///            128 sprites copied by DMA, 8x8 text layer, layers switchable by the CPU,
///            RGB444 palette behind lookup PROMs                             -> .Video / .Gfx
///    3 fire buttons per player (left / centre / right shots).
///  Timing : 384 x 262 at 6 MHz, 59.64 Hz, visible y 16..239, ROT270 ; main IRQ at vblank,
///  sound CPU IRQ 4 times per frame (periodic, not from a PROM on this board).
///  Reference : MAME driver src/mame/capcom/gunsmoke.cpp. Pure unit : no FMX.

interface

uses
  System.SysUtils,
  System.Classes,
  Arcade.Gfx,
  Arcade.RomSet,
  Arcade.Board,
  Arcade.Chip.Z80,
  Arcade.Chip.YM2203,
  Arcade.Board.Capcom85113.Gfx;

const
  C85113_LINE_CYCLES = 192;
  C85113_LINES = 262;
  C85113_VBLANK_LINE = 240;
  C85113_FIRST_VISIBLE = 16;
  C85113_LAST_VISIBLE = 239;
  C85113_WIDTH = 256;
  C85113_HEIGHT = C85113_LAST_VISIBLE - C85113_FIRST_VISIBLE + 1;
  C85113_FPS = 6000000 / (384 * 262);
  C85113_YM_CLOCK = 1500000;

  // DIP defaults (MAME) : 30K 100K 100K+, demo on, upright, normal, no freeze, service off /
  // 1C/1C x2, continue, demo sounds
  C85113_DSW1_DEFAULT = $F7;
  C85113_DSW2_DEFAULT = $FF;

type
  TBoardCapcom85113 = class(TArcadeBoard)
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
  protected
    procedure SetAudioRate(aValue: Integer); override;
  public
    Main, Audio: TZ80;

    MainRam: array[0..$0FFF] of Byte;     // E000-EFFF
    SpriteRam: array[0..$0FFF] of Byte;   // F000-FFFF (CPU side)
    SpriteBuffer: array[0..$0FFF] of Byte;// DMA copy made on a C806 write
    AudioRam: array[0..$07FF] of Byte;    // C000-C7FF (sound CPU)
    FgRam: array[0..$07FF] of Byte;       // D000-D7FF : text codes 000-3FF, attributes 400-7FF
    Scroll: array[0..2] of Byte;          // D800-D801 X (16 bits), D802 Y
    Control: Byte;                        // C804 : b0-1 coin counters, b2-3 ROM bank, b6 flip, b7 text on
    Layers: Byte;                         // D806 : b0-2 sprite bank 3, b4 background on, b5 sprites on
    SoundLatch: Byte;
    Dsw1, Dsw2: Byte;
    BgMap: TBytes;                        // 'bgtiles' : the background map ROM

    Gfx: TGfx85113;

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
  end;

implementation

uses
  Arcade.Board.Capcom85113.Video;

{ TBoardCapcom85113 }

class function TBoardCapcom85113.Family: string;
begin
  Result := 'capcom85113';
end;

class function TBoardCapcom85113.Description: string;
begin
  Result := 'Capcom PCB 85113 : 2 x Z80 @ 3 MHz, 2 x YM2203, decor 32x32 en ROM, 128 sprites, 3 boutons';
end;

constructor TBoardCapcom85113.Create(aRoms: TRomSetData);
begin
  inherited Create(aRoms);
  FMainRom := aRoms.Region('maincpu');
  FAudioRom := aRoms.Region('audiocpu');
  BgMap := aRoms.Region('bgtiles');
  Gfx := DecodeGfx85113(aRoms);

  Main := TZ80.Create;
  Main.OnRead := MainRead;
  Main.OnWrite := MainWrite;
  Main.OnPortIn := NoPortIn;
  Main.OnPortOut := NoPortOut;

  Audio := TZ80.Create;
  Audio.OnRead := AudioRead;
  Audio.OnWrite := AudioWrite;
  Audio.OnPortIn := NoPortIn;
  Audio.OnPortOut := NoPortOut;

  // MAME routes : each SSG channel 0.22, FM 0.14
  FYm[0] := TYM2203.Create(C85113_YM_CLOCK);
  FYm[1] := TYM2203.Create(C85113_YM_CLOCK);
  FYm[0].FmGain := 0.14 / 0.22;
  FYm[1].FmGain := 0.14 / 0.22;

  Dsw1 := C85113_DSW1_DEFAULT;
  Dsw2 := C85113_DSW2_DEFAULT;
  Reset;
end;

destructor TBoardCapcom85113.Destroy;
begin
  Main.Free;
  Audio.Free;
  FYm[0].Free;
  FYm[1].Free;
  inherited;
end;

function TBoardCapcom85113.ScreenInfo: TScreenInfo;
begin
  Result.Width := C85113_WIDTH;
  Result.Height := C85113_HEIGHT;
  Result.Rotation := rot270;
  Result.FrameRate := C85113_FPS;
end;

procedure TBoardCapcom85113.SetServiceMode(aOn: Boolean);
begin
  if aOn then
    Dsw1 := Dsw1 and not $80
  else
    Dsw1 := Dsw1 or $80;
end;

procedure TBoardCapcom85113.SetDip(aIndex: Integer; aValue: Byte);
begin
  case aIndex of
    0: Dsw1 := aValue;
    1: Dsw2 := aValue;
  end;
end;

procedure TBoardCapcom85113.Reset;
begin
  FillChar(MainRam, SizeOf(MainRam), 0);
  FillChar(SpriteRam, SizeOf(SpriteRam), 0);
  FillChar(SpriteBuffer, SizeOf(SpriteBuffer), 0);
  FillChar(AudioRam, SizeOf(AudioRam), 0);
  FillChar(FgRam, SizeOf(FgRam), 0);
  FillChar(Scroll, SizeOf(Scroll), 0);
  Control := 0;
  Layers := 0;
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

{ Control panel : 3 shot buttons (left, centre, right) }

function TBoardCapcom85113.PortByte(const aButtons: TArcadeButtons): Byte;
begin
  Result := 0;
  if abRight in aButtons then Result := Result or $01;
  if abLeft in aButtons then Result := Result or $02;
  if abDown in aButtons then Result := Result or $04;
  if abUp in aButtons then Result := Result or $08;
  if abButton1 in aButtons then Result := Result or $10;
  if abButton2 in aButtons then Result := Result or $20;
  if abButton3 in aButtons then Result := Result or $40;
  Result := not Result;
end;

// SYSTEM : b0 start 1, b1 start 2, b3 "vblank" (reads inactive), b4 service, b6 coin 1, b7 coin 2
function TBoardCapcom85113.SystemByte: Byte;
begin
  Result := 0;
  if asStart1 in Inputs.System then Result := Result or $01;
  if asStart2 in Inputs.System then Result := Result or $02;
  if asService in Inputs.System then Result := Result or $10;
  if asCoin1 in Inputs.System then Result := Result or $40;
  if asCoin2 in Inputs.System then Result := Result or $80;
  Result := not Result;
end;

{ Memory maps }

function TBoardCapcom85113.NoPortIn(aPort: Word): Byte;
begin
  Result := $FF;
end;

procedure TBoardCapcom85113.NoPortOut(aPort: Word; aValue: Byte);
begin
end;

function TBoardCapcom85113.MainRead(aAddr: Word): Byte;
const
  // MAME protection_r : the routine at 0E69 jumps through C4CA-C4CB when C4C9 reads 0
  CProtection: array[0..2] of Byte = ($FF, $00, $00);
begin
  case aAddr of
    $0000..$7FFF: Result := FMainRom[aAddr];
    $8000..$BFFF: Result := FMainRom[$8000 + ((Control shr 2) and 3) * $4000 + (aAddr - $8000)];
    $C000: Result := SystemByte;
    $C001: Result := PortByte(Inputs.Players[0]);
    $C002: Result := PortByte(Inputs.Players[1]);
    $C003: Result := Dsw1;
    $C004: Result := Dsw2;
    $C4C9..$C4CB: Result := CProtection[aAddr - $C4C9];
    $D000..$D7FF: Result := FgRam[aAddr - $D000];
    $D800..$D802: Result := Scroll[aAddr - $D800];
    $E000..$EFFF: Result := MainRam[aAddr - $E000];
    $F000..$FFFF: Result := SpriteRam[aAddr - $F000];
  else
    Result := 0;
  end;
end;

procedure TBoardCapcom85113.MainWrite(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $C800: SoundLatch := aValue;
    $C804: Control := aValue;          // b5 (sound CPU reset ?) ignored, as in MAME
    $C806: Move(SpriteRam[0], SpriteBuffer[0], SizeOf(SpriteBuffer));   // sprite DMA
    $D000..$D7FF: FgRam[aAddr - $D000] := aValue;
    $D800..$D802: Scroll[aAddr - $D800] := aValue;
    $D806: Layers := aValue;
    $E000..$EFFF: MainRam[aAddr - $E000] := aValue;
    $F000..$FFFF: SpriteRam[aAddr - $F000] := aValue;
  end;
end;

function TBoardCapcom85113.AudioRead(aAddr: Word): Byte;
begin
  case aAddr of
    $0000..$7FFF: Result := FAudioRom[aAddr];
    $C000..$C7FF: Result := AudioRam[aAddr - $C000];
    $C800: Result := SoundLatch;
  else
    Result := 0;
  end;
end;

procedure TBoardCapcom85113.AudioWrite(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $C000..$C7FF: AudioRam[aAddr - $C000] := aValue;
    $E000, $E001: FYm[0].Write(aAddr and 1, aValue);
    $E002, $E003: FYm[1].Write(aAddr and 1, aValue);
  end;
end;

{ Frame }

procedure TBoardCapcom85113.RunFrame;
var
  lLine, lSamples: Integer;
begin
  FAudioCount := 0;
  for lLine := 0 to C85113_LINES - 1 do
  begin
    if lLine = C85113_VBLANK_LINE then
      Main.RaiseIrq($FF);                      // irq0_line_hold at vblank : RST 38h
    // periodic sound IRQ : 4 per frame, every 65.5 lines
    if (lLine * 2) mod 131 < 2 then
      Audio.RaiseIrq($FF);

    Inc(FMainDebt, C85113_LINE_CYCLES);
    while FMainDebt > 0 do
      Dec(FMainDebt, Main.Step);
    Inc(FAudioDebt, C85113_LINE_CYCLES);
    while FAudioDebt > 0 do
      Dec(FAudioDebt, Audio.Step);

    if FAudioRate > 0 then
    begin
      FAudioPos := FAudioPos + FAudioRate / (C85113_FPS * C85113_LINES);
      lSamples := Trunc(FAudioPos);
      FAudioPos := FAudioPos - lSamples;
      RenderAudio(lSamples);
    end;

    if (lLine = C85113_LAST_VISIBLE) and RenderEnabled then
      Render85113(Self, FScreen);
  end;
  Inc(FFrame);
end;

procedure TBoardCapcom85113.SetAudioRate(aValue: Integer);
begin
  inherited;
  FAudioPos := 0;
end;

procedure TBoardCapcom85113.RenderAudio(aCount: Integer);
const
  CMix = 0.35;
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

function TBoardCapcom85113.StateHash: UInt64;
var
  lHash: UInt64;
  r, c: Integer;
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

  procedure FeedCpu(aCpu: TZ80);
  begin
    Feed(aCpu.AF, 2); Feed(aCpu.BC, 2); Feed(aCpu.DE, 2); Feed(aCpu.HL, 2);
    Feed(aCpu.AF2, 2); Feed(aCpu.BC2, 2); Feed(aCpu.DE2, 2); Feed(aCpu.HL2, 2);
    Feed(aCpu.IX, 2); Feed(aCpu.IY, 2); Feed(aCpu.SP, 2); Feed(aCpu.PC, 2);
    Feed(aCpu.I, 1); Feed(aCpu.IFF1, 1); Feed(aCpu.IM, 1); Feed(aCpu.Halted, 1);
  end;

begin
  lHash := UInt64($CBF29CE484222325);
  Feed(MainRam, SizeOf(MainRam));
  Feed(SpriteRam, SizeOf(SpriteRam));
  Feed(SpriteBuffer, SizeOf(SpriteBuffer));
  Feed(AudioRam, SizeOf(AudioRam));
  Feed(FgRam, SizeOf(FgRam));
  Feed(Scroll, SizeOf(Scroll));
  Feed(Control, 1);
  Feed(Layers, 1);
  Feed(SoundLatch, 1);
  for c := 0 to 1 do
  begin
    for r := 0 to 255 do
      lYmRegs[r] := FYm[c].Register(r);
    Feed(lYmRegs, SizeOf(lYmRegs));
  end;
  FeedCpu(Main);
  FeedCpu(Audio);
  Result := lHash;
end;

initialization
  RegisterBoard(TBoardCapcom85113);

end.
