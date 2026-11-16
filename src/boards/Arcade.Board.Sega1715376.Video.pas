unit Arcade.Board.Sega1715376.Video;

///  Sega 171-5376 (Out Run) - video, one scanline at a time :
///    1. road, background part : sky lines filled with a solid colour
///    2. System 16B tilemaps : background then foreground layer, each a 1024 x 512 window over
///       4 of 16 pages, row scroll, column scroll and per-row alternate pages ; tile bit 15 is
///       the priority against sprites
///    3. road, foreground part : two roads mixed by the priority PAL
///    4. text layer (64 x 28 tiles)
///    5. sprites from the double buffer : zoom, flip, 2-bit priority, shadow pixels
///       (the chip's scratch word +E is not written back : the picture never changes the state)
///  Reference : MAME segaorun.cpp (screen_update_outrun), segaic16.cpp (16B tilemaps),
///  segaic16_road.cpp (Out Run road), sega16sp.cpp (Out Run sprites). Pure unit : no FMX.

interface

uses
  Arcade.Gfx,
  Arcade.Board.Sega1715376;

procedure Render1715376(aBoard: TBoardSega1715376; var aImage: TImage32);

implementation

const
  W = C5376_WIDTH;
  H = C5376_HEIGHT;
  CRoadColor1 = $400;
  CRoadColor2 = $420;
  CRoadColor3 = $780;
  CSpriteLeft = 189;                 // sprite X of screen column 0
  CSpriteRight = CSpriteLeft + W - 1;
  CRoadPriority: array[0..1, 0..7] of Byte = (
    ($80, $81, $81, $87, 0, 0, 0, $00),
    ($81, $81, $81, $8F, 0, 0, 0, $80));

var
  GLine: array[0..W - 1] of Word;
  GPri: array[0..W - 1] of Byte;
  GSprites: array[0..W * H - 1] of Word;

function Sar(aValue, aShift: Integer): Integer; inline;
begin
  if aValue >= 0 then
    Result := aValue shr aShift
  else
    Result := -((-aValue - 1) shr aShift) - 1;
end;

procedure DrawSprites(aBoard: TBoardSega1715376);
var
  i, k, lWords, lBase: Integer;
  d0, d2, d3, d4, d5: Word;
  lBank, lTop, lPitch, lXPos, lVZoom, lYDelta, lXDelta, lHZoom, lHeight, lColPri: Integer;
  lFlip: Boolean;
  lAddr, lCur: Word;
  y, x, lYAcc, lXAcc, lYTarget, lPix, lNumBanks, lRow: Integer;
  lPixels: Cardinal;
  lLast: Boolean;
