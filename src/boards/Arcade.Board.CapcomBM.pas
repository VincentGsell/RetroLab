unit Arcade.Board.CapcomBM;

///  BOARD - Capcom "BM" board (1987). PCB number still to confirm : "BM" is the code printed on every
///  ROM and PROM of the board (bm01..bm25, bm1..bm12). 24 MHz crystal. Grown from PCB 85113.
///
///  What is soldered on it :
///    Z80 @ 6 MHz          main CPU, 8 x 16K program banks at 8000-BFFF        -> Arcade.Chip.Z80
///    Z80 @ 3 MHz          sound CPU                                            -> Arcade.Chip.Z80
///    Intel C8751H @ 3 MHz protection MCU : swaps bytes with the main CPU     -> Arcade.Chip.MCS51
///    2 x YM2203 @ 1.5 MHz                                                      -> Arcade.Chip.YM2203
///    video : TWO background maps in ROM (2048 x 8 tiles of 32x32), 128 sprites (86S105 custom)
///            with per-pen priority against the front background, 8x8 text layer -> .Video / .Gfx
///  Timing : 384 x 262 at 6 MHz, 59.64 Hz, visible y 16..239, ROT270.
///    main IRQ lines 144 and 240 ; sound IRQ lines 32, 96, 160, 224 ; MCU INT1 = vblank.
///  MCU wiring : P0 in = byte from main CPU (C807), P0 out + P3.6 strobe -> main CPU (C007) ;
///               P2 in/out <-> sound CPU (D800) ; P1 in = current scanline.
///  Reference : MAME driver src/mame/capcom/1943.cpp + 1943_v.cpp. Pure unit : no FMX.

interface

uses
  System.SysUtils,
  System.Classes,
  Arcade.Gfx,
  Arcade.RomSet,
  Arcade.Board,
  Arcade.Chip.Z80,
  Arcade.Chip.MCS51,
  Arcade.Chip.YM2203,
  Arcade.Board.CapcomBM.Gfx;

const
  CBM_MAIN_LINE_CYCLES = 384;    // 6 MHz
  CBM_AUDIO_LINE_CYCLES = 192;   // 3 MHz
  CBM_MCU_LINE_CYCLES = 16;      // 3 MHz / 12 per machine cycle
  CBM_LINES = 262;
  CBM_FIRST_VISIBLE = 16;
  CBM_LAST_VISIBLE = 239;
  CBM_WIDTH = 256;
  CBM_HEIGHT = CBM_LAST_VISIBLE - CBM_FIRST_VISIBLE + 1;
  CBM_FPS = 6000000 / (384 * 262);
  CBM_YM_CLOCK = 1500000;

  // DIP defaults (MAME) : difficulty 8, 2 credits for 2 players, no flip, no stop, service off / coins
  CBM_DSWA_DEFAULT = $F8;
  CBM_DSWB_DEFAULT = $FF;

