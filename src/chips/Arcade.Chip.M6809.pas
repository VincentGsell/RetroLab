unit Arcade.Chip.M6809;

///  Motorola MC6809 CPU core - full documented instruction set (pages 0, 2 and 3), every indexed
///  addressing mode, IRQ / FIRQ / NMI, SWI / SWI2 / SWI3, CWAI, SYNC.
///    - cycle counts per instruction from the Motorola datasheet, indexed modes included
///    - undefined page 0 opcodes alias their documented neighbours, as on the chip
///    - E clock : the board feeds this core the E clock (MC6809 crystal / 4)
///  Pure unit, no dependency : FPC compatible (no inline var, no generics).
///  Generic : the machine wires memory through events, as for Arcade.Chip.Z80.

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}
{$Q-}
{$R-}

interface

type
  TM6809ReadEvent = function(aAddr: Word): Byte of object;
  TM6809WriteEvent = procedure(aAddr: Word; aValue: Byte) of object;

  TM6809 = class
  private
    FCycles: Integer;          // cycles of the current Step
    FIrqPending, FFirqPending, FNmiPending: Boolean;
    FNmiArmed: Boolean;        // NMI is ignored until S has been loaded once
    FCwai, FSync: Boolean;
    function Rd(aAddr: Word): Byte; inline;
    procedure Wr(aAddr: Word; aValue: Byte); inline;
    function Rd16(aAddr: Word): Word;
    procedure Wr16(aAddr: Word; aValue: Word);
    function Fetch: Byte; inline;
    function Fetch16: Word;
    function GetD: Word; inline;
    procedure SetD(aValue: Word); inline;
    procedure PushS(aValue: Byte); inline;
    function PullS: Byte; inline;
    procedure PushU(aValue: Byte); inline;
    function PullU: Byte; inline;
    procedure PushS16(aValue: Word);
    function PullS16: Word;
    procedure PushAll;
    procedure SetNZ8(aValue: Byte); inline;
    procedure SetNZ16(aValue: Word); inline;
    function Indexed: Word;
    function EaDirect: Word; inline;
    function EaExtended: Word; inline;
    function Ea(aMode: Integer): Word;
    function Operand8(aMode: Integer): Byte;
    function Operand16(aMode: Integer): Word;
    function RegPtr16(aCode: Integer): PWord;
    function ReadReg(aCode: Integer): Word;
    procedure WriteReg(aCode: Integer; aValue: Word);
    function Add8(aA, aB, aCarry: Byte): Byte;
    function Sub8(aA, aB, aCarry: Byte): Byte;
    function Add16(aA, aB: Word): Word;
    function Sub16(aA, aB: Word): Word;
    function Unary(aOp: Integer; aValue: Byte): Byte;
    function Condition(aCode: Integer): Boolean;
    procedure PshReg(aMask: Byte; aUser: Boolean);
    procedure PulReg(aMask: Byte; aUser: Boolean);
    procedure Interrupt(aVector: Word; aFull: Boolean; aMaskF: Boolean);
    procedure ExecPage0(aOp: Byte);
    procedure ExecPage2(aOp: Byte);
    procedure ExecPage3(aOp: Byte);
  public
    A, B, DP, CC: Byte;
    X, Y, U, S, PC: Word;
    /// Total E cycles since Reset.
    Cycles: Int64;
    OnRead: TM6809ReadEvent;
    OnWrite: TM6809WriteEvent;
    procedure Reset;
    /// Executes one instruction (or takes a pending interrupt). Returns the E cycles spent.
    function Step: Integer;
    /// Maskable interrupt, MAME HOLD_LINE semantics : stays pending until accepted.
    procedure RaiseIrq;
    procedure ClearIrq;
    procedure RaiseFirq;
    procedure RaiseNmi;
    property D: Word read GetD write SetD;
    property IrqPending: Boolean read FIrqPending;
  end;

const
  M6809_CF = $01;
  M6809_VF = $02;
  M6809_ZF = $04;
  M6809_NF = $08;
  M6809_IF = $10;
  M6809_HF = $20;
  M6809_FF = $40;
  M6809_EF = $80;

implementation

const
  // addressing modes of the $80-$FF register / memory groups
  M_IMM = 0;
  M_DIR = 1;
  M_IDX = 2;
  M_EXT = 3;

{ memory }

function TM6809.Rd(aAddr: Word): Byte;
begin
  Result := OnRead(aAddr);
end;

procedure TM6809.Wr(aAddr: Word; aValue: Byte);
begin
  OnWrite(aAddr, aValue);
end;

