unit Arcade.Catalog;

///  The games a cabinet can offer : every parent ROM set registered by the romsets/ units, with
///  whether its files are there and, if not, why. Used by the game menu (and by a 3D arcade room :
///  a switched-off cabinet is a set that can't be loaded). No FMX, no VCL.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Arcade.RomSet;

type
  /// How a game runs : its original ROMs on an emulated board, or a program of its own
  /// (a remake such as Beloved 43, compiled for the PC).
  TRunMethod = (rmEmulated, rmNative);

  TCatalogEntry = record
    Def: TRomSetDef;
    Available: Boolean;
    Problem: string;   // loader message when not available
    Method: TRunMethod;
  end;

/// Parent sets, oldest first. Each one is loaded once to check it (the files are small).
function ScanCatalog(const aStartDir: string): TArray<TCatalogEntry>;

implementation

function ScanCatalog(const aStartDir: string): TArray<TCatalogEntry>;
var
  lList: TList<TCatalogEntry>;
  lDef: TRomSetDef;
  lEntry: TCatalogEntry;
begin
  lList := TList<TCatalogEntry>.Create;
  try
    for lDef in AllRomSets do
    begin
      if lDef.Parent <> '' then
        Continue;
      lEntry := Default(TCatalogEntry);
      lEntry.Def := lDef;
      lEntry.Method := rmEmulated;
      try
        LoadRomSet(lDef.Name, aStartDir).Free;
        lEntry.Available := True;
      except
        on E: Exception do
          lEntry.Problem := E.Message;
      end;
      lList.Add(lEntry);
    end;
    lList.Sort(TComparer<TCatalogEntry>.Construct(
      function(const A, B: TCatalogEntry): Integer
      begin
        Result := CompareStr(A.Def.Year, B.Def.Year);
        if Result = 0 then
          Result := CompareText(A.Def.Name, B.Def.Name);
      end));
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

end.
