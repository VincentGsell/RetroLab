/// Title      : GS.Common.I18n
/// Short Desc : Application strings in several languages, from JSON files.
///
/// The code carries the text of the default language (English) next to a key :
///     Caption := Tr('menu.quit', 'Quit');
///     Msg := TrFmt('score.best', 'Best score : %d', [lBest]);
/// so a program runs complete without any file. A translation is one JSON file per language,
/// <dir>/<lang>.json, keys flat or nested (nested objects are joined with '.') :
///     { "menu": { "quit": "Quitter" }, "score.best": "Meilleur score : %d" }
/// A key missing from the file falls back to the default text : a partial translation is fine.
///
/// Language : explicit ('fr'), or SystemLanguage (Windows UI language, LANG elsewhere).
///
/// History
/// 20261014 - VGS - Creation (1942 Revival : English by default, French translation).
unit GS.Common.I18n;

interface

{$I GSCore.inc}

uses Classes,
     SysUtils,
     {$IFDEF FPC}
     Generics.Collections
     {$ELSE}
     System.Generics.Collections
     {$ENDIF}
     {$IFDEF MSWINDOWS}
     , Windows
     {$ENDIF}
     , gs.Json;

Type

TGSI18n = class
private
  FStrings : TDictionary<string, string>;
  FLanguage : string;
  procedure AddObject(const prefix : string; const obj : igsJson);
public
  constructor Create;
  destructor Destroy; override;

  /// Two-letter ISO 639-1 code of the user's language, lowercase ('fr', 'en'...) ; 'en' if unknown.
  class function SystemLanguage : string;

  /// Back to the default texts (Language = '').
  procedure Clear;
  /// Adds the strings of a JSON file (later files override earlier ones). False if no such file.
  function LoadFile(const fileName : string) : boolean;
  /// Clear, then dir/lang.json. False if the file doesn't exist : default texts stay.
  function LoadLanguage(const dir, lang : string) : boolean;

  function Has(const key : string) : boolean;
  function Tr(const key, defaultText : string) : string;
  function TrFmt(const key, defaultText : string; const args : array of const) : string;

  /// Language of the loaded file ; '' = default texts.
  property Language : string read FLanguage;
end;

/// The process-wide table, created on first use.
function GSI18n : TGSI18n;
function Tr(const key, defaultText : string) : string;
function TrFmt(const key, defaultText : string; const args : array of const) : string;

implementation

uses
  gs.json.impl.gsJson;   // guarantees one JSON implementation : GS's own, no third-party code

var
  localI18n : TGSI18n = nil;

function GSI18n : TGSI18n;
begin
  if not Assigned(localI18n) then
    localI18n := TGSI18n.Create;
  result := localI18n;
end;

function Tr(const key, defaultText : string) : string;
begin
  result := GSI18n.Tr(key, defaultText);
end;

function TrFmt(const key, defaultText : string; const args : array of const) : string;
begin
  result := GSI18n.TrFmt(key, defaultText, args);
end;

{ TGSI18n }

constructor TGSI18n.Create;
begin
  inherited Create;
  FStrings := TDictionary<string, string>.Create;
end;

destructor TGSI18n.Destroy;
begin
  FStrings.Free;
  inherited;
end;

class function TGSI18n.SystemLanguage : string;
{$IFDEF MSWINDOWS}
var
  buffer : array[0..9] of Char;
{$ENDIF}
begin
  result := '';
  {$IFDEF MSWINDOWS}
  if GetLocaleInfo(GetUserDefaultUILanguage, LOCALE_SISO639LANGNAME, @buffer[0], Length(buffer)) > 0 then
    result := string(PChar(@buffer[0]));
  {$ELSE}
  result := GetEnvironmentVariable('LANG');   // 'fr_FR.UTF-8'
  {$ENDIF}
  result := LowerCase(Copy(result, 1, 2));
  if Length(result) <> 2 then
    result := 'en';
end;

procedure TGSI18n.Clear;
begin
  FStrings.Clear;
  FLanguage := '';
end;

procedure TGSI18n.AddObject(const prefix : string; const obj : igsJson);
var
  i : integer;
  name, value : string;
  child : igsJson;
begin
  for i := 0 to obj.jsonElementCount - 1 do
  begin
    name := prefix + obj.jsonElementName(i);
    case obj.jsonElementType(i) of
      etString :
      begin
        value := '';
        obj.get(i, value);
        FStrings.AddOrSetValue(name, value);
      end;
      etJson :
      begin
        child := obj.asObj(i);
        if Assigned(child) then
          AddObject(name + '.', child);
      end;
    end;
  end;
end;

function TGSI18n.LoadFile(const fileName : string) : boolean;
var
  text : TStringList;
  json : igsJson;
begin
  result := FileExists(fileName);
  if not result then
    exit;
  text := TStringList.Create;
  try
    text.LoadFromFile(fileName, TEncoding.UTF8);
    json := createJson;
    json.parse(text.Text);
    AddObject('', json);
  finally
    text.Free;
  end;
end;

function TGSI18n.LoadLanguage(const dir, lang : string) : boolean;
begin
  Clear;
  result := LoadFile(IncludeTrailingPathDelimiter(dir) + LowerCase(lang) + '.json');
  if result then
    FLanguage := LowerCase(lang);
end;

function TGSI18n.Has(const key : string) : boolean;
begin
  result := FStrings.ContainsKey(key);
end;

function TGSI18n.Tr(const key, defaultText : string) : string;
begin
  if not FStrings.TryGetValue(key, result) then
    result := defaultText;
end;

function TGSI18n.TrFmt(const key, defaultText : string; const args : array of const) : string;
begin
  try
    result := Format(Tr(key, defaultText), args);
  except
    on EConvertError do   // a translation with broken placeholders : the default text still works
      result := Format(defaultText, args);
  end;
end;

initialization

finalization
  FreeAndNil(localI18n);

end.