function TM6809.Rd16(aAddr: Word): Word;
begin
  Result := (Rd(aAddr) shl 8) or Rd(Word(aAddr + 1));
end;

procedure TM6809.Wr16(aAddr: Word; aValue: Word);
begin
  Wr(aAddr, aValue shr 8);
  Wr(Word(aAddr + 1), aValue and $FF);
end;

function TM6809.Fetch: Byte;
begin
  Result := Rd(PC);
  PC := Word(PC + 1);
end;

function TM6809.Fetch16: Word;
begin
  Result := Fetch shl 8;
  Result := Result or Fetch;
end;

function TM6809.GetD: Word;
begin
  Result := (A shl 8) or B;
end;

procedure TM6809.SetD(aValue: Word);
begin
  A := aValue shr 8;
  B := aValue and $FF;
end;

procedure TM6809.PushS(aValue: Byte);
begin
  S := Word(S - 1);
  Wr(S, aValue);
end;

function TM6809.PullS: Byte;
begin
  Result := Rd(S);
  S := Word(S + 1);
end;

procedure TM6809.PushU(aValue: Byte);
begin
  U := Word(U - 1);
  Wr(U, aValue);
end;

function TM6809.PullU: Byte;
begin
  Result := Rd(U);
  U := Word(U + 1);
end;

procedure TM6809.PushS16(aValue: Word);
begin
  PushS(aValue and $FF);
  PushS(aValue shr 8);
end;

function TM6809.PullS16: Word;
begin
  Result := PullS shl 8;
  Result := Result or PullS;
end;

// Whole state, as for IRQ, NMI, SWI and CWAI : PC, U, Y, X, DP, B, A, CC.
procedure TM6809.PushAll;
begin
  PushS16(PC);
  PushS16(U);
  PushS16(Y);
  PushS16(X);
  PushS(DP);
  PushS(B);
  PushS(A);
  PushS(CC);
end;

{ flags }

procedure TM6809.SetNZ8(aValue: Byte);
begin
  CC := CC and not (M6809_NF or M6809_ZF);
  if aValue = 0 then
    CC := CC or M6809_ZF;
  if (aValue and $80) <> 0 then
    CC := CC or M6809_NF;
end;

procedure TM6809.SetNZ16(aValue: Word);
begin
  CC := CC and not (M6809_NF or M6809_ZF);
  if aValue = 0 then
    CC := CC or M6809_ZF;
  if (aValue and $8000) <> 0 then
    CC := CC or M6809_NF;
end;

{ addressing }

function TM6809.EaDirect: Word;
begin
  Result := (DP shl 8) or Fetch;
end;

function TM6809.EaExtended: Word;
begin
  Result := Fetch16;
end;

// Indexed postbyte : effective address, and the extra cycles of the mode (datasheet table).
function TM6809.Indexed: Word;
var
  lPost: Byte;
  lReg: PWord;
  lOfs: Integer;
begin
  lPost := Fetch;
  case (lPost shr 5) and 3 of
    0: lReg := @X;
    1: lReg := @Y;
    2: lReg := @U;
  else
    lReg := @S;
  end;
  if (lPost and $80) = 0 then
  begin
    // ,R with a 5-bit signed offset
    lOfs := lPost and $1F;
    if lOfs >= 16 then
      Dec(lOfs, 32);
    Inc(FCycles, 1);
    Exit(Word(lReg^ + lOfs));
  end;
  case lPost and $0F of
    $0:
      begin                                   // ,R+
        Result := lReg^;
        lReg^ := Word(lReg^ + 1);
        Inc(FCycles, 2);
      end;
    $1:
      begin                                   // ,R++
        Result := lReg^;
        lReg^ := Word(lReg^ + 2);
        Inc(FCycles, 3);
      end;
    $2:
      begin                                   // ,-R
        lReg^ := Word(lReg^ - 1);
        Result := lReg^;
        Inc(FCycles, 2);
      end;
    $3:
      begin                                   // ,--R
        lReg^ := Word(lReg^ - 2);
        Result := lReg^;
        Inc(FCycles, 3);
      end;
    $4: Result := lReg^;                      // ,R
    $5:
      begin                                   // B,R
        Result := Word(lReg^ + ShortInt(B));
        Inc(FCycles, 1);
      end;
    $6:
      begin                                   // A,R
        Result := Word(lReg^ + ShortInt(A));
        Inc(FCycles, 1);
      end;
    $8:
      begin                                   // n8,R
        Result := Word(lReg^ + ShortInt(Fetch));
        Inc(FCycles, 1);
      end;
    $9:
      begin                                   // n16,R
        Result := Word(lReg^ + Fetch16);
        Inc(FCycles, 4);
      end;
    $B:
      begin                                   // D,R
        Result := Word(lReg^ + GetD);
        Inc(FCycles, 4);
      end;
    $C:
      begin                                   // n8,PC
        lOfs := ShortInt(Fetch);
        Result := Word(PC + lOfs);
        Inc(FCycles, 1);
      end;
    $D:
      begin                                   // n16,PC
        lOfs := SmallInt(Fetch16);
        Result := Word(PC + lOfs);
        Inc(FCycles, 5);
      end;
    $F:
      begin                                   // [n16] (only legal as indirect)
        Result := Fetch16;
        Inc(FCycles, 2);
      end;
  else
    Result := lReg^;                          // $7, $A, $E : undefined, treated as ,R
  end;
  if (lPost and $10) <> 0 then
  begin
    Result := Rd16(Result);                   // indirect
    Inc(FCycles, 3);
  end;
