unit Arcade.Chip.M68000;

///  Motorola MC68000 CPU core - full instruction set, every addressing mode, supervisor / user
///  stacks, autovectored interrupts (levels 1-7), trace, STOP, the documented exceptions.
///    - cycle counts per instruction from the Motorola user manual, MULU / MULS / DIVU / DIVS
///      data-dependent timings included
///    - checked against the SingleStepTests 68000 suite (labs/M68000Test)
///    - address errors (word access at an odd address) are flagged, not emulated : no game relies
///      on them, the access is aligned and AddressError is set
///  Pure unit, no dependency : FPC compatible (no inline var, no generics).
///  Generic : the machine wires memory through events, as for Arcade.Chip.Z80.

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}
{$Q-}
{$R-}

interface

type
  TM68000Read8 = function(aAddr: Cardinal): Byte of object;
  TM68000Read16 = function(aAddr: Cardinal): Word of object;
  TM68000Write8 = procedure(aAddr: Cardinal; aValue: Byte) of object;
  TM68000Write16 = procedure(aAddr: Cardinal; aValue: Word) of object;
  TM68000Signal = procedure of object;

  TM68000 = class
  private
    FSR: Word;
    FOtherSP: Cardinal;          // the inactive stack pointer (USP in supervisor mode, SSP in user mode)
    FCycles: Integer;            // cycles of the current Step
    FOpPC: Cardinal;             // address of the current instruction
    FIrqLevel: Integer;
    FNmiLatched: Boolean;
    FStopped: Boolean;
    FTrace: Boolean;             // T was set when the instruction started
    FNoTrace: Boolean;           // the instruction ended in an exception that cancels the trace
    procedure SetSR(aValue: Word);
    function GetUSP: Cardinal;
    function GetSSP: Cardinal;
    procedure SetUSP(aValue: Cardinal);
    procedure SetSSP(aValue: Cardinal);
    function Supervisor: Boolean; inline;
    function Rd8(aAddr: Cardinal): Byte; inline;
    function Rd16(aAddr: Cardinal): Word;
    function Rd32(aAddr: Cardinal): Cardinal;
    procedure Wr8(aAddr: Cardinal; aValue: Byte); inline;
    procedure Wr16(aAddr: Cardinal; aValue: Word);
    procedure Wr32(aAddr: Cardinal; aValue: Cardinal);
    function Rd(aAddr: Cardinal; aSize: Integer): Cardinal;
    procedure Wr(aAddr: Cardinal; aSize: Integer; aValue: Cardinal);
    function Fetch16: Word;
    function Fetch32: Cardinal;
    procedure Push16(aValue: Word);
    procedure Push32(aValue: Cardinal);
    function Pop16: Word;
    function Pop32: Cardinal;
    function IndexAddr(aBase: Cardinal): Cardinal;
    function EaAddress(aMode, aReg, aSize: Integer): Cardinal;
    function EaTime(aMode, aReg, aSize: Integer): Integer;
    function ReadEa(aMode, aReg, aSize: Integer; out aAddr: Cardinal): Cardinal;
    function ReadEaValue(aMode, aReg, aSize: Integer): Cardinal;
    procedure WriteBack(aMode, aReg, aSize: Integer; aAddr, aValue: Cardinal);
    procedure WriteEa(aMode, aReg, aSize: Integer; aValue: Cardinal);
    procedure SetDReg(aReg, aSize: Integer; aValue: Cardinal); inline;
    procedure SetNZ(aValue: Cardinal; aSize: Integer);
    procedure SetLogic(aValue: Cardinal; aSize: Integer);
    function DoAdd(aSrc, aDst: Cardinal; aSize: Integer; aExtend: Boolean): Cardinal;
    function DoSub(aSrc, aDst: Cardinal; aSize: Integer; aExtend, aCompare: Boolean): Cardinal;
    function Condition(aCode: Integer): Boolean;
    procedure Exception(aVector: Integer; aCycles: Integer; aPC: Cardinal);
    procedure Privilege;
    procedure Illegal;
    procedure TakeInterrupt(aLevel: Integer);
    procedure OpGroup0(aOp: Word);
    procedure OpMove(aOp: Word);
    procedure OpGroup4(aOp: Word);
    procedure OpGroup5(aOp: Word);
    procedure OpBranch(aOp: Word);
    procedure OpLogic(aOp: Word; aKind: Integer);
    procedure OpAddSub(aOp: Word; aSub: Boolean);
    procedure OpGroupB(aOp: Word);
    procedure OpGroupC(aOp: Word);
    procedure OpShift(aOp: Word);
    procedure OpMovem(aOp: Word);
    procedure OpBit(aOp: Word; aBit: Cardinal; aStatic: Boolean);
    procedure OpDiv(aOp: Word; aSigned: Boolean);
    procedure OpMul(aOp: Word; aSigned: Boolean);
    procedure OpBcd(aOp: Word; aSub: Boolean);
    function ShiftValue(aKind: Integer; aLeft: Boolean; aValue: Cardinal; aCount, aSize: Integer): Cardinal;
  public
    D: array[0..7] of Cardinal;
    A: array[0..7] of Cardinal;  // A[7] is the active stack pointer
    PC: Cardinal;
    /// Total cycles since Reset.
    Cycles: Int64;
    /// Set when a word / long access hit an odd address (the access was aligned instead).
    AddressError: Boolean;
    OnRead8: TM68000Read8;
    OnRead16: TM68000Read16;
    OnWrite8: TM68000Write8;
    OnWrite16: TM68000Write16;
    /// Instruction stream reads (opcodes, extension words) ; nil = OnRead16.
    OnFetch16: TM68000Read16;
    /// RESET instruction : pulses the reset line of the other chips.
    OnResetOut: TM68000Signal;
    /// Loads SSP and PC from the vector table, supervisor mode, interrupts masked.
    procedure Reset;
    /// Executes one instruction (or takes a pending interrupt). Returns the cycles spent.
    function Step: Integer;
    /// Interrupt priority input, 0 = none. Autovectored. Level 7 is non maskable (edge).
    procedure SetIrq(aLevel: Integer);
    property SR: Word read FSR write SetSR;
    property USP: Cardinal read GetUSP write SetUSP;
    property SSP: Cardinal read GetSSP write SetSSP;
    property Stopped: Boolean read FStopped;
  end;

const
  M68K_CF = $0001;
  M68K_VF = $0002;
  M68K_ZF = $0004;
  M68K_NF = $0008;
  M68K_XF = $0010;
  M68K_SF = $2000;
  M68K_TF = $8000;

implementation

const
  CMask: array[1..4] of Cardinal = ($FF, $FFFF, 0, $FFFFFFFF);
  CMsb: array[1..4] of Cardinal = ($80, $8000, 0, $80000000);
  // effective address calculation times, index = mode 0..6 then 7 + register for mode 7
  CEaTimeBW: array[0..11] of Integer = (0, 0, 4, 4, 6, 8, 10, 8, 12, 8, 10, 4);
  CEaTimeL: array[0..11] of Integer = (0, 0, 8, 8, 10, 12, 14, 12, 16, 12, 14, 8);
  // LEA / JMP times for the control modes, same index
  CLeaTime: array[0..11] of Integer = (0, 0, 4, 0, 0, 8, 12, 8, 12, 8, 12, 0);
  CJmpTime: array[0..11] of Integer = (0, 0, 8, 0, 0, 10, 14, 10, 12, 10, 14, 0);
  CMovemTime: array[0..11] of Integer = (0, 0, 0, 0, 0, 4, 6, 4, 8, 4, 6, 0);

function EaIndex(aMode, aReg: Integer): Integer; inline;
begin
  if aMode < 7 then
    Result := aMode
  else
    Result := 7 + aReg;
end;

function SignExt8(aValue: Cardinal): Cardinal; inline;
begin
  Result := Cardinal(Integer(ShortInt(aValue and $FF)));
end;

function SignExt16(aValue: Cardinal): Cardinal; inline;
begin
  Result := Cardinal(Integer(SmallInt(aValue and $FFFF)));
end;

function SizeOfCode(aCode: Integer): Integer; inline;
begin
  case aCode of
    0: Result := 1;
    1: Result := 2;
  else
    Result := 4;
  end;
end;

{ registers }

function TM68000.Supervisor: Boolean;
begin
  Result := (FSR and M68K_SF) <> 0;
end;

