unit Arcade.RomSet.Capcom1942;

///  CARTRIDGES - the game 1942 (Capcom, 1984) and its variants. They all run on the same board,
///  Capcom PCB 84100 ('capcom84100') : same hardware, different programs :
///    1942   1942 (Revision B)                    parent
///    1942a  1942 (Revision A)
///    1942b  1942 (First Version)
///    1942w  1942 (Williams Electronics license)  1985
///    1942h  Supercharger 1942                    1991 hack (Two Bit Score)
///  Reference : MAME src/mame/capcom/1942.cpp (ROM_START ... ROM_END). Clones only differ by their
///  main program (and Williams by its character ROM) : graphics, sound and PROMs are shared.
///  Using this unit registers the sets.

interface

implementation

uses
  Arcade.RomSet;

const
  CBoard = 'capcom84100';

// Everything but the main program : sound CPU, graphics, colour and timing PROMs.
procedure AddCommon(aSet: TRomSetDef; aCharRom: string = 'sr-02.f2'; aCharCrc: UInt32 = $6EBCA191);
begin
  aSet.AddRegion('maincpu', $20000, $FF);   // 64K + 3 banks of 16K at 10000/14000/18000, ERASEFF
  aSet.AddRegion('audiocpu', $10000);
  aSet.AddRegion('gfx1', $2000);            // characters
  aSet.AddRegion('gfx2', $C000);            // background tiles
  aSet.AddRegion('gfx3', $10000);           // sprites
  aSet.AddRegion('palproms', $300);         // red, green, blue
  aSet.AddRegion('charprom', $100);
  aSet.AddRegion('tileprom', $100);
  aSet.AddRegion('sprprom', $100);
  aSet.AddRegion('irqprom', $100);

  aSet.AddFile('sr-01.c11', 'audiocpu', $0000, $4000, $BD87F06B);
  aSet.AddFile(aCharRom,    'gfx1',     $0000, $2000, aCharCrc);
  aSet.AddFile('sr-08.a1',  'gfx2',     $0000, $2000, $3884D9EB);
  aSet.AddFile('sr-09.a2',  'gfx2',     $2000, $2000, $999CF6E0);
  aSet.AddFile('sr-10.a3',  'gfx2',     $4000, $2000, $8EDB273A);
  aSet.AddFile('sr-11.a4',  'gfx2',     $6000, $2000, $3A2726C3);
  aSet.AddFile('sr-12.a5',  'gfx2',     $8000, $2000, $1BD3D8BB);
  aSet.AddFile('sr-13.a6',  'gfx2',     $A000, $2000, $658F02C4);
  aSet.AddFile('sr-14.l1',  'gfx3',     $0000, $4000, $2528BEC6);
  aSet.AddFile('sr-15.l2',  'gfx3',     $4000, $4000, $F89287AA);
  aSet.AddFile('sr-16.n1',  'gfx3',     $8000, $4000, $024418F8);
  aSet.AddFile('sr-17.n2',  'gfx3',     $C000, $4000, $E2C7E489);
  aSet.AddFile('sb-5.e8',   'palproms', $000,  $100,  $93AB8153);
  aSet.AddFile('sb-6.e9',   'palproms', $100,  $100,  $8AB44F7D);
  aSet.AddFile('sb-7.e10',  'palproms', $200,  $100,  $F4ADE9A4);
  aSet.AddFile('sb-0.f1',   'charprom', $000,  $100,  $6047D91B);
  aSet.AddFile('sb-4.d6',   'tileprom', $000,  $100,  $4858968D);
  aSet.AddFile('sb-8.k3',   'sprprom',  $000,  $100,  $F6FAD943);
  aSet.AddFile('sb-1.k6',   'irqprom',  $000,  $100,  $712AC508);
end;

procedure AddProgram(aSet: TRomSetDef; const aNames: array of string; const aCrcs: array of UInt32);
const
  COffsets: array[0..4] of Integer = ($00000, $04000, $10000, $14000, $18000);
  CSizes: array[0..4] of Integer = ($4000, $4000, $4000, $2000, $4000);
var
  i: Integer;
begin
  for i := 0 to 4 do
    aSet.AddFile(aNames[i], 'maincpu', COffsets[i], CSizes[i], aCrcs[i]);
end;

procedure RegisterSets;
var
  lSet: TRomSetDef;
begin
  lSet := TRomSetDef.Create('1942', '', '1942 (Revision B)', '1984', 'Capcom', CBoard);
  AddCommon(lSet);
  AddProgram(lSet, ['srb-03.m3', 'srb-04.m4', 'srb-05.m5', 'srb-06.m6', 'srb-07.m7'],
    [$D9DAFCC3, $DA0CF924, $D102911C, $466F8248, $0D31038C]);
  RegisterRomSet(lSet);

  lSet := TRomSetDef.Create('1942a', '1942', '1942 (Revision A)', '1984', 'Capcom', CBoard);
  AddCommon(lSet);
  AddProgram(lSet, ['sra-03.m3', 'sr-04.m4', 'sr-05.m5', 'sr-06.m6', 'sr-07.m7'],
    [$40201BAB, $A60AC644, $835F7B24, $821C6481, $5DF525E1]);
  RegisterRomSet(lSet);

  lSet := TRomSetDef.Create('1942b', '1942', '1942 (First Version)', '1984', 'Capcom', CBoard);
  AddCommon(lSet);
  AddProgram(lSet, ['sr-03.m3', 'sr-04.m4', 'sr-05.m5', 'sr-06.m6', 'sr-07.m7'],
    [$612975F2, $A60AC644, $835F7B24, $821C6481, $5DF525E1]);
  RegisterRomSet(lSet);

  lSet := TRomSetDef.Create('1942w', '1942', '1942 (Williams Electronics license)', '1985',
    'Capcom (Williams Electronics license)', CBoard);
  AddCommon(lSet, 'sw-02.f2', $F8E9ADA2);
  AddProgram(lSet, ['sw-03.m3', 'sw-04.m4', 'sw-05.m5', 'sw-06.m6', 'sw-07.m7'],
    [$AFD79770, $933D9910, $E9A71BB6, $466F8248, $EC41655E]);
  RegisterRomSet(lSet);

  lSet := TRomSetDef.Create('1942h', '1942', 'Supercharger 1942', '1991', 'hack (Two Bit Score)', CBoard);
  AddCommon(lSet);
  AddProgram(lSet, ['supercharger_1942_@3.m3', 'supercharger_1942_@4.m4', 'supercharger_1942_@5.m5',
    'srb-06.m6', 'srb-07.m7'], [$EC70785F, $CC11355F, $42746D75, $466F8248, $0D31038C]);
  RegisterRomSet(lSet);
end;

initialization
  RegisterSets;

end.