end;

function TM6809.Ea(aMode: Integer): Word;
begin
  case aMode of
    M_DIR: Result := EaDirect;
    M_IDX: Result := Indexed;
  else
    Result := EaExtended;
  end;
end;

function TM6809.Operand8(aMode: Integer): Byte;
begin
  if aMode = M_IMM then
    Result := Fetch
  else
    Result := Rd(Ea(aMode));
end;

function TM6809.Operand16(aMode: Integer): Word;
begin
  if aMode = M_IMM then
    Result := Fetch16
  else
    Result := Rd16(Ea(aMode));
end;

{ TFR / EXG register codes }

function TM6809.RegPtr16(aCode: Integer): PWord;
begin
  case aCode of
    1: Result := @X;
    2: Result := @Y;
    3: Result := @U;
    4: Result := @S;
    5: Result := @PC;
  else
    Result := nil;
  end;
end;

function TM6809.ReadReg(aCode: Integer): Word;
begin
  case aCode of
    0: Result := GetD;
    1..5: Result := RegPtr16(aCode)^;
    8: Result := $FF00 or A;
    9: Result := $FF00 or B;
    10: Result := $FF00 or CC;
    11: Result := $FF00 or DP;
  else
    Result := $FFFF;
  end;
end;

procedure TM6809.WriteReg(aCode: Integer; aValue: Word);
begin
  case aCode of
    0: SetD(aValue);
    1..3, 5: RegPtr16(aCode)^ := aValue;
    4:
      begin
        S := aValue;
        FNmiArmed := True;
      end;
    8: A := aValue and $FF;
    9: B := aValue and $FF;
    10: CC := aValue and $FF;
    11: DP := aValue and $FF;
  end;
end;

{ arithmetic }

function TM6809.Add8(aA, aB, aCarry: Byte): Byte;
var
  lSum: Integer;
begin
  lSum := aA + aB + aCarry;
  Result := lSum and $FF;
  CC := CC and not (M6809_HF or M6809_NF or M6809_ZF or M6809_VF or M6809_CF);
  if ((aA xor aB xor Result) and $10) <> 0 then
    CC := CC or M6809_HF;
  if lSum > $FF then
    CC := CC or M6809_CF;
  if ((aA xor Result) and (aB xor Result) and $80) <> 0 then
    CC := CC or M6809_VF;
  if Result = 0 then
    CC := CC or M6809_ZF;
  if (Result and $80) <> 0 then
    CC := CC or M6809_NF;
end;

function TM6809.Sub8(aA, aB, aCarry: Byte): Byte;
var
  lDiff: Integer;
begin
  lDiff := aA - aB - aCarry;
  Result := lDiff and $FF;
  CC := CC and not (M6809_NF or M6809_ZF or M6809_VF or M6809_CF);
  if lDiff < 0 then
    CC := CC or M6809_CF;
  if ((aA xor aB) and (aA xor Result) and $80) <> 0 then
    CC := CC or M6809_VF;
  if Result = 0 then
    CC := CC or M6809_ZF;
  if (Result and $80) <> 0 then
    CC := CC or M6809_NF;
end;

function TM6809.Add16(aA, aB: Word): Word;
var
  lSum: Integer;
begin
  lSum := aA + aB;
  Result := lSum and $FFFF;
  CC := CC and not (M6809_NF or M6809_ZF or M6809_VF or M6809_CF);
  if lSum > $FFFF then
    CC := CC or M6809_CF;
  if ((aA xor Result) and (aB xor Result) and $8000) <> 0 then
    CC := CC or M6809_VF;
  if Result = 0 then
    CC := CC or M6809_ZF;
  if (Result and $8000) <> 0 then
    CC := CC or M6809_NF;
