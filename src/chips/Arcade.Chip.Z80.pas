unit Arcade.Chip.Z80;

///  Zilog Z80 CPU core - full instruction set, documented AND undocumented behaviour :
///    - undocumented opcodes (IXH/IXL/IYH/IYL, SLL, DDCB copy-to-register, ED NOPs, IN (C), OUT (C),0)
///    - undocumented flags X (bit 3) and Y (bit 5), including MEMPTR (WZ) leaking into BIT n,(HL)
///    - T-state accurate per instruction (not per memory cycle)
///  Validated against ZEXDOC / ZEXALL (Z80Test bench).
///  Decoding follows the x/y/z/p/q scheme of "Decoding Z80 opcodes" (C. Young).
///  Pure unit, no dependency : FPC compatible (no inline var, no generics).
///  Generic : nothing 1942-specific here, the machine wires memory and I/O through events.

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}
{$Q-}
{$R-}

interface

type
  TZ80ReadEvent = function(aAddr: Word): Byte of object;
  TZ80WriteEvent = procedure(aAddr: Word; aValue: Byte) of object;

  /// 16-bit register pair, little-endian : L is the low byte.
  TZ80Pair = record
    case Integer of
      0: (W: Word);
      1: (L, H: Byte);
  end;
  PZ80Pair = ^TZ80Pair;

  TZ80 = class
  private
    FIndex: PZ80Pair;        // HL, IX or IY for the instruction being executed
    FIndexed: Boolean;       // DD/FD prefix active
    FT: Integer;             // T-states of the current Step
    FAfterEI: Boolean;       // interrupts are not accepted right after EI
    FIrqPending: Boolean;
    FIrqVector: Byte;
    FNmiPending: Boolean;

    function Rd(aAddr: Word): Byte; inline;
    procedure Wr(aAddr: Word; aValue: Byte); inline;
    function FetchOp: Byte; inline;
    function Fetch: Byte; inline;
    function Fetch16: Word; inline;
    procedure Push(aValue: Word); inline;
    function Pop: Word; inline;
    procedure IncR; inline;

    function GetReg(aIdx: Integer; aUseIndex: Boolean): Byte;
    procedure SetReg(aIdx: Integer; aUseIndex: Boolean; aValue: Byte);
    function RP(aP: Integer): PZ80Pair; inline;
    function RP2(aP: Integer): PZ80Pair; inline;
    function MemOperandAddr: Word;
    function Condition(aCC: Integer): Boolean; inline;

    procedure Add8(aValue: Byte; aCarry: Integer);
    procedure Sub8(aValue: Byte; aCarry: Integer);
    procedure Cp8(aValue: Byte);
    procedure Alu(aOp: Integer; aValue: Byte);
    function Inc8(aValue: Byte): Byte;
    function Dec8(aValue: Byte): Byte;
    function Rot(aOp: Integer; aValue: Byte): Byte;
    procedure Bit(aBit: Integer; aValue, aXY: Byte);
    function Add16(aA, aB: Word): Word;
    procedure Adc16(aValue: Word);
    procedure Sbc16(aValue: Word);
    procedure Daa;

    procedure ExecMain(aOp: Byte);
    procedure ExecCB;
    procedure ExecIndexedCB;
    procedure ExecED;
    procedure TakeIrq;
    procedure TakeNmi;
  public
    AF, BC, DE, HL: TZ80Pair;
    AF2, BC2, DE2, HL2: TZ80Pair;
    IX, IY, SP, WZ: TZ80Pair;
    PC: Word;
    I, R: Byte;
    IFF1, IFF2: Boolean;
    IM: Byte;
    Halted: Boolean;
    /// Total T-states since Reset.
    Cycles: Int64;

    OnRead: TZ80ReadEvent;
    OnWrite: TZ80WriteEvent;
    /// Optional : opcode fetches (M1 cycles - opcodes and prefixes, not operands) read through
    /// this instead of OnRead. Boards with encrypted opcodes (Commando) decrypt here.
    OnFetchOpcode: TZ80ReadEvent;
    OnPortIn: TZ80ReadEvent;     // full 16-bit port address (A or B on the high byte)
    OnPortOut: TZ80WriteEvent;

    procedure Reset;
    /// Executes one instruction (or accepts a pending interrupt). Returns the T-states spent.
    function Step: Integer;
    /// Runs until at least aCycles T-states are spent. Returns the T-states really spent.
    function Run(aCycles: Integer): Integer;
    /// Maskable interrupt, MAME HOLD_LINE semantics : stays pending until accepted.
    /// aVector is the byte on the data bus (RST opcode in IM0, low vector byte in IM2).
    procedure RaiseIrq(aVector: Byte);
    procedure ClearIrq;
    procedure RaiseNmi;
    property IrqPending: Boolean read FIrqPending;
  end;

const
  Z80_CF = $01;
  Z80_NF = $02;
  Z80_PF = $04;
  Z80_XF = $08;
  Z80_HF = $10;
  Z80_YF = $20;
  Z80_ZF = $40;
  Z80_SF = $80;

implementation

