unit Arcade.Board.Sega1715609.Video;

///  Sega Y Board - video, in hardware order :
///    1. the Y Board sprites are drawn into a 512 x 512 frame buffer : zoom, flip, 16 colours
///       through an indirection table, and a left / right clip for every pair of lines read from
///       the rotation RAM
///    2. the rotation chip reads that buffer through an affine transform (start point, X step and
///       Y step in 18.14 fixed point) : this tilts and turns the whole road and scenery ; a
///       line of the buffer with no sprite pixel shows that line's own background colour
///    3. the System 16B sprites (dashboard, texts) are drawn on top, with priority against the
///       rotated layer and shadow pixels
///  The renderer never writes into sprite RAM (MAME's sprite chips use spare words as scratch) :
///  the picture never changes the board state.
///  Reference : MAME segaybd.cpp (screen_update), segaic16.cpp (rotate_draw), sega16sp.cpp
///  (Y Board and System 16B sprites). Pure unit : no FMX.

interface

uses
  Arcade.Gfx,
  Arcade.Board.Sega1715609;

procedure Render1715609(aBoard: TBoardSega1715609; var aImage: TImage32);

implementation

const
  W = C5609_WIDTH;
  H = C5609_HEIGHT;
  CYOrigin = $600;              // Y Board sprite coordinate of buffer column / line 0
  CBOrigin = 184;               // System 16B sprite X of screen column 0

var
  GYBuffer: array[0..512 * 512 - 1] of Word;
  GBSprites: array[0..W * H - 1] of Word;

procedure DrawYSprites(aBoard: TBoardSega1715609);
var
  lVisited: array[0..$FFF] of Boolean;
  lNext, lBase, lIndirect, lBank, lXPos, lTop, lHeight, lYDelta, lXDelta, lZoom, lColPri: Integer;
  lPitch, y, x, lRow, lMinX, lMaxX, lXAcc, lYAcc, lYTarget, k, lPix, lInd, lNumBanks: Integer;
  d0, d1, d2, d5, d6: Word;
  lAddr, lOffs: Word;
  lFlip: Boolean;
  lPixels: UInt64;
  lIndTab: array[0..15] of Integer;