end;

function TM6809.Sub16(aA, aB: Word): Word;
var
  lDiff: Integer;
begin
  lDiff := aA - aB;
  Result := lDiff and $FFFF;
  CC := CC and not (M6809_NF or M6809_ZF or M6809_VF or M6809_CF);
  if lDiff < 0 then
    CC := CC or M6809_CF;
  if ((aA xor aB) and (aA xor Result) and $8000) <> 0 then
    CC := CC or M6809_VF;
  if Result = 0 then
    CC := CC or M6809_ZF;
  if (Result and $8000) <> 0 then
    CC := CC or M6809_NF;
end;

// Single-operand group, low nibble of the opcode : NEG COM LSR ROR ASR ASL ROL DEC INC TST CLR.
function TM6809.Unary(aOp: Integer; aValue: Byte): Byte;
var
  lCarry: Byte;
begin
  case aOp of
    $0, $1, $2:
      begin                                                    // NEG (1, 2 : undefined aliases)
        Result := Sub8(0, aValue, 0);
      end;
    $3:
      begin                                                    // COM
        Result := not aValue;
        SetNZ8(Result);
        CC := (CC and not M6809_VF) or M6809_CF;
      end;
    $4, $5:
      begin                                                    // LSR (5 : alias)
        CC := CC and not (M6809_CF or M6809_NF or M6809_ZF);
        if (aValue and 1) <> 0 then
          CC := CC or M6809_CF;
        Result := aValue shr 1;
        if Result = 0 then
          CC := CC or M6809_ZF;
      end;
    $6:
      begin                                                    // ROR
        lCarry := CC and M6809_CF;
        CC := CC and not M6809_CF;
        if (aValue and 1) <> 0 then
          CC := CC or M6809_CF;
        Result := (aValue shr 1) or (lCarry shl 7);
        SetNZ8(Result);
      end;
    $7:
      begin                                                    // ASR
        CC := CC and not M6809_CF;
        if (aValue and 1) <> 0 then
          CC := CC or M6809_CF;
        Result := (aValue shr 1) or (aValue and $80);
        SetNZ8(Result);
      end;
    $8:
      begin                                                    // ASL / LSL
        CC := CC and not (M6809_CF or M6809_VF);
        if (aValue and $80) <> 0 then
          CC := CC or M6809_CF;
        if ((aValue xor (aValue shl 1)) and $80) <> 0 then
          CC := CC or M6809_VF;
        Result := (aValue shl 1) and $FF;
        SetNZ8(Result);
      end;
    $9:
      begin                                                    // ROL
        lCarry := CC and M6809_CF;
        CC := CC and not (M6809_CF or M6809_VF);
        if (aValue and $80) <> 0 then
          CC := CC or M6809_CF;
        if ((aValue xor (aValue shl 1)) and $80) <> 0 then
          CC := CC or M6809_VF;
        Result := ((aValue shl 1) or lCarry) and $FF;
        SetNZ8(Result);
      end;
    $A, $B:
      begin                                                    // DEC (B : alias)
        Result := Byte(aValue - 1);
        CC := CC and not M6809_VF;
        if aValue = $80 then
          CC := CC or M6809_VF;
        SetNZ8(Result);
      end;
    $C:
      begin                                                    // INC
        Result := Byte(aValue + 1);
        CC := CC and not M6809_VF;
        if aValue = $7F then
          CC := CC or M6809_VF;
        SetNZ8(Result);
      end;
    $D:
      begin                                                    // TST
        Result := aValue;
        SetNZ8(Result);
        CC := CC and not M6809_VF;
      end;
  else
    begin                                                      // CLR ($F ; $E is JMP, never here)
      Result := 0;
      CC := (CC and not (M6809_NF or M6809_VF or M6809_CF)) or M6809_ZF;
    end;
  end;
end;

function TM6809.Condition(aCode: Integer): Boolean;
var
  lN, lV: Boolean;
