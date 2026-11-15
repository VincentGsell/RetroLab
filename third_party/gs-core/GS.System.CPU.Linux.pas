///-------------------------------------------------------------------------------
/// Title      : GS.System.CPU.Linux
/// Short Desc : Linux-specific CPU monitoring implementation
/// Aim        : - Per-core CPU usage using /proc/stat
///              - Physical/Logical core detection via /proc/cpuinfo
///              - CPU model and vendor identification
///-------------------------------------------------------------------------------
unit GS.System.CPU.Linux;

{$I GSCore.inc}

interface

{$IFDEF LINUX}

uses
  {$IFDEF FPC}
  SysUtils, Classes,
  {$ELSE}
  System.SysUtils, System.Classes,
  {$ENDIF}
  GS.System.CPU;

type
  /// <summary>
  /// CPU time statistics for a single core
  /// </summary>
  TLinuxCPUCoreTimes = record
    User: UInt64;
    Nice: UInt64;
    System: UInt64;
    Idle: UInt64;
    IOWait: UInt64;
    IRQ: UInt64;
    SoftIRQ: UInt64;
  end;

  /// <summary>
  /// Linux implementation using /proc filesystem
  /// </summary>
  TgsCPUMonitorLinux = class(TgsCPUMonitor)
  private
    FCorePreviousTimes: array of TLinuxCPUCoreTimes;
    FCoreCurrentTimes: array of TLinuxCPUCoreTimes;
    FPhysicalIDs: TStringList;
    
    function ParseProcStat: Boolean;
    function ParseProcCpuInfo: Boolean;
    procedure CalculateCoreUsage(CoreIndex: Integer);
  protected
    procedure DoInitialize; override;
    procedure DoFinalize; override;
    procedure DoUpdate; override;
    function DoGetLogicalCoreCount: Integer; override;
    function DoGetPhysicalCoreCount: Integer; override;
    function DoGetModelName: string; override;
    function DoGetVendorName: string; override;
  public
    destructor Destroy; override;
  end;

{$ENDIF}

implementation

{$IF DEFINED(LINUX) OR DEFINED(ANDROID)}

{ TgsCPUMonitorLinux }

destructor TgsCPUMonitorLinux.Destroy;
begin
  if Assigned(FPhysicalIDs) then
    FreeAndNil(FPhysicalIDs);
  inherited;
end;

procedure TgsCPUMonitorLinux.DoInitialize;
var
  I: Integer;
begin
  FPhysicalIDs := TStringList.Create;
  FPhysicalIDs.Sorted := True;
  FPhysicalIDs.Duplicates := dupIgnore;
  
  // Parse CPU info to get physical IDs
  ParseProcCpuInfo;
  
  // Allocate time tracking arrays
  SetLength(FCorePreviousTimes, LogicalCoreCount);
  SetLength(FCoreCurrentTimes, LogicalCoreCount);
  
  // Initialize core info
  for I := 0 to LogicalCoreCount - 1 do
  begin
    with FCoresInfo[I] do
    begin
      LogicalIndex := I;
      IsOnline := True;
      UsagePercent := 0;
      CurrentFrequencyMHz := 0;
    end;
    FillChar(FCorePreviousTimes[I], SizeOf(TLinuxCPUCoreTimes), 0);
    FillChar(FCoreCurrentTimes[I], SizeOf(TLinuxCPUCoreTimes), 0);
  end;
  
  // Get baseline
  ParseProcStat;
  for I := 0 to LogicalCoreCount - 1 do
    FCorePreviousTimes[I] := FCoreCurrentTimes[I];
  
  FPreviousGlobalTimes := GlobalTimes;
end;

procedure TgsCPUMonitorLinux.DoFinalize;
begin
  SetLength(FCorePreviousTimes, 0);
  SetLength(FCoreCurrentTimes, 0);
  if Assigned(FPhysicalIDs) then
    FreeAndNil(FPhysicalIDs);
end;

procedure TgsCPUMonitorLinux.DoUpdate;
var
  I: Integer;
begin
  FPreviousGlobalTimes := GlobalTimes;
  
  if ParseProcStat then
  begin
    // Calculate usage for each core
    for I := 0 to LogicalCoreCount - 1 do
      CalculateCoreUsage(I);
  end;