const
  CF = Z80_CF; NF = Z80_NF; PF = Z80_PF; XF = Z80_XF;
  HF = Z80_HF; YF = Z80_YF; ZF = Z80_ZF; SF = Z80_SF;

  CIntModes: array[0..7] of Byte = (0, 0, 1, 2, 0, 0, 1, 2);

var
  SZ53: array[0..255] of Byte;    // S, Z, X, Y of a byte result
  SZ53P: array[0..255] of Byte;   // same + parity

procedure InitTables;
var
  i, b, lParity: Integer;
begin
  for i := 0 to 255 do
  begin
    SZ53[i] := i and (SF or XF or YF);
    if i = 0 then
      SZ53[i] := SZ53[i] or ZF;
    lParity := 0;
    for b := 0 to 7 do
      lParity := lParity xor ((i shr b) and 1);
    SZ53P[i] := SZ53[i];
    if lParity = 0 then
      SZ53P[i] := SZ53P[i] or PF;
  end;
end;

{ TZ80 - plumbing }

function TZ80.Rd(aAddr: Word): Byte;
begin
  Result := OnRead(aAddr);
end;

procedure TZ80.Wr(aAddr: Word; aValue: Byte);
begin
  OnWrite(aAddr, aValue);
end;

procedure TZ80.IncR;
begin
  R := (R and $80) or ((R + 1) and $7F);
end;

function TZ80.FetchOp: Byte;
begin
  IncR;
  if Assigned(OnFetchOpcode) then
    Result := OnFetchOpcode(PC)
  else
    Result := OnRead(PC);
  PC := PC + 1;
end;

function TZ80.Fetch: Byte;
begin
  Result := OnRead(PC);
  PC := PC + 1;
end;

function TZ80.Fetch16: Word;
var
  lLo: Byte;
begin
  lLo := Fetch;
  Result := lLo or (Word(Fetch) shl 8);
end;

procedure TZ80.Push(aValue: Word);
begin
  SP.W := SP.W - 1;
  Wr(SP.W, aValue shr 8);
  SP.W := SP.W - 1;
  Wr(SP.W, aValue and $FF);
end;

function TZ80.Pop: Word;
var
  lLo: Byte;
begin
  lLo := Rd(SP.W);
  SP.W := SP.W + 1;
  Result := lLo or (Word(Rd(SP.W)) shl 8);
  SP.W := SP.W + 1;
end;

procedure TZ80.Reset;
begin
  AF.W := $FFFF;
  SP.W := $FFFF;
  BC.W := 0; DE.W := 0; HL.W := 0;
  AF2.W := 0; BC2.W := 0; DE2.W := 0; HL2.W := 0;
  IX.W := $FFFF; IY.W := $FFFF; WZ.W := 0;
  PC := 0;
  I := 0; R := 0;
  IFF1 := False; IFF2 := False;
  IM := 0;
  Halted := False;
  Cycles := 0;
  FAfterEI := False;
  FIrqPending := False;
  FNmiPending := False;
end;

procedure TZ80.RaiseIrq(aVector: Byte);
begin
  FIrqPending := True;
  FIrqVector := aVector;
end;

procedure TZ80.ClearIrq;
begin
  FIrqPending := False;
end;

procedure TZ80.RaiseNmi;
begin
  FNmiPending := True;
end;

{ Register access }

// r[] table : 0 B, 1 C, 2 D, 3 E, 4 H, 5 L, 6 (HL) - never here, 7 A.
// aUseIndex : H/L become IXH/IXL (IYH/IYL) under a DD/FD prefix.
function TZ80.GetReg(aIdx: Integer; aUseIndex: Boolean): Byte;
begin
  case aIdx of
    0: Result := BC.H;
    1: Result := BC.L;
    2: Result := DE.H;
    3: Result := DE.L;
    4: if aUseIndex then Result := FIndex^.H else Result := HL.H;
    5: if aUseIndex then Result := FIndex^.L else Result := HL.L;
  else
    Result := AF.H;
  end;
end;

procedure TZ80.SetReg(aIdx: Integer; aUseIndex: Boolean; aValue: Byte);
begin
  case aIdx of
    0: BC.H := aValue;
    1: BC.L := aValue;
    2: DE.H := aValue;
    3: DE.L := aValue;
    4: if aUseIndex then FIndex^.H := aValue else HL.H := aValue;
    5: if aUseIndex then FIndex^.L := aValue else HL.L := aValue;
  else
    AF.H := aValue;
  end;
end;

function TZ80.RP(aP: Integer): PZ80Pair;
begin
  case aP of
    0: Result := @BC;
    1: Result := @DE;
    2: Result := FIndex;
  else
    Result := @SP;
  end;
end;

function TZ80.RP2(aP: Integer): PZ80Pair;
begin
  case aP of
    0: Result := @BC;
    1: Result := @DE;
    2: Result := FIndex;
  else
    Result := @AF;
  end;
end;

// Address of the r[6] operand : (HL), or (IX+d)/(IY+d) - fetching d.
function TZ80.MemOperandAddr: Word;
begin
  if FIndexed then
  begin
    Result := FIndex^.W + Word(ShortInt(Fetch));
    WZ.W := Result;
  end
  else
    Result := HL.W;
