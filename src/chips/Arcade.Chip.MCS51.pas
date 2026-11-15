unit Arcade.Chip.MCS51;

///  Intel MCS-51 microcontroller (8051 / 8751) : 4K internal program ROM, 128 bytes of RAM + SFRs,
///  4 I/O ports, 2 timers (modes 0-3), 5 interrupt sources with 2 priority levels.
///  One machine cycle = 12 clocks. Step returns machine cycles (1, 2 or 4).
///  Ports : a plain read (MOV A,P1) reads the PINS through OnPortIn ; read-modify-write
///  instructions (ANL/ORL/XRL/INC/DEC/DJNZ/CPL/CLR/SETB/JBC on a port) read the LATCH, as the chip does.
///  Not implemented : serial port data (SBUF/SCON transfer), power-down modes.
///  Pure unit, FPC compatible.

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}
{$Q-}
{$R-}

interface

uses
  System.SysUtils;

type
  TMcs51PortIn = function(aPort: Integer): Byte of object;
  TMcs51PortOut = procedure(aPort: Integer; aValue: Byte) of object;

  TMcs51 = class
  private
    FRom: TBytes;
    FIRam: array[0..$FF] of Byte;
    FSfr: array[$80..$FF] of Byte;
    FInService: Integer;           // -1 none, 0 low priority, 1 high priority running
    FInServiceStack: array[0..1] of Integer;
    FInt0Pin, FInt1Pin: Boolean;   // True = asserted (pin low)
    FRmw: Boolean;                 // current instruction is read-modify-write

    function Code(aAddr: Word): Byte;
    function FetchByte: Byte;
    function GetA: Byte;
    procedure SetA(aValue: Byte);
    function GetPsw: Byte;
    function Carry: Integer;
    procedure SetCarry(aOn: Boolean);
    function RegAddr(n: Integer): Integer;
    function ReadDirect(aAddr: Byte): Byte;
    procedure WriteDirect(aAddr, aValue: Byte);
    function ReadIndirect(aAddr: Byte): Byte;
    procedure WriteIndirect(aAddr, aValue: Byte);
    function ReadBit(aBit: Byte): Boolean;
    procedure WriteBit(aBit: Byte; aOn: Boolean);
    procedure Push(aValue: Byte);
    function Pop: Byte;
    procedure Jump(aRel: ShortInt);
    procedure AddA(aValue: Byte; aCarry: Integer);
    procedure SubbA(aValue: Byte);
    procedure ClockTimers(aCycles: Integer);
    function CheckInterrupts: Boolean;
  public
    PC: Word;
    /// Machine cycles since reset.
    Cycles: Int64;
    OnPortIn: TMcs51PortIn;
    OnPortOut: TMcs51PortOut;

    constructor Create(const aRom: TBytes);
    procedure Reset;
    /// One instruction (or an interrupt entry). Returns machine cycles.
    function Step: Integer;
    /// External interrupt pins, True = asserted (active low on the chip).
    procedure SetInt0(aAsserted: Boolean);
    procedure SetInt1(aAsserted: Boolean);
    function PortLatch(aPort: Integer): Byte;
    /// Internal RAM and SFRs, for the state hash.
    function IRam(aAddr: Byte): Byte;
    function Sfr(aAddr: Byte): Byte;
  end;

implementation

const
  SFR_P0 = $80; SFR_SP = $81; SFR_DPL = $82; SFR_DPH = $83; SFR_PCON = $87;
  SFR_TCON = $88; SFR_TMOD = $89; SFR_TL0 = $8A; SFR_TL1 = $8B; SFR_TH0 = $8C; SFR_TH1 = $8D;
  SFR_P1 = $90; SFR_SCON = $98; SFR_SBUF = $99; SFR_P2 = $A0; SFR_IE = $A8; SFR_P3 = $B0;
  SFR_IP = $B8; SFR_PSW = $D0; SFR_ACC = $E0; SFR_B = $F0;

  PSW_CY = $80; PSW_AC = $40; PSW_OV = $04; PSW_P = $01;

  // TCON bits
  TCON_IT0 = $01; TCON_IE0 = $02; TCON_IT1 = $04; TCON_IE1 = $08;
  TCON_TR0 = $10; TCON_TF0 = $20; TCON_TR1 = $40; TCON_TF1 = $80;

