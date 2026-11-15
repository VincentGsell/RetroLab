unit Arcade.Cabinet.Display;

///  CABINET - the monitor : turns the board's picture (monitor orientation) into what the player
///  sees on the cabinet (rotation as mounted), as an FMX bitmap. Pixel exact, no filtering.

interface

uses
  System.SysUtils,
  System.UITypes,
  FMX.Types,
  FMX.Graphics,
  Arcade.Gfx,
  Arcade.Board;

/// TImage32 ($AARRGGBB) -> FMX bitmap, pixel exact.
procedure Image32ToBitmap(const aImage: TImage32; aBitmap: TBitmap);

/// The board's current picture as the player sees it, into aBitmap.
procedure ShowBoardScreen(aBoard: TArcadeBoard; aBitmap: TBitmap);

implementation

procedure Image32ToBitmap(const aImage: TImage32; aBitmap: TBitmap);
var
  lData: TBitmapData;
  x, y: Integer;
begin
  if (aBitmap.Width <> aImage.Width) or (aBitmap.Height <> aImage.Height) then
    aBitmap.SetSize(aImage.Width, aImage.Height);
  if not aBitmap.Map(TMapAccess.Write, lData) then
    raise Exception.Create('Bitmap.Map impossible');
  try
    for y := 0 to aImage.Height - 1 do
      if lData.PixelFormat = TPixelFormat.BGRA then
        Move(aImage.Pixels[y * aImage.Width], lData.GetScanline(y)^, aImage.Width * SizeOf(TArgb))
      else
        for x := 0 to aImage.Width - 1 do
          lData.SetPixel(x, y, TAlphaColor(aImage.Pixels[y * aImage.Width + x]));
  finally
    aBitmap.Unmap(lData);
  end;
end;

procedure ShowBoardScreen(aBoard: TArcadeBoard; aBitmap: TBitmap);
begin
  if aBoard.Screen.Width > 0 then
    Image32ToBitmap(RotateImage(aBoard.Screen, aBoard.ScreenInfo.Rotation), aBitmap);
end;

end.
