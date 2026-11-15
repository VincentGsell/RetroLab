unit Arcade.RomSet;

///  ROM sets = the "cartridges". A set is a list of files (name, CRC32, size) loaded into named
///  memory regions ('maincpu', 'gfx1'... as in MAME), and the name of the board family that runs it.
///  Several sets can target the same board (1942 rev A, rev B, Williams...).
///
///  Loading follows MAME conventions : roms\<set>.zip, roms\<parent>.zip (merged sets keep clone
///  files in a "<clone>/" sub-folder), or the same names as extracted folders. Files are found by
///  CRC32 in zips, by name in folders, and every file is CRC-checked : a bad dump fails loudly.
///  No FMX, no VCL.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Zip,
  System.IOUtils,
  System.Generics.Collections;

type
  ERomSet = class(Exception);

  TRomRegionDef = record
    Name: string;
    Size: Integer;
    Fill: Byte;        // value of bytes no file covers (MAME ROMREGION_ERASEFF -> $FF)
  end;

  TRomFileDef = record
    Name: string;
    Region: string;
    Offset: Integer;
    Size: Integer;
    Crc: UInt32;
  end;

  /// Declaration of a set (static description, registered by the romsets/ units).
  TRomSetDef = class
  public
    Name: string;        // MAME short name : '1942', '1942a'...
    Parent: string;      // '' for a parent set
    Title: string;
    Year: string;
    Maker: string;
    Board: string;       // board family that runs it : 'capcom84100'
    Regions: TArray<TRomRegionDef>;
    Files: TArray<TRomFileDef>;
    constructor Create(const aName, aParent, aTitle, aYear, aMaker, aBoard: string);
    procedure AddRegion(const aName: string; aSize: Integer; aFill: Byte = 0);
    procedure AddFile(const aName, aRegion: string; aOffset, aSize: Integer; aCrc: UInt32);
  end;

  /// A loaded set : the cartridge plugged into a board.
  TRomSetData = class
  private
    FDef: TRomSetDef;
    FSource: string;
    FRegions: TDictionary<string, TBytes>;
  public
    constructor Create(aDef: TRomSetDef);
    destructor Destroy; override;
    /// Raises ERomSet if the board asks for a region the set does not declare.
    function Region(const aName: string): TBytes;
    function HasRegion(const aName: string): Boolean;
    property Def: TRomSetDef read FDef;
    /// Where the files came from (zips / folders), for display.
    property Source: string read FSource;
  end;

procedure RegisterRomSet(aDef: TRomSetDef);
function FindRomSet(const aName: string): TRomSetDef;
function AllRomSets: TArray<TRomSetDef>;

/// Finds the set's files walking up from aStartDir (roms\ next to the project), checks every CRC.
function LoadRomSet(const aName, aStartDir: string): TRomSetData;

implementation

uses
  GS.FileOp,
  GS.Common.I18n;

var
  GRomSets: TObjectList<TRomSetDef>;

{ TRomSetDef }

constructor TRomSetDef.Create(const aName, aParent, aTitle, aYear, aMaker, aBoard: string);
begin
  inherited Create;
  Name := aName;
  Parent := aParent;
  Title := aTitle;
  Year := aYear;
  Maker := aMaker;
  Board := aBoard;
end;

procedure TRomSetDef.AddRegion(const aName: string; aSize: Integer; aFill: Byte);
var
  lRegion: TRomRegionDef;
begin
  lRegion.Name := aName;
  lRegion.Size := aSize;
  lRegion.Fill := aFill;
  Regions := Regions + [lRegion];
end;

procedure TRomSetDef.AddFile(const aName, aRegion: string; aOffset, aSize: Integer; aCrc: UInt32);
var
  lFile: TRomFileDef;
begin
  lFile.Name := aName;
  lFile.Region := aRegion;
  lFile.Offset := aOffset;
  lFile.Size := aSize;
  lFile.Crc := aCrc;
  Files := Files + [lFile];
end;

{ TRomSetData }

constructor TRomSetData.Create(aDef: TRomSetDef);
var
  lRegion: TRomRegionDef;
  lBytes: TBytes;
begin
  inherited Create;
  FDef := aDef;
  FRegions := TDictionary<string, TBytes>.Create;
  for lRegion in aDef.Regions do
  begin
    SetLength(lBytes, lRegion.Size);
    if lRegion.Size > 0 then
      FillChar(lBytes[0], lRegion.Size, lRegion.Fill);
    FRegions.Add(lRegion.Name, lBytes);
    lBytes := nil;
  end;
end;

destructor TRomSetData.Destroy;
begin
  FRegions.Free;
  inherited;
end;

function TRomSetData.Region(const aName: string): TBytes;
begin
  if not FRegions.TryGetValue(aName, Result) then
    raise ERomSet.Create(TrFmt('romset.err.region', 'Set %s : region "%s" missing', [FDef.Name, aName]));
end;