procedure TM68000.SetSR(aValue: Word);
var
  lTmp: Cardinal;
begin
  aValue := aValue and $A71F;
  if ((aValue xor FSR) and M68K_SF) <> 0 then
  begin
    lTmp := A[7];
    A[7] := FOtherSP;
    FOtherSP := lTmp;
  end;
  FSR := aValue;
end;

function TM68000.GetUSP: Cardinal;
begin
  if Supervisor then
    Result := FOtherSP
  else
    Result := A[7];
end;

function TM68000.GetSSP: Cardinal;
begin
  if Supervisor then
    Result := A[7]
  else
    Result := FOtherSP;
end;

procedure TM68000.SetUSP(aValue: Cardinal);
begin
  if Supervisor then
    FOtherSP := aValue
  else
    A[7] := aValue;
end;

procedure TM68000.SetSSP(aValue: Cardinal);
begin
  if Supervisor then
    A[7] := aValue
  else
    FOtherSP := aValue;
end;

{ memory }

function TM68000.Rd8(aAddr: Cardinal): Byte;
begin
  Result := OnRead8(aAddr and $FFFFFF);
end;

function TM68000.Rd16(aAddr: Cardinal): Word;
begin
  if (aAddr and 1) <> 0 then
    AddressError := True;
  Result := OnRead16(aAddr and $FFFFFE);
end;

function TM68000.Rd32(aAddr: Cardinal): Cardinal;
begin
  Result := (Cardinal(Rd16(aAddr)) shl 16) or Rd16(aAddr + 2);
end;

procedure TM68000.Wr8(aAddr: Cardinal; aValue: Byte);
begin
  OnWrite8(aAddr and $FFFFFF, aValue);
end;

procedure TM68000.Wr16(aAddr: Cardinal; aValue: Word);
begin
  if (aAddr and 1) <> 0 then
    AddressError := True;
  OnWrite16(aAddr and $FFFFFE, aValue);
end;

procedure TM68000.Wr32(aAddr: Cardinal; aValue: Cardinal);
begin
  Wr16(aAddr, aValue shr 16);
  Wr16(aAddr + 2, aValue and $FFFF);
end;

function TM68000.Rd(aAddr: Cardinal; aSize: Integer): Cardinal;
begin
  case aSize of
    1: Result := Rd8(aAddr);
    2: Result := Rd16(aAddr);
  else
    Result := Rd32(aAddr);
  end;
end;

procedure TM68000.Wr(aAddr: Cardinal; aSize: Integer; aValue: Cardinal);
begin
  case aSize of
    1: Wr8(aAddr, aValue and $FF);
    2: Wr16(aAddr, aValue and $FFFF);
  else
    Wr32(aAddr, aValue);
  end;
end;

function TM68000.Fetch16: Word;
begin
  if (PC and 1) <> 0 then
    AddressError := True;
  if Assigned(OnFetch16) then
    Result := OnFetch16(PC and $FFFFFE)
  else
    Result := OnRead16(PC and $FFFFFE);
  PC := PC + 2;
end;

function TM68000.Fetch32: Cardinal;
begin
  Result := Cardinal(Fetch16) shl 16;
  Result := Result or Fetch16;
end;

procedure TM68000.Push16(aValue: Word);
begin
  A[7] := A[7] - 2;
  Wr16(A[7], aValue);
end;

procedure TM68000.Push32(aValue: Cardinal);
begin
  A[7] := A[7] - 4;
  Wr32(A[7], aValue);
end;

function TM68000.Pop16: Word;
begin
  Result := Rd16(A[7]);
  A[7] := A[7] + 2;
end;

function TM68000.Pop32: Cardinal;
begin
  Result := Rd32(A[7]);
  A[7] := A[7] + 4;
end;

{ effective addresses }

function TM68000.IndexAddr(aBase: Cardinal): Cardinal;
var
  lExt: Word;
  lIdx: Cardinal;
  lReg: Integer;
begin
  lExt := Fetch16;
  lReg := (lExt shr 12) and 7;
  if (lExt and $8000) <> 0 then
    lIdx := A[lReg]
  else
    lIdx := D[lReg];
  if (lExt and $0800) = 0 then
    lIdx := SignExt16(lIdx);
  Result := aBase + lIdx + SignExt8(lExt);
end;

function TM68000.EaAddress(aMode, aReg, aSize: Integer): Cardinal;
var
  lStep: Cardinal;
  lBase: Cardinal;
begin
  case aMode of
    2: Result := A[aReg];
    3:
      begin
        Result := A[aReg];
        lStep := aSize;
        if (aSize = 1) and (aReg = 7) then
          lStep := 2;
        A[aReg] := A[aReg] + lStep;
      end;
    4:
      begin
        lStep := aSize;
        if (aSize = 1) and (aReg = 7) then
          lStep := 2;
        A[aReg] := A[aReg] - lStep;
        Result := A[aReg];
      end;
    5: Result := A[aReg] + SignExt16(Fetch16);
    6: Result := IndexAddr(A[aReg]);
    7:
      case aReg of
        0: Result := SignExt16(Fetch16);
        1: Result := Fetch32;
        2:
          begin
            lBase := PC;
            Result := lBase + SignExt16(Fetch16);
          end;
        3: Result := IndexAddr(PC);
      else
        Result := 0;
      end;
  else
    Result := 0;
  end;
end;

function TM68000.EaTime(aMode, aReg, aSize: Integer): Integer;
begin
  if aSize = 4 then
    Result := CEaTimeL[EaIndex(aMode, aReg)]
  else
    Result := CEaTimeBW[EaIndex(aMode, aReg)];
end;

/// Reads an operand ; for memory modes aAddr receives the address (read-modify-write).
function TM68000.ReadEa(aMode, aReg, aSize: Integer; out aAddr: Cardinal): Cardinal;
begin
  aAddr := 0;
  case aMode of
    0: Result := D[aReg] and CMask[aSize];
    1: Result := A[aReg] and CMask[aSize];
    7:
      if aReg = 4 then
      begin
        case aSize of
          1: Result := Fetch16 and $FF;
          2: Result := Fetch16;
        else
          Result := Fetch32;
        end;
      end
      else
      begin
        aAddr := EaAddress(aMode, aReg, aSize);
        Result := Rd(aAddr, aSize);
      end;
  else
    aAddr := EaAddress(aMode, aReg, aSize);
    Result := Rd(aAddr, aSize);
  end;
end;

function TM68000.ReadEaValue(aMode, aReg, aSize: Integer): Cardinal;
var
  lAddr: Cardinal;
begin
  Result := ReadEa(aMode, aReg, aSize, lAddr);
end;

procedure TM68000.SetDReg(aReg, aSize: Integer; aValue: Cardinal);
begin
  case aSize of
    1: D[aReg] := (D[aReg] and $FFFFFF00) or (aValue and $FF);
    2: D[aReg] := (D[aReg] and $FFFF0000) or (aValue and $FFFF);
  else
    D[aReg] := aValue;
  end;
end;

procedure TM68000.WriteBack(aMode, aReg, aSize: Integer; aAddr, aValue: Cardinal);
begin
  case aMode of
    0: SetDReg(aReg, aSize, aValue);
    1: A[aReg] := aValue;
  else
    Wr(aAddr, aSize, aValue);
  end;
end;

procedure TM68000.WriteEa(aMode, aReg, aSize: Integer; aValue: Cardinal);
begin
  case aMode of
    0: SetDReg(aReg, aSize, aValue);
    1: A[aReg] := aValue;
  else
    Wr(EaAddress(aMode, aReg, aSize), aSize, aValue);
  end;
end;

{ flags }

procedure TM68000.SetNZ(aValue: Cardinal; aSize: Integer);
var
  lSR: Word;
begin
  lSR := FSR and not (M68K_NF or M68K_ZF);
  aValue := aValue and CMask[aSize];
  if aValue = 0 then
    lSR := lSR or M68K_ZF;
  if (aValue and CMsb[aSize]) <> 0 then
    lSR := lSR or M68K_NF;
  FSR := lSR;
end;

procedure TM68000.SetLogic(aValue: Cardinal; aSize: Integer);
begin
  FSR := FSR and not (M68K_VF or M68K_CF);
  SetNZ(aValue, aSize);
end;

function TM68000.DoAdd(aSrc, aDst: Cardinal; aSize: Integer; aExtend: Boolean): Cardinal;
var
  lRes: UInt64;
  lMask, lMsb: Cardinal;
  lSR: Word;
