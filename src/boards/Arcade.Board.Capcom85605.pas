unit Arcade.Board.Capcom85605;

///  BOARD - Capcom PCB 85605 (1985) : three-board stack 85605-C-1 (background), 85605-A-2 (CPU,
///  sound), + video. 12 MHz crystal, the direct descendant of PCB 84100 (same irq PROM, same
///  timing, same graphics formats - see the uses clause).
///
///  What is soldered on it :
///    Z80A #1 @ 3 MHz   main CPU, OPCODES ENCRYPTED (data bytes are not)   -> Arcade.Chip.Z80
///    Z80A #2 @ 3 MHz   sound CPU                                          -> Arcade.Chip.Z80
///    2 x YM2203 @ 1.5 MHz (FM + SSG), YM3014 DAC                          -> Arcade.Chip.YM2203
///    video : 512x512 background scrolling on both axes, 96 sprites copied by DMA,
///            8x8 text layer, 256-colour RGB444 PROM palette               -> .Video
///  Timing : 384 x 262 at 6 MHz = 192 CPU T-states per line, 59.64 Hz, visible y 16..239, ROT270.
///  Interrupts : irq PROM (same as 84100) -> RST 10h at line 240 (vblank) ; 4 sound IRQs per frame.
///  Reference : MAME driver src/mame/capcom/commando.cpp. Pure unit : no FMX.

interface

uses
  System.SysUtils,
  System.Classes,
  Arcade.Gfx,
  Arcade.RomSet,
  Arcade.Board,
  Arcade.Chip.Z80,
  Arcade.Chip.YM2203,
  Arcade.Board.Capcom84100.Gfx;   // char / tile / sprite formats inherited from PCB 84100

const
  C85605_LINE_CYCLES = 192;
  C85605_LINES = 262;
  C85605_FIRST_VISIBLE = 16;
  C85605_LAST_VISIBLE = 239;
  C85605_WIDTH = 256;
  C85605_HEIGHT = C85605_LAST_VISIBLE - C85605_FIRST_VISIBLE + 1;
  C85605_FPS = 6000000 / (384 * 262);
  C85605_YM_CLOCK = 1500000;

  // DIP defaults (MAME) : forest 1, 3 lives, 1C/1C x2 / 10K 50K+, demo sounds, normal, upright
  C85605_DSW1_DEFAULT = $FF;
  C85605_DSW2_DEFAULT = $1F;

type
  TBoardCapcom85605 = class(TArcadeBoard)
  private
    FMainRom, FAudioRom, FIrqProm: TBytes;
    FOpcodes: TBytes;                       // decrypted copy of 0000-BFFF for M1 fetches
    FMainDebt, FAudioDebt: Integer;
    FYm: array[0..1] of TYM2203;
    FAudioPos: Double;
    procedure RenderAudio(aCount: Integer);
    function PortByte(const aButtons: TArcadeButtons): Byte;
    function SystemByte: Byte;
    function MainRead(aAddr: Word): Byte;
    function MainFetchOpcode(aAddr: Word): Byte;
    procedure MainWrite(aAddr: Word; aValue: Byte);
    function AudioRead(aAddr: Word): Byte;
    procedure AudioWrite(aAddr: Word; aValue: Byte);
    function NoPortIn(aPort: Word): Byte;
    procedure NoPortOut(aPort: Word; aValue: Byte);
    procedure SetControl(aValue: Byte);
  protected
    procedure SetAudioRate(aValue: Integer); override;
  public
    Main, Audio: TZ80;

    MainRam: array[0..$1FFF] of Byte;     // E000-FFFF (sprite list lives at FE00-FF7F)
    AudioRam: array[0..$07FF] of Byte;    // 4000-47FF
    FgRam: array[0..$07FF] of Byte;       // D000-D7FF : text codes 000-3FF, attributes 400-7FF
    BgRam: array[0..$07FF] of Byte;       // D800-DFFF : background codes 000-3FF, attributes 400-7FF
    SpriteBuffer: array[0..$17F] of Byte; // DMA copy of FE00-FF7F, made on a C806 write
    ScrollX, ScrollY: array[0..1] of Byte;
    Control: Byte;                        // C804 : b0-1 coin counters, b4 sound CPU reset, b7 flip
    SoundLatch: Byte;                     // C800 -> sound CPU 6000
    CoinCounter: Integer;
    Dsw1, Dsw2: Byte;

    Palette: array[0..255] of TArgb;      // RGB444 PROMs : tiles 0-127, sprites 128-191, text 192-255
    Chars, Tiles, Sprites: TGfxSet;

    class function Family: string; override;
    class function Description: string; override;
    constructor Create(aRoms: TRomSetData); override;
    destructor Destroy; override;
    procedure Reset; override;
    procedure RunFrame; override;
    function ScreenInfo: TScreenInfo; override;
    function StateHash: UInt64; override;
    /// commandou : DSW2 b3 is the service switch (on the other sets it is "demo sounds").
    procedure SetServiceMode(aOn: Boolean); override;
    procedure SetDip(aIndex: Integer; aValue: Byte); override;
  end;