begin
  lN := (CC and M6809_NF) <> 0;
  lV := (CC and M6809_VF) <> 0;
  case aCode of
    $0: Result := True;                                                        // BRA
    $1: Result := False;                                                       // BRN
    $2: Result := (CC and (M6809_CF or M6809_ZF)) = 0;                         // BHI
    $3: Result := (CC and (M6809_CF or M6809_ZF)) <> 0;                        // BLS
    $4: Result := (CC and M6809_CF) = 0;                                       // BCC
    $5: Result := (CC and M6809_CF) <> 0;                                      // BCS
    $6: Result := (CC and M6809_ZF) = 0;                                       // BNE
    $7: Result := (CC and M6809_ZF) <> 0;                                      // BEQ
    $8: Result := not lV;                                                      // BVC
    $9: Result := lV;                                                          // BVS
    $A: Result := not lN;                                                      // BPL
    $B: Result := lN;                                                          // BMI
    $C: Result := lN = lV;                                                     // BGE
    $D: Result := lN <> lV;                                                    // BLT
    $E: Result := ((CC and M6809_ZF) = 0) and (lN = lV);                       // BGT
  else
    Result := ((CC and M6809_ZF) <> 0) or (lN <> lV);                          // BLE
  end;
end;

{ stack instructions : postbyte bits CC A B DP X Y U/S PC, one cycle per byte moved }

procedure TM6809.PshReg(aMask: Byte; aUser: Boolean);

  procedure P8(aValue: Byte);
  begin
    if aUser then PushU(aValue) else PushS(aValue);
    Inc(FCycles);
  end;

  procedure P16(aValue: Word);
  begin
    P8(aValue and $FF);
    P8(aValue shr 8);
  end;

begin
  if (aMask and $80) <> 0 then P16(PC);
  if (aMask and $40) <> 0 then
    if aUser then P16(S) else P16(U);
  if (aMask and $20) <> 0 then P16(Y);
  if (aMask and $10) <> 0 then P16(X);
  if (aMask and $08) <> 0 then P8(DP);
  if (aMask and $04) <> 0 then P8(B);
  if (aMask and $02) <> 0 then P8(A);
  if (aMask and $01) <> 0 then P8(CC);
end;

procedure TM6809.PulReg(aMask: Byte; aUser: Boolean);

  function L8: Byte;
  begin
    if aUser then Result := PullU else Result := PullS;
    Inc(FCycles);
  end;

  function L16: Word;
  begin
    Result := L8 shl 8;
    Result := Result or L8;
  end;

begin
  if (aMask and $01) <> 0 then CC := L8;
  if (aMask and $02) <> 0 then A := L8;
  if (aMask and $04) <> 0 then B := L8;
  if (aMask and $08) <> 0 then DP := L8;
  if (aMask and $10) <> 0 then X := L16;
  if (aMask and $20) <> 0 then Y := L16;
  if (aMask and $40) <> 0 then
    if aUser then
    begin
      S := L16;
      FNmiArmed := True;
    end
    else
      U := L16;
  if (aMask and $80) <> 0 then PC := L16;
end;

{ interrupts }

procedure TM6809.Interrupt(aVector: Word; aFull: Boolean; aMaskF: Boolean);
begin
  if FCwai then
    FCwai := False                         // CWAI already stacked everything
  else if aFull then
  begin
    CC := CC or M6809_EF;
    PushAll;
  end
  else
  begin
    CC := CC and not M6809_EF;
    PushS16(PC);
    PushS(CC);
  end;
  CC := CC or M6809_IF;
  if aMaskF then
    CC := CC or M6809_FF;
  PC := Rd16(aVector);
end;

procedure TM6809.RaiseIrq;
begin
  FIrqPending := True;
end;

procedure TM6809.ClearIrq;
begin
  FIrqPending := False;
end;

procedure TM6809.RaiseFirq;
begin
  FFirqPending := True;
end;

procedure TM6809.RaiseNmi;
begin
  if FNmiArmed then
    FNmiPending := True;
end;

procedure TM6809.Reset;
begin
  A := 0;
  B := 0;
  X := 0;
  Y := 0;
  U := 0;
  S := 0;
  DP := 0;
  CC := M6809_IF or M6809_FF;
  FIrqPending := False;
  FFirqPending := False;
  FNmiPending := False;
  FNmiArmed := False;
  FCwai := False;
  FSync := False;
  Cycles := 0;
  PC := Rd16($FFFE);
end;

function TM6809.Step: Integer;
var
  lOp: Byte;
begin
  FCycles := 0;
  if FNmiPending then
  begin
    FNmiPending := False;
    FSync := False;
    Interrupt($FFFC, True, True);
    FCycles := 19;
  end
  else if FFirqPending and ((CC and M6809_FF) = 0) then
  begin
    FFirqPending := False;
    FSync := False;
    Interrupt($FFF6, False, True);
    FCycles := 10;
  end
  else if FIrqPending and ((CC and M6809_IF) = 0) then
  begin
    FIrqPending := False;                  // HOLD_LINE : acknowledged when taken
    FSync := False;
    Interrupt($FFF8, True, False);
    FCycles := 19;
  end
  else if FCwai or FSync then
  begin
    if FSync and (FIrqPending or FFirqPending) then
      FSync := False;                      // SYNC ends on a masked interrupt too, without taking it
    FCycles := 1;
  end
  else
  begin
    lOp := Fetch;
    ExecPage0(lOp);
  end;
  Inc(Cycles, FCycles);
  Result := FCycles;
