unit Arcade.Board.CapcomBM.Gfx;

///  Capcom "BM" board - graphics formats and colour wiring (same family as PCB 85113, one more layer).
///    chars    8x8,   2 bpp, 2048
///    tiles 1  32x32, 4 bpp, 512   front background (bg1), pens whose lookup gives $0F are transparent
///    tiles 2  32x32, 4 bpp, 128   back background (bg2), opaque
///    sprites  16x16, 4 bpp, 2048
///    palette : 256 entries through the 4-bit resistor DAC (as PCB 84100), behind lookup PROMs :
///      chars 000-07F, bg1 080-17F, bg2 180-27F, sprites 280-37F ; sprite bank PROM bit 3 = priority.
///  Reference : MAME driver capcom/1943.cpp (layouts) and 1943_v.cpp (_1943_palette). No FMX.

interface

uses
  System.SysUtils,
  Arcade.Gfx,
  Arcade.RomSet;

type
  TGfxBM = record
    Chars, Bg1Tiles, Bg2Tiles, Sprites: TGfxSet;
    Rgb: array[0..255] of TArgb;
    Pens: array[0..$37F] of Byte;
    SpritePriority: array[0..255] of Boolean;   // True : the sprite pen stays BEHIND bg1
    function Color(aPen: Integer): TArgb; inline;
  end;

const
  CBMCharBase = $000;
  CBMBg1Base = $080;
  CBMBg2Base = $180;
  CBMSpriteBase = $280;

function DecodeGfxBM(aRoms: TRomSetData): TGfxBM;

implementation

function TGfxBM.Color(aPen: Integer): TArgb;
begin
  Result := Rgb[Pens[aPen]];
end;

function CharLayout(aRegionSize: Integer): TGfxLayout;
const
  X: array[0..7] of Integer = (0, 1, 2, 3, 8, 9, 10, 11);
var
  i: Integer;
begin
  Result := Default(TGfxLayout);
  Result.Width := 8;
  Result.Height := 8;
  Result.Planes := 2;
  Result.PlaneOfs[0] := 4;
  Result.PlaneOfs[1] := 0;
  for i := 0 to 7 do
  begin
    Result.XOfs[i] := X[i];
    Result.YOfs[i] := i * 16;
  end;
  Result.CharInc := 16 * 8;
  Result.Count := (aRegionSize * 8) div Result.CharInc;
end;

// STEP4(0,1) STEP4(8,1) STEP4(512,1) STEP4(520,1) ... : 8 groups of 4 pixels
function TileLayout(aRegionSize: Integer): TGfxLayout;
var
  lHalf, i: Integer;
begin
  Result := Default(TGfxLayout);
  lHalf := (aRegionSize * 8) div 2;
  Result.Width := 32;
  Result.Height := 32;
  Result.Planes := 4;
  Result.PlaneOfs[0] := lHalf + 4;
  Result.PlaneOfs[1] := lHalf + 0;
  Result.PlaneOfs[2] := 4;
  Result.PlaneOfs[3] := 0;
  for i := 0 to 31 do
  begin
    Result.XOfs[i] := (i div 8) * 512 + ((i div 4) and 1) * 8 + (i and 3);
    Result.YOfs[i] := i * 16;
  end;
  Result.CharInc := 256 * 8;
  Result.Count := lHalf div Result.CharInc;
end;

function SpriteLayout(aRegionSize: Integer): TGfxLayout;
const
  X: array[0..15] of Integer = (0, 1, 2, 3, 8, 9, 10, 11, 256, 257, 258, 259, 264, 265, 266, 267);
var
  lHalf, i: Integer;
begin
  Result := Default(TGfxLayout);
  lHalf := (aRegionSize * 8) div 2;
  Result.Width := 16;
  Result.Height := 16;
  Result.Planes := 4;
  Result.PlaneOfs[0] := lHalf + 4;
  Result.PlaneOfs[1] := lHalf + 0;
  Result.PlaneOfs[2] := 4;
  Result.PlaneOfs[3] := 0;
  for i := 0 to 15 do
  begin
    Result.XOfs[i] := X[i];
    Result.YOfs[i] := i * 16;
  end;
  Result.CharInc := 64 * 8;
  Result.Count := lHalf div Result.CharInc;
end;

function DecodeGfxBM(aRoms: TRomSetData): TGfxBM;

  function Dac(aNibble: Byte): Byte;
  begin
    Result := $0E * (aNibble and 1) + $1F * ((aNibble shr 1) and 1)
            + $43 * ((aNibble shr 2) and 1) + $8F * ((aNibble shr 3) and 1);
  end;

var
  lProm: TBytes;
  i: Integer;
begin
  Result.Chars := DecodeGfx(aRoms.Region('gfx1'), CharLayout(Length(aRoms.Region('gfx1'))));
  Result.Bg1Tiles := DecodeGfx(aRoms.Region('gfx2'), TileLayout(Length(aRoms.Region('gfx2'))));
  Result.Bg2Tiles := DecodeGfx(aRoms.Region('gfx3'), TileLayout(Length(aRoms.Region('gfx3'))));
  Result.Sprites := DecodeGfx(aRoms.Region('gfx4'), SpriteLayout(Length(aRoms.Region('gfx4'))));

  lProm := aRoms.Region('proms');
  for i := 0 to 255 do
    Result.Rgb[i] := $FF000000 or (TArgb(Dac(lProm[i])) shl 16)
      or (TArgb(Dac(lProm[i + $100])) shl 8) or TArgb(Dac(lProm[i + $200]));
  for i := 0 to $7F do
    Result.Pens[CBMCharBase + i] := (lProm[$300 + i] and $0F) or $40;
  for i := 0 to $FF do
  begin
    Result.Pens[CBMBg1Base + i] := ((lProm[$500 + i] and 3) shl 4) or (lProm[$400 + i] and $0F);
    Result.Pens[CBMBg2Base + i] := ((lProm[$700 + i] and 3) shl 4) or (lProm[$600 + i] and $0F);
    Result.Pens[CBMSpriteBase + i] := ((lProm[$900 + i] and 7) shl 4) or (lProm[$800 + i] and $0F) or $80;
    Result.SpritePriority[i] := (lProm[$900 + i] and $08) <> 0;
  end;
end;

end.