type
  TBoardCapcomBM = class(TArcadeBoard)
  private
    FMainRom, FAudioRom: TBytes;
    FMainDebt, FAudioDebt, FMcuDebt: Integer;
    FYm: array[0..1] of TYM2203;
    FAudioPos: Double;
    FLine: Integer;
    procedure RenderAudio(aCount: Integer);
    function PortByte(const aButtons: TArcadeButtons): Byte;
    function SystemByte: Byte;
    function MainRead(aAddr: Word): Byte;
    procedure MainWrite(aAddr: Word; aValue: Byte);
    function AudioRead(aAddr: Word): Byte;
    procedure AudioWrite(aAddr: Word; aValue: Byte);
    function McuPortIn(aPort: Integer): Byte;
    procedure McuPortOut(aPort: Integer; aValue: Byte);
    function NoPortIn(aPort: Word): Byte;
    procedure NoPortOut(aPort: Word; aValue: Byte);
    procedure SetControl(aValue: Byte);
  protected
    procedure SetAudioRate(aValue: Integer); override;
  public
    Main, Audio: TZ80;
    Mcu: TMcs51;

    MainRam: array[0..$0FFF] of Byte;       // E000-EFFF
    SpriteRam: array[0..$0FFF] of Byte;     // F000-FFFF
    SpriteBuffer: array[0..$0FFF] of Byte;  // DMA copy on a C806 write
    AudioRam: array[0..$07FF] of Byte;      // C000-C7FF
    FgRam: array[0..$07FF] of Byte;         // D000-D7FF : codes 000-3FF, attributes 400-7FF
    Scroll: array[0..4] of Byte;            // D800-D801 bg1 X, D802 bg1 Y, D803-D804 bg2 X
    Control: Byte;                          // C804 : b0-1 coin counters, b2-4 bank, b5 sound reset, b6 flip, b7 text
    Layers: Byte;                           // D806 : b4 bg1, b5 bg2, b6 sprites
    SoundLatch: Byte;
    CpuToMcu, McuToCpu, AudioToMcu, McuToAudio: Byte;
    McuP0, McuP2, McuP3: Byte;
    DswA, DswB: Byte;
    TileMaps: TBytes;                       // 'tilerom' : bg1 map 0000-7FFF, bg2 map 8000-FFFF

    Gfx: TGfxBM;

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
    property Line: Integer read FLine;
  end;

implementation

uses
  Arcade.Board.CapcomBM.Video;

{ TBoardCapcomBM }

class function TBoardCapcomBM.Family: string;
begin
  Result := 'capcombm';
end;

class function TBoardCapcomBM.Description: string;
begin
  Result := 'Capcom carte BM : Z80 @ 6 MHz + Z80 @ 3 MHz + i8751 (protection), 2 x YM2203, 2 decors en ROM';
end;

constructor TBoardCapcomBM.Create(aRoms: TRomSetData);
begin
  inherited Create(aRoms);
  FMainRom := aRoms.Region('maincpu');
  FAudioRom := aRoms.Region('audiocpu');
  TileMaps := aRoms.Region('tilerom');
  Gfx := DecodeGfxBM(aRoms);

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

  Mcu := TMcs51.Create(aRoms.Region('mcu'));
  Mcu.OnPortIn := McuPortIn;
  Mcu.OnPortOut := McuPortOut;

  // MAME routes : each SSG channel 0.15, FM 0.10
  FYm[0] := TYM2203.Create(CBM_YM_CLOCK);
  FYm[1] := TYM2203.Create(CBM_YM_CLOCK);
  FYm[0].FmGain := 0.10 / 0.15;
  FYm[1].FmGain := 0.10 / 0.15;

  DswA := CBM_DSWA_DEFAULT;
  DswB := CBM_DSWB_DEFAULT;
  Reset;
end;

destructor TBoardCapcomBM.Destroy;
begin
  Main.Free;
  Audio.Free;
  Mcu.Free;
  FYm[0].Free;
  FYm[1].Free;
  inherited;
end;

function TBoardCapcomBM.ScreenInfo: TScreenInfo;
begin
  Result.Width := CBM_WIDTH;
  Result.Height := CBM_HEIGHT;
  Result.Rotation := rot270;
  Result.FrameRate := CBM_FPS;
end;

procedure TBoardCapcomBM.SetServiceMode(aOn: Boolean);
begin
  if aOn then
    DswA := DswA and not $80
  else
    DswA := DswA or $80;
end;

procedure TBoardCapcomBM.SetDip(aIndex: Integer; aValue: Byte);
begin
  case aIndex of
    0: DswA := aValue;
    1: DswB := aValue;
  end;
end;