end;

procedure TM6809.ExecPage0(aOp: Byte);
var
  lEa, lW: Word;
  lV, lPost: Byte;
  lMode, lCode, lSrc, lDst: Integer;
  lMul: Word;
  lLow, lHigh: Byte;
begin
  case aOp of
    $00..$0F, $40..$4F, $50..$5F, $60..$6F, $70..$7F:
      begin
        lCode := aOp and $0F;
        if (aOp shr 4) in [4, 5] then
        begin
          FCycles := 2;
          if (aOp shr 4) = 4 then
            A := Unary(lCode, A)
          else
            B := Unary(lCode, B);
          Exit;
        end;
        case aOp shr 4 of
          0: begin lEa := EaDirect; FCycles := FCycles + 6; end;
          6: begin lEa := Indexed; FCycles := FCycles + 6; end;
        else
          begin lEa := EaExtended; FCycles := FCycles + 7; end;
        end;
        if lCode = $E then
        begin                                                    // JMP
          PC := lEa;
          Dec(FCycles, 3);
          Exit;
        end;
        if lCode = $D then
        begin
          Unary($D, Rd(lEa));                                    // TST : no write back
          Exit;
        end;
        Wr(lEa, Unary(lCode, Rd(lEa)));
      end;

    $10: ExecPage2(Fetch);
    $11: ExecPage3(Fetch);
    $12: FCycles := 2;                                           // NOP
    $13:
      begin                                                      // SYNC
        FSync := True;
        FCycles := 4;
      end;
    $16:
      begin                                                      // LBRA
        lW := Fetch16;
        PC := Word(PC + lW);
        FCycles := 5;
      end;
    $17:
      begin                                                      // LBSR
        lW := Fetch16;
        PushS16(PC);
        PC := Word(PC + lW);
        FCycles := 9;
      end;
    $19:
      begin                                                      // DAA
        lLow := A and $0F;
        lHigh := A shr 4;
        lV := 0;
        if (lLow > 9) or ((CC and M6809_HF) <> 0) then
          lV := lV or $06;
        if (lHigh > 9) or ((CC and M6809_CF) <> 0) or ((lHigh > 8) and (lLow > 9)) then
          lV := lV or $60;
        lW := A + lV;
        A := lW and $FF;
        SetNZ8(A);
        if lW > $FF then
          CC := CC or M6809_CF;
        FCycles := 2;
      end;
    $1A: begin CC := CC or Fetch; FCycles := 3; end;             // ORCC
    $1C: begin CC := CC and Fetch; FCycles := 3; end;            // ANDCC
    $1D:
      begin                                                      // SEX
        if (B and $80) <> 0 then A := $FF else A := 0;
        SetNZ16(GetD);
        FCycles := 2;
      end;
    $1E:
      begin                                                      // EXG
        lPost := Fetch;
        lSrc := lPost shr 4;
        lDst := lPost and $0F;
        lW := ReadReg(lSrc);
        WriteReg(lSrc, ReadReg(lDst));
        WriteReg(lDst, lW);
        FCycles := 8;
      end;
    $1F:
      begin                                                      // TFR
        lPost := Fetch;
        WriteReg(lPost and $0F, ReadReg(lPost shr 4));
        FCycles := 6;
      end;
    $20..$2F:
      begin                                                      // short branches
        lV := Fetch;
        if Condition(aOp and $0F) then
          PC := Word(PC + ShortInt(lV));
        FCycles := 3;
      end;
    $30..$33:
      begin                                                      // LEAX LEAY LEAS LEAU
        lEa := Indexed;
        case aOp of
          $30: begin X := lEa; CC := CC and not M6809_ZF; if X = 0 then CC := CC or M6809_ZF; end;
          $31: begin Y := lEa; CC := CC and not M6809_ZF; if Y = 0 then CC := CC or M6809_ZF; end;
          $32: begin S := lEa; FNmiArmed := True; end;
        else
          U := lEa;
        end;
        Inc(FCycles, 4);
      end;
    $34: begin lPost := Fetch; PshReg(lPost, False); Inc(FCycles, 5); end;   // PSHS
    $35: begin lPost := Fetch; PulReg(lPost, False); Inc(FCycles, 5); end;   // PULS
    $36: begin lPost := Fetch; PshReg(lPost, True); Inc(FCycles, 5); end;    // PSHU
    $37: begin lPost := Fetch; PulReg(lPost, True); Inc(FCycles, 5); end;    // PULU
    $39: begin PC := PullS16; FCycles := 5; end;                // RTS
    $3A: begin X := Word(X + B); FCycles := 3; end;             // ABX
    $3B:
      begin                                                      // RTI
        CC := PullS;
        if (CC and M6809_EF) <> 0 then
        begin
          A := PullS;
          B := PullS;
          DP := PullS;
          X := PullS16;
          Y := PullS16;
          U := PullS16;
          FCycles := 15;
        end
        else
          FCycles := 6;
        PC := PullS16;
      end;
    $3C:
      begin                                                      // CWAI
        CC := CC and Fetch;
        CC := CC or M6809_EF;
        PushAll;
        FCwai := True;
        FCycles := 20;
      end;
    $3D:
      begin                                                      // MUL
        lMul := A * B;
        SetD(lMul);
        CC := CC and not (M6809_ZF or M6809_CF);
        if lMul = 0 then CC := CC or M6809_ZF;
        if (lMul and $80) <> 0 then CC := CC or M6809_CF;
        FCycles := 11;
      end;
    $3F:
      begin                                                      // SWI
        CC := CC or M6809_EF;
        PushAll;
        CC := CC or M6809_IF or M6809_FF;
        PC := Rd16($FFFA);
        FCycles := 19;
      end;
    $8D:
      begin                                                      // BSR
        lV := Fetch;
        PushS16(PC);
        PC := Word(PC + ShortInt(lV));
        FCycles := 7;
      end;
    $80..$8C, $8E..$FF:
      begin
        lMode := (aOp shr 4) and 3;
        lCode := aOp and $0F;
        case lMode of
          M_IMM: FCycles := 2;
          M_DIR: FCycles := 4;
          M_IDX: FCycles := 4;
        else
          FCycles := 5;
        end;
        if aOp < $C0 then
          case lCode of
            $0: A := Sub8(A, Operand8(lMode), 0);                                          // SUBA
            $1: Sub8(A, Operand8(lMode), 0);                                               // CMPA
            $2: A := Sub8(A, Operand8(lMode), CC and M6809_CF);                            // SBCA
            $3: begin SetD(Sub16(GetD, Operand16(lMode))); Inc(FCycles, 2); end;          // SUBD
            $4: begin A := A and Operand8(lMode); SetNZ8(A); CC := CC and not M6809_VF; end;  // ANDA
            $5: begin SetNZ8(A and Operand8(lMode)); CC := CC and not M6809_VF; end;       // BITA
            $6: begin A := Operand8(lMode); SetNZ8(A); CC := CC and not M6809_VF; end;     // LDA
            $7: begin Wr(Ea(lMode), A); SetNZ8(A); CC := CC and not M6809_VF; end;        // STA
            $8: begin A := A xor Operand8(lMode); SetNZ8(A); CC := CC and not M6809_VF; end;  // EORA
            $9: A := Add8(A, Operand8(lMode), CC and M6809_CF);                            // ADCA
            $A: begin A := A or Operand8(lMode); SetNZ8(A); CC := CC and not M6809_VF; end;   // ORA
            $B: A := Add8(A, Operand8(lMode), 0);                                          // ADDA
            $C: begin Sub16(X, Operand16(lMode)); Inc(FCycles, 2); end;                    // CMPX
            $D:
              begin                                                                        // JSR
                lEa := Ea(lMode);
                PushS16(PC);
                PC := lEa;
                Inc(FCycles, 3);
              end;
            $E: begin X := Operand16(lMode); SetNZ16(X); CC := CC and not M6809_VF; Inc(FCycles); end;  // LDX
          else
            begin Wr16(Ea(lMode), X); SetNZ16(X); CC := CC and not M6809_VF; Inc(FCycles); end;        // STX
          end
        else
          case lCode of
            $0: B := Sub8(B, Operand8(lMode), 0);                                          // SUBB
            $1: Sub8(B, Operand8(lMode), 0);                                               // CMPB
            $2: B := Sub8(B, Operand8(lMode), CC and M6809_CF);                            // SBCB
            $3: begin SetD(Add16(GetD, Operand16(lMode))); Inc(FCycles, 2); end;          // ADDD
            $4: begin B := B and Operand8(lMode); SetNZ8(B); CC := CC and not M6809_VF; end;  // ANDB
            $5: begin SetNZ8(B and Operand8(lMode)); CC := CC and not M6809_VF; end;       // BITB
            $6: begin B := Operand8(lMode); SetNZ8(B); CC := CC and not M6809_VF; end;     // LDB
            $7: begin Wr(Ea(lMode), B); SetNZ8(B); CC := CC and not M6809_VF; end;        // STB
            $8: begin B := B xor Operand8(lMode); SetNZ8(B); CC := CC and not M6809_VF; end;  // EORB
            $9: B := Add8(B, Operand8(lMode), CC and M6809_CF);                            // ADCB
            $A: begin B := B or Operand8(lMode); SetNZ8(B); CC := CC and not M6809_VF; end;   // ORB
            $B: B := Add8(B, Operand8(lMode), 0);                                          // ADDB
            $C: begin SetD(Operand16(lMode)); SetNZ16(GetD); CC := CC and not M6809_VF; Inc(FCycles); end;  // LDD
            $D: begin Wr16(Ea(lMode), GetD); SetNZ16(GetD); CC := CC and not M6809_VF; Inc(FCycles); end;  // STD
            $E: begin U := Operand16(lMode); SetNZ16(U); CC := CC and not M6809_VF; Inc(FCycles); end;     // LDU
          else
            begin Wr16(Ea(lMode), U); SetNZ16(U); CC := CC and not M6809_VF; Inc(FCycles); end;           // STU
          end;
      end;
  else
    FCycles := 2;                                                // undefined : behaves as a 2-cycle no-op
  end;
