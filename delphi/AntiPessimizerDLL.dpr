library AntiPessimizerDLL;
uses
  Windows,
  System.SysUtils,
  JCLDebug,
  JCLTd32,
  RTTI,
  Generics.Collections,
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

var
  g_RecvCommandBuffer : array [0..1024*1024-1] of Byte;

function ReadCommandProcedures(stream : TMemoryStream): TList<String>;
var
  reader     : TBinaryReader;
  nProcCount : Integer;
  nIndex     : Integer;
  strProc    : String;
begin
  reader := TBinaryReader.Create(stream, TEncoding.UTF8);
  Result := TList<String>.Create;

  nProcCount := reader.ReadInteger;
  for nIndex := 0 to nProcCount-1 do
    begin
      strProc := reader.ReadString;
      Result.Add(strProc);
      OutputDebugString(PWidechar('Read from pipe proc ' + strProc));
    end;

  OutputDebugString(PWidechar('Finished reading command from pipe'));
  reader.Free;
end;

function WaitForInstrumentationCommand(pipe : THandle): TList<String>;
var
  nRead : Cardinal;
  stream : TMemoryStream;
begin
  stream := TMemoryStream.Create;

  OutputDebugString(PWidechar('Waiting for command in the pipe'));
  if not ReadFile(pipe, g_RecvCommandBuffer[0], Sizeof(g_RecvCommandBuffer), nRead, nil) then
    Sleep(100);

  OutputDebugString(PWidechar('Received command ' + IntToStr(nRead) + ' bytes in the pipe'));

  stream.WriteBuffer(g_RecvCommandBuffer[0], nRead);
  stream.Position := 0;
  Result := ReadCommandProcedures(stream);
  stream.Free;
end;

function Worker(pParam : Pointer): DWORD; stdcall;
var
  pipe : THandle;
  dicProcsSent : TDictionary<String, TJclTD32ProcSymbolInfo>;
  lstProcsToInstrument : TList<String>;
  lstProcToInstrumentInfo : TList<TInstrumentedProc>;
  strProc : String;
  ipInfo : TInstrumentedProc;
begin
  pipe := CreateFileA('\\.\pipe\AntiPessimizerPipe', GENERIC_READ or GENERIC_WRITE, 0, nil,
    OPEN_EXISTING, 0, 0);
  OutputDebugString(PWidechar('Debug Thread Pipe=' + IntToStr(pipe)));

  if pipe = INVALID_HANDLE_VALUE then
    Exit(1);

  dicProcsSent := ExeLoaderSendAllModules(pipe);
  lstProcsToInstrument := WaitForInstrumentationCommand(pipe);
  lstProcToInstrumentInfo := TList<TInstrumentedProc>.Create;
  for strProc in lstProcsToInstrument do
    begin
      ipInfo.strName := strProc;
      if dicProcsSent.TryGetValue(strProc, ipInfo.procInfo) then
        lstProcToInstrumentInfo.Add(ipInfo);
    end;
  lstProcsToInstrument.Free;
  dicProcsSent.Free;

  //InstrumentProcs(lstProcToInstrumentInfo);
  InstrumentModuleProcs;

  OutputDebugString(PWidechar('AntiPessimizerReady'));

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
