unit Arcade.Board.Capcom85113.Video;

///  Capcom PCB 85113 - video : background map read from ROM (2048 x 8 tiles of 32x32, scrolls
///  16-bit X / 8-bit Y), sprites, text layer ; each layer switchable by the CPU (black when off).
///  Reference : MAME driver capcom/gunsmoke.cpp (tile callbacks, draw_sprites, screen_update).
///  Output : raw 256 x 224 monitor image (ROT270 on the cabinet). Flip screen not done.
///  Pure unit : no FMX.

interface

uses
  Arcade.Gfx,
  Arcade.Board.Capcom85113;

procedure Render85113(aBoard: TBoardCapcom85113; var aImage: TImage32);

implementation

procedure DrawBackground(aBoard: TBoardCapcom85113; var aImage: TImage32);
var
  x, y, lMapX, lMapY, lOfs, lCode, lAttr, lPx, lPy, lScrollX, lScrollY: Integer;
  lRow: PCardinal;
begin
  lScrollX := aBoard.Scroll[0] or (aBoard.Scroll[1] shl 8);
  lScrollY := aBoard.Scroll[2];
  for y := C85113_FIRST_VISIBLE to C85113_LAST_VISIBLE do
  begin
    lMapY := (y + lScrollY) and 255;
    lRow := @aImage.Pixels[(y - C85113_FIRST_VISIBLE) * aImage.Width];
    for x := 0 to C85113_WIDTH - 1 do
    begin
      lMapX := (x + lScrollX) and $FFFF;
      // TILEMAP_SCAN_COLS, 8 rows : tile index = column * 8 + row, 2 bytes per tile in the ROM
      lOfs := ((lMapX shr 5) * 8 + (lMapY shr 5)) * 2;
      lAttr := aBoard.BgMap[lOfs + 1];
      lCode := aBoard.BgMap[lOfs] + ((lAttr and $01) shl 8);
      lPx := lMapX and 31;
      lPy := lMapY and 31;
      if (lAttr and $40) <> 0 then lPx := 31 - lPx;
      if (lAttr and $80) <> 0 then lPy := 31 - lPy;
      lRow^ := aBoard.Gfx.TileColor((lAttr and $3C) shr 2, aBoard.Gfx.Tiles.Pen(lCode, lPx, lPy));
      Inc(lRow);
    end;
  end;
end;

// 128 entries every 32 bytes, drawn last to first (the first ends on top) ; pen 0 is transparent.
procedure DrawSprites(aBoard: TBoardCapcom85113; var aImage: TImage32);
var
  lOfs, lAttr, lBank, lCode, lColor, lSX, lSY, lPx, lPy, x, y, sy: Integer;
  lFlipY: Boolean;
  lPen: Byte;
begin
  lOfs := SizeOf(aBoard.SpriteBuffer) - 32;
  while lOfs >= 0 do
  begin
    lAttr := aBoard.SpriteBuffer[lOfs + 1];
    lBank := (lAttr and $C0) shr 6;
    if lBank = 3 then
      Inc(lBank, aBoard.Layers and 7);
    lCode := (aBoard.SpriteBuffer[lOfs] + 256 * lBank) and 2047;
    lColor := lAttr and $0F;
    lFlipY := (lAttr and $10) <> 0;
    lSX := aBoard.SpriteBuffer[lOfs + 3] - ((lAttr and $20) shl 3);
    lSY := aBoard.SpriteBuffer[lOfs + 2];
    for lPy := 0 to 15 do
    begin
      y := lSY + lPy;
      if (y < C85113_FIRST_VISIBLE) or (y > C85113_LAST_VISIBLE) then
        Continue;
      if lFlipY then sy := 15 - lPy else sy := lPy;
      for lPx := 0 to 15 do
      begin
        x := lSX + lPx;
        if (x < 0) or (x >= C85113_WIDTH) then
          Continue;
        lPen := aBoard.Gfx.Sprites.Pen(lCode, lPx, sy);
        if lPen <> 0 then
          aImage.Pixels[(y - C85113_FIRST_VISIBLE) * aImage.Width + x] := aBoard.Gfx.SpriteColor(lColor, lPen);
      end;
    end;
    Dec(lOfs, 32);
  end;
end;

procedure DrawText(aBoard: TBoardCapcom85113; var aImage: TImage32);
var
  x, y, lIndex, lCode, lAttr, lColor: Integer;
  lPen: Byte;
  lRow: PCardinal;
begin
  for y := C85113_FIRST_VISIBLE to C85113_LAST_VISIBLE do
  begin
    lRow := @aImage.Pixels[(y - C85113_FIRST_VISIBLE) * aImage.Width];
    for x := 0 to C85113_WIDTH - 1 do
    begin
      lIndex := (y shr 3) * 32 + (x shr 3);
      lAttr := aBoard.FgRam[$400 + lIndex];
      lCode := aBoard.FgRam[lIndex] + ((lAttr and $E0) shl 2);
      lColor := lAttr and $1F;
      lPen := aBoard.Gfx.Chars.Pen(lCode, x and 7, y and 7);
      if not aBoard.Gfx.CharTransparent(lColor, lPen) then
        lRow^ := aBoard.Gfx.CharColor(lColor, lPen);
      Inc(lRow);
    end;
  end;
end;

procedure Render85113(aBoard: TBoardCapcom85113; var aImage: TImage32);
var
  i: Integer;
begin
  if (aImage.Width <> C85113_WIDTH) or (aImage.Height <> C85113_HEIGHT) then
    aImage.Init(C85113_WIDTH, C85113_HEIGHT, $FF000000);
  if (aBoard.Layers and $10) <> 0 then
    DrawBackground(aBoard, aImage)
  else
    for i := 0 to High(aImage.Pixels) do
      aImage.Pixels[i] := $FF000000;
  if (aBoard.Layers and $20) <> 0 then
    DrawSprites(aBoard, aImage);
  if (aBoard.Control and $80) <> 0 then
    DrawText(aBoard, aImage);
end;

end.
