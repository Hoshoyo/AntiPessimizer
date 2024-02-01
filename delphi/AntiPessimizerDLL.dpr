library AntiPessimizerDLL;
uses
  Windows,
  System.SysUtils,
  JCLDebug,
  JCLTd32,
  RTTI,
  System.Classes,
  CoreProfiler in 'CoreProfiler.pas',
  ExeLoader in 'ExeLoader.pas',
  Udis86 in 'Udis86.pas';

function GetCurrentDir: String;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  GetCurrentDirectory(MAX_PATH, Buffer);
  Result := String(Buffer);
end;

procedure SendData(hHandle : THandle; pData : Pointer; nSize : Int64; nDataType : Integer = 0);
const
  WM_COPYDATA = $4A;
var
  cpData : COPYDATASTRUCT;
begin
  cpData.dwData := nDataType;
  cpData.cbData := nSize;
  cpData.lpData := pData;
  if SendMessage(hHandle, WM_COPYDATA, 0, LPARAM(@cpData)) = 0 then
    begin
      // Failed
    end;
end;

function Worker(pParam : Pointer): DWORD; stdcall;
var
  pipe : THandle;
  written : Cardinal;
begin
  pipe := CreateFileA('\\.\pipe\AntiPessimizerPipe', GENERIC_READ or GENERIC_WRITE, 0, nil,
    OPEN_EXISTING, 0, 0);
  OutputDebugString(PWidechar('Debug Thread Pipe=' + IntToStr(pipe)));

  if pipe <> INVALID_HANDLE_VALUE then
    begin
      ExeLoaderSendAllModules(pipe);
      OutputDebugString(PWidechar('Debug Thread Written=' + IntToStr(written) + ' Error=' + SysErrorMessage(GetLastError)));
    end;

  while true do
    begin
      OutputDebugString(PWidechar('Debug Thread ' + IntToStr(GetCurrentThreadID)));
      PrintDHProfilerResults;
      Sleep(1000);
    end;
end;

var
  thID : DWORD;
begin
  OutputDebugString(PWidechar('AntiPessimizer started on ' + GetCurrentDir));
  CreateThread(nil, 0, @Worker, nil, 0, thID);

  OutputDebugString(PWidechar('AntiPessimizerStartup ' + IntToStr(thID)));
end.