implementation

uses
  Arcade.Board.Capcom85605.Video;

{ TBoardCapcom85605 }

class function TBoardCapcom85605.Family: string;
begin
  Result := 'capcom85605';
end;

class function TBoardCapcom85605.Description: string;
begin
  Result := 'Capcom PCB 85605 : 2 x Z80 @ 3 MHz (opcodes chiffres), 2 x YM2203, decor 2 axes, 96 sprites';
end;

constructor TBoardCapcom85605.Create(aRoms: TRomSetData);
var
  i: Integer;
  lProm: TBytes;
  lSrc: Byte;
begin
  inherited Create(aRoms);
  FMainRom := aRoms.Region('maincpu');
  FAudioRom := aRoms.Region('audiocpu');
  FIrqProm := aRoms.Region('irqprom');

  // opcode decryption (MAME init_commando) : bits 765 4 321 0 -> 321 4 765 0, first byte clear
  SetLength(FOpcodes, Length(FMainRom));
  FOpcodes[0] := FMainRom[0];
  for i := 1 to High(FMainRom) do
  begin
    lSrc := FMainRom[i];
    FOpcodes[i] := (lSrc and $11) or ((lSrc and $E0) shr 4) or ((lSrc and $0E) shl 4);
  end;

  // palette : 3 x 256x4 PROMs, 4 bits per gun (RGB_444_PROMS)
  lProm := aRoms.Region('proms');
  for i := 0 to 255 do
    Palette[i] := $FF000000
      or (TArgb((lProm[i] and $0F) * $11) shl 16)
      or (TArgb((lProm[i + $100] and $0F) * $11) shl 8)
      or TArgb((lProm[i + $200] and $0F) * $11);

  Chars := DecodeGfx(aRoms.Region('chars'), CharLayout(Length(aRoms.Region('chars'))));
  Tiles := DecodeGfx(aRoms.Region('tiles'), TileLayout(Length(aRoms.Region('tiles'))));
  Sprites := DecodeGfx(aRoms.Region('sprites'), SpriteLayout(Length(aRoms.Region('sprites'))));

  Main := TZ80.Create;
  Main.OnRead := MainRead;
  Main.OnFetchOpcode := MainFetchOpcode;
  Main.OnWrite := MainWrite;
  Main.OnPortIn := NoPortIn;
  Main.OnPortOut := NoPortOut;

  Audio := TZ80.Create;
  Audio.OnRead := AudioRead;
  Audio.OnWrite := AudioWrite;
  Audio.OnPortIn := NoPortIn;
  Audio.OnPortOut := NoPortOut;

  FYm[0] := TYM2203.Create(C85605_YM_CLOCK);
  FYm[1] := TYM2203.Create(C85605_YM_CLOCK);

  Dsw1 := C85605_DSW1_DEFAULT;
  Dsw2 := C85605_DSW2_DEFAULT;
  Reset;
