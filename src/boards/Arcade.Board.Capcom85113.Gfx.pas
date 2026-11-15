unit Arcade.Board.Capcom85113.Gfx;

///  Capcom PCB 85113 - graphics formats and colour wiring.
///    chars   8x8,   2 bpp, 1024  (stored mirrored on both axes)
///    tiles   32x32, 4 bpp, 512   (the background map itself is a ROM : 2048 x 8 tiles)
///    sprites 16x16, 4 bpp, 2048
///    palette : 256 RGB444 entries (3 PROMs) reached through lookup PROMs :
///      chars   pens 000-07F : lut | $40
///      tiles   pens 080-17F : lut | (tile bank PROM & 3) << 4
///      sprites pens 180-27F : lut | (sprite bank PROM & 7) << 4 | $80
///  Reference : MAME driver capcom/gunsmoke.cpp (layouts, palette()). Pure unit : no FMX.

interface

uses
  System.SysUtils,
  Arcade.Gfx,
  Arcade.RomSet;

type
  TGfx85113 = record
    Chars, Tiles, Sprites: TGfxSet;
    Rgb: array[0..255] of TArgb;
    Pens: array[0..$27F] of Byte;        // pen -> palette entry
    function CharColor(aColor: Integer; aPen: Byte): TArgb; inline;
    function TileColor(aColor: Integer; aPen: Byte): TArgb; inline;
    function SpriteColor(aColor: Integer; aPen: Byte): TArgb; inline;
    /// Text pixels whose lookup gives entry $4F are transparent (MAME configure_groups(.., 0x4f)).
    function CharTransparent(aColor: Integer; aPen: Byte): Boolean; inline;
  end;

function DecodeGfx85113(aRoms: TRomSetData): TGfx85113;

implementation

{ TGfx85113 }

function TGfx85113.CharColor(aColor: Integer; aPen: Byte): TArgb;
begin
  Result := Rgb[Pens[aColor * 4 + aPen]];
end;

function TGfx85113.TileColor(aColor: Integer; aPen: Byte): TArgb;
begin
  Result := Rgb[Pens[$80 + aColor * 16 + aPen]];
end;

function TGfx85113.SpriteColor(aColor: Integer; aPen: Byte): TArgb;
begin
  Result := Rgb[Pens[$180 + aColor * 16 + aPen]];
end;

function TGfx85113.CharTransparent(aColor: Integer; aPen: Byte): Boolean;
begin
  Result := Pens[aColor * 4 + aPen] = $4F;
end;

function CharLayout: TGfxLayout;
const
  X: array[0..7] of Integer = (8 + 3, 8 + 2, 8 + 1, 8 + 0, 3, 2, 1, 0);
var
  i: Integer;
begin
  Result := Default(TGfxLayout);
  Result.Width := 8;
  Result.Height := 8;
  Result.Count := 1024;
  Result.Planes := 2;
  Result.PlaneOfs[0] := 4;
  Result.PlaneOfs[1] := 0;
  for i := 0 to 7 do
  begin
    Result.XOfs[i] := X[i];
    Result.YOfs[i] := (7 - i) * 16;
  end;
  Result.CharInc := 16 * 8;
end;

function TileLayout: TGfxLayout;
var
  i: Integer;
begin
  Result := Default(TGfxLayout);
  Result.Width := 32;
  Result.Height := 32;
  Result.Count := 512;
  Result.Planes := 4;
  Result.PlaneOfs[0] := 512 * 256 * 8 + 4;
  Result.PlaneOfs[1] := 512 * 256 * 8 + 0;
  Result.PlaneOfs[2] := 4;
  Result.PlaneOfs[3] := 0;
  // 8 groups of 4 pixels : 0-3, 8-11 of bytes 0, 64, 128, 192 (64*8 bits apart)
  for i := 0 to 31 do
    Result.XOfs[i] := (i div 8) * 64 * 8 + ((i div 4) and 1) * 8 + (i and 3);
  for i := 0 to 31 do
    Result.YOfs[i] := i * 16;
  Result.CharInc := 256 * 8;
end;

function SpriteLayout: TGfxLayout;
const
  X: array[0..15] of Integer = (0, 1, 2, 3, 8 + 0, 8 + 1, 8 + 2, 8 + 3,
    32 * 8 + 0, 32 * 8 + 1, 32 * 8 + 2, 32 * 8 + 3, 33 * 8 + 0, 33 * 8 + 1, 33 * 8 + 2, 33 * 8 + 3);
var
  i: Integer;
begin
  Result := Default(TGfxLayout);
  Result.Width := 16;
  Result.Height := 16;
  Result.Count := 2048;
  Result.Planes := 4;
  Result.PlaneOfs[0] := 2048 * 64 * 8 + 4;
  Result.PlaneOfs[1] := 2048 * 64 * 8 + 0;
  Result.PlaneOfs[2] := 4;
  Result.PlaneOfs[3] := 0;
  for i := 0 to 15 do
  begin
    Result.XOfs[i] := X[i];
    Result.YOfs[i] := i * 16;
  end;
  Result.CharInc := 64 * 8;
end;

function DecodeGfx85113(aRoms: TRomSetData): TGfx85113;
var
  lProm: TBytes;
  i: Integer;
begin
  Result.Chars := DecodeGfx(aRoms.Region('chars'), CharLayout);
  Result.Tiles := DecodeGfx(aRoms.Region('tiles'), TileLayout);
  Result.Sprites := DecodeGfx(aRoms.Region('sprites'), SpriteLayout);

  lProm := aRoms.Region('proms');
  for i := 0 to 255 do
    Result.Rgb[i] := $FF000000
      or (TArgb((lProm[i] and $0F) * $11) shl 16)
      or (TArgb((lProm[i + $100] and $0F) * $11) shl 8)
      or TArgb((lProm[i + $200] and $0F) * $11);
  for i := 0 to $7F do
    Result.Pens[i] := (lProm[$300 + i] and $0F) or $40;
  for i := 0 to $FF do
    Result.Pens[$80 + i] := (lProm[$400 + i] and $0F) or ((lProm[$500 + i] and 3) shl 4);
  for i := 0 to $FF do
    Result.Pens[$180 + i] := (lProm[$600 + i] and $0F) or ((lProm[$700 + i] and 7) shl 4) or $80;
end;

end.
