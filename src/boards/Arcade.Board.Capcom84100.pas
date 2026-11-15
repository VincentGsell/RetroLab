unit Arcade.Board.Capcom84100;

///  BOARD - Capcom PCB 84100 (1984) : two-board stack 84100-01A (CPU/sound) + 84100-02A (video).
///  12 MHz crystal, 2 x Z80, 2 x AY-3-8910, one scrolling tile layer, sprites, text layer.
///  Cartridges known to run on it : see romsets/ (family id 'capcom84100').
///
///  What is soldered on it (the uses clause below lists the same chips) :
///    Z80A #1 @ 3 MHz        main CPU : the game              -> Arcade.Chip.Z80
///    Z80A #2 @ 3 MHz        sound CPU : music and effects    -> Arcade.Chip.Z80
///    2 x AY-3-8910 @ 1.5 MHz                                 -> Arcade.Chip.AY8910
///    video : scrolling 16x16 tile background, 32 sprites, 8x8 text layer, PROM palette
///                                                            -> Arcade.Board.Capcom84100.Video / .Gfx
///    irq PROM sb-1 : interrupt timing per scanline
///
///  Timing (MAME screen set_raw(12MHz/2, 384, 0, 256, 262, 16, 240)) :
///    pixel clock 6 MHz, 384 clocks per line -> 192 CPU T-states per scanline,
///    262 lines per frame -> 59.637 Hz. Visible : x 0..255, y 16..239. Monitor mounted ROT270.
///  Interrupts, from the irq PROM indexed by scanline :
///    bit 3 -> main CPU IRQ, RST 08h (line 109, sound commands) or RST 10h (line 240, vblank)
///    bit 2 -> sound CPU IRQ (4 per frame)
///  Reference : MAME driver src/mame/capcom/1942.cpp (MAME names its drivers after the first game).
///  Pure unit : no FMX.

interface

uses
  System.SysUtils,
  System.Classes,
  Arcade.Gfx,
  Arcade.RomSet,
  Arcade.Board,
  Arcade.Chip.Z80,
  Arcade.Chip.AY8910,
  Arcade.Board.Capcom84100.Gfx;

const
  C84100_LINE_CYCLES = 192;
  C84100_LINES = 262;
  C84100_FIRST_VISIBLE = 16;
  C84100_LAST_VISIBLE = 239;
  C84100_WIDTH = 256;
  C84100_HEIGHT = C84100_LAST_VISIBLE - C84100_FIRST_VISIBLE + 1;   // 224
  C84100_FPS = 6000000 / (384 * 262);                               // 59.637 Hz
  C84100_AY_CLOCK = 1500000;                                        // 12 MHz / 8

  // DIP defaults (MAME) : 1C/1C, upright, 20K 80K 80K+, 3 lives / 1C/1C, normal, no flip, no freeze
  C84100_DSWA_DEFAULT = $F7;
  C84100_DSWB_DEFAULT = $FF;
  C84100_DSWB_SERVICE = $08;   // active low

