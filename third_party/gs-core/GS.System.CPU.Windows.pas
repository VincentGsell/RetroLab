//-------------------------------------------------------------------------------
/// Title      : GS.System.CPU.Windows
/// Short Desc : Windows-specific CPU monitoring implementation
/// Aim        : - Per-core CPU usage using Performance Counters (PDH)
///              - Physical/Logical core detection
///              - CPU model and vendor identification
///-------------------------------------------------------------------------------
unit GS.System.CPU.Windows;

{$I GSCore.inc}

interface

{$IFDEF MSWINDOWS}

uses
  {$IFDEF FPC}
  SysUtils, Classes, Windows,
  {$ELSE}
  System.SysUtils, System.Classes, WinApi.Windows,
  {$ENDIF}
  GS.System.CPU;

type
  /// <summary>
  /// Windows implementation using Performance Data Helper (PDH)
  /// </summary>
  TgsCPUMonitorWindows = class(TgsCPUMonitor)
  private
    FPdhQueryHandle: THandle;
    FPdhCounterHandles: array of THandle;
    FCorePreviousTimes: array of TCPUTimes;

    function InitializePDH: Boolean;
    procedure UpdatePDH;
    procedure UpdateGlobalTimes;
    function GetCPUInfoFromRegistry: Boolean;
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

{$IFDEF MSWINDOWS}

uses
  {$IFDEF FPC}
  Registry;
  {$ELSE}
  System.Win.Registry;
  {$ENDIF}

const
  // PDH API constants
  PDH_FMT_DOUBLE = $00000200;
  ERROR_SUCCESS = 0;

type
  // PDH structures
  PDH_HQUERY = THandle;
  PDH_HCOUNTER = THandle;
  PDH_STATUS = DWORD;

  PDH_FMT_COUNTERVALUE = record
    CStatus: DWORD;
    case Integer of
      0: (longValue: LONG);
      1: (doubleValue: Double);
      2: (largeValue: Int64);
      3: (AnsiStringValue: PAnsiChar);
      4: (WideStringValue: PWideChar);
  end;

  SYSTEM_LOGICAL_PROCESSOR_INFORMATION = record
    ProcessorMask: ULONG_PTR;
    Relationship: DWORD;
    case Integer of
      0: (Flags: BYTE);
      1: (NodeNumber: DWORD);
      2: (Reserved: array[0..1] of ULONGLONG);
  end;
  PSYSTEM_LOGICAL_PROCESSOR_INFORMATION = ^SYSTEM_LOGICAL_PROCESSOR_INFORMATION;

const
  RelationProcessorCore = 0;
  RelationNumaNode = 1;
  RelationCache = 2;
  RelationProcessorPackage = 3;

// PDH API functions
function PdhOpenQueryW(szDataSource: PWideChar; dwUserData: DWORD_PTR;
  var phQuery: PDH_HQUERY): PDH_STATUS; stdcall; external 'pdh.dll';

function PdhAddCounterW(hQuery: PDH_HQUERY; szFullCounterPath: PWideChar;
  dwUserData: DWORD_PTR; var phCounter: PDH_HCOUNTER): PDH_STATUS; stdcall;
  external 'pdh.dll';

function PdhCollectQueryData(hQuery: PDH_HQUERY): PDH_STATUS; stdcall;
  external 'pdh.dll';

function PdhGetFormattedCounterValue(hCounter: PDH_HCOUNTER; dwFormat: DWORD;
  lpdwType: PDWORD; pValue: Pointer): PDH_STATUS; stdcall;
  external 'pdh.dll';

function PdhCloseQuery(hQuery: PDH_HQUERY): PDH_STATUS; stdcall;
  external 'pdh.dll';

function GetLogicalProcessorInformation(
  Buffer: PSYSTEM_LOGICAL_PROCESSOR_INFORMATION;
  var ReturnLength: DWORD): BOOL; stdcall; external kernel32
  name 'GetLogicalProcessorInformation';

function GetSystemTimes(var lpIdleTime, lpKernelTime, lpUserTime: TFileTime): BOOL;
  stdcall; external kernel32 name 'GetSystemTimes';