begin
  lMask := CMask[aSize];
  lMsb := CMsb[aSize];
  aSrc := aSrc and lMask;
  aDst := aDst and lMask;
  lRes := UInt64(aSrc) + aDst;
  if aExtend and ((FSR and M68K_XF) <> 0) then
    Inc(lRes);
  Result := Cardinal(lRes) and lMask;
  lSR := FSR and not (M68K_XF or M68K_NF or M68K_VF or M68K_CF);
  if aExtend then
  begin
    if Result <> 0 then
      lSR := lSR and not M68K_ZF;
  end
  else
  begin
    lSR := lSR and not M68K_ZF;
    if Result = 0 then
      lSR := lSR or M68K_ZF;
  end;
  if (Result and lMsb) <> 0 then
    lSR := lSR or M68K_NF;
  if lRes > lMask then
    lSR := lSR or M68K_CF or M68K_XF;
  if ((aSrc xor Result) and (aDst xor Result) and lMsb) <> 0 then
    lSR := lSR or M68K_VF;
  FSR := lSR;
end;

function TM68000.DoSub(aSrc, aDst: Cardinal; aSize: Integer; aExtend, aCompare: Boolean): Cardinal;
var
  lMask, lMsb, lX: Cardinal;
  lSR: Word;
begin
  lMask := CMask[aSize];
  lMsb := CMsb[aSize];
  aSrc := aSrc and lMask;
  aDst := aDst and lMask;
  lX := 0;
  if aExtend and ((FSR and M68K_XF) <> 0) then
    lX := 1;
  Result := (aDst - aSrc - lX) and lMask;
  if aCompare then
    lSR := FSR and not (M68K_NF or M68K_ZF or M68K_VF or M68K_CF)
  else
    lSR := FSR and not (M68K_XF or M68K_NF or M68K_VF or M68K_CF);
  if aExtend then
  begin
    if Result <> 0 then
      lSR := lSR and not M68K_ZF;
  end
  else
  begin
    lSR := lSR and not M68K_ZF;
    if Result = 0 then
      lSR := lSR or M68K_ZF;
  end;
  if (Result and lMsb) <> 0 then
    lSR := lSR or M68K_NF;
  if UInt64(aSrc) + lX > aDst then
  begin
    lSR := lSR or M68K_CF;
    if not aCompare then
      lSR := lSR or M68K_XF;
  end;
  if ((aSrc xor aDst) and (Result xor aDst) and lMsb) <> 0 then
    lSR := lSR or M68K_VF;
  FSR := lSR;
end;

function TM68000.Condition(aCode: Integer): Boolean;
var
  lC, lV, lZ, lN: Boolean;
begin
  lC := (FSR and M68K_CF) <> 0;
  lV := (FSR and M68K_VF) <> 0;
  lZ := (FSR and M68K_ZF) <> 0;
  lN := (FSR and M68K_NF) <> 0;
  case aCode of
    0: Result := True;
    1: Result := False;
    2: Result := not lC and not lZ;      // HI
    3: Result := lC or lZ;               // LS
    4: Result := not lC;                 // CC
    5: Result := lC;                     // CS
    6: Result := not lZ;                 // NE
    7: Result := lZ;                     // EQ
    8: Result := not lV;                 // VC
    9: Result := lV;                     // VS
    10: Result := not lN;                // PL
    11: Result := lN;                    // MI
    12: Result := lN = lV;               // GE
    13: Result := lN <> lV;              // LT
    14: Result := not lZ and (lN = lV);  // GT
  else
    Result := lZ or (lN <> lV);          // LE
  end;
end;

{ exceptions }

procedure TM68000.Exception(aVector: Integer; aCycles: Integer; aPC: Cardinal);
var
  lOld: Word;
begin
  lOld := FSR;
  SetSR((FSR or M68K_SF) and not M68K_TF);
  A[7] := A[7] - 4;
  Wr16(A[7] + 2, aPC and $FFFF);
  A[7] := A[7] - 2;
  Wr16(A[7], lOld);
  Wr16(A[7] + 2, aPC shr 16);
  PC := Rd32(Cardinal(aVector) * 4);
  Inc(FCycles, aCycles);
end;

procedure TM68000.Privilege;
begin
  FNoTrace := True;
  Exception(8, 34, FOpPC);
end;

procedure TM68000.Illegal;
begin
  FNoTrace := True;
  Exception(4, 34, FOpPC);
end;

procedure TM68000.TakeInterrupt(aLevel: Integer);
begin
  FStopped := False;
  Exception(24 + aLevel, 44, PC);
  FSR := (FSR and $F8FF) or (aLevel shl 8);
end;

{ public }

procedure TM68000.Reset;
var
  i: Integer;
begin
  for i := 0 to 7 do
  begin
    D[i] := 0;
    A[i] := 0;
  end;
  FOtherSP := 0;
  FSR := M68K_SF or $0700;
  FIrqLevel := 0;
  FNmiLatched := False;
  FStopped := False;
  AddressError := False;
  A[7] := Rd32(0);
  PC := Rd32(4);
  Cycles := 0;
end;

procedure TM68000.SetIrq(aLevel: Integer);
begin
  if (aLevel = 7) and (FIrqLevel <> 7) then
    FNmiLatched := True;
  FIrqLevel := aLevel;
end;

function TM68000.Step: Integer;
var
  lOp: Word;
  lMask: Integer;
begin
  FCycles := 0;
  lMask := (FSR shr 8) and 7;
  if (FIrqLevel = 7) and FNmiLatched then
  begin
    FNmiLatched := False;
    TakeInterrupt(7);
  end
  else if (FIrqLevel > lMask) and (FIrqLevel < 7) then
    TakeInterrupt(FIrqLevel)
  else if FStopped then
    FCycles := 4
  else
  begin
    FTrace := (FSR and M68K_TF) <> 0;
    FNoTrace := False;
    FOpPC := PC;
    lOp := Fetch16;
    case lOp shr 12 of
      0: OpGroup0(lOp);
      1, 2, 3: OpMove(lOp);
      4: OpGroup4(lOp);
      5: OpGroup5(lOp);
      6: OpBranch(lOp);
      7:
        if (lOp and $0100) = 0 then
        begin
          D[(lOp shr 9) and 7] := SignExt8(lOp);
          SetLogic(lOp and $FF, 1);
          Inc(FCycles, 4);
        end
        else
          Illegal;
      8: OpLogic(lOp, 0);
      9: OpAddSub(lOp, True);
      10:
        begin
          FNoTrace := True;
          Exception(10, 34, FOpPC);
        end;
      11: OpGroupB(lOp);
      12: OpGroupC(lOp);
      13: OpAddSub(lOp, False);
      14: OpShift(lOp);
    else
      FNoTrace := True;
      Exception(11, 34, FOpPC);
    end;
    if FTrace and not FNoTrace then
      Exception(9, 34, PC);
  end;
  if (PC and 1) <> 0 then
    AddressError := True;
  Cycles := Cycles + FCycles;
  Result := FCycles;
end;

{ group 0 : immediate, bit operations, MOVEP }

procedure TM68000.OpBit(aOp: Word; aBit: Cardinal; aStatic: Boolean);
var
  lMode, lReg, lKind: Integer;
  lAddr, lValue, lMask: Cardinal;
begin
  lMode := (aOp shr 3) and 7;
  lReg := aOp and 7;
  lKind := (aOp shr 6) and 3;   // 0 BTST 1 BCHG 2 BCLR 3 BSET
  if lMode = 0 then
  begin
    aBit := aBit and 31;
    lMask := Cardinal(1) shl aBit;
    lValue := D[lReg];
    if (lValue and lMask) = 0 then
      FSR := FSR or M68K_ZF
    else
      FSR := FSR and not M68K_ZF;
    case lKind of
      0:
        if aStatic then Inc(FCycles, 10) else Inc(FCycles, 6);
      1, 3:
        begin
          if lKind = 1 then
            D[lReg] := lValue xor lMask
          else
            D[lReg] := lValue or lMask;
          if aStatic then Inc(FCycles, 10) else Inc(FCycles, 6);
          if aBit >= 16 then Inc(FCycles, 2);
        end;
      2:
        begin
          D[lReg] := lValue and not lMask;
          if aStatic then Inc(FCycles, 12) else Inc(FCycles, 8);
          if aBit >= 16 then Inc(FCycles, 2);
        end;
    end;
  end
  else
  begin
    aBit := aBit and 7;
    lMask := Cardinal(1) shl aBit;
    lValue := ReadEa(lMode, lReg, 1, lAddr);
    if (lValue and lMask) = 0 then
      FSR := FSR or M68K_ZF
    else
      FSR := FSR and not M68K_ZF;
    Inc(FCycles, EaTime(lMode, lReg, 1));
    if aStatic then Inc(FCycles, 8) else Inc(FCycles, 4);
    if (lMode = 7) and (lReg = 4) then Inc(FCycles, 2);
    if lKind <> 0 then
    begin
      Inc(FCycles, 4);
      case lKind of
        1: lValue := lValue xor lMask;
        2: lValue := lValue and not lMask;
      else
        lValue := lValue or lMask;
      end;
      Wr8(lAddr, lValue);
    end;
  end;
