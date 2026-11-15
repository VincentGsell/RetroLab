unit Arcade.Chip.AY8910;

///  General Instrument AY-3-8910 PSG : 3 square tone channels, 1 noise generator, 1 envelope.
///    tone  : f = clock / (16 * period), period 12 bits (R0-R5)
///    noise : 17-bit LFSR clocked at clock / (16 * period), period 5 bits (R6)
///    mixer : R7 (bits 0-2 tone off, bits 3-5 noise off, active low)
///    level : R8-R10 4 bits, bit 4 = follow the envelope
///    envelope : period 16 bits (R11-R12), f = clock / (256 * period), shape R13 (writing restarts)
///  The chip is stepped at clock/8 and box-filtered down to the output rate (no aliasing whine).
///  Pure unit, FPC compatible. Generic : the board decides the clock (1942 : 1.5 MHz).

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}
{$Q-}
{$R-}

interface

type
  TAy8910 = class
  private
    FRegs: array[0..15] of Byte;
    FLatch: Byte;
    FToneCount: array[0..2] of Integer;
    FToneOut: array[0..2] of Integer;
    FNoiseCount: Integer;
    FNoiseLfsr: Cardinal;
    FNoiseOut: Integer;
    FNoisePrescale: Integer;
    FEnvCount: Integer;
    FEnvStep: Integer;          // 0..31 within the current cycle
    FEnvHolding: Boolean;
    FEnvVolume: Integer;
    FTickRate: Double;          // chip ticks (clock/8) per second
    FPhase: Double;             // fractional ticks carried between Render calls
    procedure UpdateEnvelopeVolume;
    procedure Tick;
    function Level: Single;
  public
    constructor Create(aClock: Double);
    procedure Reset;
    procedure WriteAddress(aValue: Byte);
    procedure WriteData(aValue: Byte);
    procedure WriteReg(aReg, aValue: Byte);
    function ReadReg(aReg: Byte): Byte;
    /// Input clock change (YM2203 prescaler) : the chip keeps its state.
    procedure SetClock(aClock: Double);
    /// Appends aCount samples (mono, 0..~1) at aSampleRate to aBuffer[aOffset..].
    procedure Render(var aBuffer: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
  end;

implementation

var
  // ~3 dB per step, as measured on the chip ; 0 is silence
  CVolume: array[0..15] of Single;

procedure InitVolumes;
var
  i: Integer;
begin
  CVolume[0] := 0;
  for i := 1 to 15 do
    CVolume[i] := Exp((i - 15) * Ln(2) / 2);   // 1 / sqrt(2)^(15-i)
end;

{ TAy8910 }

constructor TAy8910.Create(aClock: Double);
begin
  inherited Create;
  FTickRate := aClock / 8;
  Reset;
end;

procedure TAy8910.Reset;
var
  i: Integer;
begin
  FillChar(FRegs, SizeOf(FRegs), 0);
  FLatch := 0;
  for i := 0 to 2 do
  begin
    FToneCount[i] := 0;
    FToneOut[i] := 0;
  end;
  FNoiseCount := 0;
  FNoiseLfsr := 1;
  FNoiseOut := 0;
  FNoisePrescale := 0;
  FEnvCount := 0;
  FEnvStep := 0;
  FEnvHolding := False;
  FPhase := 0;
  UpdateEnvelopeVolume;
end;

procedure TAy8910.WriteAddress(aValue: Byte);
begin
  FLatch := aValue and $0F;
end;

procedure TAy8910.WriteData(aValue: Byte);
begin
  WriteReg(FLatch, aValue);
end;

procedure TAy8910.WriteReg(aReg, aValue: Byte);
begin
  aReg := aReg and $0F;
  FRegs[aReg] := aValue;
  if aReg = 13 then
  begin
    FEnvStep := 0;
    FEnvCount := 0;
    FEnvHolding := False;
    UpdateEnvelopeVolume;
  end;
end;

function TAy8910.ReadReg(aReg: Byte): Byte;
begin
  Result := FRegs[aReg and $0F];
end;

procedure TAy8910.SetClock(aClock: Double);
begin
  FTickRate := aClock / 8;
end;

// Shape R13 : bit 3 CONTinue, bit 2 ATTack, bit 1 ALTernate, bit 0 HOLD.
// One cycle = 16 steps ; FEnvStep counts 0..31 to cover the alternate half.
procedure TAy8910.UpdateEnvelopeVolume;
var
  lShape: Byte;
  lAttack: Boolean;
  lStep: Integer;
begin
  lShape := FRegs[13] and $0F;
  lAttack := (lShape and 4) <> 0;
  if FEnvStep < 16 then
  begin
    lStep := FEnvStep;
    if lAttack then FEnvVolume := lStep else FEnvVolume := 15 - lStep;
    Exit;
  end;
  // after the first cycle
  if (lShape and 8) = 0 then
  begin
    FEnvVolume := 0;                       // shapes 0-7 : decay/attack once, then 0
    Exit;
  end;
  if (lShape and 1) <> 0 then
  begin
    // hold : stays at the last level, inverted if alternate
    if ((lShape and 2) <> 0) xor lAttack then FEnvVolume := 15 else FEnvVolume := 0;
    Exit;
  end;
  lStep := FEnvStep and 15;
  if (lShape and 2) <> 0 then
    lAttack := lAttack xor (((FEnvStep shr 4) and 1) <> 0);
  if lAttack then FEnvVolume := lStep else FEnvVolume := 15 - lStep;
end;

procedure TAy8910.Tick;
var
  i, lPeriod: Integer;
begin
  // tones : the output flips every 'period' ticks of clock/8 -> f = clock / (16 * period)
  for i := 0 to 2 do
  begin
    lPeriod := FRegs[i * 2] or ((FRegs[i * 2 + 1] and $0F) shl 8);
    if lPeriod = 0 then lPeriod := 1;
    Inc(FToneCount[i]);
    if FToneCount[i] >= lPeriod then
    begin
      FToneCount[i] := 0;
      FToneOut[i] := FToneOut[i] xor 1;
    end;
  end;

  // noise : clocked at half the tone rate
  FNoisePrescale := FNoisePrescale xor 1;
  if FNoisePrescale = 0 then
  begin
    lPeriod := FRegs[6] and $1F;
    if lPeriod = 0 then lPeriod := 1;
    Inc(FNoiseCount);
    if FNoiseCount >= lPeriod then
    begin
      FNoiseCount := 0;
      // 17-bit LFSR, taps 0 and 3
      FNoiseLfsr := (FNoiseLfsr shr 1) or (((FNoiseLfsr xor (FNoiseLfsr shr 3)) and 1) shl 16);
      FNoiseOut := FNoiseLfsr and 1;
    end;
  end;

  // envelope : one step every 'period' ticks of clock/128 = every 16*period ticks here
  lPeriod := FRegs[11] or (FRegs[12] shl 8);
  if lPeriod = 0 then lPeriod := 1;
  Inc(FEnvCount);
  if FEnvCount >= lPeriod * 2 then
  begin
    FEnvCount := 0;
    if not FEnvHolding then
    begin
      Inc(FEnvStep);
      if FEnvStep >= 32 then
        FEnvStep := 0;    // continuing shapes : 2 cycles = 1 full period of the alternate pattern
      if (FEnvStep >= 16) and (((FRegs[13] and 8) = 0) or ((FRegs[13] and 1) <> 0)) then
        FEnvHolding := True;
      UpdateEnvelopeVolume;
    end;
  end;
end;

function TAy8910.Level: Single;
var
  i, lVol: Integer;
  lTone, lNoise, lOn: Boolean;
begin
  Result := 0;
  for i := 0 to 2 do
  begin
    lTone := (FRegs[7] and (1 shl i)) <> 0;          // 1 = tone disabled -> output high
    lNoise := (FRegs[7] and (8 shl i)) <> 0;
    lOn := (lTone or (FToneOut[i] <> 0)) and (lNoise or (FNoiseOut <> 0));
    if not lOn then
      Continue;
    if (FRegs[8 + i] and $10) <> 0 then
      lVol := FEnvVolume
    else
      lVol := FRegs[8 + i] and $0F;
    Result := Result + CVolume[lVol];
  end;
end;

procedure TAy8910.Render(var aBuffer: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
var
  s, lTicks, t: Integer;
  lPerSample, lAcc: Double;
begin
  lPerSample := FTickRate / aSampleRate;
  for s := 0 to aCount - 1 do
  begin
    FPhase := FPhase + lPerSample;
    lTicks := Trunc(FPhase);
    FPhase := FPhase - lTicks;
    lAcc := 0;
    for t := 1 to lTicks do
    begin
      Tick;
      lAcc := lAcc + Level;
    end;
    if lTicks > 0 then
      aBuffer[aOffset + s] := aBuffer[aOffset + s] + lAcc / lTicks / 3
    else
      aBuffer[aOffset + s] := aBuffer[aOffset + s] + Level / 3;
  end;
end;

initialization
  InitVolumes;

end.
