unit Arcade.Language;

///  The language of every program of the project. English is in the code (Tr(key, 'English text'),
///  GS.Common.I18n) ; other languages are lang\<code>.json, found walking up from the exe like the
///  ROMs (lang\ at the project root). Choice : --lang <code>, else the Windows UI language ;
///  a language without a file, or a key missing from it, shows the English text.

interface

uses
  System.SysUtils,
  GS.Common.I18n;

/// aLang = '' : the system language. Returns the language actually loaded ('' = English).
function SelectLanguage(const aLang: string): string;

implementation

function SelectLanguage(const aLang: string): string;
var
  lLang, lDir, lParent: string;
begin
  lLang := LowerCase(Trim(aLang));
  if lLang = '' then
    lLang := TGSI18n.SystemLanguage;
  GSI18n.Clear;
  if lLang <> 'en' then
  begin
    lDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
    while lDir <> '' do
    begin
      if GSI18n.LoadLanguage(lDir + PathDelim + 'lang', lLang) then
        Break;
      lParent := ExcludeTrailingPathDelimiter(ExtractFilePath(lDir));
      if lParent = lDir then
        Break;   // drive root ('C:' is its own parent)
      lDir := lParent;
    end;
  end;
  Result := GSI18n.Language;
end;

end.