end;

procedure TM68000.OpGroup0(aOp: Word);
var
  lMode, lReg, lSize, lKind, lDn: Integer;
  lImm, lAddr, lValue, lRes: Cardinal;
begin
  lMode := (aOp shr 3) and 7;
  lReg := aOp and 7;
  if (aOp and $0100) <> 0 then
  begin
    lDn := (aOp shr 9) and 7;
    if lMode = 1 then
    begin
      // MOVEP
      lAddr := A[lReg] + SignExt16(Fetch16);
      case (aOp shr 6) and 3 of
        0:
          begin
            D[lDn] := (D[lDn] and $FFFF0000) or (Cardinal(Rd8(lAddr)) shl 8) or Rd8(lAddr + 2);
            Inc(FCycles, 16);
          end;
        1:
          begin
            D[lDn] := (Cardinal(Rd8(lAddr)) shl 24) or (Cardinal(Rd8(lAddr + 2)) shl 16) or
              (Cardinal(Rd8(lAddr + 4)) shl 8) or Rd8(lAddr + 6);
            Inc(FCycles, 24);
          end;
        2:
          begin
            Wr8(lAddr, (D[lDn] shr 8) and $FF);
            Wr8(lAddr + 2, D[lDn] and $FF);
            Inc(FCycles, 16);
          end;
      else
        Wr8(lAddr, D[lDn] shr 24);
        Wr8(lAddr + 2, (D[lDn] shr 16) and $FF);
        Wr8(lAddr + 4, (D[lDn] shr 8) and $FF);
        Wr8(lAddr + 6, D[lDn] and $FF);
        Inc(FCycles, 24);
      end;
    end
    else
      OpBit(aOp, D[lDn], False);
    Exit;
  end;
  lKind := (aOp shr 9) and 7;
  if lKind = 4 then
  begin
    lImm := Fetch16 and $FF;
    OpBit(aOp, lImm, True);
    Exit;
  end;
  if lKind = 7 then
  begin
    Illegal;
    Exit;
  end;
  if ((aOp shr 6) and 3) = 3 then
  begin
    Illegal;
    Exit;
  end;
  lSize := SizeOfCode((aOp shr 6) and 3);
  // ORI / ANDI / EORI to CCR and SR
  if (lMode = 7) and (lReg = 4) and (lKind in [0, 1, 5]) then
  begin
    if lSize = 1 then
    begin
      lImm := Fetch16 and $FF;
      case lKind of
        0: SR := FSR or lImm;
        1: SR := FSR and ($FF00 or lImm);
      else
        SR := FSR xor lImm;
      end;
      Inc(FCycles, 20);
    end
    else if lSize = 2 then
    begin
      if not Supervisor then
      begin
        Privilege;
        Exit;
      end;
      lImm := Fetch16;
      case lKind of
        0: SR := FSR or lImm;
        1: SR := FSR and lImm;
      else
        SR := FSR xor lImm;
      end;
      Inc(FCycles, 20);
    end
    else
      Illegal;
    Exit;
  end;
  if lSize = 4 then
    lImm := Fetch32
  else if lSize = 2 then
    lImm := Fetch16
  else
    lImm := Fetch16 and $FF;
  lValue := ReadEa(lMode, lReg, lSize, lAddr);
  case lKind of
    0: begin lRes := lValue or lImm; SetLogic(lRes, lSize); end;
    1: begin lRes := lValue and lImm; SetLogic(lRes, lSize); end;
    2: lRes := DoSub(lImm, lValue, lSize, False, False);
    3: lRes := DoAdd(lImm, lValue, lSize, False);
    5: begin lRes := lValue xor lImm; SetLogic(lRes, lSize); end;
  else
    lRes := DoSub(lImm, lValue, lSize, False, True);
  end;
  if lKind = 6 then
  begin
    // CMPI
    if lMode = 0 then
    begin
      if lSize = 4 then Inc(FCycles, 14) else Inc(FCycles, 8);
    end
    else
    begin
      if lSize = 4 then Inc(FCycles, 12) else Inc(FCycles, 8);
      Inc(FCycles, EaTime(lMode, lReg, lSize));
    end;
    Exit;
  end;
  WriteBack(lMode, lReg, lSize, lAddr, lRes);
  if lMode = 0 then
  begin
    if lSize = 4 then
    begin
      Inc(FCycles, 16);
    end
    else
      Inc(FCycles, 8);
  end
  else
  begin
    if lSize = 4 then Inc(FCycles, 20) else Inc(FCycles, 12);
    Inc(FCycles, EaTime(lMode, lReg, lSize));
  end;
end;

{ MOVE / MOVEA }

procedure TM68000.OpMove(aOp: Word);
var
  lSize, lSMode, lSReg, lDMode, lDReg: Integer;
  lValue: Cardinal;
begin
  case aOp shr 12 of
    1: lSize := 1;
    3: lSize := 2;
  else
    lSize := 4;
  end;
  lSMode := (aOp shr 3) and 7;
  lSReg := aOp and 7;
  lDMode := (aOp shr 6) and 7;
  lDReg := (aOp shr 9) and 7;
  lValue := ReadEaValue(lSMode, lSReg, lSize);
  Inc(FCycles, 4 + EaTime(lSMode, lSReg, lSize));
  if lDMode = 1 then
  begin
    if lSize = 2 then
      lValue := SignExt16(lValue);
    A[lDReg] := lValue;
    Exit;
  end;
  SetLogic(lValue, lSize);
  WriteEa(lDMode, lDReg, lSize, lValue);
  if lDMode = 4 then
    Inc(FCycles, EaTime(2, 0, lSize))
  else
    Inc(FCycles, EaTime(lDMode, lDReg, lSize));
end;

{ group 4 : miscellaneous }

procedure TM68000.OpMovem(aOp: Word);
var
  lMask: Word;
  lSize, lMode, lReg, i, n: Integer;
  lAddr, lValue: Cardinal;
begin
  lMask := Fetch16;
  if (aOp and $0040) <> 0 then lSize := 4 else lSize := 2;
  lMode := (aOp shr 3) and 7;
  lReg := aOp and 7;
  n := 0;
  if (aOp and $0400) = 0 then
  begin
    // registers to memory
    if lMode = 4 then
    begin
      lAddr := A[lReg];
      for i := 0 to 15 do
        if (lMask and (1 shl i)) <> 0 then
        begin
          lAddr := lAddr - Cardinal(lSize);
          if i < 8 then
            lValue := A[7 - i]
          else
            lValue := D[15 - i];
          Wr(lAddr, lSize, lValue);
          Inc(n);
        end;
      A[lReg] := lAddr;
      Inc(FCycles, 8);
    end
    else
    begin
      lAddr := EaAddress(lMode, lReg, lSize);
      for i := 0 to 15 do
        if (lMask and (1 shl i)) <> 0 then
        begin
          if i < 8 then
            lValue := D[i]
          else
            lValue := A[i - 8];
          Wr(lAddr, lSize, lValue);
          lAddr := lAddr + Cardinal(lSize);
          Inc(n);
        end;
      Inc(FCycles, 8 + CMovemTime[EaIndex(lMode, lReg)]);
    end;
  end
  else
  begin
    // memory to registers
    if lMode = 3 then
      lAddr := A[lReg]
    else
      lAddr := EaAddress(lMode, lReg, lSize);
    for i := 0 to 15 do
      if (lMask and (1 shl i)) <> 0 then
      begin
        lValue := Rd(lAddr, lSize);
        if lSize = 2 then
          lValue := SignExt16(lValue);
        if i < 8 then
          D[i] := lValue
        else
          A[i - 8] := lValue;
        lAddr := lAddr + Cardinal(lSize);
        Inc(n);
      end;
    Rd16(lAddr);
    if lMode = 3 then
    begin
      A[lReg] := lAddr;
      Inc(FCycles, 12);
    end
    else
      Inc(FCycles, 12 + CMovemTime[EaIndex(lMode, lReg)]);
  end;
  if lSize = 4 then
    Inc(FCycles, 8 * n)
  else
    Inc(FCycles, 4 * n);