end;

function TZ80.Condition(aCC: Integer): Boolean;
begin
  case aCC of
    0: Result := (AF.L and Z80_ZF) = 0;
    1: Result := (AF.L and Z80_ZF) <> 0;
    2: Result := (AF.L and Z80_CF) = 0;
    3: Result := (AF.L and Z80_CF) <> 0;
    4: Result := (AF.L and Z80_PF) = 0;
    5: Result := (AF.L and Z80_PF) <> 0;
    6: Result := (AF.L and Z80_SF) = 0;
  else
    Result := (AF.L and Z80_SF) <> 0;
  end;
end;

{ ALU }

procedure TZ80.Add8(aValue: Byte; aCarry: Integer);
var
  lA, lR: Integer;
begin
  lA := AF.H;
  lR := lA + aValue + aCarry;
  AF.L := SZ53[lR and $FF] or ((lR shr 8) and CF) or ((lA xor aValue xor lR) and HF)
       or ((((lA xor not aValue) and (lA xor lR)) and $80) shr 5);
  AF.H := lR;
end;

procedure TZ80.Sub8(aValue: Byte; aCarry: Integer);
var
  lA, lR: Integer;
begin
  lA := AF.H;
  lR := lA - aValue - aCarry;
  AF.L := SZ53[lR and $FF] or NF or ((lR shr 8) and CF) or ((lA xor aValue xor lR) and HF)
       or ((((lA xor aValue) and (lA xor lR)) and $80) shr 5);
  AF.H := lR;
end;

procedure TZ80.Cp8(aValue: Byte);
var
  lA, lR: Integer;
begin
  lA := AF.H;
  lR := lA - aValue;
  // X and Y come from the operand, not from the result
  AF.L := (SZ53[lR and $FF] and (SF or ZF)) or (aValue and (XF or YF)) or NF
       or ((lR shr 8) and CF) or ((lA xor aValue xor lR) and HF)
       or ((((lA xor aValue) and (lA xor lR)) and $80) shr 5);
end;

// alu[y] : ADD ADC SUB SBC AND XOR OR CP
procedure TZ80.Alu(aOp: Integer; aValue: Byte);
begin
  case aOp of
    0: Add8(aValue, 0);
    1: Add8(aValue, AF.L and CF);
    2: Sub8(aValue, 0);
    3: Sub8(aValue, AF.L and CF);
    4: begin AF.H := AF.H and aValue; AF.L := SZ53P[AF.H] or HF; end;
    5: begin AF.H := AF.H xor aValue; AF.L := SZ53P[AF.H]; end;
    6: begin AF.H := AF.H or aValue;  AF.L := SZ53P[AF.H]; end;
  else
    Cp8(aValue);
  end;
end;

function TZ80.Inc8(aValue: Byte): Byte;
begin
  Result := aValue + 1;
  AF.L := (AF.L and CF) or SZ53[Result];
  if (Result and $0F) = 0 then
    AF.L := AF.L or HF;
  if Result = $80 then
    AF.L := AF.L or PF;
end;

function TZ80.Dec8(aValue: Byte): Byte;
begin
  Result := aValue - 1;
  AF.L := (AF.L and CF) or NF or SZ53[Result];
  if (aValue and $0F) = 0 then
    AF.L := AF.L or HF;
  if Result = $7F then
    AF.L := AF.L or PF;
end;

// rot[y] : RLC RRC RL RR SLA SRA SLL SRL
function TZ80.Rot(aOp: Integer; aValue: Byte): Byte;
var
  lC: Byte;
begin
  case aOp of
    0: begin lC := aValue shr 7; Result := (aValue shl 1) or lC; end;
    1: begin lC := aValue and 1; Result := (aValue shr 1) or (lC shl 7); end;
    2: begin lC := aValue shr 7; Result := (aValue shl 1) or (AF.L and CF); end;
    3: begin lC := aValue and 1; Result := (aValue shr 1) or ((AF.L and CF) shl 7); end;
    4: begin lC := aValue shr 7; Result := aValue shl 1; end;
    5: begin lC := aValue and 1; Result := (aValue shr 1) or (aValue and $80); end;
    6: begin lC := aValue shr 7; Result := (aValue shl 1) or 1; end;
  else
    begin lC := aValue and 1; Result := aValue shr 1; end;
  end;
  AF.L := SZ53P[Result] or lC;
end;

// aXY : source of the undocumented X/Y flags (register value, or WZ high byte for memory)
procedure TZ80.Bit(aBit: Integer; aValue, aXY: Byte);
var
  lMasked: Byte;
begin
  lMasked := aValue and (1 shl aBit);
  AF.L := (AF.L and CF) or HF or (aXY and (XF or YF)) or (lMasked and SF);
  if lMasked = 0 then
    AF.L := AF.L or ZF or PF;
end;

function TZ80.Add16(aA, aB: Word): Word;
var
  lR: Integer;
begin
  lR := Integer(aA) + aB;
  WZ.W := aA + 1;
  AF.L := (AF.L and (SF or ZF or PF)) or ((lR shr 16) and CF)
       or (((aA xor aB xor lR) shr 8) and HF) or ((lR shr 8) and (XF or YF));
  Result := lR;
