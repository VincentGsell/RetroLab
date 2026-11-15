///-------------------------------------------------------------------------------
/// Title      : GS.System.CPU.Intf
/// Short Desc : CPU Usage monitoring interface (cross-platform)
/// Source     : Enhanced version based on VincentGsell work
/// Aim        : - Unified interface for CPU monitoring
///              - Per-core usage tracking
///              - Physical/Logical core detection
///              - Factory pattern for platform-specific implementations
///-------------------------------------------------------------------------------
unit GS.System.CPU;

{$I GSCore.inc}

interface

uses
  {$IFDEF FPC}
  SysUtils, Classes, SyncObjs;
  {$ELSE}
  System.SysUtils, System.Classes, System.SyncObjs;
  {$ENDIF}

type

  /// <summary>
  /// Information about a single CPU core
  /// </summary>
  TCPUCoreInfo = record
    /// <summary>Logical processor index (0-based)</summary>
    LogicalIndex: Integer;
    /// <summary>Current usage percentage (0-100)</summary>
    UsagePercent: Single;
    /// <summary>Current frequency in MHz (0 if not available)</summary>
    CurrentFrequencyMHz: Cardinal;
    /// <summary>Is this core active/online</summary>
    IsOnline: Boolean;
  end;

  /// <summary>
  /// CPU time statistics (in system ticks)
  /// </summary>
  TCPUTimes = record
    IdleTime: UInt64;
    UserTime: UInt64;
    KernelTime: UInt64;
    NiceTime: UInt64;
  end;


  igsCPUMonitor = interface
    function Initialize: Boolean;
    procedure Update;
    function GetGlobalUsagePercent: Single;
    function GetIdlePercent: Single;
    function GetUserPercent: Single;
    function GetKernelPercent: Single;
    function LogicalCoreCount: Integer;
    function PhysicalCoreCount: Integer;
    function ModelName: string;
    function VendorName: string;
    function CoreInfo(Index: Integer) : TCPUCoreInfo;
    function Initialized: Boolean;
    function LastError: string;
  end;

  TgsCPUMonitor = class(TinterfacedObject, igsCPUMonitor)
  private
    FLogicalCoreCount: Integer;
    FPhysicalCoreCount: Integer;
    FModelName: string;
    FVendorName: string;
    FInitialized: Boolean;
    FLastError: string;

    function GetCoreInfo(Index: Integer): TCPUCoreInfo;
  protected
    FCoresInfo: array of TCPUCoreInfo;
    GlobalTimes: TCPUTimes;
    FPreviousGlobalTimes: TCPUTimes;
    
    procedure DoInitialize; virtual; abstract;
    procedure DoFinalize; virtual; abstract;
    procedure DoUpdate; virtual; abstract;
    function DoGetLogicalCoreCount: Integer; virtual; abstract;
    function DoGetPhysicalCoreCount: Integer; virtual; abstract;
    function DoGetModelName: string; virtual; abstract;
    function DoGetVendorName: string; virtual; abstract;
    procedure SetLastError(const AError: string);
  public
    constructor Create; virtual;
    destructor Destroy; override;

    function Initialize: Boolean;
    procedure Update;
    function GetGlobalUsagePercent: Single;
    function GetIdlePercent: Single;
    function GetUserPercent: Single;
    function GetKernelPercent: Single;
    function LogicalCoreCount: Integer;
    function PhysicalCoreCount: Integer;
    function ModelName: string;
    function VendorName: string;
    function CoreInfo(Index: Integer): TCPUCoreInfo;
    function Initialized: Boolean;
    function LastError: string;
  end;

  function CreateCPUMonitor: igsCPUMonitor;

  //GetTickCount funtion
  function gsGetTickCount: UInt64;

implementation

{$IFDEF MSWINDOWS}
uses GS.System.CPU.Windows;
{$ENDIF}

{$IFDEF LINUX}
uses GS.System.CPU.Linux;
{$ENDIF}

{$IFDEF MACOS}
uses GS.System.CPU.MacOS;
{$ENDIF}



{ TgsCPUMonitor }

function TgsCPUMonitor.CoreInfo(Index: Integer): TCPUCoreInfo;
begin
  result := GetCoreInfo(index);
end;

constructor TgsCPUMonitor.Create;
begin
  inherited Create;
  FInitialized := False;
  FLogicalCoreCount := 0;
  FPhysicalCoreCount := 0;
  FModelName := '';
  FVendorName := '';
  FLastError := '';
  FillChar(GlobalTimes, SizeOf(GlobalTimes), 0);
  FillChar(FPreviousGlobalTimes, SizeOf(FPreviousGlobalTimes), 0);
end;

destructor TgsCPUMonitor.Destroy;
begin
  if FInitialized then
    DoFinalize;
  SetLength(FCoresInfo, 0);
  inherited;
end;

function TgsCPUMonitor.Initialize: Boolean;
begin
  Result := False;
  
  try
    FLogicalCoreCount := DoGetLogicalCoreCount;
    FPhysicalCoreCount := DoGetPhysicalCoreCount;
    FModelName := DoGetModelName;
    FVendorName := DoGetVendorName;
    
    SetLength(FCoresInfo, FLogicalCoreCount);
    
    DoInitialize;

    FInitialized := True;
    FLastError := '';
    Result := True;
  except
    on E: Exception do
    begin
      SetLastError('Initialization failed: ' + E.Message);
      FInitialized := False;
    end;
  end;