end;

procedure TM68000.OpGroup4(aOp: Word);
var
  lMode, lReg, lSize, lAn: Integer;
  lAddr, lValue, lRes, lBound: Cardinal;
  lDisp: Cardinal;
begin
  lMode := (aOp shr 3) and 7;
  lReg := aOp and 7;
  if (aOp and $0100) <> 0 then
  begin
    lAn := (aOp shr 9) and 7;
    if ((aOp shr 6) and 7) = 7 then
    begin
      // LEA
      A[lAn] := EaAddress(lMode, lReg, 4);
      Inc(FCycles, CLeaTime[EaIndex(lMode, lReg)]);
    end
    else if ((aOp shr 6) and 7) = 6 then
    begin
      // CHK.W
      lBound := ReadEaValue(lMode, lReg, 2);
      Inc(FCycles, 10 + EaTime(lMode, lReg, 2));
      lValue := D[lAn] and $FFFF;
      FSR := FSR and not (M68K_ZF or M68K_VF or M68K_CF);
      if lValue = 0 then
        FSR := FSR or M68K_ZF;
      if SmallInt(lValue) > SmallInt(lBound) then
      begin
        if SmallInt(lValue) < 0 then
          FSR := FSR or M68K_NF
        else
          FSR := FSR and not M68K_NF;
        Exception(6, 28, PC);
      end
      else if SmallInt(lValue) < 0 then
      begin
        FSR := FSR or M68K_NF;
        Exception(6, 30, PC);
      end;
    end
    else
      Illegal;
    Exit;
  end;
  case (aOp shr 8) and $F of
    0, 2, 4, 6:
      begin
        if ((aOp shr 6) and 3) = 3 then
        begin
          case (aOp shr 9) and 3 of
            0:
              begin
                // MOVE from SR
                if lMode = 0 then
                begin
                  SetDReg(lReg, 2, FSR);
                  Inc(FCycles, 6);
                end
                else
                begin
                  lAddr := EaAddress(lMode, lReg, 2);
                  Rd16(lAddr);
                  Wr16(lAddr, FSR);
                  Inc(FCycles, 8 + EaTime(lMode, lReg, 2));
                end;
              end;
            1: Illegal;
            2:
              begin
                // MOVE to CCR
                lValue := ReadEaValue(lMode, lReg, 2);
                SR := (FSR and $FF00) or (lValue and $FF);
                Inc(FCycles, 12 + EaTime(lMode, lReg, 2));
              end;
          else
            // MOVE to SR
            if not Supervisor then
            begin
              Privilege;
              Exit;
            end;
            lValue := ReadEaValue(lMode, lReg, 2);
            SR := lValue;
            Inc(FCycles, 12 + EaTime(lMode, lReg, 2));
          end;
          Exit;
        end;
        lSize := SizeOfCode((aOp shr 6) and 3);
        lValue := ReadEa(lMode, lReg, lSize, lAddr);
        case (aOp shr 9) and 3 of
          0: lRes := DoSub(lValue, 0, lSize, True, False);   // NEGX
          1:
            begin
              lRes := 0;                                    // CLR
              FSR := (FSR and not (M68K_NF or M68K_VF or M68K_CF)) or M68K_ZF;
            end;
          2: lRes := DoSub(lValue, 0, lSize, False, False);  // NEG
        else
          lRes := not lValue;                              // NOT
          SetLogic(lRes, lSize);
        end;
        WriteBack(lMode, lReg, lSize, lAddr, lRes);
        if lMode = 0 then
        begin
          if lSize = 4 then Inc(FCycles, 6) else Inc(FCycles, 4);
        end
        else
        begin
          if lSize = 4 then Inc(FCycles, 12) else Inc(FCycles, 8);
          Inc(FCycles, EaTime(lMode, lReg, lSize));
        end;
      end;
    8:
      case (aOp shr 6) and 3 of
        0: OpBcd(aOp, True);   // NBCD
        1:
          if lMode = 0 then
          begin
            // SWAP
            D[lReg] := (D[lReg] shl 16) or (D[lReg] shr 16);
            SetLogic(D[lReg], 4);
            Inc(FCycles, 4);
          end
          else
          begin
            // PEA
            lAddr := EaAddress(lMode, lReg, 4);
            Push32(lAddr);
            Inc(FCycles, 8 + CLeaTime[EaIndex(lMode, lReg)]);
          end;
      else
        if lMode = 0 then
        begin
          // EXT
          if (aOp and $0040) = 0 then
          begin
            SetDReg(lReg, 2, SignExt8(D[lReg]));
            SetLogic(D[lReg], 2);
          end
          else
          begin
            D[lReg] := SignExt16(D[lReg]);
            SetLogic(D[lReg], 4);
          end;
          Inc(FCycles, 4);
        end
        else
          OpMovem(aOp);
      end;
    $A:
      if aOp = $4AFC then
        Illegal
      else if ((aOp shr 6) and 3) = 3 then
      begin
        // TAS
        lValue := ReadEa(lMode, lReg, 1, lAddr);
        SetLogic(lValue, 1);
        WriteBack(lMode, lReg, 1, lAddr, lValue or $80);
        if lMode = 0 then
          Inc(FCycles, 4)
        else
          Inc(FCycles, 10 + EaTime(lMode, lReg, 1));
      end
      else
      begin
        // TST
        lSize := SizeOfCode((aOp shr 6) and 3);
        lValue := ReadEaValue(lMode, lReg, lSize);
        SetLogic(lValue, lSize);
        Inc(FCycles, 4 + EaTime(lMode, lReg, lSize));
      end;
    $C:
      if ((aOp shr 7) and 1) = 1 then
        OpMovem(aOp)
      else
        Illegal;
    $E:
      case (aOp shr 6) and 3 of
        1:
          case (aOp shr 3) and 7 of
            0, 1:
              begin
                // TRAP
                FNoTrace := False;
                Exception(32 + (aOp and $F), 34, PC);
              end;
            2:
              begin
                // LINK
                lDisp := SignExt16(Fetch16);
                if lReg = 7 then
                  Push32(A[7] - 4)
                else
                  Push32(A[lReg]);
                A[lReg] := A[7];
                A[7] := A[7] + lDisp;
                Inc(FCycles, 16);
              end;
            3:
              begin
                // UNLK
                A[7] := A[lReg];
                A[lReg] := Pop32;
                Inc(FCycles, 12);
              end;
            4, 5:
              begin
                // MOVE An,USP / MOVE USP,An
                if not Supervisor then
                begin
                  Privilege;
                  Exit;
                end;
                if ((aOp shr 3) and 1) = 0 then
                  FOtherSP := A[lReg]
                else
                  A[lReg] := FOtherSP;
                Inc(FCycles, 4);
              end;
            6:
              case aOp and 7 of
                0:
                  begin
                    // RESET
                    if not Supervisor then
                    begin
                      Privilege;
                      Exit;
                    end;
                    if Assigned(OnResetOut) then
                      OnResetOut;
                    Inc(FCycles, 132);
                  end;
                1: Inc(FCycles, 4);  // NOP
                2:
                  begin
                    // STOP
                    if not Supervisor then
                    begin
                      Privilege;
                      Exit;
                    end;
                    SR := Fetch16;
                    FStopped := True;
                    Inc(FCycles, 4);
                  end;
                3:
                  begin
                    // RTE
                    if not Supervisor then
                    begin
                      Privilege;
                      Exit;
                    end;
                    lValue := Pop16;
                    lAddr := Pop32;
                    SR := lValue;
                    PC := lAddr;
                    Inc(FCycles, 20);
                  end;
                5:
                  begin
                    // RTS
                    PC := Pop32;
                    Inc(FCycles, 16);
                  end;
                6:
                  begin
                    // TRAPV
                    if (FSR and M68K_VF) <> 0 then
                      Exception(7, 34, PC)
                    else
                      Inc(FCycles, 4);
                  end;
                7:
                  begin
                    // RTR
                    lValue := Pop16;
                    SR := (FSR and $FF00) or (lValue and $FF);
                    PC := Pop32;
                    Inc(FCycles, 20);
                  end;
              else
                Illegal;
              end;
          else
            Illegal;
          end;
        2:
          begin
            // JSR
            lAddr := EaAddress(lMode, lReg, 4);
            Push32(PC);
            PC := lAddr;
            Inc(FCycles, 8 + CJmpTime[EaIndex(lMode, lReg)]);
          end;
        3:
          begin
            // JMP
            PC := EaAddress(lMode, lReg, 4);
            Inc(FCycles, CJmpTime[EaIndex(lMode, lReg)]);
          end;
      else
        Illegal;
      end;
  else
    Illegal;
  end;
