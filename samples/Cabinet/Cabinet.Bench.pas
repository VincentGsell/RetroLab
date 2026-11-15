unit Cabinet.Bench;

///  The cabinet without a window : runs a board as fast as possible, for the oracle and for checks.
///  Inputs come from a replay log or a coin/start script ; outputs are PNG shots, a per-frame state
///  hash log, a WAV of the sound, and a one-line trace next to the exe.

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  FMX.Graphics,
  Arcade.Gfx,
  Arcade.Board,
  Arcade.Cabinet.Display;

type
  TBenchOptions = record
    Frames: Integer;
    ReplayFile: string;          // '' : scripted coin/start below
    CoinAt, StartAt: Integer;    // -1 : never
    HashLogFile: string;
    WavFile: string;
    ShotFile: string;
    ShotEvery: Integer;
    ShotDir: string;
    Raw: Boolean;                // monitor orientation instead of the cabinet's
    Zoom: Integer;
    TraceFile: string;
  end;

procedure RunBench(aBoard: TArcadeBoard; const aOptions: TBenchOptions);

implementation

procedure SaveShot(aBoard: TArcadeBoard; const aFile: string; aRaw: Boolean; aZoom: Integer);
var
  lImage: TImage32;
  lBitmap: TBitmap;
begin
  if aRaw then
    lImage := aBoard.Screen
  else
    lImage := RotateImage(aBoard.Screen, aBoard.ScreenInfo.Rotation);
  lImage := lImage.Scaled(aZoom);
  lBitmap := TBitmap.Create;
  try
    Image32ToBitmap(lImage, lBitmap);
    lBitmap.SaveToFile(aFile);
  finally
    lBitmap.Free;
  end;
end;

// 16-bit mono PCM, DC removed (PSG outputs are unipolar)
procedure SaveWav(const aFile: string; const aSamples: TArray<Single>; aCount, aRate: Integer);
var
  lStream: TFileStream;
  lData: TArray<SmallInt>;
  i: Integer;
  lPrevIn, lPrevOut, lOut: Single;
  lDW: Cardinal;
  lW: Word;
begin
  SetLength(lData, aCount);
  lPrevIn := 0;
  lPrevOut := 0;
  for i := 0 to aCount - 1 do
  begin
    lOut := aSamples[i] - lPrevIn + 0.995 * lPrevOut;
    lPrevIn := aSamples[i];
    lPrevOut := lOut;
    lOut := lOut * 0.5 * 32767;
    if lOut > 32767 then lOut := 32767 else if lOut < -32767 then lOut := -32767;
    lData[i] := Round(lOut);
  end;
  lStream := TFileStream.Create(aFile, fmCreate);
  try
    lStream.WriteBuffer(AnsiString('RIFF')[1], 4);
    lDW := 36 + aCount * 2; lStream.WriteBuffer(lDW, 4);
    lStream.WriteBuffer(AnsiString('WAVEfmt ')[1], 8);
    lDW := 16; lStream.WriteBuffer(lDW, 4);
    lW := 1; lStream.WriteBuffer(lW, 2);            // PCM
    lW := 1; lStream.WriteBuffer(lW, 2);            // mono
    lDW := aRate; lStream.WriteBuffer(lDW, 4);
    lDW := aRate * 2; lStream.WriteBuffer(lDW, 4);
    lW := 2; lStream.WriteBuffer(lW, 2);
    lW := 16; lStream.WriteBuffer(lW, 2);
    lStream.WriteBuffer(AnsiString('data')[1], 4);
    lDW := aCount * 2; lStream.WriteBuffer(lDW, 4);
    if aCount > 0 then
      lStream.WriteBuffer(lData[0], aCount * 2);
  finally
    lStream.Free;
  end;
end;

procedure RunBench(aBoard: TArcadeBoard; const aOptions: TBenchOptions);
var
  f, lWavCount: Integer;
  lWatch: TStopwatch;
  lReplay: TInputLog;
  lHashLog: TStringList;
  lWav: TArray<Single>;
  lNeedPicture: Boolean;
begin
  lReplay := nil;
  lHashLog := nil;
  lWavCount := 0;
  lNeedPicture := (aOptions.ShotFile <> '') or (aOptions.ShotEvery > 0);
  try
    if aOptions.ReplayFile <> '' then
    begin
      lReplay := TInputLog.Create;
      lReplay.LoadFromFile(aOptions.ReplayFile);
    end;
    if aOptions.HashLogFile <> '' then
      lHashLog := TStringList.Create;
    if aOptions.WavFile <> '' then
    begin
      aBoard.AudioRate := 44100;
      SetLength(lWav, Trunc(aOptions.Frames * 44100 / aBoard.ScreenInfo.FrameRate) + 4096);
    end;

    lWatch := TStopwatch.StartNew;
    for f := 0 to aOptions.Frames - 1 do
    begin
      if Assigned(lReplay) then
        aBoard.Inputs := lReplay[f]
      else
      begin
        aBoard.Inputs := Default(TArcadeInputs);
        if (aOptions.CoinAt >= 0) and (f >= aOptions.CoinAt) and (f < aOptions.CoinAt + 6) then
          Include(aBoard.Inputs.System, asCoin1);
        if (aOptions.StartAt >= 0) and (f >= aOptions.StartAt) and (f < aOptions.StartAt + 6) then
          Include(aBoard.Inputs.System, asStart1);
      end;
      // the picture is only built for the frames that get shot
      aBoard.RenderEnabled := lNeedPicture and
        ((f = aOptions.Frames - 1) or ((aOptions.ShotEvery > 0) and ((f + 1) mod aOptions.ShotEvery = 0)));
      aBoard.RunFrame;
      if aBoard.AudioRate > 0 then
      begin
        Move(aBoard.AudioBuffer[0], lWav[lWavCount], aBoard.AudioCount * SizeOf(Single));
        Inc(lWavCount, aBoard.AudioCount);
      end;
      if Assigned(lHashLog) then
        lHashLog.Add(Format('%d %.16x', [f + 1, aBoard.StateHash]));
      if (aOptions.ShotEvery > 0) and ((f + 1) mod aOptions.ShotEvery = 0) then
        SaveShot(aBoard, IncludeTrailingPathDelimiter(aOptions.ShotDir) + Format('f%.5d.png', [f + 1]),
          aOptions.Raw, aOptions.Zoom);
    end;
    lWatch.Stop;

    if aOptions.ShotFile <> '' then
      SaveShot(aBoard, aOptions.ShotFile, aOptions.Raw, aOptions.Zoom);
    if Assigned(lHashLog) then
      lHashLog.SaveToFile(aOptions.HashLogFile);
    if aBoard.AudioRate > 0 then
      SaveWav(aOptions.WavFile, lWav, lWavCount, aBoard.AudioRate);
    // a GUI app has no console : one line next to the exe
    if aOptions.TraceFile <> '' then
      TFile.WriteAllText(aOptions.TraceFile,
        Format('set=%s  board=%s  frames=%d  %.2f s  %.0f fps  hash=%.16x',
          [aBoard.Roms.Def.Name, aBoard.Family, aOptions.Frames, lWatch.Elapsed.TotalSeconds,
           aOptions.Frames / lWatch.Elapsed.TotalSeconds, aBoard.StateHash]));
  finally
    lHashLog.Free;
    lReplay.Free;
  end;
end;

end.
