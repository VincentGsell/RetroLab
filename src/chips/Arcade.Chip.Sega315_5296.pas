unit Arcade.Chip.Sega315_5296;

///  Sega 315-5296 I/O controller : 8 ports A to H, each one input or output.
///    registers $0-$7 : ports A-H (an output port reads back its latch)
///    registers $8-$B : the letters 'S', 'E', 'G', 'A' (protection check)
///    register  $E    : CNT pins (d0-d2), read back at $C / $E
///    register  $F    : direction, one bit per port (1 = output), read back at $D / $F
///  At reset every port is an input and the output latches are cleared.
///  Behaviour follows MAME 315_5296.cpp (BSD-3). Pure unit, FPC compatible.

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

type
  TSegaIoPortIn = function(aPort: Integer): Byte of object;
  TSegaIoPortOut = procedure(aPort: Integer; aValue: Byte) of object;

  TSega315_5296 = class
  private
    FLatch: array[0..7] of Byte;
    FDir: Byte;
    FCnt: Byte;
  public
    OnPortIn: TSegaIoPortIn;
    OnPortOut: TSegaIoPortOut;
    procedure Reset;
    function Read(aOffset: Integer): Byte;
    procedure Write(aOffset: Integer; aValue: Byte);
    function Latch(aPort: Integer): Byte;
    property Direction: Byte read FDir;
  end;

implementation

procedure TSega315_5296.Reset;
var
  i: Integer;
begin
  FDir := 0;
  FCnt := 0;
  for i := 0 to 7 do
  begin
    FLatch[i] := 0;
    if Assigned(OnPortOut) then
      OnPortOut(i, 0);
  end;
end;

function TSega315_5296.Latch(aPort: Integer): Byte;
begin
  Result := FLatch[aPort and 7];
end;

function TSega315_5296.Read(aOffset: Integer): Byte;
begin
  aOffset := aOffset and $3F;
  case aOffset of
    0..7:
      if ((FDir shr aOffset) and 1) <> 0 then
        Result := FLatch[aOffset]
      else if Assigned(OnPortIn) then
        Result := OnPortIn(aOffset)
      else
        Result := $FF;
    8: Result := Ord('S');
    9: Result := Ord('E');
    10: Result := Ord('G');
    11: Result := Ord('A');
    12, 14: Result := FCnt;
    13, 15: Result := FDir;
  else
    Result := $FF;
  end;
end;

procedure TSega315_5296.Write(aOffset: Integer; aValue: Byte);
var
  i: Integer;
begin
  aOffset := aOffset and $3F;
  case aOffset of
    0..7:
      begin
        if (((FDir shr aOffset) and 1) <> 0) and Assigned(OnPortOut) then
          OnPortOut(aOffset, aValue);
        FLatch[aOffset] := aValue;
      end;
    14: FCnt := aValue;
    15:
      begin
        for i := 0 to 7 do
          if (((FDir xor aValue) shr i) and 1) <> 0 then
            if Assigned(OnPortOut) then
            begin
              if ((aValue shr i) and 1) <> 0 then
                OnPortOut(i, FLatch[i])
              else
                OnPortOut(i, 0);
            end;
        FDir := aValue;
      end;
  end;
end;

end.