end;

{ group 5 : ADDQ / SUBQ / Scc / DBcc }

procedure TM68000.OpGroup5(aOp: Word);
var
  lMode, lReg, lSize: Integer;
  lData, lAddr, lValue, lRes: Cardinal;
  lDisp: Cardinal;
begin
  lMode := (aOp shr 3) and 7;
  lReg := aOp and 7;
  if ((aOp shr 6) and 3) = 3 then
  begin
    if lMode = 1 then
    begin
      // DBcc
      lDisp := SignExt16(Fetch16);
      if Condition((aOp shr 8) and $F) then
        Inc(FCycles, 12)
      else
      begin
        lValue := (D[lReg] - 1) and $FFFF;
        SetDReg(lReg, 2, lValue);
        if lValue = $FFFF then
          Inc(FCycles, 14)
        else
        begin
          PC := FOpPC + 2 + lDisp;
          Inc(FCycles, 10);
        end;
      end;
    end
    else
    begin
      // Scc
      if Condition((aOp shr 8) and $F) then
        lValue := $FF
      else
        lValue := 0;
      if lMode = 0 then
      begin
        SetDReg(lReg, 1, lValue);
        if lValue <> 0 then Inc(FCycles, 6) else Inc(FCycles, 4);
      end
      else
      begin
        lAddr := EaAddress(lMode, lReg, 1);
        Rd8(lAddr);
        Wr8(lAddr, lValue);
        Inc(FCycles, 8 + EaTime(lMode, lReg, 1));
      end;
    end;
    Exit;
  end;
  lSize := SizeOfCode((aOp shr 6) and 3);
  lData := (aOp shr 9) and 7;
  if lData = 0 then
    lData := 8;
  if lMode = 1 then
  begin
    if (aOp and $0100) = 0 then
      A[lReg] := A[lReg] + lData
    else
      A[lReg] := A[lReg] - lData;
    if lSize = 4 then Inc(FCycles, 6) else Inc(FCycles, 8);
    Exit;
  end;
  lValue := ReadEa(lMode, lReg, lSize, lAddr);
  if (aOp and $0100) = 0 then
    lRes := DoAdd(lData, lValue, lSize, False)
  else
    lRes := DoSub(lData, lValue, lSize, False, False);
  WriteBack(lMode, lReg, lSize, lAddr, lRes);
  if lMode = 0 then
  begin
    if lSize = 4 then Inc(FCycles, 8) else Inc(FCycles, 4);
  end
  else
  begin
    if lSize = 4 then Inc(FCycles, 12) else Inc(FCycles, 8);
    Inc(FCycles, EaTime(lMode, lReg, lSize));
  end;
end;

{ group 6 : Bcc / BRA / BSR }

procedure TM68000.OpBranch(aOp: Word);
var
  lCond: Integer;
  lDisp: Cardinal;
  lWord: Boolean;
begin
  lCond := (aOp shr 8) and $F;
  lWord := (aOp and $FF) = 0;
  if lWord then
    lDisp := SignExt16(Fetch16)
  else
    lDisp := SignExt8(aOp);
  if lCond = 1 then
  begin
    // BSR
    Push32(PC);
    PC := FOpPC + 2 + lDisp;
    Inc(FCycles, 18);
  end
  else if Condition(lCond) then
  begin
    PC := FOpPC + 2 + lDisp;
    Inc(FCycles, 10);
  end
  else if lWord then
    Inc(FCycles, 12)
  else
    Inc(FCycles, 8);
end;

{ BCD }

procedure TM68000.OpBcd(aOp: Word; aSub: Boolean);
var
  lSrc, lDst, lRes, lCorf, lV, lAddr, lSrcAddr: Cardinal;
  lX: Cardinal;
  lRx, lRy, lMode: Integer;
begin
  if (FSR and M68K_XF) <> 0 then lX := 1 else lX := 0;
  lRx := (aOp shr 9) and 7;
  lRy := aOp and 7;
  lAddr := 0;
  if (aOp shr 12) = 4 then
  begin
    // NBCD <ea>
    lMode := (aOp shr 3) and 7;
    lDst := ReadEa(lMode, lRy, 1, lAddr);
    lSrc := lDst;
    lDst := 0;
    if lMode = 0 then
      Inc(FCycles, 6)
    else
      Inc(FCycles, 8 + EaTime(lMode, lRy, 1));
  end
  else
  begin
    lMode := 0;
    if (aOp and 8) <> 0 then
    begin
      A[lRy] := A[lRy] - 1;
      if lRy = 7 then A[lRy] := A[lRy] - 1;
      lSrcAddr := A[lRy];
      lSrc := Rd8(lSrcAddr);
      A[lRx] := A[lRx] - 1;
      if lRx = 7 then A[lRx] := A[lRx] - 1;
      lAddr := A[lRx];
      lDst := Rd8(lAddr);
      lMode := 2;
      Inc(FCycles, 18);
    end
    else
    begin
      lSrc := D[lRy] and $FF;
      lDst := D[lRx] and $FF;
      Inc(FCycles, 6);
    end;
  end;
  if aSub then
  begin
    lRes := (lDst and $F) - (lSrc and $F) - lX;
    lCorf := 0;
    if lRes > $F then
      lCorf := 6;
    lRes := lRes + (lDst and $F0) - (lSrc and $F0);
    lV := lRes;
    FSR := FSR and not (M68K_XF or M68K_CF or M68K_VF or M68K_NF);
    if lRes > $FF then
    begin
      lRes := lRes + $A0;
      FSR := FSR or M68K_XF or M68K_CF;
    end
    else if lRes < lCorf then
      FSR := FSR or M68K_XF or M68K_CF;
    lRes := (lRes - lCorf) and $FF;
    lV := lV and not lRes;
  end
  else
  begin
    lV := lSrc + lDst + lX;
    lRes := (lSrc and $F) + (lDst and $F) + lX;
    if lRes > 9 then
      lRes := lRes + 6;
    lRes := lRes + (lSrc and $F0) + (lDst and $F0);
    if lRes > $9F then
      lRes := lRes + $60;
    FSR := FSR and not (M68K_XF or M68K_CF or M68K_VF or M68K_NF);
    if lRes > $FF then
      FSR := FSR or M68K_XF or M68K_CF;
    lV := not lV and lRes;
    lRes := lRes and $FF;
  end;
  if (lV and $80) <> 0 then
    FSR := FSR or M68K_VF;
  if (lRes and $80) <> 0 then
    FSR := FSR or M68K_NF;
  if lRes <> 0 then
    FSR := FSR and not M68K_ZF;
  if (aOp shr 12) = 4 then
    WriteBack(lMode, lRy, 1, lAddr, lRes)
  else if lMode = 2 then
    Wr8(lAddr, lRes)
  else
    SetDReg(lRx, 1, lRes);
end;

{ MUL / DIV }

procedure TM68000.OpMul(aOp: Word; aSigned: Boolean);
var
  lMode, lReg, lDn, n: Integer;
  lSrc, lRes, lBits: Cardinal;