end;

destructor TBoardCapcom85605.Destroy;
begin
  Main.Free;
  Audio.Free;
  FYm[0].Free;
  FYm[1].Free;
  inherited;
end;

function TBoardCapcom85605.ScreenInfo: TScreenInfo;
begin
  Result.Width := C85605_WIDTH;
  Result.Height := C85605_HEIGHT;
  Result.Rotation := rot270;
  Result.FrameRate := C85605_FPS;
end;

procedure TBoardCapcom85605.SetServiceMode(aOn: Boolean);
begin
  if aOn then
    Dsw2 := Dsw2 and not $08
  else
    Dsw2 := Dsw2 or $08;
end;

procedure TBoardCapcom85605.SetDip(aIndex: Integer; aValue: Byte);
begin
  case aIndex of
    0: Dsw1 := aValue;
    1: Dsw2 := aValue;
  end;
end;

procedure TBoardCapcom85605.Reset;
begin
  FillChar(MainRam, SizeOf(MainRam), 0);
  FillChar(AudioRam, SizeOf(AudioRam), 0);
  FillChar(FgRam, SizeOf(FgRam), 0);
  FillChar(BgRam, SizeOf(BgRam), 0);
  FillChar(SpriteBuffer, SizeOf(SpriteBuffer), 0);
  FillChar(ScrollX, SizeOf(ScrollX), 0);
  FillChar(ScrollY, SizeOf(ScrollY), 0);
  Control := 0;
  SoundLatch := 0;
  CoinCounter := 0;
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

{ Control panel -> input ports (active low), same wiring as PCB 84100 }

function TBoardCapcom85605.PortByte(const aButtons: TArcadeButtons): Byte;
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

function TBoardCapcom85605.SystemByte: Byte;
begin
  Result := 0;
  if asStart1 in Inputs.System then Result := Result or $01;
  if asStart2 in Inputs.System then Result := Result or $02;
  if asCoin2 in Inputs.System then Result := Result or $40;
  if asCoin1 in Inputs.System then Result := Result or $80;
  Result := not Result;
end;

{ Memory maps }

function TBoardCapcom85605.NoPortIn(aPort: Word): Byte;
begin
  Result := $FF;
end;

procedure TBoardCapcom85605.NoPortOut(aPort: Word; aValue: Byte);
begin
end;

function TBoardCapcom85605.MainFetchOpcode(aAddr: Word): Byte;
begin
  if aAddr < $C000 then
    Result := FOpcodes[aAddr]
  else
    Result := MainRead(aAddr);
end;

function TBoardCapcom85605.MainRead(aAddr: Word): Byte;
begin
  case aAddr of
    $0000..$BFFF: Result := FMainRom[aAddr];
    $C000: Result := SystemByte;
    $C001: Result := PortByte(Inputs.Players[0]);
    $C002: Result := PortByte(Inputs.Players[1]);
    $C003: Result := Dsw1;
    $C004: Result := Dsw2;
    $D000..$D7FF: Result := FgRam[aAddr - $D000];
    $D800..$DFFF: Result := BgRam[aAddr - $D800];
    $E000..$FFFF: Result := MainRam[aAddr - $E000];
  else
    Result := 0;
  end;
end;