end;

procedure TZ80.Adc16(aValue: Word);
var
  lHL, lR: Integer;
begin
  lHL := FIndex^.W;
  lR := lHL + aValue + (AF.L and CF);
  WZ.W := lHL + 1;
  AF.L := ((lR shr 16) and CF) or ((lR shr 8) and (SF or XF or YF))
       or (((lHL xor aValue xor lR) shr 8) and HF)
       or ((((lHL xor not aValue) and (lHL xor lR)) and $8000) shr 13);
  if (lR and $FFFF) = 0 then
    AF.L := AF.L or ZF;
  FIndex^.W := lR;
end;

procedure TZ80.Sbc16(aValue: Word);
var
  lHL, lR: Integer;
begin
  lHL := FIndex^.W;
  lR := lHL - aValue - (AF.L and CF);
  WZ.W := lHL + 1;
  AF.L := NF or ((lR shr 16) and CF) or ((lR shr 8) and (SF or XF or YF))
       or (((lHL xor aValue xor lR) shr 8) and HF)
       or ((((lHL xor aValue) and (lHL xor lR)) and $8000) shr 13);
  if (lR and $FFFF) = 0 then
    AF.L := AF.L or ZF;
  FIndex^.W := lR;
end;

procedure TZ80.Daa;
var
  lA, lDiff, lC, lH: Byte;
begin
  lA := AF.H;
  lDiff := 0;
  lC := 0;
  if ((AF.L and HF) <> 0) or ((lA and $0F) > 9) then
    lDiff := $06;
  if ((AF.L and CF) <> 0) or (lA > $99) then
  begin
    lDiff := lDiff or $60;
    lC := CF;
  end;
  if (AF.L and NF) <> 0 then
  begin
    if ((AF.L and HF) <> 0) and ((lA and $0F) < 6) then lH := HF else lH := 0;
    AF.H := lA - lDiff;
  end
  else
  begin
    if (lA and $0F) > 9 then lH := HF else lH := 0;
    AF.H := lA + lDiff;
  end;
  AF.L := SZ53P[AF.H] or lC or lH or (AF.L and NF);
end;

{ Interrupts }

procedure TZ80.TakeNmi;
begin
  FNmiPending := False;
  Halted := False;
  IncR;
  IFF1 := False;
  Push(PC);
  PC := $0066;
  WZ.W := PC;
  Inc(FT, 11);
end;

procedure TZ80.TakeIrq;
var
  lAddr: Word;
begin
  FIrqPending := False;   // HOLD_LINE : acknowledged
  Halted := False;
  IncR;
  IFF1 := False;
  IFF2 := False;
  case IM of
    2:
      begin
        Push(PC);
        lAddr := (Word(I) shl 8) or FIrqVector;
        PC := Rd(lAddr) or (Word(Rd(Word(lAddr + 1))) shl 8);
        Inc(FT, 19);
      end;
    1:
      begin
        Push(PC);
        PC := $0038;
        Inc(FT, 13);
      end;
  else
    // IM0 : the data bus byte is executed. Arcade boards put an RST there.
    Push(PC);
    if (FIrqVector and $C7) = $C7 then
      PC := FIrqVector and $38
    else
      PC := $0038;
    Inc(FT, 13);
  end;
  WZ.W := PC;
end;

{ Execution }

function TZ80.Step: Integer;
var
  lOp: Byte;
begin
  FT := 0;
  if FNmiPending then
    TakeNmi
  else if FIrqPending and IFF1 and not FAfterEI then
    TakeIrq
  else if Halted then
  begin
    IncR;   // HALT executes NOPs
    FT := 4;
  end
  else
  begin
    FAfterEI := False;
    FIndex := @HL;
    FIndexed := False;
    lOp := FetchOp;
    // DD/FD prefixes : the last one wins, each costs 4 T-states
    while (lOp = $DD) or (lOp = $FD) do
    begin
      if lOp = $DD then FIndex := @IX else FIndex := @IY;
      FIndexed := True;
      Inc(FT, 4);
      lOp := FetchOp;
    end;
    case lOp of
      $CB: if FIndexed then ExecIndexedCB else ExecCB;
      $ED: begin FIndex := @HL; FIndexed := False; ExecED; end;
    else
      ExecMain(lOp);
    end;
  end;
  Inc(Cycles, FT);
  Result := FT;
end;

function TZ80.Run(aCycles: Integer): Integer;
begin
  Result := 0;
  while Result < aCycles do
    Inc(Result, Step);
end;

procedure TZ80.ExecMain(aOp: Byte);
var
  x, y, z, p, q: Integer;
  lAddr, lW: Word;
  lV: Byte;
  lD: ShortInt;