begin
  lMode := (aOp shr 3) and 7;
  lReg := aOp and 7;
  lDn := (aOp shr 9) and 7;
  lSrc := ReadEaValue(lMode, lReg, 2);
  if aSigned then
  begin
    lRes := Cardinal(Integer(SmallInt(lSrc)) * Integer(SmallInt(D[lDn] and $FFFF)));
    lBits := (lSrc shl 1) xor lSrc;
  end
  else
  begin
    lRes := lSrc * (D[lDn] and $FFFF);
    lBits := lSrc;
  end;
  n := 0;
  lBits := lBits and $FFFF;
  while lBits <> 0 do
  begin
    Inc(n, lBits and 1);
    lBits := lBits shr 1;
  end;
  D[lDn] := lRes;
  SetLogic(lRes, 4);
  Inc(FCycles, 38 + 2 * n + EaTime(lMode, lReg, 2));
end;

procedure TM68000.OpDiv(aOp: Word; aSigned: Boolean);
var
  lMode, lReg, lDn, i, lMc: Integer;
  lSrc, lDividend, lHDiv, lTmp, lAQuot: Cardinal;
  lQuot, lRem: Int64;
  lSDividend, lSDivisor: Integer;
begin
  lMode := (aOp shr 3) and 7;
  lReg := aOp and 7;
  lDn := (aOp shr 9) and 7;
  lSrc := ReadEaValue(lMode, lReg, 2);
  Inc(FCycles, EaTime(lMode, lReg, 2));
  lDividend := D[lDn];
  if lSrc = 0 then
  begin
    FSR := FSR and not (M68K_NF or M68K_ZF or M68K_VF or M68K_CF);
    Exception(5, 38, PC);
    Exit;
  end;
  if not aSigned then
  begin
    if (lDividend shr 16) >= lSrc then
    begin
      FSR := (FSR and not M68K_CF) or M68K_VF;
      Inc(FCycles, 10);
      Exit;
    end;
    lMc := 38;
    lHDiv := lSrc shl 16;
    lTmp := lDividend;
    for i := 0 to 14 do
    begin
      if (lTmp and $80000000) <> 0 then
      begin
        lTmp := lTmp shl 1;
        lTmp := lTmp - lHDiv;
      end
      else
      begin
        lTmp := lTmp shl 1;
        Inc(lMc, 2);
        if lTmp >= lHDiv then
        begin
          lTmp := lTmp - lHDiv;
          Dec(lMc);
        end;
      end;
    end;
    Inc(FCycles, lMc * 2);
    lQuot := lDividend div lSrc;
    lRem := lDividend mod lSrc;
    D[lDn] := (Cardinal(lRem) shl 16) or (Cardinal(lQuot) and $FFFF);
    SetLogic(Cardinal(lQuot), 2);
  end
  else
  begin
    lSDividend := Integer(lDividend);
    lSDivisor := SmallInt(lSrc);
    lMc := 6;
    if lSDividend < 0 then
      Inc(lMc);
    lQuot := Int64(lSDividend) div lSDivisor;
    if (lQuot > 32767) or (lQuot < -32768) then
    begin
      Inc(FCycles, (lMc + 2) * 2);
      FSR := (FSR and not M68K_CF) or M68K_VF;
      Exit;
    end;
    lAQuot := Cardinal(Abs(Int64(lSDividend))) div Cardinal(Abs(lSDivisor));
    Inc(lMc, 55);
    if lSDivisor >= 0 then
    begin
      if lSDividend >= 0 then
        Dec(lMc)
      else
        Inc(lMc);
    end;
    for i := 0 to 14 do
    begin
      if SmallInt(lAQuot and $FFFF) >= 0 then
        Inc(lMc);
      lAQuot := lAQuot shl 1;
    end;
    Inc(FCycles, lMc * 2);
    lRem := Int64(lSDividend) mod lSDivisor;
    D[lDn] := ((Cardinal(lRem) and $FFFF) shl 16) or (Cardinal(lQuot) and $FFFF);
    SetLogic(Cardinal(lQuot), 2);
  end;
end;

{ groups 8 / C : OR / AND and friends }

procedure TM68000.OpLogic(aOp: Word; aKind: Integer);
var
  lMode, lReg, lDn, lSize, lOpMode: Integer;
  lSrc, lDst, lAddr, lRes: Cardinal;
begin
  lMode := (aOp shr 3) and 7;
  lReg := aOp and 7;
  lDn := (aOp shr 9) and 7;
  lOpMode := (aOp shr 6) and 7;
  if aKind = 0 then
  begin
    if lOpMode = 3 then begin OpDiv(aOp, False); Exit; end;
    if lOpMode = 7 then begin OpDiv(aOp, True); Exit; end;
    if (lOpMode = 4) and (lMode < 2) then begin OpBcd(aOp, True); Exit; end;
  end;
  lSize := SizeOfCode(lOpMode and 3);
  if (lOpMode and 4) = 0 then
  begin
    // <ea>,Dn
    lSrc := ReadEaValue(lMode, lReg, lSize);
    if aKind = 0 then
      lRes := D[lDn] or lSrc
    else
      lRes := D[lDn] and lSrc;
    SetLogic(lRes, lSize);
    SetDReg(lDn, lSize, lRes);
    if lSize = 4 then
    begin
      Inc(FCycles, 6 + EaTime(lMode, lReg, lSize));
      if (lMode < 2) or ((lMode = 7) and (lReg = 4)) then
        Inc(FCycles, 2);
    end
    else
      Inc(FCycles, 4 + EaTime(lMode, lReg, lSize));
  end
  else
  begin
    // Dn,<ea>
    lDst := ReadEa(lMode, lReg, lSize, lAddr);
    if aKind = 0 then
      lRes := D[lDn] or lDst
    else
      lRes := D[lDn] and lDst;
    SetLogic(lRes, lSize);
    WriteBack(lMode, lReg, lSize, lAddr, lRes);
    if lSize = 4 then
      Inc(FCycles, 12 + EaTime(lMode, lReg, lSize))
    else
      Inc(FCycles, 8 + EaTime(lMode, lReg, lSize));
  end;
end;

procedure TM68000.OpGroupC(aOp: Word);
var
  lOpMode, lMode, lRx, lRy: Integer;
  lTmp: Cardinal;
begin
  lOpMode := (aOp shr 6) and 7;
  lMode := (aOp shr 3) and 7;
  lRx := (aOp shr 9) and 7;
  lRy := aOp and 7;
  case lOpMode of
    3: OpMul(aOp, False);
    7: OpMul(aOp, True);
    4:
      if lMode < 2 then
        OpBcd(aOp, False)
      else
        OpLogic(aOp, 1);
    5:
      if lMode = 0 then
      begin
        lTmp := D[lRx]; D[lRx] := D[lRy]; D[lRy] := lTmp;
        Inc(FCycles, 6);
      end
      else if lMode = 1 then
      begin
        lTmp := A[lRx]; A[lRx] := A[lRy]; A[lRy] := lTmp;
        Inc(FCycles, 6);
      end
      else
        OpLogic(aOp, 1);
    6:
      if lMode = 1 then
      begin
        lTmp := D[lRx]; D[lRx] := A[lRy]; A[lRy] := lTmp;
        Inc(FCycles, 6);
      end
      else
        OpLogic(aOp, 1);
  else
    OpLogic(aOp, 1);
  end;
end;

{ groups 9 / D : SUB / ADD and friends }

procedure TM68000.OpAddSub(aOp: Word; aSub: Boolean);
var
  lMode, lReg, lDn, lSize, lOpMode: Integer;
  lSrc, lDst, lAddr, lRes: Cardinal;
