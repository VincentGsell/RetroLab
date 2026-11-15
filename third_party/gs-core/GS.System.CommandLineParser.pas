unit GS.System.CommandLineParser;

{$IFDEF FPC}
{$MODE Delphi}
{$ENDIF}

interface

{$IFNDEF FPC}
{$IF CompilerVersion >= 25}
  {$LEGACYIFEND ON}
{$IFEND}
{$ENDIF}


uses
  {$IFNDEF FPC}
  {$IF CompilerVersion >= 23}
  System.Classes,
  System.Contnrs,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;
  {$ELSE}
  Classes,
  Contnrs,
  SysUtils,
  StrUtils,
  Generics.Collections;
  {$IFEND}
  {$ELSE}
  Classes,
  Contnrs,
  SysUtils,
  StrUtils,
  Generics.Collections;
  {$ENDIF}


type
  EPArameterAlreadyExists = class(Exception);


  iGSCommandLine = Interface
    procedure registerParameter(paramId : String; ParamsShortcut : TArray<String>; DescriptionHelp : string);
    function hasParameter(paramName : string) : boolean;
    function getParameter(paramName : string) : string;
    function getHelp : string;
    function CurrentParameterCount : Integer;
    function checksyntax : boolean;
    //Arguments that do not start with '-' (sub-commands, file names...), in command line order.
    //Note : with the "--name value" form, value is also returned here; use "--name=value" when mixing.
    function positionalArguments : TArray<string>;
  End;

  TGSCmdLineParam = record
    paramId : string;
    shortcutList : string;
    Desc : string;
  end;

  TGSCmdLineManager = class(TInterfacedObject, iGSCommandLine)
    FParams : TDictionary<string,TGSCmdLineParam>;
    FCMdLine : TArray<string>;
    function GetCmdLineStrAsList : String;
    //Split "--name=value" : returns name without prefix, and value (empty if no '=').
    function SplitOption(const aToken : string; out aValue : string; out aHasValue : boolean) : string;
  public
    constructor Create; virtual;
    //Testable constructor : explicit argument list instead of ParamStr.
    constructor CreateFromArgs(const aArgs : TArray<string>);
    destructor Destroy; override;
    procedure registerParameter(paramId : String; ParamsShortcut : TArray<String>; DescriptionHelp : string);
    function hasParameter(paramName : string) : boolean;
    function getParameter(paramName : string) : string;
    function getHelp : string;
    function CurrentParameterCount : Integer;
    function checksyntax : boolean;
    function positionalArguments : TArray<string>;

    function IsShortCut(aParamName : String; out aParamItem : TGSCmdLineParam) : Boolean;
    function IsShortCutInSameParam(aParam1, aParam2 : String; out aParamItem : TGSCmdLineParam) : Boolean;
  end;

  function gsCommandLineParser : iGSCommandLine;

  /// Retire uniquement le prefixe '--' ou '-' d'un argument CLI.
  /// Anciennement Replace('-',''), qui supprimait aussi les tirets internes
  /// et empechait l'usage de noms d'options comme 'verbose-light' ou 'dry-run'.
  function StripParamPrefix(const S : string) : string;


implementation

  function gsCommandLineParser : iGSCommandLine;
  begin
    result := TGSCmdLineManager.Create;
  end;

  function StripParamPrefix(const S : string) : string;
  begin
    Result := S;
    if Result.StartsWith('--') then
      Result := Result.Substring(2)
    else if Result.StartsWith('-') then
      Result := Result.Substring(1);
  end;



{ TGSCmdLineManager }

function TGSCmdLineManager.checksyntax: boolean;
var lp : TGSCmdLineParam;
begin
  result := true;
  if length(FCMdLine)>0 then
    result := IsShortCut(FCMDLine[0],lp);
end;

constructor TGSCmdLineManager.Create;
var i : integer;
    lArgs : TArray<string>;
begin
  //Built from ParamStr (not from a joined/split string) : arguments containing spaces are kept whole.
  SetLength(lArgs, ParamCount);
  for i := 1 to ParamCount do
    lArgs[i-1] := ParamStr(i);
  CreateFromArgs(lArgs);
end;

constructor TGSCmdLineManager.CreateFromArgs(const aArgs: TArray<string>);
begin
  inherited Create;
  FParams := TDictionary<string,TGSCmdLineParam>.create;
  FCmdLine := Copy(aArgs, 0, Length(aArgs));
end;

function TGSCmdLineManager.SplitOption(const aToken: string; out aValue: string;
  out aHasValue: boolean): string;
var lPos : integer;
begin
  result := StripParamPrefix(aToken);
  lPos := Pos('=', result);
  aHasValue := lPos > 0;
  if aHasValue then
  begin
    aValue := Copy(result, lPos + 1, MaxInt);
    result := Copy(result, 1, lPos - 1);
  end
  else
    aValue := '';
end;

function TGSCmdLineManager.positionalArguments: TArray<string>;
var i, lCount : integer;
begin
  SetLength(result, Length(FCmdLine));
  lCount := 0;
  for i := 0 to Length(FCmdLine) - 1 do
    if (FCmdLine[i] <> '') and not FCmdLine[i].StartsWith('-') then
    begin
      result[lCount] := FCmdLine[i];
      Inc(lCount);
    end;
  SetLength(result, lCount);