{ TMcs51 }

constructor TMcs51.Create(const aRom: TBytes);
begin
  inherited Create;
  FRom := aRom;
  Reset;
end;

procedure TMcs51.Reset;
begin
  FillChar(FIRam, SizeOf(FIRam), 0);
  FillChar(FSfr, SizeOf(FSfr), 0);
  FSfr[SFR_SP] := $07;
  FSfr[SFR_P0] := $FF;
  FSfr[SFR_P1] := $FF;
  FSfr[SFR_P2] := $FF;
  FSfr[SFR_P3] := $FF;
  PC := 0;
  Cycles := 0;
  FInService := -1;
  FInServiceStack[0] := -1;
  FInServiceStack[1] := -1;
end;

function TMcs51.Code(aAddr: Word): Byte;
begin
  if aAddr < Length(FRom) then
    Result := FRom[aAddr]
  else
    Result := $FF;   // EA high, no external program memory on the board
end;

function TMcs51.FetchByte: Byte;
begin
  Result := Code(PC);
  PC := PC + 1;
end;

function TMcs51.GetA: Byte;
begin
  Result := FSfr[SFR_ACC];
end;

procedure TMcs51.SetA(aValue: Byte);
begin
  FSfr[SFR_ACC] := aValue;
end;

// PSW.0 is the parity of A, recomputed on every read
function TMcs51.GetPsw: Byte;
var
  lA, lP: Byte;
begin
  lA := FSfr[SFR_ACC];
  lA := lA xor (lA shr 4);
  lA := lA xor (lA shr 2);
  lP := (lA xor (lA shr 1)) and 1;
  Result := (FSfr[SFR_PSW] and not PSW_P) or lP;
end;

function TMcs51.Carry: Integer;
begin
  Result := (FSfr[SFR_PSW] shr 7) and 1;
end;

procedure TMcs51.SetCarry(aOn: Boolean);
begin
  if aOn then
    FSfr[SFR_PSW] := FSfr[SFR_PSW] or PSW_CY
  else
    FSfr[SFR_PSW] := FSfr[SFR_PSW] and not PSW_CY;
end;

function TMcs51.RegAddr(n: Integer): Integer;
begin
  Result := (FSfr[SFR_PSW] and $18) + n;
end;

function TMcs51.PortLatch(aPort: Integer): Byte;
begin
  Result := FSfr[SFR_P0 + aPort * $10];
end;

function TMcs51.IRam(aAddr: Byte): Byte;
begin
  Result := FIRam[aAddr];
end;

function TMcs51.Sfr(aAddr: Byte): Byte;
begin
  if aAddr >= $80 then
    Result := FSfr[aAddr]
  else
    Result := 0;
end;

function TMcs51.ReadDirect(aAddr: Byte): Byte;
begin
  if aAddr < $80 then
    Exit(FIRam[aAddr]);
  case aAddr of
    SFR_P0, SFR_P1, SFR_P2, SFR_P3:
      if FRmw or not Assigned(OnPortIn) then
        Result := FSfr[aAddr]
      else
        Result := OnPortIn((aAddr - SFR_P0) shr 4) and FSfr[aAddr];   // pins pulled low by the latch
    SFR_PSW:
      Result := GetPsw;
  else
    Result := FSfr[aAddr];
  end;
end;

procedure TMcs51.WriteDirect(aAddr, aValue: Byte);
begin
  if aAddr < $80 then
  begin
    FIRam[aAddr] := aValue;
    Exit;
  end;
  FSfr[aAddr] := aValue;
  case aAddr of
    SFR_P0, SFR_P1, SFR_P2, SFR_P3:
      if Assigned(OnPortOut) then
        OnPortOut((aAddr - SFR_P0) shr 4, aValue);
  end;
end;

function TMcs51.ReadIndirect(aAddr: Byte): Byte;
begin
  Result := FIRam[aAddr];
end;

procedure TMcs51.WriteIndirect(aAddr, aValue: Byte);
begin
  FIRam[aAddr] := aValue;
end;

function TMcs51.ReadBit(aBit: Byte): Boolean;
var
  lAddr: Byte;
