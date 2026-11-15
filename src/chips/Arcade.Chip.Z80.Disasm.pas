unit Arcade.Chip.Z80.Disasm;

///  Z80 disassembler - same x/y/z/p/q decoding as Arcade.Z80, so both read the opcode space alike.
///  Gives the text AND the control flow (kind + target) : the code mapper follows it.
///  Syntax : lowercase Zilog, hex as $xx / $xxxx. Undocumented opcodes are named (sll, ixh, ...).
///  Pure unit, FPC compatible.

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

uses
  System.SysUtils;

type
  TZ80ByteReader = reference to function(aAddr: Word): Byte;

  TZ80FlowKind = (
    fkNormal,        // falls through
    fkJump,          // jp nn / jr d : never falls through
    fkJumpCond,      // jp cc / jr cc / djnz : target or fall through
    fkCall,          // call nn : target, then falls through
    fkCallCond,
    fkRst,           // rst n : like a call
    fkRet,           // ret / reti / retn : never falls through
    fkRetCond,
    fkJumpIndirect,  // jp (hl) / (ix) / (iy) : target unknown statically (jump tables)
    fkRepeat,        // ldir/cpir/inir/otir... : falls through, or re-executes itself
    fkHalt);

  TZ80Instr = record
    Addr: Word;
    Len: Integer;
    Text: string;
    Kind: TZ80FlowKind;
    Target: Word;          // valid when HasTarget
    HasTarget: Boolean;
    MemRef: Integer;       // absolute address read/written by ld (nn) forms, -1 if none
  end;

function Z80Disassemble(const aRead: TZ80ByteReader; aAddr: Word): TZ80Instr;

function Hex2(aValue: Integer): string; inline;
function Hex4(aValue: Integer): string; inline;

implementation

const
  CR: array[0..7] of string = ('b', 'c', 'd', 'e', 'h', 'l', '(hl)', 'a');
  CRP: array[0..3] of string = ('bc', 'de', 'hl', 'sp');
  CRP2: array[0..3] of string = ('bc', 'de', 'hl', 'af');
  CCC: array[0..7] of string = ('nz', 'z', 'nc', 'c', 'po', 'pe', 'p', 'm');
  CALU: array[0..7] of string = ('add a,', 'adc a,', 'sub ', 'sbc a,', 'and ', 'xor ', 'or ', 'cp ');
  CROT: array[0..7] of string = ('rlc', 'rrc', 'rl', 'rr', 'sla', 'sra', 'sll', 'srl');
  CIM: array[0..7] of string = ('0', '0/1', '1', '2', '0', '0/1', '1', '2');
  CBLI: array[4..7, 0..3] of string = (
    ('ldi', 'cpi', 'ini', 'outi'),
    ('ldd', 'cpd', 'ind', 'outd'),
    ('ldir', 'cpir', 'inir', 'otir'),
    ('lddr', 'cpdr', 'indr', 'otdr'));

function Hex2(aValue: Integer): string;
begin
  Result := '$' + IntToHex(aValue and $FF, 2);
end;

function Hex4(aValue: Integer): string;
begin
  Result := '$' + IntToHex(aValue and $FFFF, 4);
end;

function Z80Disassemble(const aRead: TZ80ByteReader; aAddr: Word): TZ80Instr;
var
  lPos: Word;
  lIdx: string;          // '', 'ix' or 'iy'
  lDispDone: Boolean;
  lDisp: ShortInt;

  function NextByte: Byte;
  begin
    Result := aRead(lPos);
    lPos := lPos + 1;
  end;

  function NextWord: Word;
  var
    lLo: Byte;
  begin
    lLo := NextByte;
    Result := lLo or (Word(NextByte) shl 8);
  end;

  // (hl) -> (ix+d) : the displacement byte comes right after the opcode
  function MemOperand: string;
  begin
    if lIdx = '' then
      Exit('(hl)');
    if not lDispDone then
    begin
      lDisp := ShortInt(NextByte);
      lDispDone := True;
    end;
    if lDisp < 0 then
      Result := '(' + lIdx + '-' + Hex2(-lDisp) + ')'
    else
      Result := '(' + lIdx + '+' + Hex2(lDisp) + ')';
  end;

  // r[i] ; aIndexHL : h/l become ixh/ixl (only when no (ix+d) operand in the instruction)
  function Reg(i: Integer; aIndexHL: Boolean): string;
  begin
    if i = 6 then
      Result := MemOperand
    else if aIndexHL and (lIdx <> '') and (i in [4, 5]) then
    begin
      if i = 4 then Result := lIdx + 'h' else Result := lIdx + 'l';
    end
    else
      Result := CR[i];
  end;

  function RegPair(p: Integer; aAF: Boolean): string;
  begin
    if (p = 2) and (lIdx <> '') then
      Result := lIdx
    else if aAF then
      Result := CRP2[p]
    else
      Result := CRP[p];
  end;

  procedure SetFlow(aKind: TZ80FlowKind; aTarget: Integer);
  begin
    Result.Kind := aKind;
    if aTarget >= 0 then
    begin
      Result.Target := aTarget;
      Result.HasTarget := True;
    end;
  end;

