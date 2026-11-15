unit Arcade.Board.Capcom85605.Video;

///  Capcom PCB 85605 - video : background (512 x 512, scrolls on X and Y), sprites, text layer.
///  Reference : MAME driver capcom/commando.cpp (tile callbacks, draw_sprites, screen_update).
///  Output : raw 256 x 224 monitor image (the cabinet turns it : ROT270). Flip screen not done.
///  Pure unit : no FMX.

interface

uses
  Arcade.Gfx,
  Arcade.Board.Capcom85605;

procedure Render85605(aBoard: TBoardCapcom85605; var aImage: TImage32);

implementation

const
  CTileColorBase = 0;      // 16 colours x 8 pens
  CSpriteColorBase = 128;  // 4 colours x 16 pens
  CCharColorBase = 192;    // 16 colours x 4 pens
  CCharTransparentPen = 3;
  CSpriteTransparentPen = 15;

procedure DrawBackground(aBoard: TBoardCapcom85605; var aImage: TImage32);
var
  x, y, lMapX, lMapY, lIndex, lCode, lAttr, lPx, lPy, lScrollX, lScrollY: Integer;
  lRow: PCardinal;
begin
  lScrollX := aBoard.ScrollX[0] or (aBoard.ScrollX[1] shl 8);
  lScrollY := aBoard.ScrollY[0] or (aBoard.ScrollY[1] shl 8);
  for y := C85605_FIRST_VISIBLE to C85605_LAST_VISIBLE do
  begin
    lMapY := (y + lScrollY) and 511;
    lRow := @aImage.Pixels[(y - C85605_FIRST_VISIBLE) * aImage.Width];
    for x := 0 to C85605_WIDTH - 1 do
    begin
      lMapX := (x + lScrollX) and 511;
      lIndex := (lMapX shr 4) * 32 + (lMapY shr 4);          // TILEMAP_SCAN_COLS 32 x 32
      lAttr := aBoard.BgRam[$400 + lIndex];
      lCode := aBoard.BgRam[lIndex] + ((lAttr and $C0) shl 2);
      lPx := lMapX and 15;
      lPy := lMapY and 15;
      if (lAttr and $10) <> 0 then lPx := 15 - lPx;
      if (lAttr and $20) <> 0 then lPy := 15 - lPy;
      lRow^ := aBoard.Palette[CTileColorBase + (lAttr and $0F) * 8 + aBoard.Tiles.Pen(lCode, lPx, lPy)];
      Inc(lRow);
    end;
  end;
end;

procedure DrawSprite(aBoard: TBoardCapcom85605; var aImage: TImage32;
  aCode, aColor, aSX, aSY: Integer; aFlipX, aFlipY: Boolean);
var
  lPx, lPy, x, y, sx, sy: Integer;
  lPen: Byte;
begin
  for lPy := 0 to 15 do
  begin
    y := aSY + lPy;
    if (y < C85605_FIRST_VISIBLE) or (y > C85605_LAST_VISIBLE) then
      Continue;
    if aFlipY then sy := 15 - lPy else sy := lPy;
    for lPx := 0 to 15 do
    begin
      x := aSX + lPx;
      if (x < 0) or (x >= C85605_WIDTH) then
        Continue;
      if aFlipX then sx := 15 - lPx else sx := lPx;
      lPen := aBoard.Sprites.Pen(aCode, sx, sy);
      if lPen <> CSpriteTransparentPen then
        aImage.Pixels[(y - C85605_FIRST_VISIBLE) * aImage.Width + x] :=
          aBoard.Palette[CSpriteColorBase + aColor * 16 + lPen];
    end;
  end;
end;

// 96 sprites of 4 bytes, drawn from the last to the first : the first entry ends on top.
procedure DrawSprites(aBoard: TBoardCapcom85605; var aImage: TImage32);
var
  lOfs, lAttr, lBank, lCode: Integer;
begin
  lOfs := SizeOf(aBoard.SpriteBuffer) - 4;
  while lOfs >= 0 do
  begin
    lAttr := aBoard.SpriteBuffer[lOfs + 1];
    lBank := (lAttr and $C0) shr 6;
    lCode := aBoard.SpriteBuffer[lOfs] + 256 * lBank;
    if (lBank < 3) and (lCode < aBoard.Sprites.Count) then
      DrawSprite(aBoard, aImage, lCode, (lAttr and $30) shr 4,
        aBoard.SpriteBuffer[lOfs + 3] - ((lAttr and 1) shl 8), aBoard.SpriteBuffer[lOfs + 2],
        (lAttr and $04) <> 0, (lAttr and $08) <> 0);
    Dec(lOfs, 4);
  end;
end;

procedure DrawText(aBoard: TBoardCapcom85605; var aImage: TImage32);
var
  x, y, lIndex, lCode, lAttr, lPx, lPy: Integer;
  lPen: Byte;
  lRow: PCardinal;
begin
  for y := C85605_FIRST_VISIBLE to C85605_LAST_VISIBLE do
  begin
    lRow := @aImage.Pixels[(y - C85605_FIRST_VISIBLE) * aImage.Width];
    for x := 0 to C85605_WIDTH - 1 do
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

procedure Render85605(aBoard: TBoardCapcom85605; var aImage: TImage32);
begin
  if (aImage.Width <> C85605_WIDTH) or (aImage.Height <> C85605_HEIGHT) then
    aImage.Init(C85605_WIDTH, C85605_HEIGHT, $FF000000);
  DrawBackground(aBoard, aImage);
  DrawSprites(aBoard, aImage);
  DrawText(aBoard, aImage);
end;

end.
