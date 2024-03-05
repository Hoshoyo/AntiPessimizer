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
  Udis86 in 'Udis86.pas',
  Utils in 'Utils.pas';

type
  TCommand = record
    stream : TMemoryStream;
    ctType : TCommandType;
  end;

  TDebuggeeState = record
    dicProcsSent : TDictionary<String, TJclTD32ProcSymbolInfo>;
  end;
  PDebuggeeState = ^TDebuggeeState;

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
  sendstream  : TMemoryStream;
  sendwriter  : TBinaryWriter;
  recvstream  : TMemoryStream;
  recvwriter  : TBinaryWriter;
  pipe  : THandle;
  g_PrevDllProc : procedure (Reason: Integer);
  g_RecvCommandBuffer : array [0..64*1024*1024-1] of Byte;
  g_bInstrumentationReady : Boolean = False;

procedure ProcessInstrumentationCommand(cmd : TCommand; state : PDebuggeeState);
var
  reader                  : TBinaryReader;
  nProcCount              : Integer;
  nIndex                  : Integer;
  strProc                 : String;
  lstProcsToInstrument    : TList<String>;
  lstProcToInstrumentInfo : TList<TInstrumentedProc>;
  ipInfo                  : TInstrumentedProc;
  dicProcsSent            : TDictionary<String, TJclTD32ProcSymbolInfo>;
begin
  // TODO(psv): Fail if we already instrumented. Need to reset everything.
  dicProcsSent := state.dicProcsSent;

  // Parse command
  reader := TBinaryReader.Create(cmd.stream, TEncoding.UTF8);
  lstProcsToInstrument := TList<String>.Create;

  nProcCount := reader.ReadInteger;
  for nIndex := 0 to nProcCount-1 do
    begin
      strProc := reader.ReadString;
      lstProcsToInstrument.Add(strProc);
    end;

  OutputDebugString(PWidechar('Finished reading command from pipe ' + IntToStr(nProcCount) + ' procedures.'));
  reader.Free;

  // Process command instrumentation
  lstProcToInstrumentInfo := TList<TInstrumentedProc>.Create;
  for strProc in lstProcsToInstrument do
    begin
      ipInfo.strName := strProc;
      if dicProcsSent.TryGetValue(strProc, ipInfo.procInfo) then
        begin
          lstProcToInstrumentInfo.Add(ipInfo);
          //OutputDebugString(PWidechar('Added procedure ' + ipInfo.strName));
        end;
    end;
  lstProcsToInstrument.Free;
  dicProcsSent.Free;

  InstrumentProcs(lstProcToInstrumentInfo);

  // Say that we are ready to the debugger
  OutputDebugString(PWidechar('AntiPessimizerReady'));
  g_bInstrumentationReady := True;
end;

procedure ProcessSendAllModules(pipe : THandle; state : PDebuggeeState);
begin
  state.dicProcsSent := ExeLoaderSendAllModules(pipe);
end;

function WaitForCommand(pipe : THandle): TCommand;
var
  nRead      : Cardinal;
  nSize      : Cardinal;
  nReadBytes : Cardinal;
  nToRead    : Cardinal;
begin
  //OutputDebugString(PWidechar('Waiting for command in the pipe'));

  if not ReadFile(pipe, nSize, Sizeof(Cardinal), nRead, nil) then
    Sleep(10);
  nToRead := nSize;
  nReadBytes := 0;

  //OutputDebugString(PWidechar('Command received ' + IntToStr(nToRead) + ' bytes'));

  repeat
    ReadFile(pipe, g_RecvCommandBuffer[0], nToRead, nRead, nil);

    //OutputDebugString(PWidechar('Command read ' + IntToStr(nRead) + ' bytes'));

    recvstream.WriteBuffer(g_RecvCommandBuffer[0], nRead);
    nReadBytes := nReadBytes + nRead;
    nToRead := nToRead - nRead;
  until (nReadBytes = nSize);

  //OutputDebugString(PWidechar('Received command ' + IntToStr(nReadBytes) + ' bytes in the pipe'));

  recvstream.Position := Sizeof(TCommandType);
  Result.stream := recvstream;
  Result.ctType := PCommandType(@g_RecvCommandBuffer[0])^;
end;

procedure ProcessSendResults(pipe : THandle; stream : TMemoryStream; writer : TBinaryWriter; bName : Boolean);
var
  nWritten : DWORD;
begin
  if not g_bInstrumentationReady then
    Exit;

  stream.Position := 0;

  writer.Write(Integer(-1));
  if bName then
    writer.Write(Cardinal(ctProfilingData))
  else
    writer.Write(Cardinal(ctProfilingDataNoName));

  ProfilerSerializeResults(stream, writer, bName);

  PCardinal(stream.Memory)^ := stream.Position - Sizeof(Cardinal);

  //LogDebug('Sending Profiling results to pipe %d', [stream.Size]);

  if stream.Size > 0 then
    WriteFile(pipe, PByte(stream.Memory)^, stream.Size, nWritten, nil);
end;

function Worker(pParam : Pointer): DWORD; stdcall;
var
  state  : TDebuggeeState;
  cmd    : TCommand;
begin
  pipe := CreateFileA('\\.\pipe\AntiPessimizerPipe', GENERIC_READ or GENERIC_WRITE, 0, nil,
    OPEN_EXISTING, 0, 0);
  OutputDebugString(PWidechar('AntiPessimizerPipeReady Pipe=' + IntToStr(pipe)));

  sendstream := TMemoryStream.Create;
  sendwriter := TBinaryWriter.Create(sendstream, TEncoding.UTF8);
  recvstream := TMemoryStream.Create;
  recvwriter := TBinaryWriter.Create(recvstream, TEncoding.UTF8);

  if pipe = INVALID_HANDLE_VALUE then
    Exit(1);

  ZeroMemory(@state, sizeof(state));

  try
  repeat
    recvstream.Position := 0;
    cmd := WaitForCommand(pipe);

    //OutputDebugString(PWidechar('Received command of type=' + IntToStr(Integer(cmd.ctType))));
    case cmd.ctType of
      ctRequestProcedures:   ProcessSendAllModules(pipe, @state);
      ctInstrumetProcedures: ProcessInstrumentationCommand(cmd, @state);
      ctProfilingData:       ProcessSendResults(pipe, sendstream, sendwriter, True);
      ctProfilingDataNoName: ProcessSendResults(pipe, sendstream, sendwriter, False);
    end;
  until (cmd.ctType = ctEnd);
  except
    on E: Exception do
      begin
        LogDebug('Worker Exception=%s Stack=%s', [E.Message, E.StackTrace]);
      end;
  end;

  Result := 0;
end;

procedure DLLHandler(Reason: Integer);
begin
  if Reason = DLL_PROCESS_DETACH then
    begin
      ProcessSendResults(pipe, sendstream, sendwriter, True);
    end;
  LogDebug('DLL Event %d', [Reason]);
  if @g_PrevDllProc <> nil then
    g_PrevDllProc(Reason);
end;

var
  thID : DWORD;
begin
  OutputDebugString(PWidechar('AntiPessimizer started on ' + GetCurrentDir));
  @g_PrevDllProc := @DLLProc;
  @DLLProc := @DLLHandler;

  CreateThread(nil, 0, @Worker, nil, 0, thID);
  OutputDebugString(PWidechar('AntiPessimizerStartup ' + IntToStr(thID)));
end.