begin
  for x := 0 to High(GYBuffer) do
    GYBuffer[x] := $FFFF;
  FillChar(lVisited, SizeOf(lVisited), 0);
  lNumBanks := Length(aBoard.YSpriteData) div $10000;
  lNext := 0;
  while True do
  begin
    lBase := lNext * 8;
    d0 := aBoard.YSpriteWord(lBase);
    if ((d0 and $8000) <> 0) or lVisited[lNext] then
      Break;
    lVisited[lNext] := True;
    lNext := aBoard.YSpriteWord(lBase + 7) and $FFF;
    if (d0 and $5000) <> 0 then
      Continue;
    d1 := aBoard.YSpriteWord(lBase + 1);
    d2 := aBoard.YSpriteWord(lBase + 2);
    lAddr := aBoard.YSpriteWord(lBase + 3);
    lHeight := aBoard.YSpriteWord(lBase + 4);
    d5 := aBoard.YSpriteWord(lBase + 5);
    d6 := aBoard.YSpriteWord(lBase + 6);
    if lHeight = 0 then
      Continue;
    lIndirect := (d0 and $7FF) shl 4;
    for k := 0 to 15 do
      lIndTab[k] := aBoard.YSpriteWord(lIndirect + k);
    lBank := ((d1 shr 8) and $10) or ((d2 shr 12) and $0F);
    lXPos := d1 and $FFF;
    lTop := d2 and $FFF;
    if (d5 and $4000) <> 0 then lYDelta := 1 else lYDelta := -1;
    lFlip := ((not d5) and $2000) <> 0;
    if (d5 and $1000) <> 0 then lXDelta := 1 else lXDelta := -1;
    lZoom := d5 and $7FF;
    if lZoom = 0 then lZoom := 1;
    lColPri := (d6 shl 1) and $FE00;
    lPitch := ShortInt(d6 and $FF);
    if lNumBanks > 0 then
      lBank := lBank mod lNumBanks;
    lBank := lBank * $10000;
    lYTarget := lTop + lYDelta * lHeight;
    lYAcc := 0;
    y := lTop;
    while y <> lYTarget do
    begin
      if (y >= CYOrigin) and (y < CYOrigin + 512) then
      begin
        lRow := y - CYOrigin;
        lMinX := aBoard.RotateWord(lRow and not 1);
        lMaxX := aBoard.RotateWord(lRow or 1);
        if ((lMinX and $8000) <> 0) and (lYDelta < 0) then
          Break;
        if ((lMinX and $4000) <> 0) and (lYDelta > 0) then
          Break;
        if (lMinX and $C000) = 0 then
        begin
          if lMinX < CYOrigin then lMinX := CYOrigin;
          if lMaxX > CYOrigin + 511 then lMaxX := CYOrigin + 511;
          lXAcc := 0;
          x := lXPos;
          if not lFlip then
            lOffs := Word(lAddr - 1)
          else
            lOffs := Word(lAddr + 1);
          while ((lXDelta > 0) and (x <= lMaxX)) or ((lXDelta < 0) and (x >= lMinX)) do
          begin
            if not lFlip then
            begin
              lOffs := Word(lOffs + 1);
              lPixels := aBoard.YSpriteData[lBank + lOffs];
            end
            else
            begin
              lOffs := Word(lOffs - 1);
              lPixels := aBoard.YSpriteData[lBank + lOffs];
            end;
            lPix := 0;
            for k := 0 to 15 do
            begin
              if not lFlip then
                lPix := (lPixels shr (60 - 4 * k)) and $F
              else
                lPix := (lPixels shr (4 * k)) and $F;
              lInd := lIndTab[lPix];
              while lXAcc < $200 do
              begin
                if (x >= lMinX) and (x <= lMaxX) and (lInd < $1FE) then
                  GYBuffer[lRow * 512 + (x - CYOrigin)] := lColPri or lInd;
                Inc(x, lXDelta);
                Inc(lXAcc, lZoom);
              end;
              Dec(lXAcc, $200);
            end;
            if lPix = $F then
              Break;
          end;
        end;
      end;
      Inc(lYAcc, lZoom);
      lAddr := Word(lAddr + lPitch * (lYAcc shr 9));
      lYAcc := lYAcc and $1FF;
      Inc(y, lYDelta);
    end;
  end;
end;

procedure DrawBSprites(aBoard: TBoardSega1715609);
var
  i, k, lBase, lBottom, lTop, lXPos, lPitch, lBank, lColPri, lVZoom, lHZoom, y, x, lXAcc, lPix, lNumBanks: Integer;
  d0, d1, d2, d4, d5, lPixels: Word;
  lAddr, lOffs, lYAcc: Word;
  lFlip: Boolean;

  procedure Plot;
  begin
    lXAcc := (lXAcc and $3F) + lHZoom;
    if lXAcc < $40 then
    begin
      if (x >= CBOrigin) and (x < CBOrigin + W) and (lPix <> 0) and (lPix <> 15) then
        GBSprites[y * W + (x - CBOrigin)] := lColPri or lPix;
      Inc(x);
    end;
  end;

