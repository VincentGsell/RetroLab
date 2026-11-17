unit Arcade.Board.SegaPalette;

///  The palette of the Sega 16-bit boards (System 16, X, Y, Out Run) : one RAM word per colour,
///    sBGR BBBB GGGG RRRR : 5 bits per component, the low bit of each in the top nibble,
///    s = shadow / hilight select.
///  Each 5-bit component drives a resistor network (3.9 k, 2 k, 1 k, 500, 250 ohms). A sixth
///  resistor of 470 ohms, switched by the s bit, gives the darker (shadow) or brighter (hilight)
///  version of every colour, used by the shadow pixels of the sprites.
///  Reference : MAME sega_16bit_common_base::palette_init / paletteram_w. Pure unit : no FMX.

interface

uses
  Arcade.Gfx;

/// aNormal : the colour ; aEffect : its shadow (s = 0) or hilight (s = 1) version.
procedure SegaColor(aValue: Word; out aNormal, aEffect: TArgb);

implementation

var
  GPalNormal, GPalShadow, GPalHilight: array[0..31] of Byte;

procedure InitPaletteTables;
const
  CG: array[0..4] of Double = (1 / 3900, 1 / 2000, 1 / 1000, 1 / 500, 1 / 250);
  CG6 = 1 / 470;
var
  v, b: Integer;
  lSum5, lSum6, lAcc: Double;
begin
  lSum5 := 0;
  for b := 0 to 4 do
    lSum5 := lSum5 + CG[b];
  lSum6 := lSum5 + CG6;
  for v := 0 to 31 do
  begin
    lAcc := 0;
    for b := 0 to 4 do
      if (v and (1 shl b)) <> 0 then
        lAcc := lAcc + CG[b];
    GPalNormal[v] := Round(255 * lAcc / lSum5);
    GPalShadow[v] := Round(255 * lAcc / lSum6);
    GPalHilight[v] := Round(255 * (lAcc + CG6) / lSum6);
  end;
end;

procedure SegaColor(aValue: Word; out aNormal, aEffect: TArgb);
var
  r, g, b: Integer;
begin
  r := ((aValue shr 12) and 1) or ((aValue shl 1) and $1E);
  g := ((aValue shr 13) and 1) or ((aValue shr 3) and $1E);
  b := ((aValue shr 14) and 1) or ((aValue shr 7) and $1E);
  aNormal := $FF000000 or (TArgb(GPalNormal[r]) shl 16) or (TArgb(GPalNormal[g]) shl 8) or GPalNormal[b];
  if (aValue and $8000) <> 0 then
    aEffect := $FF000000 or (TArgb(GPalHilight[r]) shl 16) or (TArgb(GPalHilight[g]) shl 8) or GPalHilight[b]
  else
    aEffect := $FF000000 or (TArgb(GPalShadow[r]) shl 16) or (TArgb(GPalShadow[g]) shl 8) or GPalShadow[b];
end;

initialization
  InitPaletteTables;

end.