begin
  if aBit < $80 then
    lAddr := $20 + (aBit shr 3)
  else
    lAddr := aBit and $F8;
  Result := (ReadDirect(lAddr) and (1 shl (aBit and 7))) <> 0;
end;

procedure TMcs51.WriteBit(aBit: Byte; aOn: Boolean);
var
  lAddr, lValue: Byte;
  lSaved: Boolean;
begin
  if aBit < $80 then
    lAddr := $20 + (aBit shr 3)
  else
    lAddr := aBit and $F8;
  lSaved := FRmw;
  FRmw := True;   // bit writes are read-modify-write : the latch, not the pins
  lValue := ReadDirect(lAddr);
  FRmw := lSaved;
  if aOn then
    lValue := lValue or (1 shl (aBit and 7))
  else
    lValue := lValue and not (1 shl (aBit and 7));
  WriteDirect(lAddr, lValue);
end;

procedure TMcs51.Push(aValue: Byte);
begin
  FSfr[SFR_SP] := FSfr[SFR_SP] + 1;
  FIRam[FSfr[SFR_SP]] := aValue;
end;

function TMcs51.Pop: Byte;
begin
  Result := FIRam[FSfr[SFR_SP]];
  FSfr[SFR_SP] := FSfr[SFR_SP] - 1;
end;

procedure TMcs51.Jump(aRel: ShortInt);
begin
  PC := PC + Word(aRel);
end;

procedure TMcs51.AddA(aValue: Byte; aCarry: Integer);
var
  lA, lR: Integer;
  lPsw: Byte;
begin
  lA := GetA;
  lR := lA + aValue + aCarry;
  lPsw := FSfr[SFR_PSW] and not (PSW_CY or PSW_AC or PSW_OV);
  if lR > $FF then lPsw := lPsw or PSW_CY;
  if ((lA and $0F) + (aValue and $0F) + aCarry) > $0F then lPsw := lPsw or PSW_AC;
  if (((lA xor not aValue) and (lA xor lR)) and $80) <> 0 then lPsw := lPsw or PSW_OV;
  FSfr[SFR_PSW] := lPsw;
  SetA(lR);
end;

procedure TMcs51.SubbA(aValue: Byte);
var
  lA, lR, lC: Integer;
  lPsw: Byte;
begin
  lA := GetA;
  lC := Carry;
  lR := lA - aValue - lC;
  lPsw := FSfr[SFR_PSW] and not (PSW_CY or PSW_AC or PSW_OV);
  if lR < 0 then lPsw := lPsw or PSW_CY;
  if ((lA and $0F) - (aValue and $0F) - lC) < 0 then lPsw := lPsw or PSW_AC;
  if (((lA xor aValue) and (lA xor lR)) and $80) <> 0 then lPsw := lPsw or PSW_OV;
  FSfr[SFR_PSW] := lPsw;
  SetA(lR);
end;

procedure TMcs51.SetInt0(aAsserted: Boolean);
begin
  // edge mode : IE0 on the falling edge ; level mode : IE0 follows the pin
  if (FSfr[SFR_TCON] and TCON_IT0) <> 0 then
  begin
    if aAsserted and not FInt0Pin then
      FSfr[SFR_TCON] := FSfr[SFR_TCON] or TCON_IE0;
  end
  else if aAsserted then
    FSfr[SFR_TCON] := FSfr[SFR_TCON] or TCON_IE0
  else
    FSfr[SFR_TCON] := FSfr[SFR_TCON] and not TCON_IE0;
  FInt0Pin := aAsserted;
end;

procedure TMcs51.SetInt1(aAsserted: Boolean);
begin
  if (FSfr[SFR_TCON] and TCON_IT1) <> 0 then
  begin
    if aAsserted and not FInt1Pin then
      FSfr[SFR_TCON] := FSfr[SFR_TCON] or TCON_IE1;
  end
  else if aAsserted then
    FSfr[SFR_TCON] := FSfr[SFR_TCON] or TCON_IE1
  else
    FSfr[SFR_TCON] := FSfr[SFR_TCON] and not TCON_IE1;
  FInt1Pin := aAsserted;
end;

