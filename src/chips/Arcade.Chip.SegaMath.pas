unit Arcade.Chip.SegaMath;

///  Sega arithmetic customs of the X / Y boards, one pair per 68000 :
///    315-5248 multiplier : two 16-bit registers, the signed 32-bit product read back in two words
///      word 0 / 1 : operands A, B ; word 2 / 3 : high / low word of A * B (signed)
///    315-5249 divider : 32-bit dividend, 16-bit divisor, triggered by a write with A4 set
///      words 0 / 1 : dividend high / low ; word 2 : divisor ; words 4 / 5 : results ; word 6 : flags
///      mode 0 (A3 low)  : signed, quotient clamped to 16 bits (flag $8000), remainder
///      mode 1 (A3 high) : unsigned, 32-bit quotient
///      divide by zero : flag $4000, the quotient is the dividend
///  Behaviour follows MAME segaic16_m.cpp (BSD-3). Pure unit, FPC compatible.

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}
{$Q-}
{$R-}

interface

type
  TSega315_5248 = class
  private
    FRegs: array[0..1] of Word;
  public
    procedure Reset;
    /// aOffset : word offset inside the chip (address shr 1).
    function Read(aOffset: Integer): Word;
    procedure Write(aOffset: Integer; aValue, aMask: Word);
  end;

  TSega315_5249 = class
  private
    FRegs: array[0..7] of Word;
    procedure Execute(aUnsigned: Boolean);
  public
    procedure Reset;
    function Read(aOffset: Integer): Word;
    procedure Write(aOffset: Integer; aValue, aMask: Word);
  end;

implementation

{ TSega315_5248 }

procedure TSega315_5248.Reset;
begin
  FRegs[0] := 0;
  FRegs[1] := 0;
end;

function TSega315_5248.Read(aOffset: Integer): Word;
var
  lProduct: Integer;
begin
  lProduct := Integer(SmallInt(FRegs[0])) * Integer(SmallInt(FRegs[1]));
  case aOffset and 3 of
    0: Result := FRegs[0];
    1: Result := FRegs[1];
    2: Result := Word(Cardinal(lProduct) shr 16);
  else
    Result := Word(Cardinal(lProduct) and $FFFF);
  end;
end;

procedure TSega315_5248.Write(aOffset: Integer; aValue, aMask: Word);
var
  i: Integer;
begin
  i := aOffset and 1;
  FRegs[i] := (FRegs[i] and not aMask) or (aValue and aMask);
end;

{ TSega315_5249 }

procedure TSega315_5249.Reset;
var
  i: Integer;
begin
  for i := 0 to 7 do
    FRegs[i] := 0;
end;

function TSega315_5249.Read(aOffset: Integer): Word;
begin
  case aOffset and 7 of
    0, 1, 2, 4, 5, 6: Result := FRegs[aOffset and 7];
  else
    Result := $FFFF;
  end;
end;

procedure TSega315_5249.Write(aOffset: Integer; aValue, aMask: Word);
var
  i: Integer;
begin
  i := aOffset and 3;
  if i < 3 then
    FRegs[i] := (FRegs[i] and not aMask) or (aValue and aMask);
  if (aOffset and 8) <> 0 then
    Execute((aOffset and 4) <> 0);
end;

procedure TSega315_5249.Execute(aUnsigned: Boolean);
var
  lDividend, lDivisor, lQuotient: Int64;
  lUDividend, lUDivisor, lUQuotient: Cardinal;
begin
  FRegs[6] := 0;
  if not aUnsigned then
  begin
    lDividend := Integer((Cardinal(FRegs[0]) shl 16) or FRegs[1]);
    lDivisor := SmallInt(FRegs[2]);
    if lDivisor = 0 then
    begin
      lQuotient := lDividend;
      FRegs[6] := FRegs[6] or $4000;
    end
    else
      lQuotient := lDividend div lDivisor;
    if lQuotient < -32768 then
    begin
      lQuotient := -32768;
      FRegs[6] := FRegs[6] or $8000;
    end
    else if lQuotient > 32767 then
    begin
      lQuotient := 32767;
      FRegs[6] := FRegs[6] or $8000;
    end;
    FRegs[4] := Word(lQuotient and $FFFF);
    FRegs[5] := Word((lDividend - lQuotient * lDivisor) and $FFFF);
  end
  else
  begin
    lUDividend := (Cardinal(FRegs[0]) shl 16) or FRegs[1];
    lUDivisor := FRegs[2];
    if lUDivisor = 0 then
    begin
      lUQuotient := lUDividend;
      FRegs[6] := FRegs[6] or $4000;
    end
    else
      lUQuotient := lUDividend div lUDivisor;
    FRegs[4] := lUQuotient shr 16;
    FRegs[5] := lUQuotient and $FFFF;
  end;
end;

end.