begin
  for i := 0 to High(GSprites) do
    GSprites[i] := $FFFF;
  lNumBanks := Length(aBoard.SpriteData) div $10000;
  for i := 0 to 255 do
  begin
    lBase := i * 8;
    d0 := aBoard.SpriteWord(lBase);
    if (d0 and $8000) <> 0 then
      Break;
    lAddr := aBoard.SpriteWord(lBase + 1);
    d2 := aBoard.SpriteWord(lBase + 2);
    d3 := aBoard.SpriteWord(lBase + 3);
    d4 := aBoard.SpriteWord(lBase + 4);
    d5 := aBoard.SpriteWord(lBase + 5);
    lBank := (d0 shr 9) and 7;
    lTop := (d0 and $1FF) - $100;
    lPitch := Sar(SmallInt(Word((d2 shr 1) or ((d4 and $1000) shl 3))), 8);
    lXPos := d2 and $1FF;
    lVZoom := d3 and $7FF;
    if (d4 and $8000) <> 0 then lYDelta := 1 else lYDelta := -1;
    lFlip := ((not d4) and $4000) <> 0;
    if (d4 and $2000) <> 0 then lXDelta := 1 else lXDelta := -1;
    lHZoom := d4 and $7FF;
    lHeight := (d5 shr 8) + 1;
    lColPri := ((d5 and $7F) shl 4) or (((d3 shr 12) and 7) shl 12);
    if (lXPos < $80) and (lXDelta < 0) then
      Inc(lXPos, $200);
    if (d0 and $5000) <> 0 then
      Continue;
    if lNumBanks > 0 then
      lBank := lBank mod lNumBanks;
    lBank := lBank * $10000;
    if lVZoom < $40 then lVZoom := $40;
    if lHZoom < $40 then lHZoom := $40;
    lCur := lAddr;
    lYAcc := 0;
    lYTarget := lTop + lYDelta * lHeight;
    y := lTop;
    while y <> lYTarget do
    begin
      if (y >= 0) and (y < H) then
      begin
        lRow := y * W - CSpriteLeft;
        lXAcc := 0;
        x := lXPos;
        lCur := lAddr;
        lWords := 0;
        while ((lXDelta > 0) and (x <= CSpriteRight)) or ((lXDelta < 0) and (x >= CSpriteLeft)) do
        begin
          lPixels := aBoard.SpriteData[lBank + lCur];
          if lFlip then
            lCur := Word(lCur - 1)
          else
          begin
            lCur := Word(lCur + 1);
            lPixels := ((lPixels shl 28) and $F0000000) or ((lPixels shl 20) and $0F000000)
              or ((lPixels shl 12) and $00F00000) or ((lPixels shl 4) and $000F0000)
              or ((lPixels shr 4) and $0000F000) or ((lPixels shr 12) and $00000F00)
              or ((lPixels shr 20) and $000000F0) or ((lPixels shr 28) and $0000000F);
          end;
          lLast := (lPixels and $0F000000) = $0F000000;
          for k := 0 to 7 do
          begin
            lPix := lPixels and $F;
            while lXAcc < $200 do
            begin
              if (x >= CSpriteLeft) and (x <= CSpriteRight) and (lPix <> 0) and (lPix <> 15) then
                GSprites[lRow + x] := lColPri or lPix;
              Inc(x, lXDelta);
              Inc(lXAcc, lHZoom);
            end;
            Dec(lXAcc, $200);
            lPixels := lPixels shr 4;
          end;
          Inc(lWords);
          if lLast or (lWords > 1024) then
            Break;
        end;
      end;
      Inc(lYAcc, lVZoom);
      lAddr := Word(lAddr + lPitch * (lYAcc shr 9));
      lYAcc := lYAcc and $1FF;
      Inc(y, lYDelta);
    end;
  end;
end;

procedure DrawRoadBackground(aBoard: TBoardSega1715376; y: Integer);
var
  lData0, lData1: Word;
  lColor, x: Integer;
begin
  lData0 := aBoard.RoadWord(y);
  lData1 := aBoard.RoadWord($100 + y);
  lColor := -1;
  case aBoard.RoadControl and 3 of
    0:
      if (lData0 and $800) <> 0 then lColor := lData0 and $7F;
    1:
      if (lData0 and $800) <> 0 then lColor := lData0 and $7F
      else if (lData1 and $800) <> 0 then lColor := lData1 and $7F;
    2:
      if (lData1 and $800) <> 0 then lColor := lData1 and $7F
      else if (lData0 and $800) <> 0 then lColor := lData0 and $7F;
    3:
      if (lData1 and $800) <> 0 then lColor := lData1 and $7F;
  end;
  if lColor >= 0 then
    for x := 0 to W - 1 do
      GLine[x] := lColor or CRoadColor3;
end;

procedure DrawRoadForeground(aBoard: TBoardSega1715376; y: Integer);
var
  lData0, lData1: Word;
  lSrc0, lSrc1, lHPos0, lHPos1, lColor0, lColor1, x, lPix0, lPix1, lBg: Integer;
  lTable: array[0..31] of Word;
  lControl: Integer;