procedure TBoardCapcom85605.MainWrite(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $C800: SoundLatch := aValue;
    $C804: SetControl(aValue);
    $C806: Move(MainRam[$FE00 - $E000], SpriteBuffer[0], SizeOf(SpriteBuffer));   // sprite DMA
    $C808: ScrollX[0] := aValue;
    $C809: ScrollX[1] := aValue;
    $C80A: ScrollY[0] := aValue;
    $C80B: ScrollY[1] := aValue;
    $D000..$D7FF: FgRam[aAddr - $D000] := aValue;
    $D800..$DFFF: BgRam[aAddr - $D800] := aValue;
    $E000..$FFFF: MainRam[aAddr - $E000] := aValue;
  end;
end;

procedure TBoardCapcom85605.SetControl(aValue: Byte);
begin
  if ((aValue and 1) <> 0) and ((Control and 1) = 0) then
    Inc(CoinCounter);
  if ((aValue and 2) <> 0) and ((Control and 2) = 0) then
    Inc(CoinCounter);
  if (aValue and $10) <> 0 then
  begin
    Audio.Reset;
    FAudioDebt := 0;
  end;
  Control := aValue;
end;

function TBoardCapcom85605.AudioRead(aAddr: Word): Byte;
begin
  case aAddr of
    $0000..$3FFF: Result := FAudioRom[aAddr];
    $4000..$47FF: Result := AudioRam[aAddr - $4000];
    $6000: Result := SoundLatch;
  else
    Result := 0;
  end;
end;

procedure TBoardCapcom85605.AudioWrite(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $4000..$47FF: AudioRam[aAddr - $4000] := aValue;
    $8000, $8001: FYm[0].Write(aAddr and 1, aValue);
    $8002, $8003: FYm[1].Write(aAddr and 1, aValue);
  end;
end;

{ Frame }

procedure TBoardCapcom85605.RunFrame;
var
  lLine, lSamples: Integer;
  lIrq: Byte;
begin
  FAudioCount := 0;
  for lLine := 0 to C85605_LINES - 1 do
  begin
    lIrq := FIrqProm[lLine and $FF];
    if (lIrq and 8) <> 0 then
      Main.RaiseIrq($C7 or ((lIrq shl 3) and $18));
    if ((lIrq and 4) <> 0) and ((Control and $10) = 0) then
      Audio.RaiseIrq($FF);

    Inc(FMainDebt, C85605_LINE_CYCLES);
    while FMainDebt > 0 do
      Dec(FMainDebt, Main.Step);

    if (Control and $10) = 0 then
    begin
      Inc(FAudioDebt, C85605_LINE_CYCLES);
      while FAudioDebt > 0 do
        Dec(FAudioDebt, Audio.Step);
    end;

    if FAudioRate > 0 then
    begin
      FAudioPos := FAudioPos + FAudioRate / (C85605_FPS * C85605_LINES);
      lSamples := Trunc(FAudioPos);
      FAudioPos := FAudioPos - lSamples;
      RenderAudio(lSamples);
    end;

    if (lLine = C85605_LAST_VISIBLE) and RenderEnabled then
      Render85605(Self, FScreen);
  end;
  Inc(FFrame);
end;

procedure TBoardCapcom85605.SetAudioRate(aValue: Integer);
begin
  inherited;
  FAudioPos := 0;
end;

procedure TBoardCapcom85605.RenderAudio(aCount: Integer);
const
  CMix = 0.35;   // two YM2203 (FM + 3 SSG channels each) brought to the 1942 board's loudness
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

function TBoardCapcom85605.StateHash: UInt64;
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
  Feed(AudioRam, SizeOf(AudioRam));
  Feed(FgRam, SizeOf(FgRam));
  Feed(BgRam, SizeOf(BgRam));
  Feed(SpriteBuffer, SizeOf(SpriteBuffer));
  Feed(ScrollX, SizeOf(ScrollX));
  Feed(ScrollY, SizeOf(ScrollY));
  Feed(Control, 1);
  Feed(SoundLatch, 1);
  for r := 0 to 255 do
    lYmRegs[r] := FYm[0].Register(r);
  Feed(lYmRegs, SizeOf(lYmRegs));
  for r := 0 to 255 do
    lYmRegs[r] := FYm[1].Register(r);
  Feed(lYmRegs, SizeOf(lYmRegs));
  FeedCpu(Main);
  FeedCpu(Audio);
  Result := lHash;
end;

initialization
  RegisterBoard(TBoardCapcom85605);

end.
