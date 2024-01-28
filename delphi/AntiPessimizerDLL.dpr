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

function Worker(pParam : Pointer): DWORD; stdcall;
begin
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
  OutputDebugString('AntiPessimizerStartup');
  OutputDebugString(PWidechar('AntiPessimizer started on ' + GetCurrentDir));
  CreateThread(nil, 0, @Worker, nil, 0, thID);
end.
