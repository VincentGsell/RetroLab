unit Arcade.Board;

///  The plug between the cabinet and a board - our software "JAMMA" edge connector.
///
///    cabinet (window, controls, speaker)  <-- TArcadeBoard -->  board (chips + wiring)  <-- ROM set
///
///  A board family (one hardware design, e.g. 'capcom84100') descends from TArcadeBoard and registers
///  itself; any ROM set declaring that family can then be plugged into it. The cabinet only knows
///  this unit : player controls in, picture and sound out, one frame at a time.
///  Deterministic by contract : same inputs from power-on -> same StateHash at every frame (oracle).
///  Pure unit : no FMX.

interface

uses
  System.SysUtils,
  GS.Common.I18n,
  System.Classes,
  System.Generics.Collections,
  Arcade.Gfx,
  Arcade.RomSet;

type
  /// One player's control panel.
  TArcadeButton = (abUp, abDown, abLeft, abRight, abButton1, abButton2, abButton3);
  TArcadeButtons = set of TArcadeButton;

  /// Cabinet-wide switches.
  TArcadeSystem = (asCoin1, asCoin2, asStart1, asStart2, asService);
  TArcadeSystems = set of TArcadeSystem;

  /// Everything a player can touch, sampled once per frame. Active = pressed.
  TArcadeInputs = record
    Players: array[0..1] of TArcadeButtons;
    System: TArcadeSystems;
  end;

  /// What the cabinet makes a player feel (wheel shaker, moving seat), 0 = still .. 1 = full.
  /// Heavy = slow, strong motor ; Light = fast, soft motor (a gamepad's two rumble motors).
  TArcadeRumble = record
    Heavy, Light: Single;
  end;

  /// One TArcadeInputs per frame from power-on : the whole game is a pure function of this log.
  TInputLog = class
  private
    FFrames: TArray<TArcadeInputs>;
    FCount: Integer;
    function GetFrame(aIndex: Integer): TArcadeInputs;
  public
    procedure Clear;
    procedure Add(const aInputs: TArcadeInputs);
    procedure SaveToFile(const aFile: string);
    procedure LoadFromFile(const aFile: string);
    property Count: Integer read FCount;
    property Frames[aIndex: Integer]: TArcadeInputs read GetFrame; default;
  end;

  /// What the board's monitor is, so the cabinet can show it.
  TScreenInfo = record
    Width, Height: Integer;          // visible area, monitor orientation
    Rotation: TScreenRotation;       // how the monitor is mounted in the cabinet
    FrameRate: Double;               // Hz
  end;

  TArcadeBoard = class;
  TArcadeBoardClass = class of TArcadeBoard;

  TArcadeBoard = class
  protected
    FRoms: TRomSetData;
    FScreen: TImage32;
    FAudioRate: Integer;
    FAudioBuffer: TArray<Single>;
    FAudioCount: Integer;
    FFrame: Int64;
    procedure SetAudioRate(aValue: Integer); virtual;
  public
    Inputs: TArcadeInputs;
    /// Force feedback of the last frame, per player ; boards without motors leave it at rest.
    Rumble: array[0..1] of TArcadeRumble;
    /// Off : RunFrame skips the video (headless oracle runs go faster).
    RenderEnabled: Boolean;

    /// Board family id, as declared by ROM sets ('capcom84100').
    class function Family: string; virtual; abstract;
    class function Description: string; virtual; abstract;
    /// The board takes ownership of nothing : aRoms must outlive it.
    constructor Create(aRoms: TRomSetData); virtual;
    procedure Reset; virtual; abstract;
    /// One video frame of emulated time ; Screen and AudioBuffer are refreshed.
    procedure RunFrame; virtual; abstract;
    function ScreenInfo: TScreenInfo; virtual; abstract;
    /// Hash of the whole emulated state (RAMs, registers of every chip) : oracle comparisons.
    function StateHash: UInt64; virtual; abstract;
    /// Service / test mode switch of the board (DIP on most boards).
    procedure SetServiceMode(aOn: Boolean); virtual;
    /// Board-specific DIP banks, index 0, 1... ; ignored when the board has fewer.
    procedure SetDip(aIndex: Integer; aValue: Byte); virtual;

    property Roms: TRomSetData read FRoms;
    property Screen: TImage32 read FScreen;
    property Frame: Int64 read FFrame;
    /// Output sample rate ; 0 (default) = no sound synthesis.
    property AudioRate: Integer read FAudioRate write SetAudioRate;
    /// Mono samples of the last frame, AudioCount of them.
    property AudioBuffer: TArray<Single> read FAudioBuffer;
    property AudioCount: Integer read FAudioCount;
  end;

