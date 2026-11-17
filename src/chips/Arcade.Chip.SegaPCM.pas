unit Arcade.Chip.SegaPCM;

///  Sega 315-5218 PCM : 16 voices of 8-bit unsigned samples read from ROM, stereo volume, loop.
///  Behaviour follows MAME segapcm.cpp (BSD-3) :
///    registers, voice v at v * 8 : +2 left volume, +3 right volume, +4/+5 loop address (bits 8-23),
///    +6 end page, +7 address step ; $84/$85 current address (bits 8-23), $86 control
///    (b0 voice off, b1 no loop, upper bits ROM bank)
///    output rate = clock / 128 (16 voices x 8 cycles)
///  Pure unit, FPC compatible.

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}
{$Q-}
{$R-}

interface

uses
  SysUtils;

type
  TSegaPcmVoice = record
    Addr: Cardinal;      // 16.8 : page.offset.fraction
    Loop: Word;
    EndPage: Byte;
    Freq: Byte;
    LVol, RVol: Byte;
    Ctrl: Byte;
  end;

  TSegaPCM = class
  private
    FClock: Double;
    FRom: TBytes;
    FRomMask: Cardinal;
    FBankShift: Integer;
    FBankMask: Byte;
    FRam: array[0..$FF] of Byte;
    FVoices: array[0..15] of TSegaPcmVoice;
    FPos: Double;
    FPrevL, FCurL, FPrevR, FCurR: Integer;
    procedure Tick(out aLeft, aRight: Integer);
  public
    /// Board mixing gain (MAME add_route). Default 1.
    Gain: Single;
    /// aRom : the PCM region ; banking as MAME set_bank : 512 KB boards (BANK_512) shift 12, mask $70 ;
    /// 2 MB boards (BANK_12M | BANK_MASKF8) shift 13, mask $F8.
    constructor Create(aClock: Double; const aRom: TBytes; aBankShift: Integer = 12; aBankMask: Byte = $70);
    procedure Reset;
    function Read(aOffset: Byte): Byte;
    procedure Write(aOffset: Byte; aValue: Byte);
    procedure RenderStereo(var aLeft, aRight: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
    procedure Render(var aBuffer: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
  end;

implementation

constructor TSegaPCM.Create(aClock: Double; const aRom: TBytes; aBankShift: Integer; aBankMask: Byte);
var
  lSize: Cardinal;
begin
  inherited Create;
  FClock := aClock;
  FRom := aRom;
  lSize := 1;
  while lSize < Cardinal(Length(aRom)) do
    lSize := lSize shl 1;
  FRomMask := lSize - 1;
  FBankShift := aBankShift;
  FBankMask := aBankMask;
  Gain := 1;
  Reset;
end;

procedure TSegaPCM.Reset;
var
  i: Integer;
begin
  FillChar(FRam, SizeOf(FRam), $FF);
  for i := 0 to 15 do
  begin
    FVoices[i] := Default(TSegaPcmVoice);
    FVoices[i].Ctrl := 1;
  end;
  FPos := 0;
  FPrevL := 0;
  FCurL := 0;
  FPrevR := 0;
  FCurR := 0;
end;

function TSegaPCM.Read(aOffset: Byte): Byte;
var
  v: ^TSegaPcmVoice;
begin
  v := @FVoices[(aOffset shr 3) and 15];
  case aOffset and $87 of
    $02: Result := v.LVol;
    $03: Result := v.RVol;
    $04: Result := v.Loop and $FF;
    $05: Result := v.Loop shr 8;
    $06: Result := v.EndPage;
    $07: Result := v.Freq;
    $84: Result := (v.Addr shr 8) and $FF;
    $85: Result := (v.Addr shr 16) and $FF;
    $86: Result := v.Ctrl;
  else
    Result := FRam[aOffset];
  end;
end;

procedure TSegaPCM.Write(aOffset: Byte; aValue: Byte);
var
  v: ^TSegaPcmVoice;
begin
  FRam[aOffset] := aValue;
  v := @FVoices[(aOffset shr 3) and 15];
  case aOffset and $87 of
    $02: v.LVol := aValue;
    $03: v.RVol := aValue;
    $04: v.Loop := (v.Loop and $FF00) or aValue;
    $05: v.Loop := (v.Loop and $00FF) or (Word(aValue) shl 8);
    $06: v.EndPage := aValue;
    $07: v.Freq := aValue;
    $84: v.Addr := (v.Addr and $FF00FF) or (Cardinal(aValue) shl 8);
    $85: v.Addr := (v.Addr and $00FFFF) or (Cardinal(aValue) shl 16);
    $86: v.Ctrl := aValue;
  end;
end;

procedure TSegaPCM.Tick(out aLeft, aRight: Integer);
var
  i, lSample: Integer;
  v: ^TSegaPcmVoice;
  lBank: Cardinal;
begin
  aLeft := 0;
  aRight := 0;
  for i := 0 to 15 do
  begin
    v := @FVoices[i];
    if (v.Ctrl and 1) = 0 then
    begin
      if (v.Addr shr 16) = Cardinal((v.EndPage + 1) and $FF) then
      begin
        if (v.Ctrl and 2) <> 0 then
        begin
          v.Ctrl := v.Ctrl or 1;
          Continue;
        end;
        v.Addr := Cardinal(v.Loop) shl 8;
      end;
      lBank := Cardinal(v.Ctrl and FBankMask) shl FBankShift;
      lSample := Integer(FRom[(lBank + (v.Addr shr 8)) and FRomMask]) - $80;
      Inc(aLeft, lSample * (v.LVol and $7F));
      Inc(aRight, lSample * (v.RVol and $7F));
      v.Addr := (v.Addr + v.Freq) and $FFFFFF;
    end
    else
      v.Addr := v.Addr and $FFFF00;
  end;
end;

procedure TSegaPCM.RenderStereo(var aLeft, aRight: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
var
  s, lL, lR: Integer;
  lStep, lFrac, lGain: Double;
begin
  lStep := FClock / 128 / aSampleRate;
  lGain := Gain / 32768;
  for s := 0 to aCount - 1 do
  begin
    FPos := FPos + lStep;
    while FPos >= 1 do
    begin
      FPos := FPos - 1;
      FPrevL := FCurL;
      FPrevR := FCurR;
      Tick(lL, lR);
      FCurL := lL;
      FCurR := lR;
    end;
    lFrac := FPos;
    aLeft[aOffset + s] := aLeft[aOffset + s] + (FPrevL + (FCurL - FPrevL) * lFrac) * lGain;
    aRight[aOffset + s] := aRight[aOffset + s] + (FPrevR + (FCurR - FPrevR) * lFrac) * lGain;
  end;
end;

procedure TSegaPCM.Render(var aBuffer: array of Single; aOffset, aCount: Integer; aSampleRate: Integer);
var
  s, lL, lR: Integer;
  lStep, lFrac, lGain: Double;
begin
  lStep := FClock / 128 / aSampleRate;
  lGain := Gain / 65536;
  for s := 0 to aCount - 1 do
  begin
    FPos := FPos + lStep;
    while FPos >= 1 do
    begin
      FPos := FPos - 1;
      FPrevL := FCurL;
      FPrevR := FCurR;
      Tick(lL, lR);
      FCurL := lL;
      FCurR := lR;
    end;
    lFrac := FPos;
    aBuffer[aOffset + s] := aBuffer[aOffset + s]
      + ((FPrevL + FPrevR) + ((FCurL + FCurR) - (FPrevL + FPrevR)) * lFrac) * lGain;
  end;
end;

end.