{ TgsCPUMonitorWindows }

destructor TgsCPUMonitorWindows.Destroy;
begin
  if FPdhQueryHandle <> 0 then
    DoFinalize;
  inherited;
end;

procedure TgsCPUMonitorWindows.DoInitialize;
var
  I: Integer;
begin
  FPdhQueryHandle := 0;

  // Initialize performance counters
  if not InitializePDH then
    raise Exception.Create('Failed to initialize Performance Counters');

  // Allocate previous times for per-core tracking
  SetLength(FCorePreviousTimes, LogicalCoreCount);
  for I := 0 to LogicalCoreCount - 1 do
  begin
    FillChar(FCorePreviousTimes[I], SizeOf(TCPUTimes), 0);

    with FCoresInfo[I] do
    begin
      LogicalIndex := I;
      IsOnline := True;
      UsagePercent := 0;
      CurrentFrequencyMHz := 0;
    end;
  end;

  // Get baseline
  UpdateGlobalTimes;

  // First PDH collection (baseline)
  PdhCollectQueryData(FPdhQueryHandle);
  Sleep(100); // Small delay for initial measurement
end;

procedure TgsCPUMonitorWindows.DoFinalize;
var
  I: Integer;
begin
  // Close PDH counters
  for I := 0 to High(FPdhCounterHandles) do
    ; // Counters are automatically closed with the query

  if FPdhQueryHandle <> 0 then
  begin
    PdhCloseQuery(FPdhQueryHandle);
    FPdhQueryHandle := 0;
  end;

  SetLength(FPdhCounterHandles, 0);
  SetLength(FCorePreviousTimes, 0);
end;

procedure TgsCPUMonitorWindows.DoUpdate;
begin
  UpdateGlobalTimes;
  UpdatePDH;
end;

function TgsCPUMonitorWindows.DoGetLogicalCoreCount: Integer;
begin
  {$IFDEF FPC}
  Result := GetCPUCount;
  {$ELSE}
  Result := TThread.ProcessorCount;
  {$ENDIF}
end;

function TgsCPUMonitorWindows.DoGetPhysicalCoreCount: Integer;
var
  Buffer: array[0..4095] of Byte;
  ReturnLength: DWORD;
  Info: PSYSTEM_LOGICAL_PROCESSOR_INFORMATION;
  Offset: Integer;
begin
  Result := 0;
  ReturnLength := SizeOf(Buffer);

  if GetLogicalProcessorInformation(@Buffer[0], ReturnLength) or
     (GetLastError = ERROR_INSUFFICIENT_BUFFER) then
  begin
    if not GetLogicalProcessorInformation(@Buffer[0], ReturnLength) then
      Exit(DoGetLogicalCoreCount); // Fallback to logical count

    Offset := 0;
    while Offset < Integer(ReturnLength) do
    begin
      Info := PSYSTEM_LOGICAL_PROCESSOR_INFORMATION(@Buffer[Offset]);
      if Info.Relationship = RelationProcessorCore then
        Inc(Result);
      Inc(Offset, SizeOf(SYSTEM_LOGICAL_PROCESSOR_INFORMATION));
    end;
  end;

  if Result = 0 then
    Result := DoGetLogicalCoreCount;
end;

function TgsCPUMonitorWindows.DoGetModelName: string;
var
  Reg: TRegistry;
begin
  Result := 'Unknown CPU';

  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('HARDWARE\DESCRIPTION\System\CentralProcessor\0') then
    begin
      if Reg.ValueExists('ProcessorNameString') then
        Result := Trim(Reg.ReadString('ProcessorNameString'));
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

function TgsCPUMonitorWindows.DoGetVendorName: string;
var
  Reg: TRegistry;
begin
  Result := 'Unknown';

  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('HARDWARE\DESCRIPTION\System\CentralProcessor\0') then
    begin
      if Reg.ValueExists('VendorIdentifier') then
        Result := Reg.ReadString('VendorIdentifier');
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