function TRomSetData.HasRegion(const aName: string): Boolean;
begin
  Result := FRegions.ContainsKey(aName);
end;

{ Registry }

procedure RegisterRomSet(aDef: TRomSetDef);
begin
  GRomSets.Add(aDef);
end;

function FindRomSet(const aName: string): TRomSetDef;
begin
  for Result in GRomSets do
    if SameText(Result.Name, aName) then
      Exit;
  raise ERomSet.Create(TrFmt('romset.err.unknown', 'Unknown ROM set : "%s"', [aName]));
end;

function AllRomSets: TArray<TRomSetDef>;
begin
  Result := GRomSets.ToArray;
end;

{ Loading }

function BytesCrc32(const aBytes: TBytes): UInt32;
var
  lStream: TBytesStream;
begin
  lStream := TBytesStream.Create(aBytes);
  try
    TGSBin.CalcCRC32(lStream, Result);
  finally
    lStream.Free;
  end;
end;

function LoadRomSet(const aName, aStartDir: string): TRomSetData;
var
  lDef: TRomSetDef;
  lZips: TObjectList<TZipFile>;
  lFolders, lSources: TStringList;
  lDir, lCandidate: string;
  i, z: Integer;
  lFile: TRomFileDef;
  lBytes, lRegion: TBytes;
  lFound: Boolean;
  lZip: TZipFile;
  lHeader: TZipHeader;

  procedure AddCandidates(const aBase: string);
  var
    lSetName, lCandidate: string;
  begin
    for lSetName in [lDef.Name, lDef.Parent] do
    begin
      if lSetName = '' then
        Continue;
      lCandidate := aBase + lSetName + '.zip';
      if FileExists(lCandidate) and (lSources.IndexOf(lCandidate) < 0) then
      begin
        lZip := TZipFile.Create;
        lZip.Open(lCandidate, zmRead);
        lZips.Add(lZip);
        lSources.Add(lCandidate);
      end;
      lCandidate := aBase + lSetName;
      if DirectoryExists(lCandidate) and (lFolders.IndexOf(lCandidate) < 0) then
      begin
        lFolders.Add(lCandidate);
        lSources.Add(lCandidate);
      end;
    end;
  end;

begin
  lDef := FindRomSet(aName);
  lZips := TObjectList<TZipFile>.Create;
  lFolders := TStringList.Create;
  lSources := TStringList.Create;
  Result := TRomSetData.Create(lDef);
  try
    try
      lDir := ExcludeTrailingPathDelimiter(aStartDir);
      for i := 0 to 7 do
      begin
        AddCandidates(IncludeTrailingPathDelimiter(lDir) + 'roms' + PathDelim);
        AddCandidates(IncludeTrailingPathDelimiter(lDir));
        lDir := ExtractFileDir(lDir);
        if lDir = '' then
          Break;
      end;
      if lSources.Count = 0 then
        raise ERomSet.Create(TrFmt('romset.err.notfound', 'Set %s : neither roms\%s.zip nor roms\%s\ found',
          [lDef.Name, lDef.Name, lDef.Name]));

      for lFile in lDef.Files do
      begin
        lFound := False;
        // folders first (by name), then zips (by CRC : clone files live in sub-folders)
        for lCandidate in lFolders do
          if FileExists(IncludeTrailingPathDelimiter(lCandidate) + lFile.Name) then
          begin
            lBytes := TFile.ReadAllBytes(IncludeTrailingPathDelimiter(lCandidate) + lFile.Name);
            if (Length(lBytes) = lFile.Size) and (BytesCrc32(lBytes) = lFile.Crc) then
            begin
              lFound := True;
              Break;
            end;
          end;
        if not lFound then
          for z := 0 to lZips.Count - 1 do
          begin
            for i := 0 to lZips[z].FileCount - 1 do
            begin
              lHeader := lZips[z].FileInfo[i];
              if (lHeader.CRC32 = lFile.Crc) and (Integer(lHeader.UncompressedSize) = lFile.Size) then
              begin
                lZips[z].Read(i, lBytes);
                lFound := BytesCrc32(lBytes) = lFile.Crc;
                Break;
              end;
            end;
            if lFound then
              Break;
          end;
        if not lFound then
          raise ERomSet.Create(TrFmt('romset.err.file', 'Set %s : file %s (CRC %.8x, %d bytes) missing or corrupt in %s',
            [lDef.Name, lFile.Name, lFile.Crc, lFile.Size, lSources.CommaText]));
        lRegion := Result.Region(lFile.Region);
        Move(lBytes[0], lRegion[lFile.Offset], lFile.Size);
      end;
      Result.FSource := lSources.CommaText;
    except
      Result.Free;
      raise;
    end;
  finally
    lSources.Free;
    lFolders.Free;
    lZips.Free;
  end;
end;

initialization
  GRomSets := TObjectList<TRomSetDef>.Create(True);

finalization
  GRomSets.Free;

end.
