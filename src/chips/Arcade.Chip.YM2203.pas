unit Arcade.Chip.YM2203;

///  Yamaha YM2203 (OPN) : 3 FM channels x 4 operators + an SSG (AY-3-8910 compatible) + 2 timers.
///
///  FM model follows ymfm (MAME's Yamaha FM core, BSD-3, built from die-level research) :
///    phase   : 20-bit accumulator, step = fnum << (block-1) + detune(keycode), x multiple
///    envelope: 10-bit attenuation, ADSR, clocked every 3 FM samples, ymfm increment table
///    output  : log-sin table (4.8) + attenuation -> exp table -> 13-bit magnitude + sign
///    algorithms : the 8 OPN operator graphs, operator 1 self-feedback
///  FM sample rate = clock / (prescaler * 12) ; default prescaler 6 -> 1.5 MHz / 72 = 20833 Hz.
///  The SSG runs at clock / 4 (default) and IS our TAy8910 (registers 00-0F).
///  Not implemented (unused by the Capcom boards targeted) : SSG-EG ($90-$9E), CSM mode.
///  Pure unit, FPC compatible.

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}
{$Q-}
{$R-}

interface

uses
  Arcade.Chip.AY8910;

type
  TYmOperator = record
    Phase: Cardinal;          // 20-bit accumulator
    Attenuation: Integer;     // 0 (loud) .. $3FF (silent)
    State: Integer;           // EG_ATTACK .. EG_RELEASE
    KeyOn: Boolean;
  end;

  TYmChannel = record
    Ops: array[0..3] of TYmOperator;   // operators 1..4 in algorithm order
    Feedback: array[0..1] of Integer;
    BlockFreq: Cardinal;               // block(3) : fnum(11)
  end;

  TYM2203 = class
  private
    FClock: Double;
    FAddress: Byte;
    FRegs: array[0..$FF] of Byte;
    FFreqLatch: Byte;           // $A4-$A6 upper bits, committed by $A0-$A2
    FMultiLatch: Byte;          // $AC-$AE, committed by $A8-$AA
    FMultiFreq: array[0..2] of Cardinal;
    FChannels: array[0..2] of TYmChannel;
    FEnvCounter: Cardinal;
    FFmPrescale: Integer;       // 6, 3 or 2
    FSsgPrescale: Integer;      // 4, 2 or 1
    FSsg: TAy8910;
    // timers
    FTimerACount, FTimerBCount, FTimerBSub: Integer;
    FStatus: Byte;
    // resampling FM -> output rate
    FFmPos: Double;
    FFmPrev, FFmCur: Integer;
    FSsgBuffer: TArray<Single>;

    function OpRegOffset(aChannel, aOp: Integer): Integer;
    function OpBlockFreq(aChannel, aOp: Integer): Cardinal;
    function KeyCode(aBlockFreq: Cardinal): Integer;
    function EffectiveRate(aRaw, aKeyCode, aOfs: Integer): Integer;
    function PhaseStep(aChannel, aOp: Integer): Cardinal;
    procedure ClockEnvelope(aChannel, aOp: Integer; aEnvCounter: Cardinal);
    function OperatorVolume(aChannel, aOp: Integer; aModulation: Integer): Integer;
    procedure KeyOperator(aChannel, aOp: Integer; aOn: Boolean);
    procedure ClockTimers;
    function FmSample: Integer;
    function GetFmRate: Double;
  public
    /// Board mixing (MAME add_route gains) : FM output and each SSG channel. Default 1 / 1.
    FmGain, SsgGain: Single;
    constructor Create(aClock: Double);
    destructor Destroy; override;
    procedure Reset;
    /// Port 0 = address, port 1 = data (as on the bus : A0 line).
    procedure Write(aPort: Integer; aValue: Byte);
    /// Port 0 = status (b0 timer A, b1 timer B, b7 busy = 0), port 1 = SSG register read.
    function Read(aPort: Integer): Byte;
    procedure WriteReg(aReg, aValue: Byte);
    /// Adds aCount mono samples at aSampleRate into aBuffer[aOffset..] (FM + SSG, ~ -1..+4).
    procedure Render(var aBuffer: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
    /// True while a timer flag is raised with its IRQ enabled (the chip's /IRQ pin).
    function IrqActive: Boolean;
    property FmRate: Double read GetFmRate;
    function Register(aIndex: Byte): Byte;
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

  // ymfm attenuation_increment : 8 nibbles per rate, indexed by 3 counter bits
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

  // operator graph : op2in(1) | op3in(3) << 1 | op4in(3) << 4 | op1out << 7 | op2out << 8 | op3out << 9
  CAlgorithms: array[0..7] of Word = (
    1 or (2 shl 1) or (3 shl 4),
    0 or (5 shl 1) or (3 shl 4),
    0 or (2 shl 1) or (6 shl 4),
    1 or (0 shl 1) or (7 shl 4),
    1 or (0 shl 1) or (3 shl 4) or (1 shl 8),
    1 or (1 shl 1) or (1 shl 4) or (1 shl 8) or (1 shl 9),
    1 or (0 shl 1) or (0 shl 4) or (1 shl 8) or (1 shl 9),
    0 or (0 shl 1) or (0 shl 4) or (1 shl 7) or (1 shl 8) or (1 shl 9));

var
  SinTable: array[0..255] of Word;     // -log2(sin) quarter wave, 4.8 fixed point
  PowTable: array[0..255] of Word;     // 2^-x mantissa, 10 bits

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

// arithmetic shift right (Delphi's shr is logical on negative values)
function Sar(aValue, aShift: Integer): Integer; inline;
begin
  if aValue >= 0 then
    Result := aValue shr aShift
  else
    Result := -((-aValue - 1) shr aShift) - 1;
end;

{ TYM2203 }

constructor TYM2203.Create(aClock: Double);
begin
  inherited Create;
  FClock := aClock;
  FmGain := 1;
  SsgGain := 1;
  FSsg := TAy8910.Create(aClock / 4);
  Reset;
end;

destructor TYM2203.Destroy;
begin
  FSsg.Free;
  inherited;
end;

procedure TYM2203.Reset;
var
  c, o: Integer;
begin
  FillChar(FRegs, SizeOf(FRegs), 0);
  for c := 0 to 2 do
  begin
    FChannels[c] := Default(TYmChannel);
    for o := 0 to 3 do
    begin
      FChannels[c].Ops[o].Attenuation := $3FF;
      FChannels[c].Ops[o].State := EG_RELEASE;
    end;
    FMultiFreq[c] := 0;
  end;
  FAddress := 0;
  FFreqLatch := 0;
  FMultiLatch := 0;
  FEnvCounter := 0;
  FFmPrescale := 6;
  FSsgPrescale := 4;
  FSsg.Reset;
  FSsg.SetClock(FClock / FSsgPrescale);
  FTimerACount := 0;
  FTimerBCount := 0;
  FTimerBSub := 0;
  FStatus := 0;
  FFmPos := 0;
  FFmPrev := 0;
  FFmCur := 0;
end;

function TYM2203.GetFmRate: Double;
begin
  Result := FClock / (FFmPrescale * 12);
end;

procedure TYM2203.Write(aPort: Integer; aValue: Byte);
begin
  if (aPort and 1) = 0 then
  begin
    FAddress := aValue;
    // prescaler commands are triggered by the address write alone
    case aValue of
      $2D: begin FFmPrescale := 6; FSsgPrescale := 4; FSsg.SetClock(FClock / 4); end;
      $2E: begin FFmPrescale := 3; FSsgPrescale := 2; FSsg.SetClock(FClock / 2); end;
      $2F: begin FFmPrescale := 2; FSsgPrescale := 1; FSsg.SetClock(FClock); end;
    end;
  end
  else
    WriteReg(FAddress, aValue);
end;

function TYM2203.Read(aPort: Integer): Byte;
begin
  if (aPort and 1) = 0 then
    Result := FStatus and 3
  else if FAddress < $10 then
    Result := FSsg.ReadReg(FAddress)
  else
    Result := 0;
end;

function TYM2203.Register(aIndex: Byte): Byte;
begin
  Result := FRegs[aIndex];
end;

function TYM2203.IrqActive: Boolean;
begin
  // $27 b2 : timer A IRQ enable, b3 : timer B IRQ enable
  Result := (((FStatus and 1) <> 0) and ((FRegs[$27] and 4) <> 0))
         or (((FStatus and 2) <> 0) and ((FRegs[$27] and 8) <> 0));
end;

// Operator register order inside a channel is S1, S3, S2, S4 : operators 1..4 -> +0, +8, +4, +12
function TYM2203.OpRegOffset(aChannel, aOp: Integer): Integer;
const
  COfs: array[0..3] of Integer = (0, 8, 4, 12);
begin
  Result := COfs[aOp] + aChannel;
end;

procedure TYM2203.KeyOperator(aChannel, aOp: Integer; aOn: Boolean);
var
  lOp: ^TYmOperator;
  lRate: Integer;
begin
  lOp := @FChannels[aChannel].Ops[aOp];
  if aOn and not lOp.KeyOn then
  begin
    lOp.Phase := 0;
    lOp.State := EG_ATTACK;
    lRate := EffectiveRate((FRegs[$50 + OpRegOffset(aChannel, aOp)] and $1F) * 2,
      KeyCode(OpBlockFreq(aChannel, aOp)), OpRegOffset(aChannel, aOp));
    if lRate >= 62 then
      lOp.Attenuation := 0;   // instant attack
  end
  else if not aOn and lOp.KeyOn then
    lOp.State := EG_RELEASE;
  lOp.KeyOn := aOn;
end;

procedure TYM2203.WriteReg(aReg, aValue: Byte);
var
  c, o: Integer;
begin
  if aReg < $10 then
  begin
    FSsg.WriteReg(aReg, aValue);
    Exit;
  end;
  FRegs[aReg] := aValue;
  case aReg of
    $27:
      begin
        // b4 / b5 : reset timer A / B flags ; b0 / b1 : load (start) timer A / B
        if (aValue and $10) <> 0 then FStatus := FStatus and not 1;
        if (aValue and $20) <> 0 then FStatus := FStatus and not 2;
      end;
    $28:
      begin
        c := aValue and 3;
        if c < 3 then
          for o := 0 to 3 do
            KeyOperator(c, o, (aValue and ($10 shl o)) <> 0);
      end;
    $A0..$A2:
      FChannels[aReg - $A0].BlockFreq := (Cardinal(FFreqLatch and $3F) shl 8) or aValue;
    $A4..$A6:
      FFreqLatch := aValue;
    $A8..$AA:
      FMultiFreq[aReg - $A8] := (Cardinal(FMultiLatch and $3F) shl 8) or aValue;
    $AC..$AE:
      FMultiLatch := aValue;
  end;
end;

// Channel 3 special mode ($27 b6-7 <> 0) : operators 1..3 get their own frequency.
// S1 <- A9/AD, S2 <- AA/AE, S3 <- A8/AC, S4 keeps the channel frequency.
function TYM2203.OpBlockFreq(aChannel, aOp: Integer): Cardinal;
begin
  Result := FChannels[aChannel].BlockFreq;
  if (aChannel = 2) and ((FRegs[$27] and $C0) <> 0) then
    case aOp of
      0: Result := FMultiFreq[1];
      1: Result := FMultiFreq[2];
      2: Result := FMultiFreq[0];
    end;
end;

// keycode = block << 2 | N4 << 1 | N3 (N4 = F11, N3 from F11..F8, table 0xFE80)
function TYM2203.KeyCode(aBlockFreq: Cardinal): Integer;
begin
  Result := Integer((aBlockFreq shr 10) and $0F) shl 1;
  Result := Result or Integer(($FE80 shr ((aBlockFreq shr 7) and $0F)) and 1);
end;

// raw rate (0..63) + key scaling ; 0 stays 0
function TYM2203.EffectiveRate(aRaw, aKeyCode, aOfs: Integer): Integer;
var
  lKs: Integer;
begin
  if aRaw = 0 then
    Exit(0);
  lKs := (FRegs[$50 + aOfs] shr 6) and 3;
  Result := Min(aRaw + (aKeyCode shr (lKs xor 3)), 63);
end;

function TYM2203.PhaseStep(aChannel, aOp: Integer): Cardinal;
var
  lOfs, lDetune, lMul: Integer;
  lBlockFreq, lFnum, lBlock: Cardinal;
  lStep: Integer;
begin
  lOfs := OpRegOffset(aChannel, aOp);
  lBlockFreq := OpBlockFreq(aChannel, aOp);
  lFnum := (lBlockFreq and $7FF) shl 1;
  lBlock := (lBlockFreq shr 11) and 7;
  lStep := Integer((lFnum shl lBlock) shr 2);
  lDetune := (FRegs[$30 + lOfs] shr 4) and 7;
  if (lDetune and 4) <> 0 then
    Dec(lStep, CDetune[KeyCode(lBlockFreq), lDetune and 3])
  else
    Inc(lStep, CDetune[KeyCode(lBlockFreq), lDetune and 3]);
  lStep := lStep and $1FFFF;
  lMul := FRegs[$30 + lOfs] and $0F;
  if lMul = 0 then lMul := 1 else lMul := lMul * 2;
  Result := Cardinal(lStep * lMul) shr 1;
end;

procedure TYM2203.ClockEnvelope(aChannel, aOp: Integer; aEnvCounter: Cardinal);
var
  lOp: ^TYmOperator;
  lOfs, lKeyCode, lRate, lShift, lSustain, lBits, lInc: Integer;
  lCounter: Cardinal;
begin
  lOp := @FChannels[aChannel].Ops[aOp];
  lOfs := OpRegOffset(aChannel, aOp);
  lSustain := (FRegs[$80 + lOfs] shr 4) and $0F;
  lSustain := (lSustain or ((lSustain + 1) and $10)) shl 5;

  if (lOp.State = EG_ATTACK) and (lOp.Attenuation = 0) then
    lOp.State := EG_DECAY;
  if (lOp.State = EG_DECAY) and (lOp.Attenuation >= lSustain) then
    lOp.State := EG_SUSTAIN;

  lKeyCode := KeyCode(OpBlockFreq(aChannel, aOp));
  case lOp.State of
    EG_ATTACK:  lRate := EffectiveRate((FRegs[$50 + lOfs] and $1F) * 2, lKeyCode, lOfs);
    EG_DECAY:   lRate := EffectiveRate((FRegs[$60 + lOfs] and $1F) * 2, lKeyCode, lOfs);
    EG_SUSTAIN: lRate := EffectiveRate((FRegs[$70 + lOfs] and $1F) * 2, lKeyCode, lOfs);
  else
    lRate := EffectiveRate((FRegs[$80 + lOfs] and $0F) * 4 + 2, lKeyCode, lOfs);
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

function TYM2203.OperatorVolume(aChannel, aOp: Integer; aModulation: Integer): Integer;
var
  lOp: ^TYmOperator;
  lIndex, lSin, lAtt, lTotal: Integer;
begin
  lOp := @FChannels[aChannel].Ops[aOp];
  if lOp.Attenuation > EG_QUIET then
    Exit(0);
  lIndex := (Integer(lOp.Phase shr 10) + aModulation) and $3FF;
  // quarter-wave table, mirrored ; second half negative
  if (lIndex and $100) <> 0 then
    lSin := SinTable[(not lIndex) and $FF]
  else
    lSin := SinTable[lIndex and $FF];
  // envelope + total level (7 bits, << 3), clamped, as 4.6 -> shifted to 4.8
  lAtt := lOp.Attenuation + ((FRegs[$40 + OpRegOffset(aChannel, aOp)] and $7F) shl 3);
  if lAtt > $3FF then lAtt := $3FF;
  lTotal := lSin + (lAtt shl 2);
  Result := ((PowTable[lTotal and $FF] or $400) shl 2) shr (lTotal shr 8);
  if (lIndex and $200) <> 0 then
    Result := -Result;
end;

procedure TYM2203.ClockTimers;
var
  lValue: Integer;
begin
  // timer A : 10 bits, one tick per FM sample ; timer B : 8 bits, one tick per 16 FM samples
  if (FRegs[$27] and 1) <> 0 then
  begin
    Inc(FTimerACount);
    lValue := (FRegs[$24] shl 2) or (FRegs[$25] and 3);
    if FTimerACount >= 1024 - lValue then
    begin
      FTimerACount := 0;
      if (FRegs[$27] and 4) <> 0 then
        FStatus := FStatus or 1;
    end;
  end;
  if (FRegs[$27] and 2) <> 0 then
  begin
    Inc(FTimerBSub);
    if FTimerBSub >= 16 then
    begin
      FTimerBSub := 0;
      Inc(FTimerBCount);
      if FTimerBCount >= 256 - FRegs[$26] then
      begin
        FTimerBCount := 0;
        if (FRegs[$27] and 8) <> 0 then
          FStatus := FStatus or 2;
      end;
    end;
  end;
end;

// One FM sample (all 3 channels), 16-bit range.
function TYM2203.FmSample: Integer;
var
  c, o, lAlgo, lFeedback, lMod, lResult: Integer;
  lOut: array[0..7] of Integer;
  lCh: ^TYmChannel;
  lClockEnv: Boolean;
begin
  ClockTimers;
  // envelope clock : every 3rd sample (low 2 bits count 0,1,2)
  Inc(FEnvCounter);
  if (FEnvCounter and 3) = 3 then
    Inc(FEnvCounter);
  lClockEnv := (FEnvCounter and 3) = 0;

  Result := 0;
  for c := 0 to 2 do
  begin
    lCh := @FChannels[c];
    if lClockEnv then
      for o := 0 to 3 do
        ClockEnvelope(c, o, FEnvCounter shr 2);

    lAlgo := CAlgorithms[FRegs[$B0 + c] and 7];
    lFeedback := (FRegs[$B0 + c] shr 3) and 7;
    if lFeedback <> 0 then
      lMod := Sar(lCh.Feedback[0] + lCh.Feedback[1], 10 - lFeedback)
    else
      lMod := 0;

    lOut[0] := 0;
    lOut[1] := OperatorVolume(c, 0, lMod);
    lCh.Feedback[0] := lCh.Feedback[1];
    lCh.Feedback[1] := lOut[1];
    lOut[2] := OperatorVolume(c, 1, Sar(lOut[lAlgo and 1], 1));
    lOut[5] := lOut[1] + lOut[2];
    lOut[3] := OperatorVolume(c, 2, Sar(lOut[(lAlgo shr 1) and 7], 1));
    lOut[6] := lOut[1] + lOut[3];
    lOut[7] := lOut[2] + lOut[3];
    lResult := OperatorVolume(c, 3, Sar(lOut[(lAlgo shr 4) and 7], 1));
    if (lAlgo and $80) <> 0 then Inc(lResult, lOut[1]);
    if (lAlgo and $100) <> 0 then Inc(lResult, lOut[2]);
    if (lAlgo and $200) <> 0 then Inc(lResult, lOut[3]);
    if lResult > 8191 then lResult := 8191 else if lResult < -8192 then lResult := -8192;
    Inc(Result, lResult);

    // advance the phases
    for o := 0 to 3 do
      lCh.Ops[o].Phase := (lCh.Ops[o].Phase + PhaseStep(c, o)) and $FFFFF;
  end;
end;

procedure TYM2203.Render(var aBuffer: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
var
  s: Integer;
  lStep, lFrac: Double;
begin
  // SSG part (unipolar sum of 3 channels / 3) -> scaled to the 3 channels as MAME mixes them
  if Length(FSsgBuffer) < aCount then
    SetLength(FSsgBuffer, aCount);
  for s := 0 to aCount - 1 do
    FSsgBuffer[s] := 0;
  FSsg.Render(FSsgBuffer, 0, aCount, aSampleRate);

  // FM part : native rate, linearly interpolated to the output rate
  lStep := GetFmRate / aSampleRate;
  for s := 0 to aCount - 1 do
  begin
    FFmPos := FFmPos + lStep;
    while FFmPos >= 1 do
    begin
      FFmPos := FFmPos - 1;
      FFmPrev := FFmCur;
      FFmCur := FmSample;
    end;
    lFrac := FFmPos;
    aBuffer[aOffset + s] := aBuffer[aOffset + s]
      + (FFmPrev + (FFmCur - FFmPrev) * lFrac) / 32768 * FmGain
      + FSsgBuffer[s] * 3 * SsgGain;
  end;
end;

initialization
  InitTables;

end.
