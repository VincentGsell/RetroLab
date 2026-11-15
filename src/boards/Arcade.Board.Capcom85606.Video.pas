unit Arcade.Board.Capcom85606.Video;

///  Capcom PCB 85606 - video : background (512 x 512, scrolls on X and Y, two priority levels),
///  sprites, text layer.
///  Background priority (MAME tilemap transmasks) : a tile of group 0 is entirely behind the sprites ;
///  a tile of group 1 has pens 0 and 6 behind the sprites and its other pens in front of them.
///  Flip screen : the finished picture is turned by 180 degrees.
///  Reference : MAME driver capcom/gng.cpp (tile callbacks, draw_sprites, screen_update).
///  Output : 256 x 224, ROT0. Pure unit : no FMX.

interface

uses
  Arcade.Gfx,
  Arcade.Board.Capcom85606;

procedure Render85606(aBoard: TBoardCapcom85606; var aImage: TImage32);

implementation

const
  CTileColorBase = $00;    // 8 colours x 8 pens
  CSpriteColorBase = $40;  // 4 colours x 16 pens
  CCharColorBase = $80;    // 16 colours x 4 pens
  CCharTransparentPen = 3;
  CSpriteTransparentPen = 15;

var
  GFront: array[0..C85606_WIDTH * C85606_HEIGHT - 1] of TArgb;   // 0 : nothing in front of sprites

procedure DrawBackground(aBoard: TBoardCapcom85606; var aImage: TImage32);
var
  x, y, lMapX, lMapY, lIndex, lCode, lAttr, lPx, lPy, lScrollX, lScrollY, lPos: Integer;
  lPen: Byte;
  lColor: TArgb;
begin
  lScrollX := aBoard.ScrollX[0] or (aBoard.ScrollX[1] shl 8);
  lScrollY := aBoard.ScrollY[0] or (aBoard.ScrollY[1] shl 8);
  lPos := 0;
  for y := C85606_FIRST_VISIBLE to C85606_LAST_VISIBLE do
  begin
    lMapY := (y + lScrollY) and 511;
    for x := 0 to C85606_WIDTH - 1 do
    begin
      lMapX := (x + lScrollX) and 511;
      lIndex := (lMapX shr 4) * 32 + (lMapY shr 4);          // TILEMAP_SCAN_COLS 32 x 32
      lAttr := aBoard.BgRam[$400 + lIndex];
      lCode := aBoard.BgRam[lIndex] + ((lAttr and $C0) shl 2);
      lPx := lMapX and 15;
      lPy := lMapY and 15;
      if (lAttr and $10) <> 0 then lPx := 15 - lPx;
      if (lAttr and $20) <> 0 then lPy := 15 - lPy;
      lPen := aBoard.Tiles.Pen(lCode, lPx, lPy);
      lColor := aBoard.Palette[CTileColorBase + (lAttr and $07) * 8 + lPen];
      aImage.Pixels[lPos] := lColor;
      if ((lAttr and $08) <> 0) and (lPen <> 0) and (lPen <> 6) then
        GFront[lPos] := lColor
      else
        GFront[lPos] := 0;
      Inc(lPos);
    end;
  end;
end;

procedure DrawSprite(aBoard: TBoardCapcom85606; var aImage: TImage32;
  aCode, aColor, aSX, aSY: Integer; aFlipX, aFlipY: Boolean);
var
  lPx, lPy, x, y, sx, sy: Integer;
  lPen: Byte;
begin
  for lPy := 0 to 15 do
  begin
    y := aSY + lPy;
    if (y < C85606_FIRST_VISIBLE) or (y > C85606_LAST_VISIBLE) then
      Continue;
    if aFlipY then sy := 15 - lPy else sy := lPy;
    for lPx := 0 to 15 do
    begin
      x := aSX + lPx;
      if (x < 0) or (x >= C85606_WIDTH) then
        Continue;
      if aFlipX then sx := 15 - lPx else sx := lPx;
      lPen := aBoard.Sprites.Pen(aCode, sx, sy);
      if lPen <> CSpriteTransparentPen then
        aImage.Pixels[(y - C85606_FIRST_VISIBLE) * aImage.Width + x] :=
          aBoard.Palette[CSpriteColorBase + aColor * 16 + lPen];
    end;
  end;
end;

// 128 sprites of 4 bytes, drawn from the last to the first : the first entry ends on top.
procedure DrawSprites(aBoard: TBoardCapcom85606; var aImage: TImage32);
var
  lOfs, lAttr, lCode: Integer;
begin
  lOfs := SizeOf(aBoard.SpriteBuffer) - 4;
  while lOfs >= 0 do
  begin
    lAttr := aBoard.SpriteBuffer[lOfs + 1];
    lCode := aBoard.SpriteBuffer[lOfs] + ((lAttr shl 2) and $300);
    if lCode < aBoard.Sprites.Count then
      DrawSprite(aBoard, aImage, lCode, (lAttr shr 4) and 3,
        aBoard.SpriteBuffer[lOfs + 3] - ((lAttr and 1) shl 8), aBoard.SpriteBuffer[lOfs + 2],
        (lAttr and $04) <> 0, (lAttr and $08) <> 0);
    Dec(lOfs, 4);
  end;
end;

procedure DrawFront(var aImage: TImage32);
var
  i: Integer;
begin
  for i := 0 to High(GFront) do
    if GFront[i] <> 0 then
      aImage.Pixels[i] := GFront[i];
end;

procedure DrawText(aBoard: TBoardCapcom85606; var aImage: TImage32);
var
  x, y, lIndex, lCode, lAttr, lPx, lPy: Integer;
  lPen: Byte;
  lRow: PCardinal;
begin
  for y := C85606_FIRST_VISIBLE to C85606_LAST_VISIBLE do
  begin
    lRow := @aImage.Pixels[(y - C85606_FIRST_VISIBLE) * aImage.Width];
    for x := 0 to C85606_WIDTH - 1 do
    begin
      lIndex := (y shr 3) * 32 + (x shr 3);                   // TILEMAP_SCAN_ROWS 32 x 32
      lAttr := aBoard.FgRam[$400 + lIndex];
      lCode := aBoard.FgRam[lIndex] + ((lAttr and $C0) shl 2);
      lPx := x and 7;
      lPy := y and 7;
      if (lAttr and $10) <> 0 then lPx := 7 - lPx;
      if (lAttr and $20) <> 0 then lPy := 7 - lPy;
      lPen := aBoard.Chars.Pen(lCode, lPx, lPy);
      if lPen <> CCharTransparentPen then
        lRow^ := aBoard.Palette[CCharColorBase + (lAttr and $0F) * 4 + lPen];
      Inc(lRow);
    end;
  end;
end;

procedure Turn180(var aImage: TImage32);
var
  i, j: Integer;
  lTmp: TArgb;
begin
  i := 0;
  j := High(aImage.Pixels);
  while i < j do
  begin
    lTmp := aImage.Pixels[i];
    aImage.Pixels[i] := aImage.Pixels[j];
    aImage.Pixels[j] := lTmp;
    Inc(i);
    Dec(j);
  end;
end;

procedure Render85606(aBoard: TBoardCapcom85606; var aImage: TImage32);
begin
  if (aImage.Width <> C85606_WIDTH) or (aImage.Height <> C85606_HEIGHT) then
    aImage.Init(C85606_WIDTH, C85606_HEIGHT, $FF000000);
  DrawBackground(aBoard, aImage);
  DrawSprites(aBoard, aImage);
  DrawFront(aImage);
  DrawText(aBoard, aImage);
  if aBoard.Flipped then
    Turn180(aImage);
end;

end.
