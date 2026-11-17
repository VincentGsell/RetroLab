program Cabinet;

///  LA BORNE - a generic arcade cabinet : plug a ROM set in, the matching board runs it.
///
///    Cabinet.exe [--set 1942a]                       window (default set : 1942)
///    Cabinet.exe --frames N [--set s] [--replay f.inp | --coin F --start F] [--hash-log h.txt]
///                [--shot f.png] [--shot-every K --shot-dir d] [--wav f.wav] [--raw] [--zoom N]
///                                                    headless bench (oracle, checks)
///    options : --record f.inp (window), --mute, --service, --dip0 XX / --dip1 XX (hex)
///
///  Reading this uses clause is reading the machine, from the outside in.
///  Every unit of the project is listed with its path : open this .dpr in Delphi and compile,
///  no search path to set (build.bat / dcc64.cfg do the same from the command line).

uses
  System.SysUtils,
  System.IOUtils,
  FMX.Forms,

  // ---- LA BORNE (the cabinet) : monitor, speaker, control panel, gamepads, controls card --------
  Arcade.Cabinet.Display in '..\..\src\cabinet\Arcade.Cabinet.Display.pas',
  Arcade.Cabinet.Sound in '..\..\src\cabinet\Arcade.Cabinet.Sound.pas',
  Arcade.Cabinet.Gamepad in '..\..\src\cabinet\Arcade.Cabinet.Gamepad.pas',
  Arcade.Cabinet.Controls in '..\..\src\cabinet\Arcade.Cabinet.Controls.pas',
  Cabinet.Logo in 'Cabinet.Logo.pas',
  Cabinet.Overlay in 'Cabinet.Overlay.pas',
  Cabinet.Menu in 'Cabinet.Menu.pas',
  Cabinet.Window in 'Cabinet.Window.pas',
  Cabinet.Bench in 'Cabinet.Bench.pas',

  // ---- LA PRISE (the edge connector every board plugs into) ------------------------------------
  Arcade.Board in '..\..\src\core\Arcade.Board.pas',
  Arcade.RomSet in '..\..\src\core\Arcade.RomSet.pas',
  Arcade.Catalog in '..\..\src\core\Arcade.Catalog.pas',
  Arcade.Gfx in '..\..\src\core\Arcade.Gfx.pas',
  Arcade.Language in '..\..\src\core\Arcade.Language.pas',   // English in the code, lang\<code>.json for the others

  // ---- LES CARTES (board families) - each one lists its own chips in its uses clause ----------
  // PCB Capcom 84100 : 2 x Z80, 2 x AY-3-8910, tiles + sprites, ROT270
  Arcade.Board.Capcom84100 in '..\..\src\boards\Arcade.Board.Capcom84100.pas',
  Arcade.Board.Capcom84100.Video in '..\..\src\boards\Arcade.Board.Capcom84100.Video.pas',
  Arcade.Board.Capcom84100.Gfx in '..\..\src\boards\Arcade.Board.Capcom84100.Gfx.pas',
  // PCB Capcom 85605 : 2 x Z80 (opcodes chiffres), 2 x YM2203, ROT270
  Arcade.Board.Capcom85605 in '..\..\src\boards\Arcade.Board.Capcom85605.pas',
  Arcade.Board.Capcom85605.Video in '..\..\src\boards\Arcade.Board.Capcom85605.Video.pas',
  // PCB Capcom 85113 : 2 x Z80, 2 x YM2203, decor en ROM, 3 boutons, ROT270
  Arcade.Board.Capcom85113 in '..\..\src\boards\Arcade.Board.Capcom85113.pas',
  Arcade.Board.Capcom85113.Video in '..\..\src\boards\Arcade.Board.Capcom85113.Video.pas',
  Arcade.Board.Capcom85113.Gfx in '..\..\src\boards\Arcade.Board.Capcom85113.Gfx.pas',
  // carte Capcom "BM" : Z80 6 MHz + Z80 + i8751, 2 x YM2203, 2 decors, ROT270
  Arcade.Board.CapcomBM in '..\..\src\boards\Arcade.Board.CapcomBM.pas',
  Arcade.Board.CapcomBM.Video in '..\..\src\boards\Arcade.Board.CapcomBM.Video.pas',
  Arcade.Board.CapcomBM.Gfx in '..\..\src\boards\Arcade.Board.CapcomBM.Gfx.pas',
  // PCB Capcom 85606 : MC6809 + Z80, 2 x YM2203, decor 2 niveaux, ROT0
  Arcade.Board.Capcom85606 in '..\..\src\boards\Arcade.Board.Capcom85606.pas',
  Arcade.Board.Capcom85606.Video in '..\..\src\boards\Arcade.Board.Capcom85606.Video.pas',

  Arcade.Board.Sega1715376 in '..\..\src\boards\Arcade.Board.Sega1715376.pas',
  Arcade.Board.Sega1715376.Video in '..\..\src\boards\Arcade.Board.Sega1715376.Video.pas',
  Arcade.Board.Sega1715609 in '..\..\src\boards\Arcade.Board.Sega1715609.pas',
  Arcade.Board.Sega1715609.Video in '..\..\src\boards\Arcade.Board.Sega1715609.Video.pas',
  Arcade.Board.SegaPalette in '..\..\src\boards\Arcade.Board.SegaPalette.pas',

  // ---- LES PUCES (chips) - soldered on the boards above ----------------------------------------
  Arcade.Chip.Z80 in '..\..\src\chips\Arcade.Chip.Z80.pas',
  Arcade.Chip.AY8910 in '..\..\src\chips\Arcade.Chip.AY8910.pas',
  Arcade.Chip.YM2203 in '..\..\src\chips\Arcade.Chip.YM2203.pas',
  Arcade.Chip.MCS51 in '..\..\src\chips\Arcade.Chip.MCS51.pas',
  Arcade.Chip.M6809 in '..\..\src\chips\Arcade.Chip.M6809.pas',
  Arcade.Chip.M68000 in '..\..\src\chips\Arcade.Chip.M68000.pas',
  Arcade.Chip.YM2151 in '..\..\src\chips\Arcade.Chip.YM2151.pas',
  Arcade.Chip.SegaPCM in '..\..\src\chips\Arcade.Chip.SegaPCM.pas',
  Arcade.Chip.SegaMath in '..\..\src\chips\Arcade.Chip.SegaMath.pas',
  Arcade.Chip.Sega315_5296 in '..\..\src\chips\Arcade.Chip.Sega315_5296.pas',

  // ---- LES CARTOUCHES (ROM sets) - each one names the board family it needs -------------------
  Arcade.RomSet.Capcom1942 in '..\..\src\romsets\Arcade.RomSet.Capcom1942.pas',   // 1942, 1942a, 1942b, 1942w, 1942h -> capcom84100
  Arcade.RomSet.Commando in '..\..\src\romsets\Arcade.RomSet.Commando.pas',       // commando, commandou, commandou2, commandoj, sinvasn -> capcom85605
  Arcade.RomSet.GunSmoke in '..\..\src\romsets\Arcade.RomSet.GunSmoke.pas',       // gunsmoke, gunsmokej, gunsmokeu, gunsmokeua/ub/uc, gunsmokeg -> capcom85113
  Arcade.RomSet.Midway1943 in '..\..\src\romsets\Arcade.RomSet.Midway1943.pas',   // 1943, 1943u, 1943ua, 1943j, 1943ja, 1943jah -> capcombm
  Arcade.RomSet.GhostsNGoblins in '..\..\src\romsets\Arcade.RomSet.GhostsNGoblins.pas',   // gng, gngb, gngc, gngt, makaimur* -> capcom85606
  Arcade.RomSet.OutRun in '..\..\src\romsets\Arcade.RomSet.OutRun.pas',   // outrun, outrunra, outrundx, outrundxa -> sega1715376
  Arcade.RomSet.PowerDrift in '..\..\src\romsets\Arcade.RomSet.PowerDrift.pas',   // pdrift, pdrifta, pdrifte, pdriftj, pdriftja, pdriftjb -> sega1715609

  // ---- LIBRAIRIES : GS-Core (command line, CRC32, i18n, JSON) -----------------------------------
  GS.System.CommandLineParser in '..\..\third_party\gs-core\GS.System.CommandLineParser.pas',
  GS.FileOp in '..\..\third_party\gs-core\GS.FileOp.pas',
  GS.System.CPU in '..\..\third_party\gs-core\GS.System.CPU.pas',
  GS.System.CPU.Windows in '..\..\third_party\gs-core\GS.System.CPU.Windows.pas',
  GS.Common.I18n in '..\..\third_party\gs-core\GS.Common.I18n.pas',
  gs.Json in '..\..\third_party\gs-core\gs.Json.pas',
  gs.jsonCore in '..\..\third_party\gs-core\gs.jsonCore.pas',
  gs.json.impl.gsJson in '..\..\third_party\gs-core\gs.json.impl.gsJson.pas';