type
  TAy8910Regs = record
    Latch: Byte;
    Regs: array[0..15] of Byte;
  end;

  /// Analysis hooks (code mapper, oracle) : nil in normal play, zero cost.
  TStepHook = procedure(aPC: Word) of object;
  TAccessHook = procedure(aAddr: Word; aValue: Byte; aWrite: Boolean) of object;

  TBoardCapcom84100 = class(TArcadeBoard)
  private
    FMainRom, FAudioRom, FIrqProm: TBytes;
    FMainDebt, FAudioDebt: Integer;
    FPsg: array[0..1] of TAy8910;
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
    procedure SetControl(aValue: Byte);
  protected
    procedure SetAudioRate(aValue: Integer); override;
  public
    Main, Audio: TZ80;
    /// Called before each main CPU instruction (PC = instruction about to run, or interrupted).
    OnMainStep: TStepHook;
    /// Called on each main CPU data access (opcode fetches included : filter with OnMainStep).
    OnMainAccess: TAccessHook;

    // Board state (public : the video and the oracle read it directly)
    MainRam: array[0..$0FFF] of Byte;     // E000-EFFF
    AudioRam: array[0..$07FF] of Byte;    // 4000-47FF (sound CPU)
    FgRam: array[0..$07FF] of Byte;       // D000-D7FF : codes 000-3FF, attributes 400-7FF
    BgRam: array[0..$03FF] of Byte;       // D800-DBFF : groups of 32 bytes, 16 codes + 16 attributes
    SpriteRam: array[0..$7F] of Byte;     // CC00-CC7F, 32 sprites x 4 bytes
    Scroll: array[0..1] of Byte;          // C802-C803
    PaletteBank: Byte;                    // C805
    RomBank: Byte;                        // C806
    Control: Byte;                        // C804 : b7 flip, b4 sound CPU reset, b0 coin counter
    SoundLatch: array[0..1] of Byte;      // C800-C801 -> sound CPU 6000-6001
    Ay: array[0..1] of TAy8910Regs;       // PSG registers as last written (part of the state hash)
    CoinCounter: Integer;
    DswA, DswB: Byte;

    Gfx: TGfx84100;

    class function Family: string; override;
    class function Description: string; override;
    constructor Create(aRoms: TRomSetData); override;
    destructor Destroy; override;
    procedure Reset; override;
    procedure RunFrame; override;
    function ScreenInfo: TScreenInfo; override;
    /// FNV-1a 64 over every RAM, latches, video registers and both CPUs' registers.
    function StateHash: UInt64; override;
    procedure SetServiceMode(aOn: Boolean); override;
    /// 0 = DSW A ($C003), 1 = DSW B ($C004)
    procedure SetDip(aIndex: Integer; aValue: Byte); override;
  end;

implementation

uses
  Arcade.Board.Capcom84100.Video;

{ TBoardCapcom84100 }

class function TBoardCapcom84100.Family: string;
begin
  Result := 'capcom84100';
end;

class function TBoardCapcom84100.Description: string;
begin
  Result := 'Capcom PCB 84100 : 2 x Z80 @ 3 MHz, 2 x AY-3-8910, tuiles + sprites + texte, ecran vertical';
end;

constructor TBoardCapcom84100.Create(aRoms: TRomSetData);
begin
  inherited Create(aRoms);
  FMainRom := aRoms.Region('maincpu');
  FAudioRom := aRoms.Region('audiocpu');
  FIrqProm := aRoms.Region('irqprom');
  Gfx := DecodeGfx84100(aRoms);

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

  FPsg[0] := TAy8910.Create(C84100_AY_CLOCK);
  FPsg[1] := TAy8910.Create(C84100_AY_CLOCK);

  DswA := C84100_DSWA_DEFAULT;
  DswB := C84100_DSWB_DEFAULT;
  Reset;
end;

destructor TBoardCapcom84100.Destroy;
begin
  Main.Free;
  Audio.Free;
  FPsg[0].Free;
  FPsg[1].Free;
  inherited;
end;

function TBoardCapcom84100.ScreenInfo: TScreenInfo;
begin
  Result.Width := C84100_WIDTH;
  Result.Height := C84100_HEIGHT;
  Result.Rotation := rot270;
  Result.FrameRate := C84100_FPS;
end;

procedure TBoardCapcom84100.SetServiceMode(aOn: Boolean);
begin
  if aOn then
    DswB := DswB and not C84100_DSWB_SERVICE
  else
    DswB := DswB or C84100_DSWB_SERVICE;
end;

procedure TBoardCapcom84100.SetDip(aIndex: Integer; aValue: Byte);
begin
  case aIndex of
    0: DswA := aValue;
    1: DswB := aValue;
  end;
end;