var
  lOp, x, y, z, p, q: Integer;
  lN: Word;
  lD: ShortInt;
  lOperand: string;
begin
  Result := Default(TZ80Instr);
  Result.Addr := aAddr;
  Result.MemRef := -1;
  lPos := aAddr;
  lIdx := '';
  lDispDone := False;
  lDisp := 0;

  lOp := NextByte;
  while (lOp = $DD) or (lOp = $FD) do
  begin
    if lOp = $DD then lIdx := 'ix' else lIdx := 'iy';
    lOp := NextByte;
  end;

  x := lOp shr 6; y := (lOp shr 3) and 7; z := lOp and 7; p := y shr 1; q := y and 1;

  if lOp = $CB then
  begin
    if lIdx <> '' then
    begin
      lDisp := ShortInt(NextByte);   // DD CB d op
      lDispDone := True;
    end;
    lOp := NextByte;
    x := lOp shr 6; y := (lOp shr 3) and 7; z := lOp and 7;
    if lIdx <> '' then
      lOperand := MemOperand
    else
      lOperand := CR[z];
    case x of
      0: Result.Text := CROT[y] + ' ' + lOperand;
      1: Result.Text := 'bit ' + IntToStr(y) + ',' + lOperand;
      2: Result.Text := 'res ' + IntToStr(y) + ',' + lOperand;
    else
      Result.Text := 'set ' + IntToStr(y) + ',' + lOperand;
    end;
    if (lIdx <> '') and (z <> 6) and (x <> 1) then
      Result.Text := Result.Text + ',' + CR[z];   // undocumented copy to register
  end
  else if lOp = $ED then
  begin
    lOp := NextByte;
    x := lOp shr 6; y := (lOp shr 3) and 7; z := lOp and 7; p := y shr 1; q := y and 1;
    if x = 1 then
      case z of
        0: if y = 6 then Result.Text := 'in (c)' else Result.Text := 'in ' + CR[y] + ',(c)';
        1: if y = 6 then Result.Text := 'out (c),0' else Result.Text := 'out (c),' + CR[y];
        2: if q = 0 then Result.Text := 'sbc hl,' + CRP[p] else Result.Text := 'adc hl,' + CRP[p];
        3: begin
             lN := NextWord;
             Result.MemRef := lN;
             if q = 0 then
               Result.Text := 'ld (' + Hex4(lN) + '),' + CRP[p]
             else
               Result.Text := 'ld ' + CRP[p] + ',(' + Hex4(lN) + ')';
           end;
        4: Result.Text := 'neg';
        5: begin
             if y = 1 then Result.Text := 'reti' else Result.Text := 'retn';
             SetFlow(fkRet, -1);
           end;
        6: Result.Text := 'im ' + CIM[y];
      else
        case y of
          0: Result.Text := 'ld i,a';
          1: Result.Text := 'ld r,a';
          2: Result.Text := 'ld a,i';
          3: Result.Text := 'ld a,r';
          4: Result.Text := 'rrd';
          5: Result.Text := 'rld';
        else
          Result.Text := 'nop*';
        end;
      end
    else if (x = 2) and (z <= 3) and (y >= 4) then
    begin
      Result.Text := CBLI[y, z];
      if y >= 6 then
        SetFlow(fkRepeat, -1);
    end
    else
      Result.Text := 'db $ED,' + Hex2(lOp);
  end
  else
    case x of
      0:
        case z of
          0:
            case y of
              0: Result.Text := 'nop';
              1: Result.Text := 'ex af,af''';
              2: begin
                   lD := ShortInt(NextByte);
                   Result.Text := 'djnz ' + Hex4(lPos + lD);
                   SetFlow(fkJumpCond, Word(lPos + lD));
                 end;
              3: begin
                   lD := ShortInt(NextByte);
                   Result.Text := 'jr ' + Hex4(lPos + lD);
                   SetFlow(fkJump, Word(lPos + lD));
                 end;
            else
              lD := ShortInt(NextByte);
              Result.Text := 'jr ' + CCC[y - 4] + ',' + Hex4(lPos + lD);
              SetFlow(fkJumpCond, Word(lPos + lD));
            end;
          1:
            if q = 0 then
            begin
              lN := NextWord;
              Result.Text := 'ld ' + RegPair(p, False) + ',' + Hex4(lN);
            end
            else
              Result.Text := 'add ' + RegPair(2, False) + ',' + RegPair(p, False);
          2:
            case y of
              0: Result.Text := 'ld (bc),a';
              1: Result.Text := 'ld a,(bc)';
              2: Result.Text := 'ld (de),a';
              3: Result.Text := 'ld a,(de)';
              4: begin lN := NextWord; Result.MemRef := lN; Result.Text := 'ld (' + Hex4(lN) + '),' + RegPair(2, False); end;
              5: begin lN := NextWord; Result.MemRef := lN; Result.Text := 'ld ' + RegPair(2, False) + ',(' + Hex4(lN) + ')'; end;
              6: begin lN := NextWord; Result.MemRef := lN; Result.Text := 'ld (' + Hex4(lN) + '),a'; end;
            else
              lN := NextWord; Result.MemRef := lN; Result.Text := 'ld a,(' + Hex4(lN) + ')';
            end;
          3:
            if q = 0 then Result.Text := 'inc ' + RegPair(p, False) else Result.Text := 'dec ' + RegPair(p, False);
          4: Result.Text := 'inc ' + Reg(y, True);
          5: Result.Text := 'dec ' + Reg(y, True);
          6:
            begin
              lOperand := Reg(y, True);   // fetches d before n for (ix+d),n
              Result.Text := 'ld ' + lOperand + ',' + Hex2(NextByte);
            end;
        else
          case y of
            0: Result.Text := 'rlca';
            1: Result.Text := 'rrca';
            2: Result.Text := 'rla';
            3: Result.Text := 'rra';
            4: Result.Text := 'daa';
            5: Result.Text := 'cpl';
            6: Result.Text := 'scf';
          else
            Result.Text := 'ccf';
          end;
        end;
      1:
        if (y = 6) and (z = 6) then
        begin
          Result.Text := 'halt';
          SetFlow(fkHalt, -1);
        end
        else if (y = 6) or (z = 6) then
          Result.Text := 'ld ' + Reg(y, False) + ',' + Reg(z, False)
        else
          Result.Text := 'ld ' + Reg(y, True) + ',' + Reg(z, True);
      2:
        Result.Text := CALU[y] + Reg(z, z <> 6);
    else
      case z of
        0:
          begin
            Result.Text := 'ret ' + CCC[y];
            SetFlow(fkRetCond, -1);
          end;
        1:
          if q = 0 then
            Result.Text := 'pop ' + RegPair(p, True)
          else
            case p of
              0: begin Result.Text := 'ret'; SetFlow(fkRet, -1); end;
              1: Result.Text := 'exx';
              2: begin Result.Text := 'jp (' + RegPair(2, False) + ')'; SetFlow(fkJumpIndirect, -1); end;
            else
              Result.Text := 'ld sp,' + RegPair(2, False);
            end;
        2:
          begin
            lN := NextWord;
            Result.Text := 'jp ' + CCC[y] + ',' + Hex4(lN);
            SetFlow(fkJumpCond, lN);
          end;
        3:
          case y of
            0: begin lN := NextWord; Result.Text := 'jp ' + Hex4(lN); SetFlow(fkJump, lN); end;
            2: Result.Text := 'out (' + Hex2(NextByte) + '),a';
            3: Result.Text := 'in a,(' + Hex2(NextByte) + ')';
            4: Result.Text := 'ex (sp),' + RegPair(2, False);
            5: Result.Text := 'ex de,hl';
            6: Result.Text := 'di';
            7: Result.Text := 'ei';
          end;
        4:
          begin
            lN := NextWord;
            Result.Text := 'call ' + CCC[y] + ',' + Hex4(lN);
            SetFlow(fkCallCond, lN);
          end;
        5:
          if q = 0 then
            Result.Text := 'push ' + RegPair(p, True)
          else
          begin
            lN := NextWord;
            Result.Text := 'call ' + Hex4(lN);
            SetFlow(fkCall, lN);
          end;
        6:
          Result.Text := CALU[y] + Hex2(NextByte);
      else
        Result.Text := 'rst ' + Hex2(y * 8);
        SetFlow(fkRst, y * 8);
      end;
    end;

  Result.Len := Word(lPos - aAddr);
end;

end.