procedure TBoardCapcomBM.Reset;
begin
  FillChar(MainRam, SizeOf(MainRam), 0);
  FillChar(SpriteRam, SizeOf(SpriteRam), 0);
  FillChar(SpriteBuffer, SizeOf(SpriteBuffer), 0);
  FillChar(AudioRam, SizeOf(AudioRam), 0);
  FillChar(FgRam, SizeOf(FgRam), 0);
  FillChar(Scroll, SizeOf(Scroll), 0);
  Control := 0;   // MAME machine_reset : control_w(0), layer_w(0)
  Layers := 0;
  SoundLatch := 0;
  CpuToMcu := 0; McuToCpu := 0; AudioToMcu := 0; McuToAudio := 0;
  McuP0 := 0; McuP2 := 0; McuP3 := 0;
  Inputs := Default(TArcadeInputs);
  FMainDebt := 0;
  FAudioDebt := 0;
  FMcuDebt := 0;
  FFrame := 0;
  FLine := 0;
  Main.Reset;
  Audio.Reset;
  Mcu.Reset;
  FYm[0].Reset;
  FYm[1].Reset;
  FAudioPos := 0;
end;

function TBoardCapcomBM.PortByte(const aButtons: TArcadeButtons): Byte;
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

// SYSTEM : b0 start 1, b1 start 2, b3 VBLANK (active high), b6 coin 1, b7 coin 2
function TBoardCapcomBM.SystemByte: Byte;
begin
  Result := 0;
  if asStart1 in Inputs.System then Result := Result or $01;
  if asStart2 in Inputs.System then Result := Result or $02;
  if asCoin1 in Inputs.System then Result := Result or $40;
  if asCoin2 in Inputs.System then Result := Result or $80;
  Result := not Result and not $08;
  if (FLine >= 240) or (FLine < CBM_FIRST_VISIBLE) then
    Result := Result or $08;
end;

{ Memory maps }

function TBoardCapcomBM.NoPortIn(aPort: Word): Byte;
begin
  Result := $FF;
end;

procedure TBoardCapcomBM.NoPortOut(aPort: Word; aValue: Byte);
begin
end;

function TBoardCapcomBM.MainRead(aAddr: Word): Byte;
begin
  case aAddr of
    $0000..$7FFF: Result := FMainRom[aAddr];
    $8000..$BFFF: Result := FMainRom[$10000 + ((Control shr 2) and 7) * $4000 + (aAddr - $8000)];
    $C000: Result := SystemByte;
    $C001: Result := PortByte(Inputs.Players[0]);
    $C002: Result := PortByte(Inputs.Players[1]);
    $C003: Result := DswA;
    $C004: Result := DswB;
    $C007: Result := McuToCpu;
    $D000..$D7FF: Result := FgRam[aAddr - $D000];
    $D800..$D804: Result := Scroll[aAddr - $D800];
    $E000..$EFFF: Result := MainRam[aAddr - $E000];
    $F000..$FFFF: Result := SpriteRam[aAddr - $F000];
  else
    Result := 0;
  end;
end;