begin
  x := aOp shr 6;
  y := (aOp shr 3) and 7;
  z := aOp and 7;
  p := y shr 1;
  q := y and 1;
  case x of
    0:
      case z of
        0:
          case y of
            0: Inc(FT, 4);                                        // NOP
            1: begin                                              // EX AF,AF'
                 lW := AF.W; AF.W := AF2.W; AF2.W := lW;
                 Inc(FT, 4);
               end;
            2: begin                                              // DJNZ d
                 lD := ShortInt(Fetch);
                 BC.H := BC.H - 1;
                 if BC.H <> 0 then
                 begin
                   PC := PC + Word(lD);
                   WZ.W := PC;
                   Inc(FT, 13);
                 end
                 else
                   Inc(FT, 8);
               end;
            3: begin                                              // JR d
                 lD := ShortInt(Fetch);
                 PC := PC + Word(lD);
                 WZ.W := PC;
                 Inc(FT, 12);
               end;
          else                                                    // JR cc,d
            lD := ShortInt(Fetch);
            if Condition(y - 4) then
            begin
              PC := PC + Word(lD);
              WZ.W := PC;
              Inc(FT, 12);
            end
            else
              Inc(FT, 7);
          end;
        1:
          if q = 0 then
          begin                                                   // LD rp,nn
            RP(p)^.W := Fetch16;
            Inc(FT, 10);
          end
          else
          begin                                                   // ADD HL,rp
            FIndex^.W := Add16(FIndex^.W, RP(p)^.W);
            Inc(FT, 11);
          end;
        2:
          case y of
            0: begin                                              // LD (BC),A
                 Wr(BC.W, AF.H);
                 WZ.L := BC.W + 1; WZ.H := AF.H;
                 Inc(FT, 7);
               end;
            1: begin                                              // LD A,(BC)
                 AF.H := Rd(BC.W);
                 WZ.W := BC.W + 1;
                 Inc(FT, 7);
               end;
            2: begin                                              // LD (DE),A
                 Wr(DE.W, AF.H);
                 WZ.L := DE.W + 1; WZ.H := AF.H;
                 Inc(FT, 7);
               end;
            3: begin                                              // LD A,(DE)
                 AF.H := Rd(DE.W);
                 WZ.W := DE.W + 1;
                 Inc(FT, 7);
               end;
            4: begin                                              // LD (nn),HL
                 lAddr := Fetch16;
                 Wr(lAddr, FIndex^.L);
                 Wr(Word(lAddr + 1), FIndex^.H);
                 WZ.W := lAddr + 1;
                 Inc(FT, 16);
               end;
            5: begin                                              // LD HL,(nn)
                 lAddr := Fetch16;
                 FIndex^.L := Rd(lAddr);
                 FIndex^.H := Rd(Word(lAddr + 1));
                 WZ.W := lAddr + 1;
                 Inc(FT, 16);
               end;
            6: begin                                              // LD (nn),A
                 lAddr := Fetch16;
                 Wr(lAddr, AF.H);
                 WZ.L := lAddr + 1; WZ.H := AF.H;
                 Inc(FT, 13);
               end;
          else                                                    // LD A,(nn)
            lAddr := Fetch16;
            AF.H := Rd(lAddr);
            WZ.W := lAddr + 1;
            Inc(FT, 13);
          end;
        3:
          begin                                                   // INC rp / DEC rp
            if q = 0 then
              RP(p)^.W := RP(p)^.W + 1
            else
              RP(p)^.W := RP(p)^.W - 1;
            Inc(FT, 6);
          end;
        4, 5:
          if y = 6 then
          begin                                                   // INC/DEC (HL)
            if FIndexed then Inc(FT, 8);
            lAddr := MemOperandAddr;
            if z = 4 then
              Wr(lAddr, Inc8(Rd(lAddr)))
            else
              Wr(lAddr, Dec8(Rd(lAddr)));
            Inc(FT, 11);
          end
          else
          begin                                                   // INC/DEC r
            if z = 4 then
              SetReg(y, True, Inc8(GetReg(y, True)))
            else
              SetReg(y, True, Dec8(GetReg(y, True)));
            Inc(FT, 4);
          end;
        6:
          if y = 6 then
          begin                                                   // LD (HL),n
            if FIndexed then Inc(FT, 5);
            lAddr := MemOperandAddr;
            Wr(lAddr, Fetch);
            Inc(FT, 10);
          end
          else
          begin                                                   // LD r,n
            SetReg(y, True, Fetch);
            Inc(FT, 7);
          end;
      else                                                        // z = 7 : accumulator / flags ops
        case y of
          0: begin                                                // RLCA
               lV := AF.H shr 7;
               AF.H := (AF.H shl 1) or lV;
               AF.L := (AF.L and (SF or ZF or PF)) or lV or (AF.H and (XF or YF));
             end;
          1: begin                                                // RRCA
               lV := AF.H and 1;
               AF.H := (AF.H shr 1) or (lV shl 7);
               AF.L := (AF.L and (SF or ZF or PF)) or lV or (AF.H and (XF or YF));
             end;
          2: begin                                                // RLA
               lV := AF.H shr 7;
               AF.H := (AF.H shl 1) or (AF.L and CF);
               AF.L := (AF.L and (SF or ZF or PF)) or lV or (AF.H and (XF or YF));
             end;
          3: begin                                                // RRA
               lV := AF.H and 1;
               AF.H := (AF.H shr 1) or ((AF.L and CF) shl 7);
               AF.L := (AF.L and (SF or ZF or PF)) or lV or (AF.H and (XF or YF));
             end;
          4: Daa;
          5: begin                                                // CPL
               AF.H := not AF.H;
               AF.L := (AF.L and (SF or ZF or PF or CF)) or HF or NF or (AF.H and (XF or YF));
             end;
          6: begin                                                // SCF (X/Y = F or A, NMOS Z80)
               AF.L := (AF.L and (SF or ZF or PF)) or CF or ((AF.L or AF.H) and (XF or YF));
             end;
        else                                                      // CCF
          AF.L := ((AF.L and (SF or ZF or PF or CF)) or ((AF.L and CF) shl 4)
                 or ((AF.L or AF.H) and (XF or YF))) xor CF;
        end;
        Inc(FT, 4);
      end;

    1:
      if (y = 6) and (z = 6) then
      begin                                                       // HALT
        Halted := True;
        Inc(FT, 4);
      end
      else if y = 6 then
      begin                                                       // LD (HL),r : H/L stay H/L
        if FIndexed then Inc(FT, 8);
        lAddr := MemOperandAddr;
        Wr(lAddr, GetReg(z, False));
        Inc(FT, 7);
      end
      else if z = 6 then
      begin                                                       // LD r,(HL)
        if FIndexed then Inc(FT, 8);
        lAddr := MemOperandAddr;
        SetReg(y, False, Rd(lAddr));
        Inc(FT, 7);
      end
      else
      begin                                                       // LD r,r' (IXH/IXL allowed)
        SetReg(y, True, GetReg(z, True));
        Inc(FT, 4);
      end;

    2:
      if z = 6 then
      begin                                                       // alu A,(HL)
        if FIndexed then Inc(FT, 8);
        lAddr := MemOperandAddr;
        Alu(y, Rd(lAddr));
        Inc(FT, 7);
      end
      else
      begin                                                       // alu A,r
        Alu(y, GetReg(z, True));
        Inc(FT, 4);
      end;

  else                                                            // x = 3
    case z of
      0:
        if Condition(y) then
        begin                                                     // RET cc
          PC := Pop;
          WZ.W := PC;
          Inc(FT, 11);
        end
        else
          Inc(FT, 5);
      1:
        if q = 0 then
        begin                                                     // POP rp2
          RP2(p)^.W := Pop;
          Inc(FT, 10);
        end
        else
          case p of
            0: begin                                              // RET
                 PC := Pop;
                 WZ.W := PC;
                 Inc(FT, 10);
               end;
            1: begin                                              // EXX
                 lW := BC.W; BC.W := BC2.W; BC2.W := lW;
                 lW := DE.W; DE.W := DE2.W; DE2.W := lW;
                 lW := HL.W; HL.W := HL2.W; HL2.W := lW;
                 Inc(FT, 4);
               end;
            2: begin                                              // JP (HL)
                 PC := FIndex^.W;
                 Inc(FT, 4);
               end;
          else                                                    // LD SP,HL
            SP.W := FIndex^.W;
            Inc(FT, 6);
          end;
      2:
        begin                                                     // JP cc,nn
          lAddr := Fetch16;
          WZ.W := lAddr;
          if Condition(y) then
            PC := lAddr;
          Inc(FT, 10);
        end;
      3:
        case y of
          0: begin                                                // JP nn
               PC := Fetch16;
               WZ.W := PC;
               Inc(FT, 10);
             end;
          1: ;                                                    // CB : handled in Step
          2: begin                                                // OUT (n),A
               lV := Fetch;
               OnPortOut((Word(AF.H) shl 8) or lV, AF.H);
               WZ.L := lV + 1; WZ.H := AF.H;
               Inc(FT, 11);
             end;
          3: begin                                                // IN A,(n)
               lW := (Word(AF.H) shl 8) or Fetch;
               AF.H := OnPortIn(lW);
               WZ.W := lW + 1;
               Inc(FT, 11);
             end;
          4: begin                                                // EX (SP),HL
               lW := Rd(SP.W) or (Word(Rd(Word(SP.W + 1))) shl 8);
               Wr(SP.W, FIndex^.L);
               Wr(Word(SP.W + 1), FIndex^.H);
               FIndex^.W := lW;
               WZ.W := lW;
               Inc(FT, 19);
             end;
          5: begin                                                // EX DE,HL (never IX/IY)
               lW := DE.W; DE.W := HL.W; HL.W := lW;
               Inc(FT, 4);
             end;
          6: begin                                                // DI
               IFF1 := False; IFF2 := False;
               Inc(FT, 4);
             end;
        else                                                      // EI
          IFF1 := True; IFF2 := True;
          FAfterEI := True;
          Inc(FT, 4);
        end;
      4:
        begin                                                     // CALL cc,nn
          lAddr := Fetch16;
          WZ.W := lAddr;
          if Condition(y) then
          begin
            Push(PC);
            PC := lAddr;
            Inc(FT, 17);
          end
          else
            Inc(FT, 10);
        end;
      5:
        if q = 0 then
        begin                                                     // PUSH rp2
          Push(RP2(p)^.W);
          Inc(FT, 11);
        end
        else
        begin                                                     // CALL nn (p=0 ; DD/ED/FD handled in Step)
          lAddr := Fetch16;
          WZ.W := lAddr;
          Push(PC);
          PC := lAddr;
          Inc(FT, 17);
        end;
      6:
        begin                                                     // alu A,n
          Alu(y, Fetch);
          Inc(FT, 7);
        end;
    else                                                          // RST y*8
      Push(PC);
      PC := y * 8;
      WZ.W := PC;
      Inc(FT, 11);
    end;
  end;
