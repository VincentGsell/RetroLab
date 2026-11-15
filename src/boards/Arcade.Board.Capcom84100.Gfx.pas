unit Arcade.Board.Capcom84100.Gfx;

///  Capcom PCB 84100 - graphics formats and colour wiring.
///    gfx1 : characters 8x8, 2 bpp       (text layer)
///    gfx2 : tiles 16x16, 3 bpp          (scrolling background)
///    gfx3 : sprites 16x16, 4 bpp
///    palette : 256 entries from 3 x 256x4 PROMs through a 4-bit resistor DAC, then 3 lookup PROMs
///    (pen -> palette entry) for characters, tiles (4 banks) and sprites.
///  Reference : MAME driver capcom/1942.cpp (gfx_layout) and 1942_v.cpp (_1942_palette).
///  Pure unit : no FMX.

interface

uses
  System.SysUtils,
  Arcade.Gfx,
  Arcade.RomSet;

type
  /// Palette as wired on the board : 256 RGB entries + 3 lookup PROMs (pen -> entry).
  TPalette84100 = record
    Rgb: array[0..255] of TArgb;
    CharLut: array[0..255] of Byte;    // 64 colors x 4 pens
    TileLut: array[0..1023] of Byte;   // 4 banks x 32 colors x 8 pens
    SpriteLut: array[0..255] of Byte;  // 16 colors x 16 pens
    function CharColor(aColor: Integer; aPen: Byte): TArgb; inline;
    function TileColor(aBank, aColor: Integer; aPen: Byte): TArgb; inline;
    function SpriteColor(aColor: Integer; aPen: Byte): TArgb; inline;
  end;

  /// The three decoded graphics banks of a 1942 ROM set, and its palette.
  TGfx84100 = record
    Chars, Tiles, Sprites: TGfxSet;
    Palette: TPalette84100;
  end;

const
  CCharTransparentPen = 0;    // fg tilemap : set_transparent_pen(0)
  CSpriteTransparentPen = 15; // draw_sprites : transpen(..., 15)

  CCharColors = 64;
  CTileColors = 32;
  CTileBanks = 4;
  CSpriteColors = 16;

function CharLayout(aRegionSize: Integer): TGfxLayout;
function TileLayout(aRegionSize: Integer): TGfxLayout;
function SpriteLayout(aRegionSize: Integer): TGfxLayout;

function BuildPalette(aRoms: TRomSetData): TPalette84100;
/// Decodes gfx1/gfx2/gfx3 and builds the palette.
function DecodeGfx84100(aRoms: TRomSetData): TGfx84100;

implementation

{ TPalette84100 }

function TPalette84100.CharColor(aColor: Integer; aPen: Byte): TArgb;
begin
  Result := Rgb[CharLut[aColor * 4 + aPen]];
end;

function TPalette84100.TileColor(aBank, aColor: Integer; aPen: Byte): TArgb;
begin
  Result := Rgb[TileLut[aBank * 256 + aColor * 8 + aPen]];
end;

function TPalette84100.SpriteColor(aColor: Integer; aPen: Byte): TArgb;
begin
  Result := Rgb[SpriteLut[aColor * 16 + aPen]];
end;

{ Layouts - verbatim from MAME 1942.cpp }

function CharLayout(aRegionSize: Integer): TGfxLayout;
const
  X: array[0..7] of Integer = (0, 1, 2, 3, 8 + 0, 8 + 1, 8 + 2, 8 + 3);
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
  Result.Count := (aRegionSize * 8) div Result.CharInc;   // RGN_FRAC(1,1)
end;

function TileLayout(aRegionSize: Integer): TGfxLayout;
var
  lThird, i: Integer;
begin
  Result := Default(TGfxLayout);
  lThird := (aRegionSize * 8) div 3;
  Result.Width := 16;
  Result.Height := 16;
  Result.Planes := 3;
  Result.PlaneOfs[0] := 0;           // RGN_FRAC(0,3)
  Result.PlaneOfs[1] := lThird;      // RGN_FRAC(1,3)
  Result.PlaneOfs[2] := 2 * lThird;  // RGN_FRAC(2,3)
  for i := 0 to 7 do
  begin
    Result.XOfs[i] := i;
    Result.XOfs[8 + i] := 16 * 8 + i;
  end;
  for i := 0 to 15 do
    Result.YOfs[i] := i * 8;
  Result.CharInc := 32 * 8;
  Result.Count := lThird div Result.CharInc;
end;

function SpriteLayout(aRegionSize: Integer): TGfxLayout;
const
  X: array[0..15] of Integer = (0, 1, 2, 3, 8 + 0, 8 + 1, 8 + 2, 8 + 3,
    16 * 16 + 0, 16 * 16 + 1, 16 * 16 + 2, 16 * 16 + 3,
    16 * 16 + 8 + 0, 16 * 16 + 8 + 1, 16 * 16 + 8 + 2, 16 * 16 + 8 + 3);
var
  lHalf, i: Integer;
begin
  Result := Default(TGfxLayout);
  lHalf := (aRegionSize * 8) div 2;
  Result.Width := 16;
  Result.Height := 16;
  Result.Planes := 4;
  Result.PlaneOfs[0] := lHalf + 4;   // RGN_FRAC(1,2)+4
  Result.PlaneOfs[1] := lHalf + 0;   // RGN_FRAC(1,2)+0
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

function BuildPalette(aRoms: TRomSetData): TPalette84100;

  // 4-bit resistor DAC : 2.2k, 1k, 470, 220 ohms
  function Dac(aNibble: Byte): Byte;
  begin
    Result := $0E * (aNibble and 1) + $1F * ((aNibble shr 1) and 1)
            + $43 * ((aNibble shr 2) and 1) + $8F * ((aNibble shr 3) and 1);
  end;

var
  lProm, lLut: TBytes;
  i: Integer;
begin
  lProm := aRoms.Region('palproms');
  for i := 0 to 255 do
    Result.Rgb[i] := $FF000000
      or (TArgb(Dac(lProm[i])) shl 16)
      or (TArgb(Dac(lProm[i + 256])) shl 8)
      or TArgb(Dac(lProm[i + 512]));

  // characters use palette entries 128-143
  lLut := aRoms.Region('charprom');
  for i := 0 to 255 do
    Result.CharLut[i] := $80 or (lLut[i] and $0F);

  // background tiles use palette entries 0-63 in four banks
  lLut := aRoms.Region('tileprom');
  for i := 0 to 255 do
  begin
    Result.TileLut[0 * 256 + i] := $00 or (lLut[i] and $0F);
    Result.TileLut[1 * 256 + i] := $10 or (lLut[i] and $0F);
    Result.TileLut[2 * 256 + i] := $20 or (lLut[i] and $0F);
    Result.TileLut[3 * 256 + i] := $30 or (lLut[i] and $0F);
  end;

  // sprites use palette entries 64-79
  lLut := aRoms.Region('sprprom');
  for i := 0 to 255 do
    Result.SpriteLut[i] := $40 or (lLut[i] and $0F);
end;

function DecodeGfx84100(aRoms: TRomSetData): TGfx84100;
begin
  Result.Chars := DecodeGfx(aRoms.Region('gfx1'), CharLayout(Length(aRoms.Region('gfx1'))));
  Result.Tiles := DecodeGfx(aRoms.Region('gfx2'), TileLayout(Length(aRoms.Region('gfx2'))));
  Result.Sprites := DecodeGfx(aRoms.Region('gfx3'), SpriteLayout(Length(aRoms.Region('gfx3'))));
  Result.Palette := BuildPalette(aRoms);
end;

end.
