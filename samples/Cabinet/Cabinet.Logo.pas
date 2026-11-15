unit Cabinet.Logo;

///  The RETROLAB logo : a 5 x 7 pixel font (only the letters it needs), arcade colours, drawn into a
///  bitmap one pixel per dot, to be shown enlarged without interpolation.

interface

uses
  System.UITypes,
  FMX.Graphics;

const
  CLogoText = 'RETROLAB';
  CTagline = 'CLASSIC GAMES, RETRO GAMING REIMAGINED';

procedure DrawLogo(aBitmap: TBitmap; const aText: string);

implementation

// 5 x 7 pixel font, only the letters of the logo.
function Glyph(aChar: Char): TArray<string>;
begin
  case aChar of
    'A': Result := ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'];
    'B': Result := ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'];
    'D': Result := ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'];
    'E': Result := ['#####', '#....', '#....', '####.', '#....', '#....', '#####'];
    'G': Result := ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.###.'];
    'H': Result := ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'];
    'I': Result := ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '#####'];
    'L': Result := ['#....', '#....', '#....', '#....', '#....', '#....', '#####'];
    'M': Result := ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'];
    'N': Result := ['#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'];
    'O': Result := ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'];
    'P': Result := ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'];
    'R': Result := ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'];
    'T': Result := ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'];
  else
    Result := ['...', '...', '...', '...', '...', '...', '...'];
  end;
end;

// The logo as a bitmap : one pixel per dot, yellow to red from top to bottom, dark red shadow.
procedure DrawLogo(aBitmap: TBitmap; const aText: string);
const
  CRows: array[0..6] of TAlphaColor = ($FFFFF060, $FFFFE040, $FFFFC020, $FFFFA010, $FFFF8000,
    $FFFF5A00, $FFE83000);
  CShadow: TAlphaColor = $FF600000;
var
  lData: TBitmapData;
  lChar: Char;
  lRows: TArray<string>;
  lWidth, x, y, lLeft: Integer;
begin
  lWidth := 0;
  for lChar in aText do
    Inc(lWidth, Length(Glyph(lChar)[0]) + 1);
  aBitmap.SetSize(lWidth + 1, 8);
  aBitmap.Clear(TAlphaColors.Null);
  if not aBitmap.Map(TMapAccess.Write, lData) then
    Exit;
  try
    lLeft := 0;
    for lChar in aText do
    begin
      lRows := Glyph(lChar);
      for y := 0 to 6 do
        for x := 1 to Length(lRows[y]) do
          if lRows[y][x] = '#' then
            lData.SetPixel(lLeft + x, y + 1, CShadow);
      for y := 0 to 6 do
        for x := 1 to Length(lRows[y]) do
          if lRows[y][x] = '#' then
            lData.SetPixel(lLeft + x - 1, y, CRows[y]);
      Inc(lLeft, Length(lRows[0]) + 1);
    end;
  finally
    aBitmap.Unmap(lData);
  end;
end;

end.