begin
  lMode := (aOp shr 3) and 7;
  lReg := aOp and 7;
  lDn := (aOp shr 9) and 7;
  lOpMode := (aOp shr 6) and 7;
  if (lOpMode = 3) or (lOpMode = 7) then
  begin
    // ADDA / SUBA
    if lOpMode = 3 then lSize := 2 else lSize := 4;
    lSrc := ReadEaValue(lMode, lReg, lSize);
    if lSize = 2 then
      lSrc := SignExt16(lSrc);
    if aSub then
      A[lDn] := A[lDn] - lSrc
    else
      A[lDn] := A[lDn] + lSrc;
    if lSize = 2 then
      Inc(FCycles, 8 + EaTime(lMode, lReg, lSize))
    else
    begin
      Inc(FCycles, 6 + EaTime(lMode, lReg, lSize));
      if (lMode < 2) or ((lMode = 7) and (lReg = 4)) then
        Inc(FCycles, 2);
    end;
    Exit;
  end;
  lSize := SizeOfCode(lOpMode and 3);
  if ((lOpMode and 4) <> 0) and (lMode < 2) then
  begin
    // ADDX / SUBX
    if lMode = 0 then
    begin
      if aSub then
        lRes := DoSub(D[lReg], D[lDn], lSize, True, False)
      else
        lRes := DoAdd(D[lReg], D[lDn], lSize, True);
      SetDReg(lDn, lSize, lRes);
      if lSize = 4 then Inc(FCycles, 8) else Inc(FCycles, 4);
    end
    else
    begin
      lSrc := Rd(EaAddress(4, lReg, lSize), lSize);
      lAddr := EaAddress(4, lDn, lSize);
      lDst := Rd(lAddr, lSize);
      if aSub then
        lRes := DoSub(lSrc, lDst, lSize, True, False)
      else
        lRes := DoAdd(lSrc, lDst, lSize, True);
      Wr(lAddr, lSize, lRes);
      if lSize = 4 then Inc(FCycles, 30) else Inc(FCycles, 18);
    end;
    Exit;
  end;
  if (lOpMode and 4) = 0 then
  begin
    // <ea>,Dn
    lSrc := ReadEaValue(lMode, lReg, lSize);
    if aSub then
      lRes := DoSub(lSrc, D[lDn], lSize, False, False)
    else
      lRes := DoAdd(lSrc, D[lDn], lSize, False);
    SetDReg(lDn, lSize, lRes);
    if lSize = 4 then
    begin
      Inc(FCycles, 6 + EaTime(lMode, lReg, lSize));
      if (lMode < 2) or ((lMode = 7) and (lReg = 4)) then
        Inc(FCycles, 2);
    end
    else
      Inc(FCycles, 4 + EaTime(lMode, lReg, lSize));
  end
  else
  begin
    // Dn,<ea>
    lDst := ReadEa(lMode, lReg, lSize, lAddr);
    if aSub then
      lRes := DoSub(D[lDn], lDst, lSize, False, False)
    else
      lRes := DoAdd(D[lDn], lDst, lSize, False);
    WriteBack(lMode, lReg, lSize, lAddr, lRes);
    if lSize = 4 then
      Inc(FCycles, 12 + EaTime(lMode, lReg, lSize))
    else
      Inc(FCycles, 8 + EaTime(lMode, lReg, lSize));
  end;
end;

{ group B : CMP / CMPA / CMPM / EOR }

procedure TM68000.OpGroupB(aOp: Word);
var
  lMode, lReg, lDn, lSize, lOpMode: Integer;
  lSrc, lDst, lAddr, lRes: Cardinal;
begin
  lMode := (aOp shr 3) and 7;
  lReg := aOp and 7;
  lDn := (aOp shr 9) and 7;
  lOpMode := (aOp shr 6) and 7;
  if (lOpMode = 3) or (lOpMode = 7) then
  begin
    // CMPA
    if lOpMode = 3 then lSize := 2 else lSize := 4;
    lSrc := ReadEaValue(lMode, lReg, lSize);
    if lSize = 2 then
      lSrc := SignExt16(lSrc);
    DoSub(lSrc, A[lDn], 4, False, True);
    Inc(FCycles, 6 + EaTime(lMode, lReg, lSize));
    Exit;
  end;
  lSize := SizeOfCode(lOpMode and 3);
  if (lOpMode and 4) = 0 then
  begin
    // CMP
    lSrc := ReadEaValue(lMode, lReg, lSize);
    DoSub(lSrc, D[lDn], lSize, False, True);
    if lSize = 4 then
      Inc(FCycles, 6 + EaTime(lMode, lReg, lSize))
    else
      Inc(FCycles, 4 + EaTime(lMode, lReg, lSize));
  end
  else if lMode = 1 then
  begin
    // CMPM
    lSrc := Rd(EaAddress(3, lReg, lSize), lSize);
    lDst := Rd(EaAddress(3, lDn, lSize), lSize);
    DoSub(lSrc, lDst, lSize, False, True);
    if lSize = 4 then Inc(FCycles, 20) else Inc(FCycles, 12);
  end
  else
  begin
    // EOR
    lDst := ReadEa(lMode, lReg, lSize, lAddr);
    lRes := D[lDn] xor lDst;
    SetLogic(lRes, lSize);
    WriteBack(lMode, lReg, lSize, lAddr, lRes);
    if lMode = 0 then
    begin
      if lSize = 4 then Inc(FCycles, 8) else Inc(FCycles, 4);
    end
    else
    begin
      if lSize = 4 then Inc(FCycles, 12) else Inc(FCycles, 8);
      Inc(FCycles, EaTime(lMode, lReg, lSize));
    end;
  end;
end;

{ group E : shifts and rotates }

/// aKind : 0 AS, 1 LS, 2 ROX, 3 RO. Sets every flag.
function TM68000.ShiftValue(aKind: Integer; aLeft: Boolean; aValue: Cardinal; aCount, aSize: Integer): Cardinal;
var
  lMask, lMsb, lBit, lX: Cardinal;
  lC, lV: Boolean;
  i: Integer;
  lSR: Word;
begin
  lMask := CMask[aSize];
  lMsb := CMsb[aSize];
  aValue := aValue and lMask;
  lC := False;
  lV := False;
  lX := 0;
  if (FSR and M68K_XF) <> 0 then
    lX := 1;
  for i := 1 to aCount do
  begin
    if aLeft then
    begin
      lBit := Ord((aValue and lMsb) <> 0);
      case aKind of
        0, 1: aValue := (aValue shl 1) and lMask;
        2: aValue := ((aValue shl 1) or lX) and lMask;
      else
        aValue := ((aValue shl 1) or lBit) and lMask;
      end;
      if (aKind = 0) and ((Ord((aValue and lMsb) <> 0)) <> lBit) then
        lV := True;
    end
    else
    begin
      lBit := aValue and 1;
      case aKind of
        0: aValue := (aValue shr 1) or (aValue and lMsb);
        1: aValue := aValue shr 1;
        2: aValue := (aValue shr 1) or (lX * lMsb);
      else
        aValue := (aValue shr 1) or (lBit * lMsb);
      end;
    end;
    lC := lBit <> 0;
    if aKind <> 3 then
      lX := lBit;
  end;
  lSR := FSR and not (M68K_NF or M68K_ZF or M68K_VF or M68K_CF);
  if aCount = 0 then
  begin
    if (aKind = 2) and (lX <> 0) then
      lSR := lSR or M68K_CF;
  end
  else
  begin
    if lC then
      lSR := lSR or M68K_CF;
    if aKind <> 3 then
    begin
      if lX <> 0 then
        lSR := lSR or M68K_XF
      else
        lSR := lSR and not M68K_XF;
    end;
  end;
  if lV then
    lSR := lSR or M68K_VF;
  if aValue = 0 then
    lSR := lSR or M68K_ZF;
  if (aValue and lMsb) <> 0 then
    lSR := lSR or M68K_NF;
  FSR := lSR;
  Result := aValue;
end;

procedure TM68000.OpShift(aOp: Word);
var
  lMode, lReg, lSize, lKind, lCount: Integer;
  lAddr, lValue: Cardinal;
  lLeft: Boolean;
begin
  lLeft := (aOp and $0100) <> 0;
  lReg := aOp and 7;
  if ((aOp shr 6) and 3) = 3 then
  begin
    // memory, word, one bit
    if (aOp and $0800) <> 0 then
    begin
      Illegal;
      Exit;
    end;
    lMode := (aOp shr 3) and 7;
    lKind := (aOp shr 9) and 3;
    lValue := ReadEa(lMode, lReg, 2, lAddr);
    lValue := ShiftValue(lKind, lLeft, lValue, 1, 2);
    Wr16(lAddr, lValue);
    Inc(FCycles, 8 + EaTime(lMode, lReg, 2));
    Exit;
  end;
  lSize := SizeOfCode((aOp shr 6) and 3);
  lKind := (aOp shr 3) and 3;
  if (aOp and $0020) <> 0 then
    lCount := D[(aOp shr 9) and 7] and 63
  else
  begin
    lCount := (aOp shr 9) and 7;
    if lCount = 0 then
      lCount := 8;
  end;
  lValue := ShiftValue(lKind, lLeft, D[lReg], lCount, lSize);
  SetDReg(lReg, lSize, lValue);
  if lSize = 4 then
    Inc(FCycles, 8 + 2 * lCount)
  else
    Inc(FCycles, 6 + 2 * lCount);
end;

end.
