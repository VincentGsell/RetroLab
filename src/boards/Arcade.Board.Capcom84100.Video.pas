unit Arcade.Board.Capcom84100.Video;

///  Capcom PCB 84100 - video circuit (bottom board 84100-02A) : background tilemap (scrolling), sprites, text layer - in that order.
///  Reference : MAME src/mame/capcom/1942_v.cpp (tile callbacks, draw_sprites, screen_update).
///  Output is the raw 256 x 224 screen in MONITOR coordinates (the cabinet turns it : ROT270).
///  Flip screen (cocktail) is not implemented yet : upright cabinet only.
///  Pure unit : no FMX.

interface

uses
  Arcade.Gfx,
  Arcade.Board.Capcom84100,
  Arcade.Board.Capcom84100.Gfx;

/// Renders the current board state into aImage (re-allocated to 256 x 224 if needed).
procedure Render84100(aBoard: TBoardCapcom84100; var aImage: TImage32);

implementation

const
  CMapWidth = 512;   // background : 32 columns x 16 rows of 16x16 tiles, scrolls horizontally

procedure DrawBackground(aBoard: TBoardCapcom84100; var aImage: TImage32);
var
  x, y, lMapX, lMapY, lTileIndex, lOfs, lCode, lAttr, lPx, lPy, lScroll: Integer;
  lPen: Byte;
  lRow: PCardinal;
begin
  lScroll := aBoard.Scroll[0] or (aBoard.Scroll[1] shl 8);
  for y := C84100_FIRST_VISIBLE to C84100_LAST_VISIBLE do
  begin
    lMapY := y and 255;
    lRow := @aImage.Pixels[(y - C84100_FIRST_VISIBLE) * aImage.Width];
    for x := 0 to C84100_WIDTH - 1 do
    begin
      lMapX := (x + lScroll) and (CMapWidth - 1);
      // TILEMAP_SCAN_COLS, then get_bg_tile_info's remap to the RAM layout
      lTileIndex := (lMapX shr 4) * 16 + (lMapY shr 4);
      lOfs := (lTileIndex and $0F) or ((lTileIndex and $01F0) shl 1);
      lAttr := aBoard.BgRam[lOfs + $10];
      lCode := aBoard.BgRam[lOfs] + ((lAttr and $80) shl 1);
      lPx := lMapX and 15;
      lPy := lMapY and 15;
      if (lAttr and $20) <> 0 then lPx := 15 - lPx;   // TILE_FLIPX
      if (lAttr and $40) <> 0 then lPy := 15 - lPy;   // TILE_FLIPY
      lPen := aBoard.Gfx.Tiles.Pen(lCode, lPx, lPy);
      lRow^ := aBoard.Gfx.Palette.TileColor(aBoard.PaletteBank, lAttr and $1F, lPen);
      Inc(lRow);
    end;
  end;
end;

procedure DrawSpriteLine(aBoard: TBoardCapcom84100; var aImage: TImage32; aY, aCode, aColor, aSX, aSY: Integer);
var
  lRowInSprite, lPx, x: Integer;
  lPen: Byte;
  lDst: PCardinal;
begin
  lRowInSprite := aY - aSY;
  if (lRowInSprite < 0) or (lRowInSprite > 15) then
    Exit;
  lDst := @aImage.Pixels[(aY - C84100_FIRST_VISIBLE) * aImage.Width];
  for lPx := 0 to 15 do
  begin
    x := aSX + lPx;
    if (x < 0) or (x >= C84100_WIDTH) then
      Continue;
    lPen := aBoard.Gfx.Sprites.Pen(aCode and $1FF, lPx, lRowInSprite);
    if lPen <> CSpriteTransparentPen then
      PCardinal(PByte(lDst) + x * SizeOf(Cardinal))^ := aBoard.Gfx.Palette.SpriteColor(aColor, lPen);
  end;
end;