begin
  lData0 := aBoard.RoadWord(y);
  lData1 := aBoard.RoadWord($100 + y);
  if ((lData0 and $800) <> 0) and ((lData1 and $800) <> 0) then
    Exit;
  if (lData0 and $800) <> 0 then
    lSrc0 := 256 * 2 * 512
  else
    lSrc0 := ((lData0 shr 1) and $FF) * 512;
  lHPos0 := aBoard.RoadWord($200 + (lData0 and $1FF)) and $FFF;
  lColor0 := aBoard.RoadWord($600 + (lData0 and $1FF));
  if (lData1 and $800) <> 0 then
    lSrc1 := 256 * 2 * 512
  else
    lSrc1 := ($100 + ((lData1 shr 1) and $FF)) * 512;
  lHPos1 := aBoard.RoadWord($400 + (lData1 and $1FF)) and $FFF;
  lColor1 := aBoard.RoadWord($600 + (lData1 and $1FF));

  lTable[$00] := CRoadColor1 xor $00 xor ((lColor0 shr 0) and 1);
  lTable[$01] := CRoadColor1 xor $02 xor ((lColor0 shr 1) and 1);
  lTable[$02] := CRoadColor1 xor $04 xor ((lColor0 shr 2) and 1);
  lBg := (lColor0 shr 8) and $F;
  if (lData0 and $200) <> 0 then
    lTable[$03] := lTable[$00]
  else
    lTable[$03] := CRoadColor2 xor $00 xor lBg;
  lTable[$07] := CRoadColor1 xor $06 xor ((lColor0 shr 3) and 1);
  lTable[$10] := CRoadColor1 xor $08 xor ((lColor1 shr 4) and 1);
  lTable[$11] := CRoadColor1 xor $0A xor ((lColor1 shr 5) and 1);
  lTable[$12] := CRoadColor1 xor $0C xor ((lColor1 shr 6) and 1);
  lBg := (lColor1 shr 8) and $F;
  if (lData1 and $200) <> 0 then
    lTable[$13] := lTable[$10]
  else
    lTable[$13] := CRoadColor2 xor $10 xor lBg;
  lTable[$17] := CRoadColor1 xor $0E xor ((lColor1 shr 7) and 1);

  lControl := aBoard.RoadControl and 3;
  lHPos0 := (lHPos0 - $5F8) and $FFF;
  lHPos1 := (lHPos1 - $5F8) and $FFF;
  case lControl of
    0:
      begin
        if (lData0 and $800) <> 0 then
          Exit;
        for x := 0 to W - 1 do
        begin
          if lHPos0 < $200 then lPix0 := aBoard.RoadGfx[lSrc0 + lHPos0] else lPix0 := 3;
          GLine[x] := lTable[lPix0];
          lHPos0 := (lHPos0 + 1) and $FFF;
        end;
      end;
    1, 2:
      for x := 0 to W - 1 do
      begin
        if lHPos0 < $200 then lPix0 := aBoard.RoadGfx[lSrc0 + lHPos0] else lPix0 := 3;
        if lHPos1 < $200 then lPix1 := aBoard.RoadGfx[lSrc1 + lHPos1] else lPix1 := 3;
        if ((CRoadPriority[lControl - 1, lPix0] shr lPix1) and 1) <> 0 then
          GLine[x] := lTable[$10 + lPix1]
        else
          GLine[x] := lTable[lPix0];
        lHPos0 := (lHPos0 + 1) and $FFF;
        lHPos1 := (lHPos1 + 1) and $FFF;
      end;
    3:
      begin
        if (lData1 and $800) <> 0 then
          Exit;
        for x := 0 to W - 1 do
        begin
          if lHPos1 < $200 then lPix1 := aBoard.RoadGfx[lSrc1 + lHPos1] else lPix1 := 3;
          GLine[x] := lTable[$10 + lPix1];
          lHPos1 := (lHPos1 + 1) and $FFF;
        end;
      end;
  end;
end;

/// aWhich : 0 = foreground, 1 = background ; tile bit 15 picks the mark (aMark0 / aMark1).
procedure DrawLayer(aBoard: TBoardSega1715376; y, aWhich: Integer; aMark0, aMark1: Byte);
var
  lXScroll, lYScroll, lPages, lRowScroll, lEffX, lEffY, lEffPages, lColY: Word;
  lAlt, lColScroll: Boolean;
  x, lVX, lVY, lQuad, lPage, lCode, lPen: Integer;
  lData: Word;
