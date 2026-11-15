unit Arcade.Board.CapcomBM.Video;

///  Capcom "BM" board - video : back background (bg2), front background (bg1, with transparent
///  pens), sprites with per-pen priority against bg1, text layer ; every layer switchable.
///  Sprite rules (MAME _1943_drawgfx) : the FIRST sprite in the list wins a pixel ; a sprite pen
///  whose priority bit is set is hidden where bg1 is opaque, but still claims the pixel.
///  Reference : MAME driver capcom/1943_v.cpp. Output : raw 256 x 224 (ROT270). No flip screen.
///  Pure unit : no FMX.

interface

uses
  Arcade.Gfx,
  Arcade.Board.CapcomBM;

procedure RenderBM(aBoard: TBoardCapcomBM; var aImage: TImage32);

implementation

uses
  Arcade.Board.CapcomBM.Gfx;

var
  // 0 : nothing / bg2 only, 2 : bg1 opaque, $FF : a sprite already took the pixel
  Priority: array[0..CBM_HEIGHT - 1, 0..CBM_WIDTH - 1] of Byte;

// One 2048 x 8 map of 32x32 tiles, from the tile map ROM at aMapBase
procedure DrawMap(aBoard: TBoardCapcomBM; var aImage: TImage32; aMapBase, aScrollX, aScrollY: Integer;
  aFront: Boolean);
var
  x, y, lMapX, lMapY, lOfs, lCode, lAttr, lPx, lPy, lPenIndex: Integer;
  lPen: Byte;
  lTiles: ^TGfxSet;
begin
  if aFront then lTiles := @aBoard.Gfx.Bg1Tiles else lTiles := @aBoard.Gfx.Bg2Tiles;
  for y := CBM_FIRST_VISIBLE to CBM_LAST_VISIBLE do
  begin
    lMapY := (y + aScrollY) and 255;
    for x := 0 to CBM_WIDTH - 1 do
    begin
      lMapX := (x + aScrollX) and $FFFF;
      lOfs := aMapBase + ((lMapX shr 5) * 8 + (lMapY shr 5)) * 2;
      lAttr := aBoard.TileMaps[lOfs + 1];
      if aFront then
        lCode := aBoard.TileMaps[lOfs] + ((lAttr and 1) shl 8)
      else
        lCode := aBoard.TileMaps[lOfs];
      lCode := lCode mod lTiles.Count;
      lPx := lMapX and 31;
      lPy := lMapY and 31;
      if (lAttr and $40) <> 0 then lPx := 31 - lPx;
      if (lAttr and $80) <> 0 then lPy := 31 - lPy;
      lPen := lTiles.Pen(lCode, lPx, lPy);
      if aFront then
      begin
        lPenIndex := CBMBg1Base + ((lAttr and $3C) shr 2) * 16 + lPen;
        if aBoard.Gfx.Pens[lPenIndex] = $0F then
          Continue;   // transparent : bg2 shows through
        Priority[y - CBM_FIRST_VISIBLE, x] := 2;
      end
      else
        lPenIndex := CBMBg2Base + ((lAttr and $3C) shr 2) * 16 + lPen;
      aImage.Pixels[(y - CBM_FIRST_VISIBLE) * aImage.Width + x] := aBoard.Gfx.Color(lPenIndex);
    end;
  end;
end;

procedure DrawSprites(aBoard: TBoardCapcomBM; var aImage: TImage32);
var
  lOfs, lAttr, lCode, lColor, lSX, lSY, lPx, lPy, x, y: Integer;
  lPen: Byte;
  lPri: PByte;
begin
  lOfs := 0;
  while lOfs < SizeOf(aBoard.SpriteBuffer) do
  begin
    lAttr := aBoard.SpriteBuffer[lOfs + 1];
    lCode := (aBoard.SpriteBuffer[lOfs] + ((lAttr and $E0) shl 3)) mod aBoard.Gfx.Sprites.Count;
    lColor := lAttr and $0F;
    lSX := aBoard.SpriteBuffer[lOfs + 3] - ((lAttr and $10) shl 4);
    lSY := aBoard.SpriteBuffer[lOfs + 2];
    for lPy := 0 to 15 do
    begin
      y := lSY + lPy;
      if (y < CBM_FIRST_VISIBLE) or (y > CBM_LAST_VISIBLE) then
        Continue;
      for lPx := 0 to 15 do
      begin
        x := lSX + lPx;
        if (x < 0) or (x >= CBM_WIDTH) then
          Continue;
        lPri := @Priority[y - CBM_FIRST_VISIBLE, x];
        if (lPri^ and $80) <> 0 then
          Continue;
        lPen := aBoard.Gfx.Sprites.Pen(lCode, lPx, lPy);
        if lPen = 0 then
          Continue;
        if ((lPri^ and 2) = 0) or not aBoard.Gfx.SpritePriority[lColor * 16 + lPen] then
          aImage.Pixels[(y - CBM_FIRST_VISIBLE) * aImage.Width + x] :=
            aBoard.Gfx.Color(CBMSpriteBase + lColor * 16 + lPen);
        lPri^ := $FF;
      end;
    end;
    Inc(lOfs, 32);
  end;
end;

procedure DrawText(aBoard: TBoardCapcomBM; var aImage: TImage32);
var
  x, y, lIndex, lCode, lAttr: Integer;
  lPen: Byte;
  lRow: PCardinal;
begin
  for y := CBM_FIRST_VISIBLE to CBM_LAST_VISIBLE do
  begin
    lRow := @aImage.Pixels[(y - CBM_FIRST_VISIBLE) * aImage.Width];
    for x := 0 to CBM_WIDTH - 1 do
    begin
      lIndex := (y shr 3) * 32 + (x shr 3);
      lAttr := aBoard.FgRam[$400 + lIndex];
      lCode := aBoard.FgRam[lIndex] + ((lAttr and $E0) shl 3);
      lPen := aBoard.Gfx.Chars.Pen(lCode, x and 7, y and 7);
      if lPen <> 0 then
        lRow^ := aBoard.Gfx.Color(CBMCharBase + (lAttr and $1F) * 4 + lPen);
      Inc(lRow);
    end;
  end;
end;

procedure RenderBM(aBoard: TBoardCapcomBM; var aImage: TImage32);
var
  i: Integer;
begin
  if (aImage.Width <> CBM_WIDTH) or (aImage.Height <> CBM_HEIGHT) then
    aImage.Init(CBM_WIDTH, CBM_HEIGHT, $FF000000);
  FillChar(Priority, SizeOf(Priority), 0);
  if (aBoard.Layers and $20) <> 0 then
    DrawMap(aBoard, aImage, $8000, aBoard.Scroll[3] or (aBoard.Scroll[4] shl 8), 0, False)
  else
    for i := 0 to High(aImage.Pixels) do
      aImage.Pixels[i] := $FF000000;
  if (aBoard.Layers and $10) <> 0 then
    DrawMap(aBoard, aImage, $0000, aBoard.Scroll[0] or (aBoard.Scroll[1] shl 8), aBoard.Scroll[2], True);
  if (aBoard.Layers and $40) <> 0 then
    DrawSprites(aBoard, aImage);
  if (aBoard.Control and $80) <> 0 then
    DrawText(aBoard, aImage);
end;

end.