// Port of MAME _1942_state::draw_sprites : the hardware walks the sprite list per scanline,
// sprites 16-23 only on lines 16-127, 24-31 only on 128-239 ; first sprite wins, hence the
// reverse drawing order.
procedure DrawSprites(aBoard: TBoardCapcom84100; var aImage: TImage32);
var
  y, h, i, lObjIdx, lCode, lCol, lSX, lSY, lRow, lVLen: Integer;
  v, lVAlpha, lV2C, lLVBeta, lVBeta: Byte;
  lObjCnt3, lObjCnt4, lVLeq, lVInLen: Boolean;
  o0, o1, o2, o3: Byte;
begin
  for y := C84100_FIRST_VISIBLE to C84100_LAST_VISIBLE do
  begin
    v := Byte(y - 1);
    h := 496;
    while h >= 128 do
    begin
      lObjCnt4 := ((h shr 8) and 1) <> ((not h shr 7) and 1);
      lObjCnt3 := ((((v shr 7) and 1) <> 0) and lObjCnt4) <> (((not h shr 7) and 1) <> 0);
      lObjIdx := (h shr 4) and 7;
      if lObjCnt3 then lObjIdx := lObjIdx or $08;
      if lObjCnt4 then lObjIdx := lObjIdx or $10;
      lObjIdx := lObjIdx shl 2;
      o0 := aBoard.SpriteRam[lObjIdx];
      o1 := aBoard.SpriteRam[lObjIdx or 1];
      o2 := aBoard.SpriteRam[lObjIdx or 2];
      o3 := aBoard.SpriteRam[lObjIdx or 3];

      lCode := (o0 and $7F) or (((o1 shr 5) and 1) shl 7) or (((o0 shr 7) and 1) shl 8);
      lCol := o1 and $0F;
      lSX := o3 - (((o1 shr 4) and 1) shl 8);
      lSY := o2;

      lVAlpha := Byte(lSY);
      lV2C := Byte(Byte(not v) + $FF);
      lLVBeta := Byte(lV2C + lVAlpha);
      lVBeta := Byte(not lLVBeta);
      lVLeq := lVBeta <= Byte(not lVAlpha);
      lVLen := o1 shr 6;
      case lVLen of
        0: lVInLen := (lLVBeta and $F0) = $F0;
        1: lVInLen := (lLVBeta and $E0) = $E0;
        2: lVInLen := (lLVBeta and $C0) = $C0;
      else
        lVInLen := True;
      end;

      if lVLeq and lVInLen then   // !vinzone
      begin
        if lVLen = 3 then lRow := 16 else lRow := 1 shl lVLen;
        lCode := lCode and not (lRow - 1);
        for i := 0 to lRow - 1 do
          DrawSpriteLine(aBoard, aImage, y, lCode + i, lCol, lSX, lSY + 16 * i);
      end;
      Dec(h, 16);
    end;
  end;
end;

procedure DrawText(aBoard: TBoardCapcom84100; var aImage: TImage32);
var
  x, y, lTileIndex, lCode, lAttr: Integer;
  lPen: Byte;
  lRow: PCardinal;
begin
  for y := C84100_FIRST_VISIBLE to C84100_LAST_VISIBLE do
  begin
    lRow := @aImage.Pixels[(y - C84100_FIRST_VISIBLE) * aImage.Width];
    for x := 0 to C84100_WIDTH - 1 do
    begin
      lTileIndex := (y shr 3) * 32 + (x shr 3);   // TILEMAP_SCAN_ROWS 32 x 32
      lAttr := aBoard.FgRam[lTileIndex + $400];
      lCode := aBoard.FgRam[lTileIndex] + ((lAttr and $80) shl 1);
      lPen := aBoard.Gfx.Chars.Pen(lCode, x and 7, y and 7);
      if lPen <> CCharTransparentPen then
        lRow^ := aBoard.Gfx.Palette.CharColor(lAttr and $3F, lPen);
      Inc(lRow);
    end;
  end;
end;

procedure Render84100(aBoard: TBoardCapcom84100; var aImage: TImage32);
begin
  if (aImage.Width <> C84100_WIDTH) or (aImage.Height <> C84100_HEIGHT) then
    aImage.Init(C84100_WIDTH, C84100_HEIGHT, $FF000000);
  DrawBackground(aBoard, aImage);
  DrawSprites(aBoard, aImage);
  DrawText(aBoard, aImage);
end;

end.