procedure TMcs51.ClockTimers(aCycles: Integer);

  procedure Tick(aTimer: Integer);
  var
    lMode, lTL, lTH: Integer;
    lTLAddr, lTHAddr: Byte;
    lFlag: Byte;
    lCount: Integer;
  begin
    lMode := (FSfr[SFR_TMOD] shr (aTimer * 4)) and 3;
    lTLAddr := SFR_TL0 + aTimer;
    lTHAddr := SFR_TH0 + aTimer;
    if aTimer = 0 then lFlag := TCON_TF0 else lFlag := TCON_TF1;
    for lCount := 1 to aCycles do
    begin
      lTL := FSfr[lTLAddr];
      lTH := FSfr[lTHAddr];
      case lMode of
        0:  // 13 bits : TL low 5 bits + TH
          begin
            lTL := (lTL and $1F) + 1;
            if lTL > $1F then
            begin
              lTL := 0;
              lTH := (lTH + 1) and $FF;
              if lTH = 0 then
                FSfr[SFR_TCON] := FSfr[SFR_TCON] or lFlag;
            end;
            FSfr[lTLAddr] := (FSfr[lTLAddr] and $E0) or lTL;
            FSfr[lTHAddr] := lTH;
          end;
        1:  // 16 bits
          begin
            lTL := lTL + 1;
            if lTL > $FF then
            begin
              lTL := 0;
              lTH := (lTH + 1) and $FF;
              if lTH = 0 then
                FSfr[SFR_TCON] := FSfr[SFR_TCON] or lFlag;
            end;
            FSfr[lTLAddr] := lTL;
            FSfr[lTHAddr] := lTH;
          end;
        2:  // 8 bits auto-reload from TH
          begin
            lTL := lTL + 1;
            if lTL > $FF then
            begin
              lTL := lTH;
              FSfr[SFR_TCON] := FSfr[SFR_TCON] or lFlag;
            end;
            FSfr[lTLAddr] := lTL;
          end;
      else
        // mode 3 : timer 0 splits in two 8-bit counters (TH0 borrows TF1) ; timer 1 stops
        if aTimer = 0 then
        begin
          lTL := lTL + 1;
          if lTL > $FF then
          begin
            lTL := 0;
            FSfr[SFR_TCON] := FSfr[SFR_TCON] or TCON_TF0;
          end;
          FSfr[lTLAddr] := lTL;
          if (FSfr[SFR_TCON] and TCON_TR1) <> 0 then
          begin
            lTH := lTH + 1;
            if lTH > $FF then
            begin
              lTH := 0;
              FSfr[SFR_TCON] := FSfr[SFR_TCON] or TCON_TF1;
            end;
            FSfr[lTHAddr] := lTH;
          end;
        end;
      end;
    end;
  end;

  function Running(aTimer: Integer): Boolean;
  var
    lCfg: Byte;
    lTR, lGateOpen: Boolean;
  begin
    lCfg := (FSfr[SFR_TMOD] shr (aTimer * 4)) and $0F;
    if (lCfg and 4) <> 0 then
      Exit(False);   // counter mode (T0/T1 pins) : not wired on the boards emulated here
    if aTimer = 0 then
    begin
      lTR := (FSfr[SFR_TCON] and TCON_TR0) <> 0;
      lGateOpen := FInt0Pin;
    end
    else
    begin
      lTR := (FSfr[SFR_TCON] and TCON_TR1) <> 0;
      lGateOpen := FInt1Pin;
      if ((FSfr[SFR_TMOD] and 3) = 3) then
        Exit(False);   // timer 0 in mode 3 steals timer 1's run control
    end;
    Result := lTR and (((lCfg and 8) = 0) or lGateOpen);
  end;

begin
  if Running(0) then Tick(0);
  if Running(1) then Tick(1);
end;

// Interrupt entry : sources in priority-poll order INT0, T0, INT1, T1, serial
function TMcs51.CheckInterrupts: Boolean;
const
  CVectors: array[0..4] of Word = ($0003, $000B, $0013, $001B, $0023);
var
  lIE, lIP, lTCON: Byte;
  lPending: array[0..4] of Boolean;
  lLevel, i: Integer;
