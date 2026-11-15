unit Arcade.Chip.YM2151;

///  Yamaha YM2151 (OPM) : 8 FM channels x 4 operators, LFO (AM / PM, 4 waveforms), noise on
///  channel 8, 2 timers, stereo output through a YM3012 DAC.
///
///  Model follows ymfm (MAME's Yamaha FM core, BSD-3), as Arcade.Chip.YM2203 does :
///    phase    : key code + key fraction -> phase step table (David Viens' chip data),
///               detune 1 and 2, multiple, LFO PM
///    envelope : 10-bit attenuation, ADSR, clocked every 3 FM samples, ymfm increment table
///    output   : log-sin + attenuation -> exp table, 14-bit per channel, YM3012 10.3 truncation
///  FM sample rate = clock / 64 (3.58 MHz -> 55.9 kHz, 4 MHz -> 62.5 kHz).
///  Pure unit, FPC compatible.

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}
{$Q-}
{$R-}

interface

type
  TOpmOperator = record
    Phase: Cardinal;          // 10.10 accumulator
    Attenuation: Integer;     // 0 (loud) .. $3FF (silent)
    State: Integer;
    KeyOn: Boolean;
  end;

  TOpmChannel = record
    Ops: array[0..3] of TOpmOperator;   // operators 1..4 in algorithm order (M1, C1, M2, C2)
    Feedback: array[0..1] of Integer;
  end;

  TYM2151PortWrite = procedure(aValue: Byte) of object;

  TYM2151 = class
  private
    FClock: Double;
    FAddress: Byte;
    FRegs: array[0..$FF] of Byte;
    FChannels: array[0..7] of TOpmChannel;
    FEnvCounter: Cardinal;
    FTimerACount, FTimerBCount, FTimerBSub: Integer;
    FStatus: Byte;
    FLfoCounter: Cardinal;
    FLfoAm: Integer;
    FLfoPm: Integer;
    FNoiseLfsr: Cardinal;
    FNoiseCounter: Cardinal;
    FNoiseState: Cardinal;
    FLfoNoise: array[0..255] of SmallInt;
    FFmPos: Double;
    FFmPrevL, FFmCurL, FFmPrevR, FFmCurR: Integer;
    function OpOffset(aChannel, aOp: Integer): Integer;
    function BlockFreq(aChannel: Integer): Cardinal;
    function EffectiveRate(aRaw, aKsr: Integer): Integer;
    function PhaseStep(aChannel, aOp: Integer): Cardinal;
    procedure ClockEnvelope(aChannel, aOp: Integer; aEnvCounter: Cardinal);
    function EnvAttenuation(aChannel, aOp, aAmOffset: Integer): Integer;
    function OperatorVolume(aChannel, aOp: Integer; aModulation, aAmOffset: Integer): Integer;
    function NoiseVolume(aChannel, aAmOffset: Integer): Integer;
    procedure KeyOperator(aChannel, aOp: Integer; aOn: Boolean);
    procedure ClockTimers;
    procedure ClockNoiseAndLfo;
    procedure FmSample(out aLeft, aRight: Integer);
    function GetFmRate: Double;
  public
    /// Board mixing gain (MAME add_route), applied to both outputs. Default 1.
    FmGain: Single;
    /// CT1 / CT2 output pins (register $1B bits 6-7) : some boards use them as bank lines.
    OnPortWrite: TYM2151PortWrite;
    constructor Create(aClock: Double);
    procedure Reset;
    /// Port 0 = address, port 1 = data (A0 line).
    procedure Write(aPort: Integer; aValue: Byte);
    /// Port 1 = status (b0 timer A, b1 timer B, b7 busy = 0).
    function Read(aPort: Integer): Byte;
    procedure WriteReg(aReg, aValue: Byte);
    /// Adds aCount stereo frames at aSampleRate into aLeft / aRight (16-bit range / 32768).
    procedure RenderStereo(var aLeft, aRight: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
    /// Adds aCount mono samples ((left + right) / 2).
    procedure Render(var aBuffer: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
    /// True while a timer flag is raised with its IRQ enabled (the chip's /IRQ pin).
    function IrqActive: Boolean;
    function Register(aIndex: Byte): Byte;
    property FmRate: Double read GetFmRate;
  end;

implementation

uses
  Math;

const
  EG_ATTACK = 0;
  EG_DECAY = 1;
  EG_SUSTAIN = 2;
  EG_RELEASE = 3;
  EG_QUIET = $380;

  // register offset of operators 1..4 inside a channel : M1, C1, M2, C2
  COpOfs: array[0..3] of Integer = (0, 16, 8, 24);

  // ymfm s_detune_adjustment[keycode][detune & 3]
  CDetune: array[0..31, 0..3] of Byte = (
    (0, 0, 1, 2), (0, 0, 1, 2), (0, 0, 1, 2), (0, 0, 1, 2),
    (0, 1, 2, 2), (0, 1, 2, 3), (0, 1, 2, 3), (0, 1, 2, 3),
    (0, 1, 2, 4), (0, 1, 3, 4), (0, 1, 3, 4), (0, 1, 3, 5),
    (0, 2, 4, 5), (0, 2, 4, 6), (0, 2, 4, 6), (0, 2, 5, 7),
    (0, 2, 5, 8), (0, 3, 6, 8), (0, 3, 6, 9), (0, 3, 7, 10),
    (0, 4, 8, 11), (0, 4, 8, 12), (0, 4, 9, 13), (0, 5, 10, 14),
    (0, 5, 11, 16), (0, 6, 12, 17), (0, 6, 13, 19), (0, 7, 14, 20),
    (0, 8, 16, 22), (0, 8, 16, 22), (0, 8, 16, 22), (0, 8, 16, 22));

  // detune 2 : 0, 600, 781, 950 cents in 1/64ths of a semitone step
  CDetune2: array[0..3] of Integer = (0, (600 * 64 + 50) div 100, (781 * 64 + 50) div 100, (950 * 64 + 50) div 100);

  CIncrement: array[0..63] of Cardinal = (
    $00000000, $00000000, $10101010, $10101010,
    $10101010, $10101010, $11101110, $11101110,
    $10101010, $10111010, $11101110, $11111110,
    $10101010, $10111010, $11101110, $11111110,
    $10101010, $10111010, $11101110, $11111110,
    $10101010, $10111010, $11101110, $11111110,
    $10101010, $10111010, $11101110, $11111110,
    $10101010, $10111010, $11101110, $11111110,
    $10101010, $10111010, $11101110, $11111110,
    $10101010, $10111010, $11101110, $11111110,
    $10101010, $10111010, $11101110, $11111110,
    $10101010, $10111010, $11101110, $11111110,
    $11111111, $21112111, $21212121, $22212221,
    $22222222, $42224222, $42424242, $44424442,
    $44444444, $84448444, $84848484, $88848884,
    $88888888, $88888888, $88888888, $88888888);

  CAlgorithms: array[0..7] of Word = (
    1 or (2 shl 1) or (3 shl 4),
    0 or (5 shl 1) or (3 shl 4),
    0 or (2 shl 1) or (6 shl 4),
    1 or (0 shl 1) or (7 shl 4),
    1 or (0 shl 1) or (3 shl 4) or (1 shl 8),
    1 or (1 shl 1) or (1 shl 4) or (1 shl 8) or (1 shl 9),
    1 or (0 shl 1) or (0 shl 4) or (1 shl 8) or (1 shl 9),
    0 or (0 shl 1) or (0 shl 4) or (1 shl 7) or (1 shl 8) or (1 shl 9));

  // key code + fraction -> phase step, octave 7 (ymfm s_phase_step, from chip analysis)
  CPhaseStep: array[0..767] of Cardinal = (
    41568, 41600, 41632, 41664, 41696, 41728, 41760, 41792, 41856, 41888, 41920, 41952, 42016, 42048, 42080, 42112,
    42176, 42208, 42240, 42272, 42304, 42336, 42368, 42400, 42464, 42496, 42528, 42560, 42624, 42656, 42688, 42720,
    42784, 42816, 42848, 42880, 42912, 42944, 42976, 43008, 43072, 43104, 43136, 43168, 43232, 43264, 43296, 43328,
    43392, 43424, 43456, 43488, 43552, 43584, 43616, 43648, 43712, 43744, 43776, 43808, 43872, 43904, 43936, 43968,
    44032, 44064, 44096, 44128, 44192, 44224, 44256, 44288, 44352, 44384, 44416, 44448, 44512, 44544, 44576, 44608,
    44672, 44704, 44736, 44768, 44832, 44864, 44896, 44928, 44992, 45024, 45056, 45088, 45152, 45184, 45216, 45248,
    45312, 45344, 45376, 45408, 45472, 45504, 45536, 45568, 45632, 45664, 45728, 45760, 45792, 45824, 45888, 45920,
    45984, 46016, 46048, 46080, 46144, 46176, 46208, 46240, 46304, 46336, 46368, 46400, 46464, 46496, 46528, 46560,
    46656, 46688, 46720, 46752, 46816, 46848, 46880, 46912, 46976, 47008, 47072, 47104, 47136, 47168, 47232, 47264,
    47328, 47360, 47392, 47424, 47488, 47520, 47552, 47584, 47648, 47680, 47744, 47776, 47808, 47840, 47904, 47936,
    48032, 48064, 48096, 48128, 48192, 48224, 48288, 48320, 48384, 48416, 48448, 48480, 48544, 48576, 48640, 48672,
    48736, 48768, 48800, 48832, 48896, 48928, 48992, 49024, 49088, 49120, 49152, 49184, 49248, 49280, 49344, 49376,
    49440, 49472, 49504, 49536, 49600, 49632, 49696, 49728, 49792, 49824, 49856, 49888, 49952, 49984, 50048, 50080,
    50144, 50176, 50208, 50240, 50304, 50336, 50400, 50432, 50496, 50528, 50560, 50592, 50656, 50688, 50752, 50784,
    50880, 50912, 50944, 50976, 51040, 51072, 51136, 51168, 51232, 51264, 51328, 51360, 51424, 51456, 51488, 51520,
    51616, 51648, 51680, 51712, 51776, 51808, 51872, 51904, 51968, 52000, 52064, 52096, 52160, 52192, 52224, 52256,
    52384, 52416, 52448, 52480, 52544, 52576, 52640, 52672, 52736, 52768, 52832, 52864, 52928, 52960, 52992, 53024,
    53120, 53152, 53216, 53248, 53312, 53344, 53408, 53440, 53504, 53536, 53600, 53632, 53696, 53728, 53792, 53824,
    53920, 53952, 54016, 54048, 54112, 54144, 54208, 54240, 54304, 54336, 54400, 54432, 54496, 54528, 54592, 54624,
    54688, 54720, 54784, 54816, 54880, 54912, 54976, 55008, 55072, 55104, 55168, 55200, 55264, 55296, 55360, 55392,
    55488, 55520, 55584, 55616, 55680, 55712, 55776, 55808, 55872, 55936, 55968, 56032, 56064, 56128, 56160, 56224,
    56288, 56320, 56384, 56416, 56480, 56512, 56576, 56608, 56672, 56736, 56768, 56832, 56864, 56928, 56960, 57024,
    57120, 57152, 57216, 57248, 57312, 57376, 57408, 57472, 57536, 57568, 57632, 57664, 57728, 57792, 57824, 57888,
    57952, 57984, 58048, 58080, 58144, 58208, 58240, 58304, 58368, 58400, 58464, 58496, 58560, 58624, 58656, 58720,
    58784, 58816, 58880, 58912, 58976, 59040, 59072, 59136, 59200, 59232, 59296, 59328, 59392, 59456, 59488, 59552,
    59648, 59680, 59744, 59776, 59840, 59904, 59936, 60000, 60064, 60128, 60160, 60224, 60288, 60320, 60384, 60416,
    60512, 60544, 60608, 60640, 60704, 60768, 60800, 60864, 60928, 60992, 61024, 61088, 61152, 61184, 61248, 61280,
    61376, 61408, 61472, 61536, 61600, 61632, 61696, 61760, 61824, 61856, 61920, 61984, 62048, 62080, 62144, 62208,
    62272, 62304, 62368, 62432, 62496, 62528, 62592, 62656, 62720, 62752, 62816, 62880, 62944, 62976, 63040, 63104,
    63200, 63232, 63296, 63360, 63424, 63456, 63520, 63584, 63648, 63680, 63744, 63808, 63872, 63904, 63968, 64032,
    64096, 64128, 64192, 64256, 64320, 64352, 64416, 64480, 64544, 64608, 64672, 64704, 64768, 64832, 64896, 64928,
    65024, 65056, 65120, 65184, 65248, 65312, 65376, 65408, 65504, 65536, 65600, 65664, 65728, 65792, 65856, 65888,
    65984, 66016, 66080, 66144, 66208, 66272, 66336, 66368, 66464, 66496, 66560, 66624, 66688, 66752, 66816, 66848,
    66944, 66976, 67040, 67104, 67168, 67232, 67296, 67328, 67424, 67456, 67520, 67584, 67648, 67712, 67776, 67808,
    67904, 67936, 68000, 68064, 68128, 68192, 68256, 68288, 68384, 68448, 68512, 68544, 68640, 68672, 68736, 68800,
    68896, 68928, 68992, 69056, 69120, 69184, 69248, 69280, 69376, 69440, 69504, 69536, 69632, 69664, 69728, 69792,
    69920, 69952, 70016, 70080, 70144, 70208, 70272, 70304, 70400, 70464, 70528, 70560, 70656, 70688, 70752, 70816,
    70912, 70976, 71040, 71104, 71136, 71232, 71264, 71360, 71424, 71488, 71552, 71616, 71648, 71744, 71776, 71872,
    71968, 72032, 72096, 72160, 72192, 72288, 72320, 72416, 72480, 72544, 72608, 72672, 72704, 72800, 72832, 72928,
    72992, 73056, 73120, 73184, 73216, 73312, 73344, 73440, 73504, 73568, 73632, 73696, 73728, 73824, 73856, 73952,
    74080, 74144, 74208, 74272, 74304, 74400, 74432, 74528, 74592, 74656, 74720, 74784, 74816, 74912, 74944, 75040,
    75136, 75200, 75264, 75328, 75360, 75456, 75488, 75584, 75648, 75712, 75776, 75840, 75872, 75968, 76000, 76096,
    76224, 76288, 76352, 76416, 76448, 76544, 76576, 76672, 76736, 76800, 76864, 76928, 77024, 77120, 77152, 77248,
    77344, 77408, 77472, 77536, 77568, 77664, 77696, 77792, 77856, 77920, 77984, 78048, 78144, 78240, 78272, 78368,
    78464, 78528, 78592, 78656, 78688, 78784, 78816, 78912, 78976, 79040, 79104, 79168, 79264, 79360, 79392, 79488,
    79616, 79680, 79744, 79808, 79840, 79936, 79968, 80064, 80128, 80192, 80256, 80320, 80416, 80512, 80544, 80640,
    80768, 80832, 80896, 80960, 80992, 81088, 81120, 81216, 81280, 81344, 81408, 81472, 81568, 81664, 81696, 81792,
    81952, 82016, 82080, 82144, 82176, 82272, 82304, 82400, 82464, 82528, 82592, 82656, 82752, 82848, 82880, 82976);

var
  SinTable: array[0..255] of Word;
  PowTable: array[0..255] of Word;

procedure InitTables;
var
  i: Integer;
begin
  for i := 0 to 255 do
  begin
    SinTable[i] := Round(-Log2(Sin((2 * i + 1) * Pi / 1024)) * 256);
    PowTable[i] := Round(Power(2, (255 - i) / 256) * 1024) - 1024;
  end;
end;

function Sar(aValue, aShift: Integer): Integer; inline;
begin
  if aValue >= 0 then
    Result := aValue shr aShift
  else
    Result := -((-aValue - 1) shr aShift) - 1;
end;

function Clamp(aValue, aMin, aMax: Integer): Integer; inline;
begin
  if aValue < aMin then
    Result := aMin
  else if aValue > aMax then
    Result := aMax
  else
    Result := aValue;
end;

/// YM3012 DAC : 10-bit mantissa + 3-bit exponent, low bits lost on large values.
function RoundTripFp(aValue: Integer): Integer;
var
  lScan, lExp, lBits: Integer;
begin
  if aValue < -32768 then
    Exit(-32768);
  if aValue > 32767 then
    Exit(32767);
  if aValue < 0 then
    lScan := not aValue
  else
    lScan := aValue;
  // exponent = number of significant bits above bit 8, in 1..7
  lBits := 0;
  while (lScan shr lBits) > 0 do
    Inc(lBits);
  lExp := lBits - 8;
  if lExp < 1 then
    lExp := 1;
  if lExp > 7 then
    lExp := 7;
  Dec(lExp);
  Result := aValue and not ((1 shl lExp) - 1);
end;

{ TYM2151 }

constructor TYM2151.Create(aClock: Double);
begin
  inherited Create;
  FClock := aClock;
  FmGain := 1;
  Reset;
end;

procedure TYM2151.Reset;
var
  c, o: Integer;
begin
  FillChar(FRegs, SizeOf(FRegs), 0);
  for c := $20 to $27 do
    FRegs[c] := $C0;
  for c := 0 to 7 do
  begin
    FChannels[c] := Default(TOpmChannel);
    for o := 0 to 3 do
    begin
      FChannels[c].Ops[o].Attenuation := $3FF;
      FChannels[c].Ops[o].State := EG_RELEASE;
    end;
  end;
  FAddress := 0;
  FEnvCounter := 0;
  FTimerACount := 0;
  FTimerBCount := 0;
  FTimerBSub := 0;
  FStatus := 0;
  FLfoCounter := 0;
  FLfoAm := 0;
  FLfoPm := 0;
  FNoiseLfsr := 1;
  FNoiseCounter := 0;
  FNoiseState := 0;
  FillChar(FLfoNoise, SizeOf(FLfoNoise), 0);
  FFmPos := 0;
  FFmPrevL := 0;
  FFmCurL := 0;
  FFmPrevR := 0;
  FFmCurR := 0;
end;

function TYM2151.GetFmRate: Double;
begin
  Result := FClock / 64;
end;

function TYM2151.Register(aIndex: Byte): Byte;
begin
  Result := FRegs[aIndex];
end;

procedure TYM2151.Write(aPort: Integer; aValue: Byte);
begin
  if (aPort and 1) = 0 then
    FAddress := aValue
  else
    WriteReg(FAddress, aValue);
end;

function TYM2151.Read(aPort: Integer): Byte;
begin
  if (aPort and 1) <> 0 then
    Result := FStatus and 3
  else
    Result := $FF;
end;

function TYM2151.IrqActive: Boolean;
begin
  Result := (((FStatus and 1) <> 0) and ((FRegs[$14] and 4) <> 0))
         or (((FStatus and 2) <> 0) and ((FRegs[$14] and 8) <> 0));
end;

function TYM2151.OpOffset(aChannel, aOp: Integer): Integer;
begin
  Result := COpOfs[aOp] + aChannel;
end;

/// block(3) : note code(4) : key fraction(6)
function TYM2151.BlockFreq(aChannel: Integer): Cardinal;
begin
  Result := (Cardinal(FRegs[$28 + aChannel] and $7F) shl 6) or (FRegs[$30 + aChannel] shr 2);
end;

procedure TYM2151.WriteReg(aReg, aValue: Byte);
var
  c, o: Integer;
begin
  if aReg = $19 then
    FRegs[$19 + (aValue shr 7)] := aValue
  else if aReg <> $1A then
    FRegs[aReg] := aValue;
  case aReg of
    $08:
      begin
        c := aValue and 7;
        for o := 0 to 3 do
          KeyOperator(c, o, (aValue and ($08 shl o)) <> 0);
      end;
    $14:
      begin
        if (aValue and $10) <> 0 then FStatus := FStatus and not 1;
        if (aValue and $20) <> 0 then FStatus := FStatus and not 2;
      end;
    $1B:
      if Assigned(OnPortWrite) then
        OnPortWrite(aValue shr 6);
  end;
end;

function TYM2151.EffectiveRate(aRaw, aKsr: Integer): Integer;
begin
  if aRaw = 0 then
    Result := 0
  else
    Result := Min(aRaw + aKsr, 63);
end;

procedure TYM2151.KeyOperator(aChannel, aOp: Integer; aOn: Boolean);
var
  lOp: ^TOpmOperator;
  lOfs, lKeyCode: Integer;
begin
  lOp := @FChannels[aChannel].Ops[aOp];
  if aOn and not lOp.KeyOn then
  begin
    lOp.Phase := 0;
    lOp.State := EG_ATTACK;
    lOfs := OpOffset(aChannel, aOp);
    lKeyCode := (BlockFreq(aChannel) shr 8) and $1F;
    if EffectiveRate((FRegs[$80 + lOfs] and $1F) * 2, lKeyCode shr ((FRegs[$80 + lOfs] shr 6) xor 3)) >= 62 then
      lOp.Attenuation := 0;
  end
  else if not aOn and lOp.KeyOn then
    lOp.State := EG_RELEASE;
  lOp.KeyOn := aOn;
end;

function TYM2151.PhaseStep(aChannel, aOp: Integer): Cardinal;
var
  lOfs, lDelta, lPmSens, lEff, lDetune, lMul: Integer;
  lBlockFreq, lBlock, lKeyCode, lStep: Cardinal;
begin
  lOfs := OpOffset(aChannel, aOp);
  lBlockFreq := BlockFreq(aChannel);
  lDelta := CDetune2[FRegs[$C0 + lOfs] shr 6];
  lPmSens := (FRegs[$38 + aChannel] shr 4) and 7;
  if lPmSens <> 0 then
  begin
    if lPmSens < 6 then
      Inc(lDelta, Sar(FLfoPm, 6 - lPmSens))
    else
      Inc(lDelta, FLfoPm shl (lPmSens - 5));
  end;
  // key code -> phase step
  lBlock := (lBlockFreq shr 10) and 7;
  lEff := Integer(((lBlockFreq shr 6) and $F) - ((lBlockFreq shr 8) and 3));
  lEff := (lEff shl 6) or Integer(lBlockFreq and $3F);
  Inc(lEff, lDelta);
  lStep := 0;
  if (lEff < 0) or (lEff >= 768) then
  begin
    if lEff < 0 then
    begin
      Inc(lEff, 768);
      if lBlock = 0 then
        lStep := CPhaseStep[0] shr 7
      else
        Dec(lBlock);
    end
    else
    begin
      Dec(lEff, 768);
      if lEff >= 768 then
      begin
        Inc(lBlock);
        Dec(lEff, 768);
      end;
      if lBlock >= 7 then
        lStep := CPhaseStep[767]
      else
        Inc(lBlock);
    end;
  end;
  if lStep = 0 then
    lStep := CPhaseStep[lEff] shr (lBlock xor 7);
  // detune 1
  lKeyCode := (lBlockFreq shr 8) and $1F;
  lDetune := (FRegs[$40 + lOfs] shr 4) and 7;
  if (lDetune and 4) <> 0 then
    lStep := lStep - CDetune[lKeyCode, lDetune and 3]
  else
    lStep := lStep + CDetune[lKeyCode, lDetune and 3];
  lMul := FRegs[$40 + lOfs] and $0F;
  if lMul = 0 then lMul := 1 else lMul := lMul * 2;
  Result := (lStep * Cardinal(lMul)) shr 1;
end;

procedure TYM2151.ClockEnvelope(aChannel, aOp: Integer; aEnvCounter: Cardinal);
var
  lOp: ^TOpmOperator;
  lOfs, lKsr, lRate, lShift, lSustain, lBits, lInc: Integer;
  lCounter: Cardinal;
begin
  lOp := @FChannels[aChannel].Ops[aOp];
  lOfs := OpOffset(aChannel, aOp);
  lSustain := (FRegs[$E0 + lOfs] shr 4) and $0F;
  lSustain := (lSustain or ((lSustain + 1) and $10)) shl 5;

  if (lOp.State = EG_ATTACK) and (lOp.Attenuation = 0) then
    lOp.State := EG_DECAY;
  if (lOp.State = EG_DECAY) and (lOp.Attenuation >= lSustain) then
    lOp.State := EG_SUSTAIN;

  lKsr := Integer((BlockFreq(aChannel) shr 8) and $1F) shr ((FRegs[$80 + lOfs] shr 6) xor 3);
  case lOp.State of
    EG_ATTACK:  lRate := EffectiveRate((FRegs[$80 + lOfs] and $1F) * 2, lKsr);
    EG_DECAY:   lRate := EffectiveRate((FRegs[$A0 + lOfs] and $1F) * 2, lKsr);
    EG_SUSTAIN: lRate := EffectiveRate((FRegs[$C0 + lOfs] and $1F) * 2, lKsr);
  else
    lRate := EffectiveRate((FRegs[$E0 + lOfs] and $0F) * 4 + 2, lKsr);
  end;

  lShift := lRate shr 2;
  lCounter := aEnvCounter shl lShift;
  if (lCounter and $7FF) <> 0 then
    Exit;
  if lShift <= 11 then
    lBits := (lCounter shr 11) and 7
  else
    lBits := (lCounter shr lShift) and 7;
  lInc := (CIncrement[lRate] shr (4 * lBits)) and $0F;

  if lOp.State = EG_ATTACK then
  begin
    if lRate < 62 then
      lOp.Attenuation := lOp.Attenuation + Sar((not lOp.Attenuation) * lInc, 4);
  end
  else
  begin
    lOp.Attenuation := lOp.Attenuation + lInc;
    if lOp.Attenuation >= $400 then
      lOp.Attenuation := $3FF;
  end;
end;

function TYM2151.EnvAttenuation(aChannel, aOp, aAmOffset: Integer): Integer;
var
  lOfs: Integer;
begin
  lOfs := OpOffset(aChannel, aOp);
  Result := FChannels[aChannel].Ops[aOp].Attenuation;
  if (FRegs[$A0 + lOfs] and $80) <> 0 then
    Inc(Result, aAmOffset);
  Inc(Result, (FRegs[$60 + lOfs] and $7F) shl 3);
  if Result > $3FF then
    Result := $3FF;
end;

function TYM2151.OperatorVolume(aChannel, aOp: Integer; aModulation, aAmOffset: Integer): Integer;
var
  lIndex, lSin, lTotal: Integer;
begin
  if FChannels[aChannel].Ops[aOp].Attenuation > EG_QUIET then
    Exit(0);
  lIndex := (Integer(FChannels[aChannel].Ops[aOp].Phase shr 10) + aModulation) and $3FF;
  if (lIndex and $100) <> 0 then
    lSin := SinTable[(not lIndex) and $FF]
  else
    lSin := SinTable[lIndex and $FF];
  lTotal := lSin + (EnvAttenuation(aChannel, aOp, aAmOffset) shl 2);
  Result := ((PowTable[lTotal and $FF] or $400) shl 2) shr (lTotal shr 8);
  if (lIndex and $200) <> 0 then
    Result := -Result;
end;

function TYM2151.NoiseVolume(aChannel, aAmOffset: Integer): Integer;
begin
  Result := (EnvAttenuation(aChannel, 3, aAmOffset) xor $3FF) shl 1;
  if (FNoiseState and 1) <> 0 then
    Result := -Result;
end;

procedure TYM2151.ClockTimers;
var
  lValue: Integer;
begin
  if (FRegs[$14] and 1) <> 0 then
  begin
    Inc(FTimerACount);
    lValue := (FRegs[$10] shl 2) or (FRegs[$11] and 3);
    if FTimerACount >= 1024 - lValue then
    begin
      FTimerACount := 0;
      if (FRegs[$14] and 4) <> 0 then
        FStatus := FStatus or 1;
    end;
  end;
  if (FRegs[$14] and 2) <> 0 then
  begin
    Inc(FTimerBSub);
    if FTimerBSub >= 16 then
    begin
      FTimerBSub := 0;
      Inc(FTimerBCount);
      if FTimerBCount >= 256 - FRegs[$12] then
      begin
        FTimerBCount := 0;
        if (FRegs[$14] and 8) <> 0 then
          FStatus := FStatus or 2;
      end;
    end;
  end;
end;

procedure TYM2151.ClockNoiseAndLfo;
var
  lRep: Integer;
  lFreq, lRate, lLfo, lNoise: Cardinal;
  lAm, lPm: Integer;
begin
  lFreq := (FRegs[$0F] and $1F) xor $1F;
  for lRep := 0 to 1 do
  begin
    FNoiseLfsr := (FNoiseLfsr shl 1) or (((FNoiseLfsr shr 17) xor (FNoiseLfsr shr 14) xor 1) and 1);
    if FNoiseCounter >= lFreq then
    begin
      FNoiseCounter := 0;
      FNoiseState := (FNoiseLfsr shr 17) and 1;
    end
    else
      Inc(FNoiseCounter);
  end;
  lRate := FRegs[$18];
  FLfoCounter := FLfoCounter + (Cardinal($10 or (lRate and $F)) shl (lRate shr 4));
  if (FRegs[$01] and 2) <> 0 then
    FLfoCounter := 0;
  lLfo := (FLfoCounter shr 22) and $FF;
  lNoise := (FNoiseLfsr shr 17) and $FF;
  FLfoNoise[(lLfo + 1) and $FF] := SmallInt(lNoise or (lNoise shl 8));
  case FRegs[$1B] and 3 of
    0:
      begin
        lAm := lLfo xor $FF;
        lPm := ShortInt(lLfo);
      end;
    1:
      begin
        if (lLfo and $80) <> 0 then lAm := 0 else lAm := $FF;
        lPm := ShortInt(lAm xor $80);
      end;
    2:
      begin
        if (lLfo and $80) <> 0 then
          lAm := (lLfo shl 1) and $FF
        else
          lAm := ((lLfo xor $FF) shl 1) and $FF;
        if (lLfo and $40) <> 0 then
          lPm := ShortInt(lAm)
        else
          lPm := ShortInt((not lAm) and $FF);
      end;
  else
    lAm := FLfoNoise[lLfo] and $FF;
    lPm := ShortInt(FLfoNoise[lLfo] shr 8);
  end;
  FLfoAm := (lAm * (FRegs[$19] and $7F)) shr 7;
  FLfoPm := Sar(lPm * (FRegs[$1A] and $7F), 7);
end;

procedure TYM2151.FmSample(out aLeft, aRight: Integer);
var
  c, o, lAlgo, lFeedback, lMod, lResult, lAmSens, lAmOffset: Integer;
  lOut: array[0..7] of Integer;
  lCh: ^TOpmChannel;
  lClockEnv: Boolean;
begin
  ClockTimers;
  Inc(FEnvCounter);
  if (FEnvCounter and 3) = 3 then
    Inc(FEnvCounter);
  lClockEnv := (FEnvCounter and 3) = 0;
  ClockNoiseAndLfo;
  for c := 0 to 7 do
    for o := 0 to 3 do
    begin
      if lClockEnv then
        ClockEnvelope(c, o, FEnvCounter shr 2);
      FChannels[c].Ops[o].Phase := FChannels[c].Ops[o].Phase + PhaseStep(c, o);
    end;

  aLeft := 0;
  aRight := 0;
  for c := 0 to 7 do
  begin
    lCh := @FChannels[c];
    lAmSens := FRegs[$38 + c] and 3;
    if lAmSens = 0 then
      lAmOffset := 0
    else
      lAmOffset := FLfoAm shl (lAmSens - 1);

    lAlgo := CAlgorithms[FRegs[$20 + c] and 7];
    lFeedback := (FRegs[$20 + c] shr 3) and 7;
    if lFeedback <> 0 then
      lMod := Sar(lCh.Feedback[0] + lCh.Feedback[1], 10 - lFeedback)
    else
      lMod := 0;

    lOut[0] := 0;
    lOut[1] := OperatorVolume(c, 0, lMod, lAmOffset);
    lCh.Feedback[0] := lCh.Feedback[1];
    lCh.Feedback[1] := lOut[1];
    if (FRegs[$20 + c] and $C0) <> 0 then
    begin
      lOut[2] := OperatorVolume(c, 1, Sar(lOut[lAlgo and 1], 1), lAmOffset);
      lOut[5] := lOut[1] + lOut[2];
      lOut[3] := OperatorVolume(c, 2, Sar(lOut[(lAlgo shr 1) and 7], 1), lAmOffset);
      lOut[6] := lOut[1] + lOut[3];
      lOut[7] := lOut[2] + lOut[3];
      if ((FRegs[$0F] and $80) <> 0) and (c = 7) then
        lResult := NoiseVolume(c, lAmOffset)
      else
        lResult := OperatorVolume(c, 3, Sar(lOut[(lAlgo shr 4) and 7], 1), lAmOffset);
      if (lAlgo and $80) <> 0 then lResult := Clamp(lResult + lOut[1], -32768, 32767);
      if (lAlgo and $100) <> 0 then lResult := Clamp(lResult + lOut[2], -32768, 32767);
      if (lAlgo and $200) <> 0 then lResult := Clamp(lResult + lOut[3], -32768, 32767);
      if (FRegs[$20 + c] and $40) <> 0 then Inc(aLeft, lResult);
      if (FRegs[$20 + c] and $80) <> 0 then Inc(aRight, lResult);
    end;
  end;
  aLeft := RoundTripFp(aLeft);
  aRight := RoundTripFp(aRight);
end;

procedure TYM2151.RenderStereo(var aLeft, aRight: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
var
  s, lL, lR: Integer;
  lStep, lFrac, lGain: Double;
begin
  lStep := GetFmRate / aSampleRate;
  lGain := FmGain / 32768;
  for s := 0 to aCount - 1 do
  begin
    FFmPos := FFmPos + lStep;
    while FFmPos >= 1 do
    begin
      FFmPos := FFmPos - 1;
      FFmPrevL := FFmCurL;
      FFmPrevR := FFmCurR;
      FmSample(lL, lR);
      FFmCurL := lL;
      FFmCurR := lR;
    end;
    lFrac := FFmPos;
    aLeft[aOffset + s] := aLeft[aOffset + s] + (FFmPrevL + (FFmCurL - FFmPrevL) * lFrac) * lGain;
    aRight[aOffset + s] := aRight[aOffset + s] + (FFmPrevR + (FFmCurR - FFmPrevR) * lFrac) * lGain;
  end;
end;

procedure TYM2151.Render(var aBuffer: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
var
  s, lL, lR: Integer;
  lStep, lFrac, lGain: Double;
begin
  lStep := GetFmRate / aSampleRate;
  lGain := FmGain / 65536;
  for s := 0 to aCount - 1 do
  begin
    FFmPos := FFmPos + lStep;
    while FFmPos >= 1 do
    begin
      FFmPos := FFmPos - 1;
      FFmPrevL := FFmCurL;
      FFmPrevR := FFmCurR;
      FmSample(lL, lR);
      FFmCurL := lL;
      FFmCurR := lR;
    end;
    lFrac := FFmPos;
    aBuffer[aOffset + s] := aBuffer[aOffset + s]
      + ((FFmPrevL + FFmPrevR) + ((FFmCurL + FFmCurR) - (FFmPrevL + FFmPrevR)) * lFrac) * lGain;
  end;
end;

initialization
  InitTables;

end.