end;

function TgsCPUMonitorLinux.DoGetLogicalCoreCount: Integer;
var
  CpuInfo: TStringList;
  Line: string;
begin
  Result := 1; // Default fallback
  
  CpuInfo := TStringList.Create;
  try
    if FileExists('/proc/cpuinfo') then
    begin
      CpuInfo.LoadFromFile('/proc/cpuinfo');
      Result := 0;
      
      for Line in CpuInfo do
      begin
        if (Pos('processor', Line) = 1) and (Pos(':', Line) > 0) then
          Inc(Result);
      end;
      
      if Result = 0 then
        Result := 1;
    end;
  finally
    CpuInfo.Free;
  end;
end;

function TgsCPUMonitorLinux.DoGetPhysicalCoreCount: Integer;
begin
  // FPhysicalIDs is filled by ParseProcCpuInfo
  Result := FPhysicalIDs.Count;
  if Result = 0 then
    Result := DoGetLogicalCoreCount;
end;

function TgsCPUMonitorLinux.DoGetModelName: string;
var
  CpuInfo: TStringList;
  Line: string;
  ColonPos: Integer;
begin
  Result := 'Unknown CPU';
  
  CpuInfo := TStringList.Create;
  try
    if FileExists('/proc/cpuinfo') then
    begin
      CpuInfo.LoadFromFile('/proc/cpuinfo');
      
      for Line in CpuInfo do
      begin
        if Pos('model name', Line) = 1 then
        begin
          ColonPos := Pos(':', Line);
          if ColonPos > 0 then
          begin
            Result := Trim(Copy(Line, ColonPos + 1, Length(Line)));
            Break;
          end;
        end;
      end;
    end;
  finally
    CpuInfo.Free;
  end;
end;

function TgsCPUMonitorLinux.DoGetVendorName: string;
var
  CpuInfo: TStringList;
  Line: string;
  ColonPos: Integer;
begin
  Result := 'Unknown';
  
  CpuInfo := TStringList.Create;
  try
    if FileExists('/proc/cpuinfo') then
    begin
      CpuInfo.LoadFromFile('/proc/cpuinfo');
      
      for Line in CpuInfo do
      begin
        if Pos('vendor_id', Line) = 1 then
        begin
          ColonPos := Pos(':', Line);
          if ColonPos > 0 then
          begin
            Result := Trim(Copy(Line, ColonPos + 1, Length(Line)));
            Break;
          end;
        end;
      end;
    end;
  finally
    CpuInfo.Free;
  end;
end;

function TgsCPUMonitorLinux.ParseProcStat: Boolean;
var
  StatFile: TStringList;
  Line, Token: string;
  Parts: TStringList;
  CoreIndex: Integer;
  I: Integer;
begin
  Result := False;
  
  if not FileExists('/proc/stat') then
    Exit;
  
  StatFile := TStringList.Create;
  Parts := TStringList.Create;
  try
    StatFile.LoadFromFile('/proc/stat');
    Parts.Delimiter := ' ';
    Parts.StrictDelimiter := False;
    
    // Reset global times
    FillChar(GlobalTimes, SizeOf(GlobalTimes), 0);
    
    for Line in StatFile do
    begin
      if Length(Line) = 0 then
        Continue;
      
      // Parse global CPU line (first line: "cpu  ...")
      if Copy(Line, 1, 4) = 'cpu ' then
      begin
        Parts.DelimitedText := Line;
        if Parts.Count >= 5 then
        begin
          GlobalTimes.UserTime := StrToUInt64Def(Parts[1], 0);
          GlobalTimes.NiceTime := StrToUInt64Def(Parts[2], 0);
          GlobalTimes.KernelTime := StrToUInt64Def(Parts[3], 0);
          GlobalTimes.IdleTime := StrToUInt64Def(Parts[4], 0);
          Result := True;
        end;
      end
      // Parse per-core lines (cpu0, cpu1, cpu2, etc.)
      else if (Copy(Line, 1, 3) = 'cpu') and (Line[4] in ['0'..'9']) then
      begin
        Parts.DelimitedText := Line;
        if Parts.Count >= 5 then
        begin
          Token := Parts[0];
          Delete(Token, 1, 3); // Remove "cpu" prefix
          CoreIndex := StrToIntDef(Token, -1);
          
          if (CoreIndex >= 0) and (CoreIndex < LogicalCoreCount) then
          begin
            FCoreCurrentTimes[CoreIndex].User := StrToUInt64Def(Parts[1], 0);
            FCoreCurrentTimes[CoreIndex].Nice := StrToUInt64Def(Parts[2], 0);
            FCoreCurrentTimes[CoreIndex].System := StrToUInt64Def(Parts[3], 0);
            FCoreCurrentTimes[CoreIndex].Idle := StrToUInt64Def(Parts[4], 0);
            
            // Optional fields (may not be present on all systems)
            if Parts.Count > 5 then
              FCoreCurrentTimes[CoreIndex].IOWait := StrToUInt64Def(Parts[5], 0);
            if Parts.Count > 6 then
              FCoreCurrentTimes[CoreIndex].IRQ := StrToUInt64Def(Parts[6], 0);
            if Parts.Count > 7 then
              FCoreCurrentTimes[CoreIndex].SoftIRQ := StrToUInt64Def(Parts[7], 0);
          end;
        end;
      end
      else
        // Stop when we reach non-CPU lines
        Break;
    end;
  finally
    Parts.Free;
    StatFile.Free;
  end;