end;

procedure TZ80.ExecCB;
var
  lOp, lV: Byte;
  x, y, z: Integer;
begin
  lOp := FetchOp;
  x := lOp shr 6;
  y := (lOp shr 3) and 7;
  z := lOp and 7;
  if z = 6 then
  begin
    lV := Rd(HL.W);
    case x of
      0: begin Wr(HL.W, Rot(y, lV)); Inc(FT, 15); end;
      1: begin Bit(y, lV, WZ.H); Inc(FT, 12); end;
      2: begin Wr(HL.W, lV and not (1 shl y)); Inc(FT, 15); end;
    else
      Wr(HL.W, lV or (1 shl y)); Inc(FT, 15);
    end;
  end
  else
  begin
    lV := GetReg(z, False);
    case x of
      0: SetReg(z, False, Rot(y, lV));
      1: Bit(y, lV, lV);
      2: SetReg(z, False, lV and not (1 shl y));
    else
      SetReg(z, False, lV or (1 shl y));
    end;
    Inc(FT, 8);
  end;
end;

// DD CB d op / FD CB d op : d and op are NOT M1 fetches (no R increment).
// Undocumented : for z <> 6 the result is also copied to r[z] (BIT excepted).
procedure TZ80.ExecIndexedCB;
var
  lOp, lV, lRes: Byte;
  lAddr: Word;
  x, y, z: Integer;