begin
  Result := False;
  lIE := FSfr[SFR_IE];
  if (lIE and $80) = 0 then
    Exit;
  lTCON := FSfr[SFR_TCON];
  lPending[0] := ((lIE and $01) <> 0) and ((lTCON and TCON_IE0) <> 0);
  lPending[1] := ((lIE and $02) <> 0) and ((lTCON and TCON_TF0) <> 0);
  lPending[2] := ((lIE and $04) <> 0) and ((lTCON and TCON_IE1) <> 0);
  lPending[3] := ((lIE and $08) <> 0) and ((lTCON and TCON_TF1) <> 0);
  lPending[4] := ((lIE and $10) <> 0) and ((FSfr[SFR_SCON] and 3) <> 0);
  lIP := FSfr[SFR_IP];
  for lLevel := 1 downto 0 do
  begin
    if FInService >= lLevel then
      Exit;   // a same or higher level routine is running
    for i := 0 to 4 do
      if lPending[i] and ((((lIP shr i) and 1) = Byte(lLevel))) then
      begin
        // hardware clears edge-triggered and timer flags on entry
        case i of
          0: if (lTCON and TCON_IT0) <> 0 then FSfr[SFR_TCON] := FSfr[SFR_TCON] and not TCON_IE0;
          1: FSfr[SFR_TCON] := FSfr[SFR_TCON] and not TCON_TF0;
          2: if (lTCON and TCON_IT1) <> 0 then FSfr[SFR_TCON] := FSfr[SFR_TCON] and not TCON_IE1;
          3: FSfr[SFR_TCON] := FSfr[SFR_TCON] and not TCON_TF1;
        end;
        Push(PC and $FF);
        Push(PC shr 8);
        PC := CVectors[i];
        FInServiceStack[lLevel] := FInService;
        FInService := lLevel;
        Exit(True);
      end;
  end;
end;

function TMcs51.Step: Integer;
var
  lOp, lB1, lB2, lV: Byte;
  lAddr: Word;
  lTmp, n: Integer;
  lBit: Boolean;