end;

function TgsCPUMonitorLinux.ParseProcCpuInfo: Boolean;
var
  CpuInfo: TStringList;
  Line: string;
  ColonPos: Integer;
  PhysicalID: string;
begin
  Result := False;
  
  if not FileExists('/proc/cpuinfo') then
    Exit;
  
  CpuInfo := TStringList.Create;
  try
    CpuInfo.LoadFromFile('/proc/cpuinfo');
    FPhysicalIDs.Clear;
    
    for Line in CpuInfo do
    begin
      // Look for physical id
      if Pos('physical id', Line) = 1 then
      begin
        ColonPos := Pos(':', Line);
        if ColonPos > 0 then
        begin
          PhysicalID := Trim(Copy(Line, ColonPos + 1, Length(Line)));
          FPhysicalIDs.Add(PhysicalID);
        end;
      end;
    end;
    
    Result := FPhysicalIDs.Count > 0;
    
    // If no physical IDs found, assume single physical CPU
    if FPhysicalIDs.Count = 0 then
      FPhysicalIDs.Add('0');
  finally
    CpuInfo.Free;
  end;
end;

procedure TgsCPUMonitorLinux.CalculateCoreUsage(CoreIndex: Integer);
var
  PrevTotal, CurrTotal: UInt64;
  PrevIdle, CurrIdle: UInt64;
  DeltaTotal, DeltaIdle: UInt64;
  CoreInfo: TCPUCoreInfo;
begin
  if (CoreIndex < 0) or (CoreIndex >= LogicalCoreCount) then
    Exit;
  
  with FCorePreviousTimes[CoreIndex] do
    PrevTotal := User + Nice + System + Idle + IOWait + IRQ + SoftIRQ;
  PrevIdle := FCorePreviousTimes[CoreIndex].Idle + 
              FCorePreviousTimes[CoreIndex].IOWait;
  
  with FCoreCurrentTimes[CoreIndex] do
    CurrTotal := User + Nice + System + Idle + IOWait + IRQ + SoftIRQ;
  CurrIdle := FCoreCurrentTimes[CoreIndex].Idle + 
              FCoreCurrentTimes[CoreIndex].IOWait;
  
  DeltaTotal := CurrTotal - PrevTotal;
  DeltaIdle := CurrIdle - PrevIdle;
  
  CoreInfo := FCoresInfo[CoreIndex];
  
  if DeltaTotal > 0 then
  begin
    CoreInfo.UsagePercent := ((DeltaTotal - DeltaIdle) * 100.0) / DeltaTotal;
    
    if CoreInfo.UsagePercent < 0 then
      CoreInfo.UsagePercent := 0;
    if CoreInfo.UsagePercent > 100 then
      CoreInfo.UsagePercent := 100;
  end
  else
    CoreInfo.UsagePercent := 0;
  
  FCoresInfo[CoreIndex] := CoreInfo;
  FCorePreviousTimes[CoreIndex] := FCoreCurrentTimes[CoreIndex];
end;

{$ENDIF}

end.
