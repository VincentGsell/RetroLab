unit Arcade.Gfx;

///  Generic tile / sprite graphics : MAME gfx_layout decoding (bit offsets, MSB-first bytes, first
///  plane = most significant bit of the pen) so a board can copy its layouts verbatim from MAME.
///  Plus the 32-bit image type every board renders into, and sheet helpers for viewers.
///  Pure unit : no FMX, no VCL.

interface

uses
  System.SysUtils;

type
  /// $AARRGGBB, i.e. FMX TAlphaColor without the dependency.
  TArgb = Cardinal;

  /// MAME gfx_layout. Every offset is in BITS.
  TGfxLayout = record
    Width, Height: Integer;
    Count: Integer;
    Planes: Integer;
    PlaneOfs: array[0..3] of Integer;
    XOfs: array[0..31] of Integer;
    YOfs: array[0..31] of Integer;
    CharInc: Integer;
  end;

  /// Decoded graphics : one pen index (0..2^Planes-1) per pixel, element after element.
  TGfxSet = record
    Width, Height, Count: Integer;
    Pens: TBytes;
    function Pen(aCode, aX, aY: Integer): Byte; inline;
  end;

  /// 32-bit image, row-major, top-down.
  TImage32 = record
    Width, Height: Integer;
    Pixels: TArray<TArgb>;
    procedure Init(aWidth, aHeight: Integer; aFill: TArgb);
    procedure Blit(const aSrc: TImage32; aX, aY: Integer);
    /// Nearest-neighbour integer upscale : pixels stay pixels.
    function Scaled(aZoom: Integer): TImage32;
  end;

  /// Monitor mounting, as MAME's ROT0 / ROT90 / ROT180 / ROT270.
  TScreenRotation = (rot0, rot90, rot180, rot270);

  TPenColorizer = reference to function(aCode: Integer; aPen: Byte): TArgb;

function DecodeGfx(const aData: TBytes; const aLayout: TGfxLayout): TGfxSet;

/// Monitor image -> what the player sees on the cabinet.
function RotateImage(const aImage: TImage32; aRotation: TScreenRotation): TImage32;

/// Lays out every element of aSet in a grid of aColumns, 1 pixel gap, colored by aColorizer.
/// aRotation turns each element in place (the grid itself is unchanged) : square elements only.
function RenderSheet(const aSet: TGfxSet; aColumns: Integer; const aColorizer: TPenColorizer;
  aGapColor: TArgb; aRotation: TScreenRotation = rot0): TImage32;
/// Grid of colour swatches, 16 per row, aCell pixels each.
function RenderPaletteSheet(const aColors: array of TArgb; aCell: Integer): TImage32;

implementation

{ TGfxSet }

function TGfxSet.Pen(aCode, aX, aY: Integer): Byte;
begin
  Result := Pens[(aCode * Height + aY) * Width + aX];
end;

{ TImage32 }

procedure TImage32.Init(aWidth, aHeight: Integer; aFill: TArgb);
var
  i: Integer;
begin
  Width := aWidth;
  Height := aHeight;
  SetLength(Pixels, aWidth * aHeight);
  for i := 0 to High(Pixels) do
    Pixels[i] := aFill;
end;

procedure TImage32.Blit(const aSrc: TImage32; aX, aY: Integer);
var
  y: Integer;
begin
  for y := 0 to aSrc.Height - 1 do
    Move(aSrc.Pixels[y * aSrc.Width], Pixels[(aY + y) * Width + aX], aSrc.Width * SizeOf(TArgb));
end;

function TImage32.Scaled(aZoom: Integer): TImage32;
var
  x, y: Integer;
begin
  Result.Init(Width * aZoom, Height * aZoom, 0);
  for y := 0 to Result.Height - 1 do
    for x := 0 to Result.Width - 1 do
      Result.Pixels[y * Result.Width + x] := Pixels[(y div aZoom) * Width + x div aZoom];
end;