procedure TBoardCapcomBM.MainWrite(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $C800: SoundLatch := aValue;
    $C804: SetControl(aValue);
    $C806: Move(SpriteRam[0], SpriteBuffer[0], SizeOf(SpriteBuffer));   // 86S105 DMA request
    $C807: CpuToMcu := aValue;
    $D000..$D7FF: FgRam[aAddr - $D000] := aValue;
    $D800..$D804: Scroll[aAddr - $D800] := aValue;
    $D806: Layers := aValue;
    $E000..$EFFF: MainRam[aAddr - $E000] := aValue;
    $F000..$FFFF: SpriteRam[aAddr - $F000] := aValue;
  end;
end;

procedure TBoardCapcomBM.SetControl(aValue: Byte);
begin
  if (aValue and $20) <> 0 then
  begin
    Audio.Reset;     // held in reset while b5 is set
    FAudioDebt := 0;
  end;
  Control := aValue;
end;

function TBoardCapcomBM.AudioRead(aAddr: Word): Byte;
begin
  case aAddr of
    $0000..$7FFF: Result := FAudioRom[aAddr];
    $C000..$C7FF: Result := AudioRam[aAddr - $C000];
    $C800: Result := SoundLatch;
    $D800: Result := McuToAudio;
  else
    Result := 0;
  end;
end;

procedure TBoardCapcomBM.AudioWrite(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $C000..$C7FF: AudioRam[aAddr - $C000] := aValue;
    $D800: AudioToMcu := aValue;
    $E000, $E001: FYm[0].Write(aAddr and 1, aValue);
    $E002, $E003: FYm[1].Write(aAddr and 1, aValue);
  end;
end;

function TBoardCapcomBM.McuPortIn(aPort: Integer): Byte;
begin
  case aPort of
    0: Result := CpuToMcu;
    1: Result := Byte(FLine);       // screen vpos
    2: Result := AudioToMcu;
  else
    Result := $FF;
  end;
end;

procedure TBoardCapcomBM.McuPortOut(aPort: Integer; aValue: Byte);
begin
  case aPort of
    0: McuP0 := aValue;
    2: McuP2 := aValue;
    3:
      begin
        // write strobe : falling edge of P3.6 latches P0 for the main CPU, P2 for the sound CPU
        if ((McuP3 and $40) <> 0) and ((aValue and $40) = 0) then
        begin
          McuToCpu := McuP0;
          McuToAudio := McuP2;
        end;
        McuP3 := aValue;
      end;
  end;
end;

{ Frame }

procedure TBoardCapcomBM.RunFrame;
var
  lSamples, lLine: Integer;
begin
  FAudioCount := 0;
  for lLine := 0 to CBM_LINES - 1 do
  begin
    FLine := lLine;
    if (FLine = 144) or (FLine = 240) then
      Main.RaiseIrq($FF);
    if (FLine mod 64) = 32 then
      Audio.RaiseIrq($FF);
    if FLine = 240 then
      Mcu.SetInt1(True)
    else if FLine = CBM_FIRST_VISIBLE then
      Mcu.SetInt1(False);

    Inc(FMainDebt, CBM_MAIN_LINE_CYCLES);
    while FMainDebt > 0 do
      Dec(FMainDebt, Main.Step);
    if (Control and $20) = 0 then
    begin
      Inc(FAudioDebt, CBM_AUDIO_LINE_CYCLES);
      while FAudioDebt > 0 do
        Dec(FAudioDebt, Audio.Step);
    end;
    Inc(FMcuDebt, CBM_MCU_LINE_CYCLES);
    while FMcuDebt > 0 do
      Dec(FMcuDebt, Mcu.Step);

    if FAudioRate > 0 then
    begin
      FAudioPos := FAudioPos + FAudioRate / (CBM_FPS * CBM_LINES);
      lSamples := Trunc(FAudioPos);
      FAudioPos := FAudioPos - lSamples;
      RenderAudio(lSamples);
    end;

    if (FLine = CBM_LAST_VISIBLE) and RenderEnabled then
      RenderBM(Self, FScreen);
  end;
  FLine := 0;
  Inc(FFrame);
end;

procedure TBoardCapcomBM.SetAudioRate(aValue: Integer);
begin
  inherited;
  FAudioPos := 0;
end;

procedure TBoardCapcomBM.RenderAudio(aCount: Integer);
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

function TBoardCapcomBM.StateHash: UInt64;
var
  lHash: UInt64;
  r, c: Integer;
  lBuf: array[0..255] of Byte;

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
  Feed(CpuToMcu, 1); Feed(McuToCpu, 1); Feed(AudioToMcu, 1); Feed(McuToAudio, 1);
  for c := 0 to 1 do
  begin
    for r := 0 to 255 do
      lBuf[r] := FYm[c].Register(r);
    Feed(lBuf, SizeOf(lBuf));
  end;
  for r := 0 to 255 do
    lBuf[r] := Mcu.IRam(r);
  Feed(lBuf, SizeOf(lBuf));
  for r := 0 to 255 do
    lBuf[r] := Mcu.Sfr(r);
  Feed(lBuf, SizeOf(lBuf));
  Feed(Mcu.PC, 2);
  FeedCpu(Main);
  FeedCpu(Audio);
  Result := lHash;
end;

initialization
  RegisterBoard(TBoardCapcomBM);

end.
