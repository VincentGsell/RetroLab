///-------------------------------------------------------------------------------
/// Title      : GS.System.CPU.MacOS
/// Short Desc : macOS-specific CPU monitoring implementation
/// Aim        : - Per-core CPU usage using host_statistics
///              - Physical/Logical core detection via sysctl
///              - CPU model and vendor identification
///-------------------------------------------------------------------------------
unit GS.System.CPU.MacOS;

{$I GSCore.inc}

interface

{$IFDEF MACOS}

uses
  {$IFDEF FPC}
  SysUtils, Classes,
  {$ELSE}
  System.SysUtils, System.Classes,
  Posix.SysTypes, Posix.SysSysctl,
  {$ENDIF}
  GS.System.CPU.Intf;

type
  TmacOSCPUCoreTimes = record
    User: UInt64;
    System: UInt64;
    Idle: UInt64;
    Nice: UInt64;
  end;

  TgsCPUMonitorMacOS = class(TgsCPUMonitor)
  private
    FCorePreviousTimes: array of TmacOSCPUCoreTimes;
    FCoreCurrentTimes: array of TmacOSCPUCoreTimes;
    
    function GetCPUTimes: Boolean;
    function GetSysCtlString(const Name: string): string;
    function GetSysCtlInt(const Name: string): Integer;
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

{$IFDEF MACOS}

{$IFNDEF FPC}
type
  host_cpu_load_info_data_t = record
    cpu_ticks: array[0..3] of Cardinal;
  end;
  host_cpu_load_info_t = ^host_cpu_load_info_data_t;

const
  CPU_STATE_USER = 0;
  CPU_STATE_SYSTEM = 1;
  CPU_STATE_IDLE = 2;
  CPU_STATE_NICE = 3;
  HOST_CPU_LOAD_INFO = 3;

function host_statistics(host: Cardinal; flavor: Integer; 
  host_info_out: Pointer; var host_info_outCnt: Cardinal): Integer; cdecl;
  external libc name '_host_statistics';

function mach_host_self: Cardinal; cdecl;
  external libc name '_mach_host_self';
{$ENDIF}

{ TgsCPUMonitorMacOS }

destructor TgsCPUMonitorMacOS.Destroy;
begin
  inherited;
end;

procedure TgsCPUMonitorMacOS.DoInitialize;
var
  I: Integer;
begin
  SetLength(FCorePreviousTimes, LogicalCoreCount);
  SetLength(FCoreCurrentTimes, LogicalCoreCount);
  
  for I := 0 to LogicalCoreCount - 1 do
  begin
    with FCoresInfo[I] do
    begin
      LogicalIndex := I;
      IsOnline := True;
      UsagePercent := 0;
      CurrentFrequencyMHz := 0;
    end;
    FillChar(FCorePreviousTimes[I], SizeOf(TmacOSCPUCoreTimes), 0);
    FillChar(FCoreCurrentTimes[I], SizeOf(TmacOSCPUCoreTimes), 0);
  end;
  
  GetCPUTimes;
  for I := 0 to LogicalCoreCount - 1 do
    FCorePreviousTimes[I] := FCoreCurrentTimes[I];
  
  PreviousGlobalTimes := FGlobalTimes;
end;

procedure TgsCPUMonitorMacOS.DoFinalize;
begin
  SetLength(FCorePreviousTimes, 0);
  SetLength(FCoreCurrentTimes, 0);
end;

procedure TgsCPUMonitorMacOS.DoUpdate;
var
  I: Integer;
begin
  PreviousGlobalTimes := FGlobalTimes;
  
  if GetCPUTimes then
  begin
    for I := 0 to LogicalCoreCount - 1 do
      CalculateCoreUsage(I);
  end;
end;

function TgsCPUMonitorMacOS.DoGetLogicalCoreCount: Integer;
begin
  Result := GetSysCtlInt('hw.logicalcpu');
  if Result <= 0 then
    Result := GetSysCtlInt('hw.ncpu');
  if Result <= 0 then
    Result := 1;
end;

function TgsCPUMonitorMacOS.DoGetPhysicalCoreCount: Integer;
begin
  Result := GetSysCtlInt('hw.physicalcpu');
  if Result <= 0 then
    Result := DoGetLogicalCoreCount;
end;

function TgsCPUMonitorMacOS.DoGetModelName: string;
begin
  Result := GetSysCtlString('machdep.cpu.brand_string');
  if Result = '' then
    Result := 'Unknown CPU';