begin
  lXScroll := aBoard.LatchedXScroll[aWhich];
  lYScroll := aBoard.LatchedYScroll[aWhich];
  lPages := aBoard.LatchedPages[aWhich];
  lRowScroll := aBoard.TextWord($F80 div 2 + $20 * aWhich + y div 8);
  if (lXScroll and $8000) <> 0 then
    lEffX := lRowScroll
  else
    lEffX := lXScroll;
  lEffY := lYScroll;
  lEffPages := lPages;
  lAlt := (lRowScroll and $8000) <> 0;
  if lAlt then
  begin
    lEffX := aBoard.LatchedXScroll[aWhich + 2];
    lEffY := aBoard.LatchedYScroll[aWhich + 2];
    lEffPages := aBoard.LatchedPages[aWhich + 2];
  end;
  lEffX := ($C0 - lEffX) and $3FF;
  lColScroll := ((lYScroll and $8000) <> 0) and not lAlt;
  lColY := lEffY and $1FF;
  for x := 0 to W - 1 do
  begin
    if lColScroll then
      lColY := aBoard.TextWord($F16 div 2 + $20 * aWhich + (x + 8) div 16) and $1FF;
    lVX := (x + lEffX) and $3FF;
    lVY := (y + lColY) and $1FF;
    lQuad := (lVX shr 9) or ((lVY shr 8) shl 1);
    lPage := (lEffPages shr (4 * lQuad)) and $F;
    lData := aBoard.TileWord(lPage * $800 + ((lVY and $FF) shr 3) * 64 + ((lVX and $1FF) shr 3));
    lCode := lData and $1FFF;
    lPen := aBoard.Tiles.Pen(lCode, lVX and 7, lVY and 7);
    if lPen = 0 then
      Continue;
    GLine[x] := ((lData shr 6) and $7F) * 8 + lPen;
    if (lData and $8000) <> 0 then
      GPri[x] := GPri[x] or aMark1
    else
      GPri[x] := GPri[x] or aMark0;
  end;
end;

procedure DrawText(aBoard: TBoardSega1715376; y: Integer);
var
  x, lTX, lPen: Integer;
  lData: Word;
begin
  for x := 0 to W - 1 do
  begin
    lTX := x + 192;
    lData := aBoard.TextWord((y shr 3) * 64 + (lTX shr 3));
    lPen := aBoard.Tiles.Pen(lData and $1FF, lTX and 7, y and 7);
    if lPen = 0 then
      Continue;
    GLine[x] := ((lData shr 9) and 7) * 8 + lPen;
    if (lData and $8000) <> 0 then
      GPri[x] := GPri[x] or $08
    else
      GPri[x] := GPri[x] or $04;
  end;
end;

procedure MixSprites(y: Integer);
var
  x, lPri: Integer;
  lPix: Word;
begin
  for x := 0 to W - 1 do
  begin
    lPix := GSprites[y * W + x];
    if lPix = $FFFF then
      Continue;
    lPri := (lPix shr 12) and 3;
    if (1 shl lPri) > GPri[x] then
    begin
      if (lPix and $400F) = $400A then
        GLine[x] := (GLine[x] + C5376_PALETTE) and (2 * C5376_PALETTE - 1)
      else
        GLine[x] := $800 or (lPix and $7FF);
    end;
  end;
end;

procedure Render1715376(aBoard: TBoardSega1715376; var aImage: TImage32);
var
  x, y, lPos: Integer;
begin
  if (aImage.Width <> W) or (aImage.Height <> H) then
    aImage.Init(W, H, $FF000000);
  if not aBoard.DisplayEnabled then
  begin
    for x := 0 to W * H - 1 do
      aImage.Pixels[x] := $FF000000;
    Exit;
  end;
  DrawSprites(aBoard);
  lPos := 0;
  for y := 0 to H - 1 do
  begin
    FillChar(GLine, SizeOf(GLine), 0);
    FillChar(GPri, SizeOf(GPri), 0);
    if lyRoadBack in aBoard.Layers then DrawRoadBackground(aBoard, y);
    if lyBackground in aBoard.Layers then DrawLayer(aBoard, y, 1, $01, $02);
    if lyForeground in aBoard.Layers then DrawLayer(aBoard, y, 0, $02, $04);
    if lyRoadFront in aBoard.Layers then DrawRoadForeground(aBoard, y);
    if lyText in aBoard.Layers then DrawText(aBoard, y);
    if lySprites in aBoard.Layers then MixSprites(y);
    for x := 0 to W - 1 do
    begin
      aImage.Pixels[lPos] := aBoard.Palette[GLine[x]];
      Inc(lPos);
    end;
  end;
end;

end.