begin
  for i := 0 to High(GBSprites) do
    GBSprites[i] := $FFFF;
  lNumBanks := Length(aBoard.BSpriteData) div $10000;
  for i := 0 to 255 do
  begin
    lBase := i * 8;
    d2 := aBoard.BSpriteWord(lBase + 2);
    if (d2 and $8000) <> 0 then
      Break;
    d0 := aBoard.BSpriteWord(lBase);
    d1 := aBoard.BSpriteWord(lBase + 1);
    lAddr := aBoard.BSpriteWord(lBase + 3);
    d4 := aBoard.BSpriteWord(lBase + 4);
    d5 := aBoard.BSpriteWord(lBase + 5);
    lBottom := d0 shr 8;
    lTop := d0 and $FF;
    lXPos := d1 and $1FF;
    lFlip := (d2 and $100) <> 0;
    lPitch := ShortInt(d2 and $FF);
    lBank := (d4 shr 8) and $F;
    lColPri := ((d4 and $FF) shl 4) or (((d1 shr 9) and $F) shl 12);
    lVZoom := (d5 shr 5) and $1F;
    lHZoom := d5 and $1F;
    if ((d2 and $4000) <> 0) or (lTop >= lBottom) then
      Continue;
    if lNumBanks > 0 then
      lBank := lBank mod lNumBanks;
    lBank := lBank * $10000;
    lYAcc := d5 and $03FF;
    for y := lTop to lBottom - 1 do
    begin
      lAddr := Word(lAddr + lPitch);
      lYAcc := Word(lYAcc + (lVZoom shl 10));
      if (lYAcc and $8000) <> 0 then
      begin
        lAddr := Word(lAddr + lPitch);
        lYAcc := lYAcc and not $8000;
      end;
      if y >= H then
        Continue;
      lXAcc := 4 * lHZoom;
      x := lXPos;
      if not lFlip then
        lOffs := Word(lAddr - 1)
      else
        lOffs := Word(lAddr + 1);
      while ((lXPos - x) and $1FF) <> 1 do
      begin
        if not lFlip then
          lOffs := Word(lOffs + 1)
        else
          lOffs := Word(lOffs - 1);
        lPixels := aBoard.BSpriteData[lBank + lOffs];
        lPix := 0;
        for k := 0 to 3 do
        begin
          if not lFlip then
            lPix := (lPixels shr (12 - 4 * k)) and $F
          else
            lPix := (lPixels shr (4 * k)) and $F;
          Plot;
        end;
        if lPix = 15 then
          Break;
      end;
    end;
  end;
end;

procedure Render1715609(aBoard: TBoardSega1715609; var aImage: TImage32);
var
  x, y, lPos, sx, sy: Integer;
  lCurX, lCurY, lDYY, lDXX, lDXY, lDYX, tx, ty: Integer;
  lPix, lPen, lB: Word;
  lPri, lSpPri: Integer;
begin
  if (aImage.Width <> W) or (aImage.Height <> H) then
    aImage.Init(W, H, $FF000000);
  if not aBoard.DisplayEnabled then
  begin
    for x := 0 to W * H - 1 do
      aImage.Pixels[x] := $FF000000;
    Exit;
  end;
  DrawYSprites(aBoard);
  DrawBSprites(aBoard);
  lCurX := Integer((Cardinal(aBoard.RotateWord($3F0)) shl 16) or aBoard.RotateWord($3F1));
  lCurY := Integer((Cardinal(aBoard.RotateWord($3F2)) shl 16) or aBoard.RotateWord($3F3));
  lDYY := Integer((Cardinal(aBoard.RotateWord($3F4)) shl 16) or aBoard.RotateWord($3F5));
  lDXX := Integer((Cardinal(aBoard.RotateWord($3F6)) shl 16) or aBoard.RotateWord($3F7));
  lDXY := Integer((Cardinal(aBoard.RotateWord($3F8)) shl 16) or aBoard.RotateWord($3F9));
  lDYX := Integer((Cardinal(aBoard.RotateWord($3FA)) shl 16) or aBoard.RotateWord($3FB));
  lCurX := lCurX + lDXX * 27;
  lCurY := lCurY + lDYX * 27;
  lPos := 0;
  for y := 0 to H - 1 do
  begin
    tx := lCurX;
    ty := lCurY;
    for x := 0 to W - 1 do
    begin
      sx := (Cardinal(tx) shr 14) and $1FF;
      sy := (Cardinal(ty) shr 14) and $1FF;
      lPix := GYBuffer[sy * 512 + sx];
      if lPix <> $FFFF then
      begin
        lPen := (lPix and $1FF) or ((lPix shr 6) and $200) or ((lPix shr 3) and $C00) or $1000;
        lPri := ((lPix shr 8) or 1) and $1F;
      end
      else
      begin
        lPen := sy;
        lPri := $1F;
      end;
      lB := GBSprites[lPos];
      if lB <> $FFFF then
      begin
        lSpPri := (lB shr 11) and $1E;
        if lSpPri < lPri then
        begin
          if (lB and $F) = $E then
            lPen := (lPen + C5609_PALETTE) and (2 * C5609_PALETTE - 1)
          else
            lPen := $800 or (lB and $7FF);
        end;
      end;
      aImage.Pixels[lPos] := aBoard.Palette[lPen];
      Inc(lPos);
      Inc(tx, lDXX);
      Inc(ty, lDYX);
    end;
    Inc(lCurX, lDXY);
    Inc(lCurY, lDYY);
  end;
end;

end.