end;

function TgsCPUMonitor.Initialized: Boolean;
begin
  result := FInitialized;
end;

function TgsCPUMonitor.LastError: string;
begin
  result := FLastError;
end;

function TgsCPUMonitor.LogicalCoreCount: Integer;
begin
  result := FLogicalCoreCount;
end;

function TgsCPUMonitor.ModelName: string;
begin
  result := FModelName;
end;

function TgsCPUMonitor.PhysicalCoreCount: Integer;
begin
  result := FPhysicalCoreCount;
end;

procedure TgsCPUMonitor.Update;
begin
  if not FInitialized then
  begin
    SetLastError('Monitor not initialized. Call Initialize first.');
    Exit;
  end;
  
  try
    DoUpdate;
    FLastError := '';
  except
    on E: Exception do
      SetLastError('Update failed: ' + E.Message);
  end;
end;

function TgsCPUMonitor.VendorName: string;
begin
  result := FVendorName;
end;

function TgsCPUMonitor.GetGlobalUsagePercent: Single;
var
  DeltaTotal, DeltaIdle: UInt64;
begin
  Result := 0.0;
  
  DeltaTotal := (GlobalTimes.UserTime - FPreviousGlobalTimes.UserTime) +
                (GlobalTimes.KernelTime - FPreviousGlobalTimes.KernelTime) +
                (GlobalTimes.NiceTime - FPreviousGlobalTimes.NiceTime) +
                (GlobalTimes.IdleTime - FPreviousGlobalTimes.IdleTime);
                
  if DeltaTotal = 0 then
    Exit;
    
  DeltaIdle := GlobalTimes.IdleTime - FPreviousGlobalTimes.IdleTime;
  
  Result := ((DeltaTotal - DeltaIdle) * 100.0) / DeltaTotal;
  
  if Result < 0 then Result := 0.0;
  if Result > 100 then Result := 100.0;
end;

function TgsCPUMonitor.GetIdlePercent: Single;
var
  DeltaTotal, DeltaIdle: UInt64;
begin
  Result := 0.0;
  
  DeltaTotal := (GlobalTimes.UserTime - FPreviousGlobalTimes.UserTime) +
                (GlobalTimes.KernelTime - FPreviousGlobalTimes.KernelTime) +
                (GlobalTimes.NiceTime - FPreviousGlobalTimes.NiceTime) +
                (GlobalTimes.IdleTime - FPreviousGlobalTimes.IdleTime);

  if DeltaTotal = 0 then
    Exit;

  DeltaIdle := GlobalTimes.IdleTime - FPreviousGlobalTimes.IdleTime;
  Result := (DeltaIdle * 100.0) / DeltaTotal;
end;

function TgsCPUMonitor.GetUserPercent: Single;
var
  DeltaTotal, DeltaUser: UInt64;
begin
  Result := 0.0;

  DeltaTotal := (GlobalTimes.UserTime - FPreviousGlobalTimes.UserTime) +
                (GlobalTimes.KernelTime - FPreviousGlobalTimes.KernelTime) +
                (GlobalTimes.NiceTime - FPreviousGlobalTimes.NiceTime) +
                (GlobalTimes.IdleTime - FPreviousGlobalTimes.IdleTime);

  if DeltaTotal = 0 then
    Exit;
    
  DeltaUser := GlobalTimes.UserTime - FPreviousGlobalTimes.UserTime;
  Result := (DeltaUser * 100.0) / DeltaTotal;
end;

function TgsCPUMonitor.GetKernelPercent: Single;
var
  DeltaTotal, DeltaKernel: UInt64;
begin
  Result := 0.0;
  
  DeltaTotal := (GlobalTimes.UserTime - FPreviousGlobalTimes.UserTime) +
                (GlobalTimes.KernelTime - FPreviousGlobalTimes.KernelTime) +
                (GlobalTimes.NiceTime - FPreviousGlobalTimes.NiceTime) +
                (GlobalTimes.IdleTime - FPreviousGlobalTimes.IdleTime);
                
  if DeltaTotal = 0 then
    Exit;
    
  DeltaKernel := GlobalTimes.KernelTime - FPreviousGlobalTimes.KernelTime;
  Result := (DeltaKernel * 100.0) / DeltaTotal;
end;

function TgsCPUMonitor.GetCoreInfo(Index: Integer): TCPUCoreInfo;
begin
  if (Index >= 0) and (Index < Length(FCoresInfo)) then
    Result := FCoresInfo[Index]
  else
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.LogicalIndex := -1;
  end;
end;

procedure TgsCPUMonitor.SetLastError(const AError: string);
begin
  FLastError := AError;
end;

function CreateCPUMonitor: igsCPUMonitor;
begin
  {$IFDEF MSWINDOWS}
  Result := TgsCPUMonitorWindows.Create;
  {$ELSE}
    {$IFDEF MACOS}
    Result := TgsCPUMonitorMacOS.Create;
    {$ELSE}
      {$IFDEF LINUX}
      Result := TgsCPUMonitorLinux.Create;
      {$ELSE}
      Result := nil;
      {$ENDIF}
    {$ENDIF}
  {$ENDIF}

  if assigned(result) then
    if not(Result.Initialized) then
      result.Initialize;
end;

function gsGetTickCount: UInt64;
begin
  result := TThread.GetTickCount64;
end;

end.