procedure RegisterBoard(aClass: TArcadeBoardClass);
function FindBoard(const aFamily: string): TArcadeBoardClass;

/// Plugs a ROM set into the board family it declares. The caller frees both, board first.
function CreateBoardForSet(aRoms: TRomSetData): TArcadeBoard;

implementation

var
  GBoards: TList<TArcadeBoardClass>;

{ TInputLog }

const
  CInputLogMagic: array[0..3] of AnsiChar = ('A', 'R', 'C', '1');

function TInputLog.GetFrame(aIndex: Integer): TArcadeInputs;
begin
  if (aIndex >= 0) and (aIndex < FCount) then
    Result := FFrames[aIndex]
  else
    Result := Default(TArcadeInputs);
end;

procedure TInputLog.Clear;
begin
  FCount := 0;
end;

procedure TInputLog.Add(const aInputs: TArcadeInputs);
begin
  if FCount = Length(FFrames) then
    SetLength(FFrames, 2 * FCount + 1024);
  FFrames[FCount] := aInputs;
  Inc(FCount);
end;

procedure TInputLog.SaveToFile(const aFile: string);
var
  lStream: TFileStream;
begin
  lStream := TFileStream.Create(aFile, fmCreate);
  try
    lStream.WriteBuffer(CInputLogMagic, SizeOf(CInputLogMagic));
    lStream.WriteBuffer(FCount, SizeOf(FCount));
    if FCount > 0 then
      lStream.WriteBuffer(FFrames[0], FCount * SizeOf(TArcadeInputs));
  finally
    lStream.Free;
  end;
end;

procedure TInputLog.LoadFromFile(const aFile: string);
var
  lStream: TFileStream;
  lMagic: array[0..3] of AnsiChar;
begin
  lStream := TFileStream.Create(aFile, fmOpenRead or fmShareDenyWrite);
  try
    lStream.ReadBuffer(lMagic, SizeOf(lMagic));
    if lMagic <> CInputLogMagic then
      raise Exception.Create(TrFmt('board.err.inputlog', '%s : not a cabinet input log', [aFile]));
    lStream.ReadBuffer(FCount, SizeOf(FCount));
    SetLength(FFrames, FCount);
    if FCount > 0 then
      lStream.ReadBuffer(FFrames[0], FCount * SizeOf(TArcadeInputs));
  finally
    lStream.Free;
  end;
end;

{ TArcadeBoard }

constructor TArcadeBoard.Create(aRoms: TRomSetData);
begin
  inherited Create;
  FRoms := aRoms;
  RenderEnabled := True;
end;

procedure TArcadeBoard.SetAudioRate(aValue: Integer);
begin
  FAudioRate := aValue;
  FAudioCount := 0;
  if aValue > 0 then
    SetLength(FAudioBuffer, Trunc(aValue / ScreenInfo.FrameRate) + 16)
  else
    FAudioBuffer := nil;
end;

procedure TArcadeBoard.SetServiceMode(aOn: Boolean);
begin
end;

procedure TArcadeBoard.SetDip(aIndex: Integer; aValue: Byte);
begin
end;

{ Registry }

procedure RegisterBoard(aClass: TArcadeBoardClass);
begin
  GBoards.Add(aClass);
end;

function FindBoard(const aFamily: string): TArcadeBoardClass;
begin
  for Result in GBoards do
    if SameText(Result.Family, aFamily) then
      Exit;
  raise Exception.Create(TrFmt('board.err.noboard', 'No board "%s" is plugged into this program', [aFamily]));
end;

function CreateBoardForSet(aRoms: TRomSetData): TArcadeBoard;
begin
  Result := FindBoard(aRoms.Def.Board).Create(aRoms);
end;

initialization
  GBoards := TList<TArcadeBoardClass>.Create;

finalization
  GBoards.Free;

end.
