unit Arcade.Cabinet.Sound;

///  CABINET - the speaker. Minimal streaming audio output (Windows waveOut) : 16-bit mono, a ring of buffers.
///  The emulator pushes one frame of samples at a time. Pacing stays on the emulator's clock :
///  when the queue grows too long a frame is dropped, when it runs dry a silence frame pads it.
///  A DC blocker removes the PSG's unipolar offset.

interface

uses
  Winapi.Windows,
  Winapi.MMSystem,
  System.SysUtils;

type
  TWaveOut = class
  private
    FHandle: HWAVEOUT;
    FHeaders: array of TWaveHdr;
    FData: array of TArray<SmallInt>;
    FNext: Integer;
    FPrevIn, FPrevOut: Single;
    FVolume: Single;
    FOpen: Boolean;
    function Queued: Integer;
    procedure Submit(const aSamples: array of Single; aCount: Integer; aSilence: Boolean);
  public
    constructor Create(aSampleRate: Integer; aBufferSamples: Integer = 2048; aBufferCount: Integer = 8);
    destructor Destroy; override;
    procedure Push(const aSamples: array of Single; aCount: Integer);
    property Volume: Single read FVolume write FVolume;
    property IsOpen: Boolean read FOpen;
  end;

implementation

const
  CMaxQueued = 4;   // ~4 frames of latency at most

constructor TWaveOut.Create(aSampleRate, aBufferSamples, aBufferCount: Integer);
var
  lFormat: TWaveFormatEx;
  i: Integer;
begin
  inherited Create;
  FVolume := 0.5;
  lFormat := Default(TWaveFormatEx);
  lFormat.wFormatTag := WAVE_FORMAT_PCM;
  lFormat.nChannels := 1;
  lFormat.nSamplesPerSec := aSampleRate;
  lFormat.wBitsPerSample := 16;
  lFormat.nBlockAlign := 2;
  lFormat.nAvgBytesPerSec := aSampleRate * 2;
  FOpen := waveOutOpen(@FHandle, WAVE_MAPPER, @lFormat, 0, 0, CALLBACK_NULL) = MMSYSERR_NOERROR;
  if not FOpen then
    Exit;   // no audio device : the emulator runs silent
  SetLength(FHeaders, aBufferCount);
  SetLength(FData, aBufferCount);
  for i := 0 to aBufferCount - 1 do
  begin
    SetLength(FData[i], aBufferSamples);
    FHeaders[i] := Default(TWaveHdr);
    FHeaders[i].lpData := PAnsiChar(@FData[i][0]);
    FHeaders[i].dwBufferLength := aBufferSamples * 2;
    waveOutPrepareHeader(FHandle, @FHeaders[i], SizeOf(TWaveHdr));
    FHeaders[i].dwFlags := FHeaders[i].dwFlags or WHDR_DONE;
  end;
end;

destructor TWaveOut.Destroy;
var
  i: Integer;
begin
  if FOpen then
  begin
    waveOutReset(FHandle);
    for i := 0 to High(FHeaders) do
      waveOutUnprepareHeader(FHandle, @FHeaders[i], SizeOf(TWaveHdr));
    waveOutClose(FHandle);
  end;
  inherited;
end;

function TWaveOut.Queued: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FHeaders) do
    if (FHeaders[i].dwFlags and WHDR_DONE) = 0 then
      Inc(Result);
end;

procedure TWaveOut.Submit(const aSamples: array of Single; aCount: Integer; aSilence: Boolean);
var
  i: Integer;
  lIn, lOut: Single;
  lHdr: PWaveHdr;
begin
  lHdr := @FHeaders[FNext];
  if (lHdr.dwFlags and WHDR_DONE) = 0 then
    Exit;   // ring full
  if aCount > Length(FData[FNext]) then
    aCount := Length(FData[FNext]);
  for i := 0 to aCount - 1 do
  begin
    if aSilence then lIn := FPrevIn else lIn := aSamples[i];
    // DC blocker : y = x - x[-1] + 0.995 y[-1]
    lOut := lIn - FPrevIn + 0.995 * FPrevOut;
    FPrevIn := lIn;
    FPrevOut := lOut;
    lOut := lOut * FVolume * 32767;
    if lOut > 32767 then lOut := 32767 else if lOut < -32767 then lOut := -32767;
    FData[FNext][i] := Round(lOut);
  end;
  lHdr.dwBufferLength := aCount * 2;
  lHdr.dwFlags := lHdr.dwFlags and not WHDR_DONE;
  waveOutWrite(FHandle, lHdr, SizeOf(TWaveHdr));
  FNext := (FNext + 1) mod Length(FHeaders);
end;

procedure TWaveOut.Push(const aSamples: array of Single; aCount: Integer);
var
  lQueued: Integer;
begin
  if not FOpen or (aCount <= 0) then
    Exit;
  lQueued := Queued;
  if lQueued >= CMaxQueued then
    Exit;   // emulator ahead of the sound card : drop this frame
  if lQueued = 0 then
    Submit(aSamples, aCount, True);   // ran dry : pad one frame of silence first
  Submit(aSamples, aCount, False);
end;

end.