var
  lCmd: iGSCommandLine;
  lRoms: TRomSetData;
  lBoard: TArcadeBoard;
  lBench: TBenchOptions;
  lWindow: TCabinetWindow;
  lOptions: TCabinetOptions;

function IntParam(const aName: string; aDefault: Integer): Integer;
begin
  if lCmd.hasParameter(aName) then
    Result := StrToIntDef(lCmd.getParameter(aName), aDefault)
  else
    Result := aDefault;
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  lCmd := gsCommandLineParser;
  SelectLanguage(lCmd.getParameter('lang'));
  lCmd.registerParameter('lang', [], Tr('cmd.lang', 'Language : en, fr... (default : the Windows language)'));
  lCmd.registerParameter('set', [], Tr('cabinet.cmd.set', 'Game to start (default : the game menu)'));
  lCmd.registerParameter('frames', [], Tr('cabinet.cmd.frames', 'Headless bench : number of frames to run'));
  lCmd.registerParameter('replay', [], Tr('cabinet.cmd.replay', 'Replays an input log (.inp)'));
  lCmd.registerParameter('coin', [], Tr('cabinet.cmd.coin', 'Bench : frame where a coin is inserted'));
  lCmd.registerParameter('start', [], Tr('cabinet.cmd.start', 'Bench : frame where Start 1 is pressed'));
  lCmd.registerParameter('hash-log', [], Tr('cabinet.cmd.hashlog', 'Bench : state hash of every frame (oracle)'));
  lCmd.registerParameter('shot', [], Tr('cabinet.cmd.shot', 'Bench : PNG of the last frame'));
  lCmd.registerParameter('shot-every', [], Tr('cabinet.cmd.shotevery', 'Bench : a PNG every K frames (with --shot-dir)'));
  lCmd.registerParameter('shot-dir', [], Tr('cabinet.cmd.shotdir', 'Bench : folder of the --shot-every PNGs'));
  lCmd.registerParameter('wav', [], Tr('cabinet.cmd.wav', 'Bench : sound of the N frames into this .wav'));
  lCmd.registerParameter('raw', [], Tr('cabinet.cmd.raw', 'Bench : monitor picture, without the cabinet rotation'));
  lCmd.registerParameter('zoom', [], Tr('cabinet.cmd.zoom', 'Bench : integer zoom of the PNGs'));
  lCmd.registerParameter('record', [], Tr('cabinet.cmd.record', 'Window : records the inputs into this .inp on close'));
  lCmd.registerParameter('mute', [], Tr('cabinet.cmd.mute', 'Window without sound'));
  lCmd.registerParameter('debug', [], Tr('cabinet.cmd.debug', 'Window : frame / focus / inputs in the title bar'));
  lCmd.registerParameter('service', [], Tr('cabinet.cmd.service', 'Board test mode (service DIP)'));
  lCmd.registerParameter('dip0', [], Tr('cabinet.cmd.dip0', 'DIP bank 0 in hex'));
  lCmd.registerParameter('dip1', [], Tr('cabinet.cmd.dip1', 'DIP bank 1 in hex'));

  // headless : errors go to the trace file and the exit code, never to a dialog nobody sees
  if lCmd.hasParameter('frames') then
  try
    if lCmd.hasParameter('set') then
      lRoms := LoadRomSet(lCmd.getParameter('set'), ExtractFilePath(ParamStr(0)))
    else
      lRoms := LoadRomSet('1942', ExtractFilePath(ParamStr(0)));
    lRoms.Free;
  except
    on E: Exception do
    begin
      TFile.WriteAllText(ChangeFileExt(ParamStr(0), '.trace.txt'), Tr('cmd.error', 'ERROR') + ' ' + E.ClassName + ' : ' + E.Message);
      ExitCode := 1;
      Exit;
    end;
  end;

  // headless bench : the cartridge, then the board it asks for
  if lCmd.hasParameter('frames') then
  begin
    if lCmd.hasParameter('set') then
      lRoms := LoadRomSet(lCmd.getParameter('set'), ExtractFilePath(ParamStr(0)))
    else
      lRoms := LoadRomSet('1942', ExtractFilePath(ParamStr(0)));
    try
      lBoard := CreateBoardForSet(lRoms);
      try
        if lCmd.hasParameter('dip0') then
          lBoard.SetDip(0, StrToInt('$' + lCmd.getParameter('dip0')));
        if lCmd.hasParameter('dip1') then
          lBoard.SetDip(1, StrToInt('$' + lCmd.getParameter('dip1')));
        if lCmd.hasParameter('service') then
          lBoard.SetServiceMode(True);
        lBench := Default(TBenchOptions);
        lBench.Frames := IntParam('frames', 600);
        lBench.ReplayFile := lCmd.getParameter('replay');
        lBench.CoinAt := IntParam('coin', -1);
        lBench.StartAt := IntParam('start', -1);
        lBench.HashLogFile := lCmd.getParameter('hash-log');
        lBench.WavFile := lCmd.getParameter('wav');
        lBench.ShotFile := lCmd.getParameter('shot');
        lBench.ShotEvery := IntParam('shot-every', 0);
        lBench.ShotDir := lCmd.getParameter('shot-dir');
        lBench.Raw := lCmd.hasParameter('raw');
        lBench.Zoom := IntParam('zoom', 2);
        lBench.TraceFile := ChangeFileExt(ParamStr(0), '.trace.txt');
        RunBench(lBoard, lBench);
      finally
        lBoard.Free;
      end;
    finally
      lRoms.Free;
    end;
    Exit;
  end;

  // the window : the game menu, or the game asked with --set ; it plugs the boards in itself
  lOptions := Default(TCabinetOptions);
  lOptions.SetName := lCmd.getParameter('set');
  lOptions.RecordFile := lCmd.getParameter('record');
  lOptions.Sound := not lCmd.hasParameter('mute');
  lOptions.Dip0 := -1;
  lOptions.Dip1 := -1;
  if lCmd.hasParameter('dip0') then
    lOptions.Dip0 := StrToInt('$' + lCmd.getParameter('dip0'));
  if lCmd.hasParameter('dip1') then
    lOptions.Dip1 := StrToInt('$' + lCmd.getParameter('dip1'));
  lOptions.Service := lCmd.hasParameter('service');
  Application.Initialize;
  lWindow := TCabinetWindow.CreateCabinet(nil, lOptions);
  try
    lWindow.Debug := lCmd.hasParameter('debug');
    Application.MainForm := lWindow;
    lWindow.Show;
    Application.Run;
  finally
    Application.MainForm := nil;
    lWindow.Free;
  end;
end.