begin
  if CheckInterrupts then
  begin
    ClockTimers(2);
    Inc(Cycles, 2);
    Exit(2);
  end;

  FRmw := False;
  lOp := FetchByte;
  Result := 1;
  n := lOp and 7;
  case lOp of
    $00: ;                                                          // NOP
    $01, $21, $41, $61, $81, $A1, $C1, $E1:                         // AJMP addr11
      begin
        lB1 := FetchByte;
        PC := (PC and $F800) or (Word(lOp shr 5) shl 8) or lB1;
        Result := 2;
      end;
    $11, $31, $51, $71, $91, $B1, $D1, $F1:                         // ACALL addr11
      begin
        lB1 := FetchByte;
        Push(PC and $FF);
        Push(PC shr 8);
        PC := (PC and $F800) or (Word(lOp shr 5) shl 8) or lB1;
        Result := 2;
      end;
    $02:                                                            // LJMP
      begin
        lB1 := FetchByte; lB2 := FetchByte;
        PC := (Word(lB1) shl 8) or lB2;
        Result := 2;
      end;
    $12:                                                            // LCALL
      begin
        lB1 := FetchByte; lB2 := FetchByte;
        Push(PC and $FF);
        Push(PC shr 8);
        PC := (Word(lB1) shl 8) or lB2;
        Result := 2;
      end;
    $03: SetA((GetA shr 1) or (GetA shl 7));                        // RR A
    $13:                                                            // RRC A
      begin
        lV := GetA;
        SetA((lV shr 1) or (Carry shl 7));
        SetCarry((lV and 1) <> 0);
      end;
    $23: SetA((GetA shl 1) or (GetA shr 7));                        // RL A
    $33:                                                            // RLC A
      begin
        lV := GetA;
        SetA((lV shl 1) or Carry);
        SetCarry((lV and $80) <> 0);
      end;
    $04: SetA(GetA + 1);                                            // INC A
    $05:                                                            // INC dir
      begin
        lB1 := FetchByte;
        FRmw := True;
        WriteDirect(lB1, ReadDirect(lB1) + 1);
      end;
    $06, $07: WriteIndirect(FIRam[RegAddr(n and 1)], ReadIndirect(FIRam[RegAddr(n and 1)]) + 1);
    $08..$0F: FIRam[RegAddr(n)] := FIRam[RegAddr(n)] + 1;
    $14: SetA(GetA - 1);                                            // DEC A
    $15:
      begin
        lB1 := FetchByte;
        FRmw := True;
        WriteDirect(lB1, ReadDirect(lB1) - 1);
      end;
    $16, $17: WriteIndirect(FIRam[RegAddr(n and 1)], ReadIndirect(FIRam[RegAddr(n and 1)]) - 1);
    $18..$1F: FIRam[RegAddr(n)] := FIRam[RegAddr(n)] - 1;
    $10:                                                            // JBC bit,rel
      begin
        lB1 := FetchByte; lB2 := FetchByte;
        FRmw := True;
        if ReadBit(lB1) then
        begin
          WriteBit(lB1, False);
          Jump(ShortInt(lB2));
        end;
        Result := 2;
      end;
    $20, $30:                                                       // JB / JNB bit,rel
      begin
        lB1 := FetchByte; lB2 := FetchByte;
        if ReadBit(lB1) = (lOp = $20) then
          Jump(ShortInt(lB2));
        Result := 2;
      end;
    $22, $32:                                                       // RET / RETI
      begin
        lB1 := Pop; lB2 := Pop;
        PC := (Word(lB1) shl 8) or lB2;
        if (lOp = $32) and (FInService >= 0) then
          FInService := FInServiceStack[FInService];
        Result := 2;
      end;
    $24: AddA(FetchByte, 0);
    $25: AddA(ReadDirect(FetchByte), 0);
    $26, $27: AddA(ReadIndirect(FIRam[RegAddr(n and 1)]), 0);
    $28..$2F: AddA(FIRam[RegAddr(n)], 0);
    $34: AddA(FetchByte, Carry);
    $35: AddA(ReadDirect(FetchByte), Carry);
    $36, $37: AddA(ReadIndirect(FIRam[RegAddr(n and 1)]), Carry);
    $38..$3F: AddA(FIRam[RegAddr(n)], Carry);
    $40, $50, $60, $70:                                             // JC JNC JZ JNZ
      begin
        lB1 := FetchByte;
        case lOp of
          $40: lBit := Carry <> 0;
          $50: lBit := Carry = 0;
          $60: lBit := GetA = 0;
        else
          lBit := GetA <> 0;
        end;
        if lBit then
          Jump(ShortInt(lB1));
        Result := 2;
      end;
    $42, $52, $62:                                                  // ORL/ANL/XRL dir,A
      begin
        lB1 := FetchByte;
        FRmw := True;
        lV := ReadDirect(lB1);
        case lOp of
          $42: lV := lV or GetA;
          $52: lV := lV and GetA;
        else
          lV := lV xor GetA;
        end;
        WriteDirect(lB1, lV);
      end;
    $43, $53, $63:                                                  // ORL/ANL/XRL dir,#data
      begin
        lB1 := FetchByte; lB2 := FetchByte;
        FRmw := True;
        lV := ReadDirect(lB1);
        case lOp of
          $43: lV := lV or lB2;
          $53: lV := lV and lB2;
        else
          lV := lV xor lB2;
        end;
        WriteDirect(lB1, lV);
        Result := 2;
      end;
    $44..$4F, $54..$5F, $64..$6F:                                   // ORL/ANL/XRL A,src
      begin
        case lOp and $0F of
          $04: lV := FetchByte;
          $05: lV := ReadDirect(FetchByte);
          $06, $07: lV := ReadIndirect(FIRam[RegAddr(n and 1)]);
        else
          lV := FIRam[RegAddr(n)];
        end;
        case lOp and $F0 of
          $40: SetA(GetA or lV);
          $50: SetA(GetA and lV);
        else
          SetA(GetA xor lV);
        end;
      end;
    $72, $82, $A0, $B0:                                             // ORL/ANL C,bit / C,/bit
      begin
        lBit := ReadBit(FetchByte);
        if lOp in [$A0, $B0] then lBit := not lBit;
        if lOp in [$72, $A0] then
          SetCarry((Carry <> 0) or lBit)
        else
          SetCarry((Carry <> 0) and lBit);
        Result := 2;
      end;
    $73:                                                            // JMP @A+DPTR
      begin
        PC := ((Word(FSfr[SFR_DPH]) shl 8) or FSfr[SFR_DPL]) + GetA;
        Result := 2;
      end;
    $74: SetA(FetchByte);                                           // MOV A,#data
    $75:                                                            // MOV dir,#data
      begin
        lB1 := FetchByte; lB2 := FetchByte;
        WriteDirect(lB1, lB2);
        Result := 2;
      end;
    $76, $77: WriteIndirect(FIRam[RegAddr(n and 1)], FetchByte);
    $78..$7F: FIRam[RegAddr(n)] := FetchByte;
    $80:                                                            // SJMP
      begin
        lB1 := FetchByte;
        Jump(ShortInt(lB1));
        Result := 2;
      end;
    $83:                                                            // MOVC A,@A+PC
      begin
        SetA(Code(PC + GetA));
        Result := 2;
      end;
    $84:                                                            // DIV AB
      begin
        lV := FSfr[SFR_B];
        FSfr[SFR_PSW] := FSfr[SFR_PSW] and not (PSW_CY or PSW_OV);
        if lV = 0 then
          FSfr[SFR_PSW] := FSfr[SFR_PSW] or PSW_OV
        else
        begin
          lTmp := GetA;
          SetA(lTmp div lV);
          FSfr[SFR_B] := lTmp mod lV;
        end;
        Result := 4;
      end;
    $85:                                                            // MOV dir,dir (src first)
      begin
        lB1 := FetchByte; lB2 := FetchByte;
        WriteDirect(lB2, ReadDirect(lB1));
        Result := 2;
      end;
    $86, $87:
      begin
        WriteDirect(FetchByte, ReadIndirect(FIRam[RegAddr(n and 1)]));
        Result := 2;
      end;
    $88..$8F:
      begin
        WriteDirect(FetchByte, FIRam[RegAddr(n)]);
        Result := 2;
      end;
    $90:                                                            // MOV DPTR,#data16
      begin
        FSfr[SFR_DPH] := FetchByte;
        FSfr[SFR_DPL] := FetchByte;
        Result := 2;
      end;
    $92:                                                            // MOV bit,C
      begin
        WriteBit(FetchByte, Carry <> 0);
        Result := 2;
      end;
    $93:                                                            // MOVC A,@A+DPTR
      begin
        SetA(Code(((Word(FSfr[SFR_DPH]) shl 8) or FSfr[SFR_DPL]) + GetA));
        Result := 2;
      end;
    $94: SubbA(FetchByte);
    $95: SubbA(ReadDirect(FetchByte));
    $96, $97: SubbA(ReadIndirect(FIRam[RegAddr(n and 1)]));
    $98..$9F: SubbA(FIRam[RegAddr(n)]);
    $A2: SetCarry(ReadBit(FetchByte));                              // MOV C,bit
    $A3:                                                            // INC DPTR
      begin
        lAddr := ((Word(FSfr[SFR_DPH]) shl 8) or FSfr[SFR_DPL]) + 1;
        FSfr[SFR_DPH] := lAddr shr 8;
        FSfr[SFR_DPL] := lAddr and $FF;
        Result := 2;
      end;
    $A4:                                                            // MUL AB
      begin
        lTmp := GetA * FSfr[SFR_B];
        SetA(lTmp and $FF);
        FSfr[SFR_B] := lTmp shr 8;
        FSfr[SFR_PSW] := FSfr[SFR_PSW] and not (PSW_CY or PSW_OV);
        if lTmp > $FF then
          FSfr[SFR_PSW] := FSfr[SFR_PSW] or PSW_OV;
        Result := 4;
      end;
    $A6, $A7:
      begin
        WriteIndirect(FIRam[RegAddr(n and 1)], ReadDirect(FetchByte));
        Result := 2;
      end;
    $A8..$AF:
      begin
        FIRam[RegAddr(n)] := ReadDirect(FetchByte);
        Result := 2;
      end;
    $B2:                                                            // CPL bit
      begin
        lB1 := FetchByte;
        FRmw := True;
        WriteBit(lB1, not ReadBit(lB1));
      end;
    $B3: SetCarry(Carry = 0);                                       // CPL C
    $B4..$BF:                                                       // CJNE
      begin
        case lOp of
          $B4: begin lV := GetA; lB1 := FetchByte; end;
          $B5: begin lV := GetA; lB1 := ReadDirect(FetchByte); end;
          $B6, $B7: begin lV := ReadIndirect(FIRam[RegAddr(n and 1)]); lB1 := FetchByte; end;
        else
          begin lV := FIRam[RegAddr(n)]; lB1 := FetchByte; end;
        end;
        lB2 := FetchByte;
        SetCarry(lV < lB1);
        if lV <> lB1 then
          Jump(ShortInt(lB2));
        Result := 2;
      end;
    $C0:                                                            // PUSH dir
      begin
        Push(ReadDirect(FetchByte));
        Result := 2;
      end;
    $C2: WriteBit(FetchByte, False);                                // CLR bit
    $C3: SetCarry(False);                                           // CLR C
    $C4: SetA((GetA shr 4) or (GetA shl 4));                        // SWAP A
    $C5:                                                            // XCH A,dir
      begin
        lB1 := FetchByte;
        lV := ReadDirect(lB1);
        WriteDirect(lB1, GetA);
        SetA(lV);
      end;
    $C6, $C7:
      begin
        lB1 := FIRam[RegAddr(n and 1)];
        lV := ReadIndirect(lB1);
        WriteIndirect(lB1, GetA);
        SetA(lV);
      end;
    $C8..$CF:
      begin
        lV := FIRam[RegAddr(n)];
        FIRam[RegAddr(n)] := GetA;
        SetA(lV);
      end;
    $D0:                                                            // POP dir
      begin
        lB1 := FetchByte;
        WriteDirect(lB1, Pop);
        Result := 2;
      end;
    $D2: WriteBit(FetchByte, True);                                 // SETB bit
    $D3: SetCarry(True);                                            // SETB C
    $D4:                                                            // DA A
      begin
        lTmp := GetA;
        if ((lTmp and $0F) > 9) or ((FSfr[SFR_PSW] and PSW_AC) <> 0) then
          lTmp := lTmp + $06;
        if lTmp > $FF then
          SetCarry(True);
        if (((lTmp shr 4) and $1F) > 9) or (Carry <> 0) then
          lTmp := lTmp + $60;
        if lTmp > $FF then
          SetCarry(True);
        SetA(lTmp and $FF);
      end;
    $D5:                                                            // DJNZ dir,rel
      begin
        lB1 := FetchByte; lB2 := FetchByte;
        FRmw := True;
        lV := ReadDirect(lB1) - 1;
        WriteDirect(lB1, lV);
        if lV <> 0 then
          Jump(ShortInt(lB2));
        Result := 2;
      end;
    $D6, $D7:                                                       // XCHD A,@Ri
      begin
        lB1 := FIRam[RegAddr(n and 1)];
        lV := ReadIndirect(lB1);
        WriteIndirect(lB1, (lV and $F0) or (GetA and $0F));
        SetA((GetA and $F0) or (lV and $0F));
      end;
    $D8..$DF:                                                       // DJNZ Rn,rel
      begin
        lB2 := FetchByte;
        FIRam[RegAddr(n)] := FIRam[RegAddr(n)] - 1;
        if FIRam[RegAddr(n)] <> 0 then
          Jump(ShortInt(lB2));
        Result := 2;
      end;
    $E0, $E2, $E3:                                                  // MOVX A,@DPTR / @Ri : no external RAM
      begin
        SetA($FF);
        Result := 2;
      end;
    $F0, $F2, $F3:                                                  // MOVX @DPTR,A / @Ri,A : ignored
      Result := 2;
    $E4: SetA(0);                                                   // CLR A
    $E5: SetA(ReadDirect(FetchByte));
    $E6, $E7: SetA(ReadIndirect(FIRam[RegAddr(n and 1)]));
    $E8..$EF: SetA(FIRam[RegAddr(n)]);
    $F4: SetA(not GetA);                                            // CPL A
    $F5: WriteDirect(FetchByte, GetA);
    $F6, $F7: WriteIndirect(FIRam[RegAddr(n and 1)], GetA);
    $F8..$FF: FIRam[RegAddr(n)] := GetA;
  else
    ;                                                               // A5 : reserved
  end;
  FRmw := False;
  ClockTimers(Result);
  Inc(Cycles, Result);
end;

end.