end;

procedure TM6809.ExecPage2(aOp: Byte);
var
  lW: Word;
  lMode: Integer;
begin
  case aOp of
    $21..$2F:
      begin                                                      // long branches
        lW := Fetch16;
        FCycles := 5;
        if Condition(aOp and $0F) then
        begin
          PC := Word(PC + lW);
          Inc(FCycles);
        end;
      end;
    $3F:
      begin                                                      // SWI2
        CC := CC or M6809_EF;
        PushAll;
        PC := Rd16($FFF4);
        FCycles := 20;
      end;
    $83, $93, $A3, $B3, $8C, $9C, $AC, $BC:
      begin                                                      // CMPD, CMPY
        lMode := (aOp shr 4) and 3;
        case lMode of
          M_IMM: FCycles := 5;
          M_DIR: FCycles := 7;
          M_IDX: FCycles := 7;
        else
          FCycles := 8;
        end;
        if (aOp and $0F) = $3 then
          Sub16(GetD, Operand16(lMode))
        else
          Sub16(Y, Operand16(lMode));
      end;
    $8E, $9E, $AE, $BE, $CE, $DE, $EE, $FE:
      begin                                                      // LDY, LDS
        lMode := (aOp shr 4) and 3;
        case lMode of
          M_IMM: FCycles := 4;
          M_DIR: FCycles := 6;
          M_IDX: FCycles := 6;
        else
          FCycles := 7;
        end;
        lW := Operand16(lMode);
        if aOp < $C0 then
          Y := lW
        else
        begin
          S := lW;
          FNmiArmed := True;
        end;
        SetNZ16(lW);
        CC := CC and not M6809_VF;
      end;
    $9F, $AF, $BF, $DF, $EF, $FF:
      begin                                                      // STY, STS
        lMode := (aOp shr 4) and 3;
        if lMode = M_EXT then FCycles := 7 else FCycles := 6;
        if aOp < $C0 then
          lW := Y
        else
          lW := S;
        Wr16(Ea(lMode), lW);
        SetNZ16(lW);
        CC := CC and not M6809_VF;
      end;
  else
    FCycles := 2;
  end;
end;

procedure TM6809.ExecPage3(aOp: Byte);
var
  lMode: Integer;
begin
  case aOp of
    $3F:
      begin                                                      // SWI3
        CC := CC or M6809_EF;
        PushAll;
        PC := Rd16($FFF2);
        FCycles := 20;
      end;
    $83, $93, $A3, $B3, $8C, $9C, $AC, $BC:
      begin                                                      // CMPU, CMPS
        lMode := (aOp shr 4) and 3;
        case lMode of
          M_IMM: FCycles := 5;
          M_DIR: FCycles := 7;
          M_IDX: FCycles := 7;
        else
          FCycles := 8;
        end;
        if (aOp and $0F) = $3 then
          Sub16(U, Operand16(lMode))
        else
          Sub16(S, Operand16(lMode));
      end;
  else
    FCycles := 2;
  end;
end;

end.