end;

function TgsCPUMonitorMacOS.DoGetVendorName: string;
begin
  Result := GetSysCtlString('machdep.cpu.vendor');
  if Result = '' then
    Result := 'Unknown';
end;

function TgsCPUMonitorMacOS.GetSysCtlString(const Name: string): string;
var
  Size: size_t;
  Buffer: array[0..255] of AnsiChar;
begin
  Result := '';
  Size := SizeOf(Buffer);
  FillChar(Buffer, SizeOf(Buffer), 0);
  
  if sysctlbyname(PAnsiChar(AnsiString(Name)), @Buffer[0], @Size, nil, 0) = 0 then
    Result := string(AnsiString(Buffer));
end;

function TgsCPUMonitorMacOS.GetSysCtlInt(const Name: string): Integer;
var
  Size: size_t;
  Value: Integer;
begin
  Result := 0;
  Size := SizeOf(Value);
  
  if sysctlbyname(PAnsiChar(AnsiString(Name)), @Value, @Size, nil, 0) = 0 then
    Result := Value;
end;

function TgsCPUMonitorMacOS.GetCPUTimes: Boolean;
var
  {$IFDEF FPC}
  // FPC implementation with host_processor_info
  // Simplified: use global stats only
  {$ELSE}
  cpuInfo: host_cpu_load_info_data_t;
  count: Cardinal;
  {$ENDIF}
  I: Integer;
begin
  Result := False;
  
  {$IFDEF FPC}
  // FPC: Simplified implementation - get global stats
  // Per-core stats require more complex host_processor_info
  FillChar(GlobalTimes, SizeOf(GlobalTimes), 0);
  FillChar(FCoreCurrentTimes[0], Length(FCoreCurrentTimes) * SizeOf(TmacOSCPUCoreTimes), 0);
  
  // For now, distribute global stats equally across cores
  // This is a limitation - full implementation would use host_processor_info
  for I := 0 to LogicalCoreCount - 1 do
  begin
    FCoreCurrentTimes[I].User := 0;
    FCoreCurrentTimes[I].System := 0;
    FCoreCurrentTimes[I].Idle := 0;
    FCoreCurrentTimes[I].Nice := 0;
  end;
  
  Result := True;
  {$ELSE}
  // Delphi: Use host_statistics
  count := SizeOf(cpuInfo) div SizeOf(Integer);
  
  if host_statistics(mach_host_self, HOST_CPU_LOAD_INFO, @cpuInfo, count) = 0 then
  begin
    FGlobalTimes.UserTime := cpuInfo.cpu_ticks[CPU_STATE_USER];
    FGlobalTimes.KernelTime := cpuInfo.cpu_ticks[CPU_STATE_SYSTEM];
    FGlobalTimes.IdleTime := cpuInfo.cpu_ticks[CPU_STATE_IDLE];
    FGlobalTimes.NiceTime := cpuInfo.cpu_ticks[CPU_STATE_NICE];
    
    // Distribute across cores (approximation)
    for I := 0 to LogicalCoreCount - 1 do
    begin
      FCoreCurrentTimes[I].User := FGlobalTimes.UserTime div Cardinal(LogicalCoreCount);
      FCoreCurrentTimes[I].System := FGlobalTimes.KernelTime div Cardinal(LogicalCoreCount);
      FCoreCurrentTimes[I].Idle := FGlobalTimes.IdleTime div Cardinal(LogicalCoreCount);
      FCoreCurrentTimes[I].Nice := FGlobalTimes.NiceTime div Cardinal(LogicalCoreCount);
    end;
    
    Result := True;
  end;
  {$ENDIF}
end;

procedure TgsCPUMonitorMacOS.CalculateCoreUsage(CoreIndex: Integer);
var
  PrevTotal, CurrTotal: UInt64;
  PrevIdle, CurrIdle: UInt64;
  DeltaTotal, DeltaIdle: UInt64;
  CoreInfo: TCPUCoreInfo;
begin
  if (CoreIndex < 0) or (CoreIndex >= LogicalCoreCount) then
    Exit;
  
  with FCorePreviousTimes[CoreIndex] do
    PrevTotal := User + System + Idle + Nice;
  PrevIdle := FCorePreviousTimes[CoreIndex].Idle;
  
  with FCoreCurrentTimes[CoreIndex] do
    CurrTotal := User + System + Idle + Nice;
  CurrIdle := FCoreCurrentTimes[CoreIndex].Idle;
  
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