function DecodeGfx(const aData: TBytes; const aLayout: TGfxLayout): TGfxSet;
var
  lCode, x, y, p, lBit, lPen, lOut: Integer;
begin
  Result.Width := aLayout.Width;
  Result.Height := aLayout.Height;
  Result.Count := aLayout.Count;
  SetLength(Result.Pens, aLayout.Count * aLayout.Width * aLayout.Height);
  lOut := 0;
  for lCode := 0 to aLayout.Count - 1 do
    for y := 0 to aLayout.Height - 1 do
      for x := 0 to aLayout.Width - 1 do
      begin
        lPen := 0;
        for p := 0 to aLayout.Planes - 1 do
        begin
          lBit := lCode * aLayout.CharInc + aLayout.PlaneOfs[p] + aLayout.YOfs[y] + aLayout.XOfs[x];
          if (aData[lBit shr 3] and ($80 shr (lBit and 7))) <> 0 then
            lPen := lPen or (1 shl (aLayout.Planes - 1 - p));
        end;
        Result.Pens[lOut] := lPen;
        Inc(lOut);
      end;
end;

// Source pixel of destination (x, y) for a rotated W x H image (MAME orientation semantics).
procedure SourceOf(aRotation: TScreenRotation; aW, aH, x, y: Integer; out sx, sy: Integer);
begin
  case aRotation of
    rot90:  begin sx := y;          sy := aH - 1 - x; end;
    rot180: begin sx := aW - 1 - x; sy := aH - 1 - y; end;
    rot270: begin sx := aW - 1 - y; sy := x;          end;
  else
    begin sx := x; sy := y; end;
  end;
end;

function RotateImage(const aImage: TImage32; aRotation: TScreenRotation): TImage32;
var
  x, y, sx, sy: Integer;
begin
  if aRotation in [rot90, rot270] then
    Result.Init(aImage.Height, aImage.Width, 0)
  else
    Result.Init(aImage.Width, aImage.Height, 0);
  for y := 0 to Result.Height - 1 do
    for x := 0 to Result.Width - 1 do
    begin
      SourceOf(aRotation, aImage.Width, aImage.Height, x, y, sx, sy);
      Result.Pixels[y * Result.Width + x] := aImage.Pixels[sy * aImage.Width + sx];
    end;
end;

function RenderSheet(const aSet: TGfxSet; aColumns: Integer; const aColorizer: TPenColorizer;
  aGapColor: TArgb; aRotation: TScreenRotation): TImage32;
var
  lRows, lCode, lCx, lCy, x, y, sx, sy: Integer;
begin
  lRows := (aSet.Count + aColumns - 1) div aColumns;
  Result.Init(aColumns * (aSet.Width + 1) + 1, lRows * (aSet.Height + 1) + 1, aGapColor);
  for lCode := 0 to aSet.Count - 1 do
  begin
    lCx := 1 + (lCode mod aColumns) * (aSet.Width + 1);
    lCy := 1 + (lCode div aColumns) * (aSet.Height + 1);
    for y := 0 to aSet.Height - 1 do
      for x := 0 to aSet.Width - 1 do
      begin
        SourceOf(aRotation, aSet.Width, aSet.Height, x, y, sx, sy);
        Result.Pixels[(lCy + y) * Result.Width + lCx + x] := aColorizer(lCode, aSet.Pen(lCode, sx, sy));
      end;
  end;
end;

function RenderPaletteSheet(const aColors: array of TArgb; aCell: Integer): TImage32;
var
  i, x, y, lRows: Integer;
begin
  lRows := (Length(aColors) + 15) div 16;
  Result.Init(16 * aCell, lRows * aCell, $FF000000);
  for i := 0 to High(aColors) do
    for y := 1 to aCell - 1 do
      for x := 1 to aCell - 1 do
        Result.Pixels[((i div 16) * aCell + y) * Result.Width + (i mod 16) * aCell + x] := aColors[i];
end;

end.