begin
  lAddr := FIndex^.W + Word(ShortInt(Fetch));
  WZ.W := lAddr;
  lOp := Fetch;
  x := lOp shr 6;
  y := (lOp shr 3) and 7;
  z := lOp and 7;
  lV := Rd(lAddr);
  if x = 1 then
  begin
    Bit(y, lV, WZ.H);
    Inc(FT, 16);   // + 4 of the prefix = 20
    Exit;
  end;
  case x of
    0: lRes := Rot(y, lV);
    2: lRes := lV and not (1 shl y);
  else
    lRes := lV or (1 shl y);
  end;
  Wr(lAddr, lRes);
  if z <> 6 then
    SetReg(z, False, lRes);
  Inc(FT, 19);     // + 4 = 23
end;

procedure TZ80.ExecED;
var
  lOp, lV, lK: Byte;
  x, y, z, p, q: Integer;
  lAddr: Word;
  lSum: Integer;
begin
  lOp := FetchOp;
  x := lOp shr 6;
  y := (lOp shr 3) and 7;
  z := lOp and 7;
  p := y shr 1;
  q := y and 1;

  if x = 1 then
  begin
    case z of
      0:
        begin                                                     // IN r,(C) / IN (C)
          lV := OnPortIn(BC.W);
          WZ.W := BC.W + 1;
          AF.L := (AF.L and CF) or SZ53P[lV];
          if y <> 6 then
            SetReg(y, False, lV);
          Inc(FT, 12);
        end;
      1:
        begin                                                     // OUT (C),r / OUT (C),0
          if y = 6 then lV := 0 else lV := GetReg(y, False);
          OnPortOut(BC.W, lV);
          WZ.W := BC.W + 1;
          Inc(FT, 12);
        end;
      2:
        begin                                                     // SBC/ADC HL,rp
          if q = 0 then Sbc16(RP(p)^.W) else Adc16(RP(p)^.W);
          Inc(FT, 15);
        end;
      3:
        begin
          lAddr := Fetch16;
          if q = 0 then
          begin                                                   // LD (nn),rp
            Wr(lAddr, RP(p)^.L);
            Wr(Word(lAddr + 1), RP(p)^.H);
          end
          else
          begin                                                   // LD rp,(nn)
            RP(p)^.L := Rd(lAddr);
            RP(p)^.H := Rd(Word(lAddr + 1));
          end;
          WZ.W := lAddr + 1;
          Inc(FT, 20);
        end;
      4:
        begin                                                     // NEG
          lV := AF.H;
          AF.H := 0;
          Sub8(lV, 0);
          Inc(FT, 8);
        end;
      5:
        begin                                                     // RETN / RETI
          IFF1 := IFF2;
          PC := Pop;
          WZ.W := PC;
          Inc(FT, 14);
        end;
      6:
        begin                                                     // IM 0/1/2
          IM := CIntModes[y];
          Inc(FT, 8);
        end;
    else
      case y of
        0: begin I := AF.H; Inc(FT, 9); end;                      // LD I,A
        1: begin R := AF.H; Inc(FT, 9); end;                      // LD R,A
        2, 3:
          begin                                                   // LD A,I / LD A,R
            if y = 2 then AF.H := I else AF.H := R;
            AF.L := (AF.L and CF) or SZ53[AF.H];
            if IFF2 then
              AF.L := AF.L or PF;
            Inc(FT, 9);
          end;
        4:
          begin                                                   // RRD
            lV := Rd(HL.W);
            Wr(HL.W, (lV shr 4) or (AF.H shl 4));
            AF.H := (AF.H and $F0) or (lV and $0F);
            AF.L := (AF.L and CF) or SZ53P[AF.H];
            WZ.W := HL.W + 1;
            Inc(FT, 18);
          end;
        5:
          begin                                                   // RLD
            lV := Rd(HL.W);
            Wr(HL.W, (lV shl 4) or (AF.H and $0F));
            AF.H := (AF.H and $F0) or (lV shr 4);
            AF.L := (AF.L and CF) or SZ53P[AF.H];
            WZ.W := HL.W + 1;
            Inc(FT, 18);
          end;
      else
        Inc(FT, 8);                                               // ED 77 / ED 7F : NOP
      end;
    end;
    Exit;
  end;

  if (x = 2) and (z <= 3) and (y >= 4) then
  begin
    // Block instructions. y : 4 = I (increment), 5 = D, 6 = IR, 7 = DR
    case z of
      0:
        begin                                                     // LDI LDD LDIR LDDR
          lV := Rd(HL.W);
          Wr(DE.W, lV);
          if (y and 1) = 0 then
          begin HL.W := HL.W + 1; DE.W := DE.W + 1; end
          else
          begin HL.W := HL.W - 1; DE.W := DE.W - 1; end;
          BC.W := BC.W - 1;
          lK := lV + AF.H;
          AF.L := (AF.L and (SF or ZF or CF)) or (lK and XF) or ((lK shl 4) and YF);
          if BC.W <> 0 then
            AF.L := AF.L or PF;
          if (y >= 6) and (BC.W <> 0) then
          begin
            PC := PC - 2;
            WZ.W := PC + 1;
            Inc(FT, 21);
          end
          else
            Inc(FT, 16);
        end;
      1:
        begin                                                     // CPI CPD CPIR CPDR
          lV := Rd(HL.W);
          lSum := AF.H - lV;
          lK := (AF.H xor lV xor lSum) and HF;
          if (y and 1) = 0 then
          begin HL.W := HL.W + 1; WZ.W := WZ.W + 1; end
          else
          begin HL.W := HL.W - 1; WZ.W := WZ.W - 1; end;
          BC.W := BC.W - 1;
          AF.L := (AF.L and CF) or NF or (SZ53[lSum and $FF] and (SF or ZF)) or lK;
          if lK <> 0 then
            lSum := lSum - 1;
          AF.L := AF.L or (lSum and XF) or ((lSum shl 4) and YF);
          if BC.W <> 0 then
            AF.L := AF.L or PF;
          if (y >= 6) and (BC.W <> 0) and ((AF.L and ZF) = 0) then
          begin
            PC := PC - 2;
            WZ.W := PC + 1;
            Inc(FT, 21);
          end
          else
            Inc(FT, 16);
        end;
      2:
        begin                                                     // INI IND INIR INDR
          lV := OnPortIn(BC.W);
          Wr(HL.W, lV);
          if (y and 1) = 0 then
          begin
            WZ.W := BC.W + 1;
            HL.W := HL.W + 1;
            lSum := lV + Byte(BC.L + 1);
          end
          else
          begin
            WZ.W := BC.W - 1;
            HL.W := HL.W - 1;
            lSum := lV + Byte(BC.L - 1);
          end;
          BC.H := BC.H - 1;
          AF.L := SZ53[BC.H] or ((lV and $80) shr 6) or (SZ53P[(lSum and 7) xor BC.H] and PF);
          if lSum > 255 then
            AF.L := AF.L or HF or CF;
          if (y >= 6) and (BC.H <> 0) then
          begin
            PC := PC - 2;
            Inc(FT, 21);
          end
          else
            Inc(FT, 16);
        end;
    else
      begin                                                       // OUTI OUTD OTIR OTDR
        lV := Rd(HL.W);
        BC.H := BC.H - 1;
        OnPortOut(BC.W, lV);
        if (y and 1) = 0 then
        begin
          HL.W := HL.W + 1;
          WZ.W := BC.W + 1;
        end
        else
        begin
          HL.W := HL.W - 1;
          WZ.W := BC.W - 1;
        end;
        lSum := lV + HL.L;
        AF.L := SZ53[BC.H] or ((lV and $80) shr 6) or (SZ53P[(lSum and 7) xor BC.H] and PF);
        if lSum > 255 then
          AF.L := AF.L or HF or CF;
        if (y >= 6) and (BC.H <> 0) then
        begin
          PC := PC - 2;
          Inc(FT, 21);
        end
        else
          Inc(FT, 16);
      end;
    end;
    Exit;
  end;

  Inc(FT, 8);                                                     // undefined ED xx : NOP
end;

initialization
  InitTables;

end.