end;

function TGSCmdLineManager.CurrentParameterCount: Integer;
begin
  result := length(FCMdLine);
end;

destructor TGSCmdLineManager.Destroy;
begin
  FreeAndNil(FParams);
  inherited;
end;

function TGSCmdLineManager.GetCmdLineStrAsList: String;
var i: Integer;
begin
  for i := 1 to ParamCount do
    Result := Result + ParamStr(I) + ' ';
  Result := Result.Trim;
end;

function TGSCmdLineManager.getHelp: string;
var l : TPair<string,TGSCmdLineParam>;
    lsc : string;
    lscAlternate : string;
    lscl : TArray<string>;
    i : integer;
begin
  if FParams.Count=0 then
    exit;
  for l in FParams do begin
    lsc := l.Value.paramId;
    lscl := l.Value.shortcutList.Split([' ',',',';']);
    if length(lscl)>1 then
      for i := Low(lscl) to High(lscl) do
        lscAlternate := lscAlternate + '-'+lscl[i]+ ' --'+lscl[i]+' ';
      lscAlternate := lscAlternate.Trim;
    writeln(format('- %s [%s])',[lsc,lscAlternate]));
    writeln(format('    %s',[l.Value.Desc]));
    writeln;
    lscAlternate := '';
  end;
end;

function TGSCmdLineManager.getParameter(paramName: string): string;
var l : TArray<String>;
    i,j: Integer;
    lf : string;
    aParam : TGSCmdLineParam;
    lInlineValue : string;
    lHasInlineValue : boolean;
    lValue : string;
begin
  //Accumulate in an initialized local : FPC does not guarantee an empty managed result
  //(previous content of the caller's destination leaked into the value).
  lValue := '';
  l := FCmdLine;
  for i := 0 to Length(l)-1 do
    if (l[i].StartsWith('-')) or (l[i].StartsWith('--')) then begin
      lf := SplitOption(l[i], lInlineValue, lHasInlineValue);
      if (lf = paramName) or IsShortCutInSameParam(paramname,lf,aParam) then begin
        if lHasInlineValue then begin //"--name=value" form.
          result := lInlineValue;
          exit;
        end;
        if i<length(l)-1 then
          for j := i+1 to length(l)-1 do begin
            if (l[j].StartsWith('-')) or (l[j].StartsWith('--')) then
              break;
            lValue := lValue + l[j] + ' ';
          end;
      end;
    end;
  result := lValue.Trim;
end;

function TGSCmdLineManager.hasParameter(paramName: string): boolean;
var l : TArray<String>;
    i: Integer;
    lf : string;
    aParam : TGSCmdLineParam;
    lInlineValue : string;
    lHasInlineValue : boolean;
begin
  result := False;
  l := FCmdLine;
  for i := 0 to Length(l)-1 do
    if (l[i].StartsWith('-')) or (l[i].StartsWith('--')) then begin
      lf := SplitOption(l[i], lInlineValue, lHasInlineValue);
      if (lf = paramName) or IsShortCutInSameParam(paramname,lf,aParam)  then begin //direct parameter Or registered one.
        result := true;
        break;
      end;
    end;
end;

function TGSCmdLineManager.IsShortCut(aParamName: String;
  out aParamItem: TGSCmdLineParam): Boolean;
var l : TPair<string,TGSCmdLineParam>;
    lsc : TArray<string>;
    lp : string;
    i : integer;
begin
  result := false;
  if aParamName.Trim='' then
    Exit;
  lp := aParamName.ToLower;
  lp := StripParamPrefix(lp);
  for l in FParams do begin
    lsc := l.Value.shortcutList.Split([' ',',',';']);
    if length(lsc)>0 then
      for i := Low(lsc) to High(lsc) do
        if lsc[i].ToLower = lp then begin
          result := true;
          aParamItem := l.Value;
          exit;
        end;
  end;
end;

function TGSCmdLineManager.IsShortCutInSameParam(aParam1, aParam2: String;
  out aParamItem: TGSCmdLineParam): Boolean;
var a,b : TGSCmdLineParam;
begin
  result := IsShortCut(aParam1,a) and IsShortCut(aParam2,b) and (a.paramId = b.paramId);
end;

procedure TGSCmdLineManager.registerParameter(paramId: String;
  ParamsShortcut: TArray<String>; DescriptionHelp: string);
var lp : TGSCmdLineParam;
    i : integer;
begin
  if FParams.TryGetValue(paramId,lp) then
    raise EPArameterAlreadyExists.Create(paramId);

  for i := Low(ParamsShortcut) to High(ParamsShortcut) do
    if (IsShortCut(ParamsShortcut[i],lp)) Or (ParamsShortcut[i].ToLower = paramId.ToLower) then
      raise Exception.Create(ParamsShortcut[i]+' is already shortcuts of '+paramId.ToLower);

  lp.paramId := paramId;
  for i := Low(ParamsShortcut) to High(ParamsShortcut) do
    lp.shortcutList := lp.shortcutList + ParamsShortcut[i]+' ';
  lp.shortcutList := lp.shortcutList + paramId;
  lp.shortcutList := lp.shortcutList.Trim;
  lp.Desc := DescriptionHelp;
  FParams.Add(paramId,lp);
end;

end.