procedure TBoardCapcom84100.Reset;
begin
  // Power-on RAM content is undefined on the board : zero it, the oracle needs determinism.
  FillChar(MainRam, SizeOf(MainRam), 0);
  FillChar(AudioRam, SizeOf(AudioRam), 0);
  FillChar(FgRam, SizeOf(FgRam), 0);
  FillChar(BgRam, SizeOf(BgRam), 0);
  FillChar(SpriteRam, SizeOf(SpriteRam), 0);
  FillChar(Ay, SizeOf(Ay), 0);
  Scroll[0] := 0;
  Scroll[1] := 0;
  PaletteBank := 0;
  RomBank := 0;
  Control := 0;
  SoundLatch[0] := 0;
  SoundLatch[1] := 0;
  CoinCounter := 0;
  Inputs := Default(TArcadeInputs);
  FMainDebt := 0;
  FAudioDebt := 0;
  FFrame := 0;
  Main.Reset;
  Audio.Reset;
  FPsg[0].Reset;
  FPsg[1].Reset;
  FAudioPos := 0;
end;

{ Control panel -> the board's input ports (active low on the wire) }

// P1 / P2 : b0 right, b1 left, b2 down, b3 up, b4 fire, b5 loop
function TBoardCapcom84100.PortByte(const aButtons: TArcadeButtons): Byte;
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

// SYSTEM : b0 start 1, b1 start 2, b4 service, b6 coin 2, b7 coin 1
function TBoardCapcom84100.SystemByte: Byte;
begin
  Result := 0;
  if asStart1 in Inputs.System then Result := Result or $01;
  if asStart2 in Inputs.System then Result := Result or $02;
  if asService in Inputs.System then Result := Result or $10;
  if asCoin2 in Inputs.System then Result := Result or $40;
  if asCoin1 in Inputs.System then Result := Result or $80;
  Result := not Result;
end;

{ Memory maps }

function TBoardCapcom84100.NoPortIn(aPort: Word): Byte;
begin
  Result := $FF;
end;

procedure TBoardCapcom84100.NoPortOut(aPort: Word; aValue: Byte);
begin
end;

function TBoardCapcom84100.MainRead(aAddr: Word): Byte;
begin
  if Assigned(OnMainAccess) then
    OnMainAccess(aAddr, 0, False);
  case aAddr of
    $0000..$7FFF: Result := FMainRom[aAddr];
    $8000..$BFFF: Result := FMainRom[$10000 + RomBank * $4000 + (aAddr - $8000)];
    $C000: Result := SystemByte;
    $C001: Result := PortByte(Inputs.Players[0]);
    $C002: Result := PortByte(Inputs.Players[1]);
    $C003: Result := DswA;
    $C004: Result := DswB;
    $D000..$D7FF: Result := FgRam[aAddr - $D000];
    $D800..$DBFF: Result := BgRam[aAddr - $D800];
    $E000..$EFFF: Result := MainRam[aAddr - $E000];
  else
    Result := $FF;   // map.unmap_value_high() ; spriteram is write-only
  end;
end;

procedure TBoardCapcom84100.MainWrite(aAddr: Word; aValue: Byte);
begin
  if Assigned(OnMainAccess) then
    OnMainAccess(aAddr, aValue, True);
  case aAddr of
    $C800: SoundLatch[0] := aValue;
    $C801: SoundLatch[1] := aValue;
    $C802: Scroll[0] := aValue;
    $C803: Scroll[1] := aValue;
    $C804: SetControl(aValue);
    $C805: PaletteBank := aValue and 3;
    $C806: RomBank := aValue and 3;
    $CC00..$CC7F: SpriteRam[aAddr - $CC00] := aValue;
    $D000..$D7FF: FgRam[aAddr - $D000] := aValue;
    $D800..$DBFF: BgRam[aAddr - $D800] := aValue;
    $E000..$EFFF: MainRam[aAddr - $E000] := aValue;
  end;
end;

procedure TBoardCapcom84100.SetControl(aValue: Byte);
begin
  // b0 : coin counter (count rising edges)
  if ((aValue and 1) <> 0) and ((Control and 1) = 0) then
    Inc(CoinCounter);
  // b4 : sound CPU reset line, held while the bit is set
  if (aValue and $10) <> 0 then
  begin
    Audio.Reset;
    FAudioDebt := 0;
  end;
  Control := aValue;
end;

function TBoardCapcom84100.AudioRead(aAddr: Word): Byte;
begin
  case aAddr of
    $0000..$3FFF: Result := FAudioRom[aAddr];
    $4000..$47FF: Result := AudioRam[aAddr - $4000];
    $6000: Result := SoundLatch[0];
    $6001: Result := SoundLatch[1];
  else
    Result := 0;
  end;
end;

procedure TBoardCapcom84100.AudioWrite(aAddr: Word; aValue: Byte);
begin
  case aAddr of
    $4000..$47FF: AudioRam[aAddr - $4000] := aValue;
    $8000: begin Ay[0].Latch := aValue and $0F; FPsg[0].WriteAddress(aValue); end;
    $8001: begin Ay[0].Regs[Ay[0].Latch] := aValue; FPsg[0].WriteData(aValue); end;
    $C000: begin Ay[1].Latch := aValue and $0F; FPsg[1].WriteAddress(aValue); end;
    $C001: begin Ay[1].Regs[Ay[1].Latch] := aValue; FPsg[1].WriteData(aValue); end;
  end;
end;

{ Frame }

procedure TBoardCapcom84100.RunFrame;
var
  lLine: Integer;
  lIrq: Byte;
  lSamples: Integer;
begin
  FAudioCount := 0;
  for lLine := 0 to C84100_LINES - 1 do
  begin
    lIrq := FIrqProm[lLine and $FF];
    if (lIrq and 8) <> 0 then
      Main.RaiseIrq($C7 or ((lIrq shl 3) and $18));
    if ((lIrq and 4) <> 0) and ((Control and $10) = 0) then
      Audio.RaiseIrq($FF);

    Inc(FMainDebt, C84100_LINE_CYCLES);
    while FMainDebt > 0 do
    begin
      if Assigned(OnMainStep) then
        OnMainStep(Main.PC);
      Dec(FMainDebt, Main.Step);
    end;

    if (Control and $10) = 0 then
    begin
      Inc(FAudioDebt, C84100_LINE_CYCLES);
      while FAudioDebt > 0 do
        Dec(FAudioDebt, Audio.Step);
    end;

    // sound : the samples of this scanline, with the PSG registers as the sound CPU left them
    if FAudioRate > 0 then
    begin
      FAudioPos := FAudioPos + FAudioRate / (C84100_FPS * C84100_LINES);
      lSamples := Trunc(FAudioPos);
      FAudioPos := FAudioPos - lSamples;
      RenderAudio(lSamples);
    end;

    // the picture is complete once the last visible line has been scanned
    if (lLine = C84100_LAST_VISIBLE) and RenderEnabled then
      Render84100(Self, FScreen);
  end;
  Inc(FFrame);
end;

procedure TBoardCapcom84100.SetAudioRate(aValue: Integer);
begin
  inherited;
  FAudioPos := 0;
end;

procedure TBoardCapcom84100.RenderAudio(aCount: Integer);
var
  i: Integer;
begin
  if FAudioCount + aCount > Length(FAudioBuffer) then
    aCount := Length(FAudioBuffer) - FAudioCount;
  if aCount <= 0 then
    Exit;
  for i := FAudioCount to FAudioCount + aCount - 1 do
    FAudioBuffer[i] := 0;
  FPsg[0].Render(FAudioBuffer, FAudioCount, aCount, FAudioRate);
  FPsg[1].Render(FAudioBuffer, FAudioCount, aCount, FAudioRate);
  Inc(FAudioCount, aCount);
end;

function TBoardCapcom84100.StateHash: UInt64;
var
  lHash: UInt64;

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
  Feed(SpriteRam, SizeOf(SpriteRam));
  Feed(Scroll, SizeOf(Scroll));
  Feed(PaletteBank, 1);
  Feed(RomBank, 1);
  Feed(Control, 1);
  Feed(SoundLatch, SizeOf(SoundLatch));
  Feed(Ay, SizeOf(Ay));
  FeedCpu(Main);
  FeedCpu(Audio);
  Result := lHash;
end;

initialization
  RegisterBoard(TBoardCapcom84100);

end.