function TgsCPUMonitorWindows.InitializePDH: Boolean;
var
  Status: PDH_STATUS;
  CounterPath: string;
  I: Integer;
  UseNumericIndexes: Boolean;
begin
  Result := False;

  // Open PDH query
  Status := PdhOpenQueryW(nil, 0, FPdhQueryHandle);
  if Status <> ERROR_SUCCESS then
  begin
    SetLastError(Format('PdhOpenQuery failed with status: 0x%x', [Status]));
    Exit;
  end;

  // Add counters for each logical processor
  SetLength(FPdhCounterHandles, LogicalCoreCount);

  // Try numeric indexes first (language-independent)
  UseNumericIndexes := True;

  for I := 0 to LogicalCoreCount - 1 do
  begin
    if UseNumericIndexes then
      CounterPath := Format('\238(%d)\6', [I])
    else
      CounterPath := Format('\Processor(%d)\%% Processor Time', [I]);

    Status := PdhAddCounterW(FPdhQueryHandle, PWideChar(CounterPath), 0,
                             FPdhCounterHandles[I]);

    if Status <> ERROR_SUCCESS then
    begin
      // If first counter fails with numeric indexes, try English names
      if (I = 0) and UseNumericIndexes then
      begin
        UseNumericIndexes := False;
        CounterPath := Format('\Processor(%d)\%% Processor Time', [I]);
        Status := PdhAddCounterW(FPdhQueryHandle, PWideChar(CounterPath), 0,
                                 FPdhCounterHandles[I]);
      end;

      if Status <> ERROR_SUCCESS then
      begin
        SetLastError(Format('PdhAddCounter failed for core %d (path: %s) with status: 0x%x',
                           [I, CounterPath, Status]));
        PdhCloseQuery(FPdhQueryHandle);
        FPdhQueryHandle := 0;
        Exit;
      end;
    end;
  end;

  Result := True;
end;

procedure TgsCPUMonitorWindows.UpdatePDH;
var
  Status: PDH_STATUS;
  CounterValue: PDH_FMT_COUNTERVALUE;
  I: Integer;
  CoreInfo: TCPUCoreInfo;
begin
  Status := PdhCollectQueryData(FPdhQueryHandle);
  if Status <> ERROR_SUCCESS then
    Exit;

  for I := 0 to LogicalCoreCount - 1 do
  begin
    Status := PdhGetFormattedCounterValue(FPdhCounterHandles[I],
                                          PDH_FMT_DOUBLE, nil, @CounterValue);
    if Status = ERROR_SUCCESS then
    begin
      CoreInfo := FCoresInfo[I];
      CoreInfo.UsagePercent := CounterValue.doubleValue;

      if CoreInfo.UsagePercent < 0 then
        CoreInfo.UsagePercent := 0;
      if CoreInfo.UsagePercent > 100 then
        CoreInfo.UsagePercent := 100;

      FCoresInfo[I] := CoreInfo;
    end;
  end;
end;

procedure TgsCPUMonitorWindows.UpdateGlobalTimes;
var
  IdleTime, KernelTime, UserTime: TFileTime;
begin
  if GetSystemTimes(IdleTime, KernelTime, UserTime) then
  begin
    GlobalTimes.IdleTime := UInt64(IdleTime.dwHighDateTime) shl 32 or
                            IdleTime.dwLowDateTime;
    GlobalTimes.UserTime := UInt64(UserTime.dwHighDateTime) shl 32 or
                            UserTime.dwLowDateTime;
    // Note: Windows KernelTime includes IdleTime
    GlobalTimes.KernelTime := (UInt64(KernelTime.dwHighDateTime) shl 32 or
                               KernelTime.dwLowDateTime) - GlobalTimes.IdleTime;
    GlobalTimes.NiceTime := 0; // Not available on Windows
  end;
end;

function TgsCPUMonitorWindows.GetCPUInfoFromRegistry: Boolean;
begin
  Result := True;
  // ModelName and VendorName are already loaded in DoGetModelName/DoGetVendorName
end;

{$ENDIF}

end.
