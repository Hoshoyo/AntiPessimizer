unit ExeLoader;

interface
uses
  Udis86,
  JclTD32,
  Generics.Collections,
  Windows;

type
  PEXCEPTION_RECORD = ^EXCEPTION_RECORD;
  EXCEPTION_RECORD = record
    ExceptionCode    : DWORD;
    ExceptionFlags   : DWORD;
    ExceptionRecord  : PEXCEPTION_RECORD;
    ExceptionAddress : PVOID;
    NumberParameters : DWORD;
    ExceptionInformation : array [0..EXCEPTION_MAXIMUM_PARAMETERS-1] of ULONG_PTR;
  end;

  EXCEPTION_POINTERS = record
    ExceptionRecord : PEXCEPTION_RECORD;
    ContextRecord   : PCONTEXT;
  end;
  PEXCEPTION_POINTERS = ^EXCEPTION_POINTERS;

{$Z4}
  TCommandType = (ctEnd = 0, ctRequestProcedures = 1, ctInstrumetProcedures = 2, ctProfilingData = 3);
  PCommandType = ^TCommandType;
{$Z1}

  TAnchorBuffer = array [0..63] of Byte;
  PAnchorBuffer = ^TAnchorBuffer;

  TInstrumentedProc = record
    strName  : String;
    procInfo : TJclTD32ProcSymbolInfo;
  end;

  function  ExeLoaderSendAllModules(pipe : THandle): TDictionary<String, TJclTD32ProcSymbolInfo>;
  procedure InstrumentModuleProcs;
  procedure InstrumentProcs(lstProcs : TList<TInstrumentedProc>);
  function  ExceptionHandler(ExceptionInfo : PEXCEPTION_POINTERS): LONG; stdcall;

  procedure PrintDebugStack(ExceptionInfo : PEXCEPTION_POINTERS);
  procedure PrintRegisters(ExceptionInfo : PEXCEPTION_POINTERS);

implementation
uses
  Utils,
  JclPeImage,
  psAPI,
  CoreProfiler,
  JCLDebug,
  RTTI,
  Classes,
  Character,
  SysUtils,
  StrUtils;

const
  c_nModuleCodeOffset = $1000;

var
  AddVectoredExceptionHandler : function (nFirst : ULONG; pHandler : Pointer): PVOID; stdcall;
  RemoveVectoredExceptionHandler : function (pHandler : Pointer): ULONG; stdcall;
  g_hKernel : THandle;
  g_InfoSourceClassList : TList = nil;
  g_LastHookedJump : PPointer = nil;
  RtlCaptureStackBackTrace : function(FramesToSkip, FramesToCapture : DWORD; BackTrace : PVOID; BackTraceHash : Pointer): Word; stdcall;

procedure RemoveHandler;
begin
  RemoveVectoredExceptionHandler(@ExceptionHandler);
end;

procedure HookEpilogue;
asm
  .noframe
  push rax
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11

  sub rsp, 40
  call DHExitProfileBlock  // Returns the address where we need to jump back
  add rsp, 40

  pop r11
  pop r10
  pop r9
  pop r8
  pop rdx
  pop rcx

{$IF False}
  mov rcx, rax
  pop rax
  jmp rcx
{$ELSE}

  push rax // jump target
  mov rax, [rsp+8] // return value
  push rax

  mov rax, [rsp+8] // jump target
  mov [rsp+16], rax

  pop rax // restore the return value
  add rsp, 8
{$ENDIF}

  // return to the jump target
end;

function HookEpilogueException: Pointer;
asm
  .noframe
  sub rsp, 40
  call DHExitProfileBlockException
  add rsp, 40
end;

procedure HookJump;
asm
  .noframe
  mov r11, rax

  mov rax, qword ptr[rsp+8]
  mov r10, r11
  shl r11, 8
  shr r11, 8
  shr r10, 56

  push rcx
  push rdx
  push rbx
  mov rbx, qword ptr gs:[$30]
  lea rcx, [g_ThreadTranslateT]
  xor rdx, rdx
  mov edx, dword ptr [rbx+$48] // ThreadID
  shl rdx, 5 // * sizeof (TThrTranslate)
  add rcx, rdx

  mov qword ptr[rcx], rax     // save the old return address EpilogueJump Address

  lea rdx, [rsp+32]           // save the last hook jump
  mov qword ptr[rcx+8], rdx

  pop rbx
  pop rdx
  pop rcx

  lea rax, HookEpilogue
  mov qword ptr[rsp+8], rax // mov new address as return

  // This is where we are called from this needs to be done, eventhough the call
  // stack appears unaligned, since the HookJump is called via "call"
  pop rax

  //mov g_LastHookedJump, rsp

  // Whatever it needs to be done do it here
    // Naive implementation for now
    push rcx
    push rdx
    push r8
    push r9
    push r11

    mov rcx, rax  // rax is the base address of the function called after executing the first 15 bytes
    sub rcx, 15   // rcx here is the base address of the called function
    add r10, rax  // go back to the position after the buffered execution
    push r10

    sub rsp, 40
    call DHEnterProfileBlock
    add rsp, 40

    pop r10
    pop r11
    pop r9
    pop r8
    pop rdx
    pop rcx

  jmp r11
end;

function ExceptionHandler(ExceptionInfo : PEXCEPTION_POINTERS): LONG; stdcall;
var
  pLastHook : PPointer;
begin
  LogDebug('Exception at %p Thread %d', [ExceptionInfo.ExceptionRecord.ExceptionAddress, GetCurrentThreadID]);
  
  // TODO(psv): Not handle exceptions that are not from the module address space
  //if (Uint64(ExceptionInfo.ExceptionRecord.ExceptionAddress) > $FFFFFFFF) then
  //  Exit(0);

  //PrintRegisters(ExceptionInfo);
  //PrintDebugStack(ExceptionInfo);

  HookEpilogueException;

  Result := 0;
end;

function GetBase(obj: TObject): TJclPeBorTD32Image;
type
  PJclPeBorTD32Image = ^TJclPeBorTD32Image;
var
  ctx : TRTTIContext;
  MemberVarOffset : Integer;
begin
  MemberVarOffset := ctx.GetType(TJclDebugInfoTD32).GetField('FImage').Offset;
  Result := PJclPeBorTD32Image(Pointer(NativeInt(obj) + MemberVarOffset))^;
end;

procedure InstrumentFunction(strName : String; pProcAddr : PByte; nSize : Cardinal; pAnchor : PProfileAnchor);
var
  pExecBuffer : PAnchorBuffer;
  nOldProtect : DWORD;
  nToSave     : Cardinal;
  udErr       : TUdisDisasmError;
begin
  New(pExecBuffer);
  pAnchor.nThreadID := -1;
  pAnchor.strName := strName;

  OutputDebugString(Pwidechar(Format('Instrumenting Execbuffer=%p Function=%s Addr=%p', [pExecBuffer, strName, pProcAddr])));

  VirtualProtect(Pointer(pExecBuffer), sizeof(TAnchorBuffer), PAGE_EXECUTE_READWRITE, nOldProtect);

  udErr := UdisDisasmAtLeastAndPatchRelatives(pProcAddr, nSize, 15, PByte(pExecBuffer), sizeof(TAnchorBuffer), nToSave);
  if udErr = udErrNone then
    begin
      if (nToSave >= 15) and (nToSave <= Cardinal(Length(pExecBuffer^))) then
        begin
          VirtualProtect(Pointer(pProcAddr), nSize, PAGE_EXECUTE_READWRITE, nOldProtect);
          // 15 bytes in total
          // mov rax imm64
          // jmp HookJump
          pProcAddr[0] := $48;
          pProcAddr[1] := $B8;
          PUint64(pProcAddr + 2)^ := Uint64(pExecBuffer);
          pProcAddr[9] := Byte(nToSave - 15);
          pProcAddr[$A] := $E8;
          PCardinal(pProcAddr + $B)^ := Cardinal(Int64(@HookJump) - Int64(pProcAddr + $B + 4));
        end;
    end
  else
    begin
      OutputDebugString(PWideChar('Could not instrument function ' + strName + ', reason=' + UdErrorToStr(udErr)));
      Dispose(pExecBuffer);
    end;
end;

function ProcBinarySearch(Image : TJclPeBorTD32Image; nStart : DWORD): Integer;
var
  nLow  : Integer;
  nHigh : Integer;
  nMid  : Integer;
  procInfo : TJclTD32ProcSymbolInfo;
begin
  Result := -1;
  nLow   := 0;
  nHigh  := Image.TD32Scanner.ProcSymbolCount-1;
  while nLow < nHigh do  
    begin
      nMid := (nHigh + nLow) div 2;
      procInfo := Image.TD32Scanner.ProcSymbols[nMid];
      if procInfo.Offset > nStart then
        nHigh := nMid - 1
      else if procInfo.Offset < nStart then
        begin
          nLow := nMid + 1;
          Result := nMid;
        end
      else
        begin
          Result := nMid;
          Break;
        end;
    end;
end;

function ProcNameFromSymbolInfo(Image : TJclPeBorTD32Image; Symbol : TJclTD32ProcSymbolInfo): String;
begin
  Result := String(Image.TD32Scanner.Names[Symbol.NameIndex]);
end;

function ClassifyProcBySourceModule(Item: TJclDebugInfoSource; moduleBaseAddr : Uint64): TDictionary<String, TList<TJclTD32ProcSymbolInfo>>;
var
  Image        : TJclPeBorTD32Image;
  nIndex       : Integer;
  nSeg         : Integer;
  nSearchStart : Integer;
  nSearchEnd   : Integer;
  nStart       : Integer;
  strName      : String;
  srcModule    : TJclTD32SourceModuleInfo;
  lstProcs     : TList<TJclTD32ProcSymbolInfo>;
  procInfo     : TJclTD32ProcSymbolInfo;
  nProc        : Integer;
begin
  Result := TDictionary<String, TList<TJclTD32ProcSymbolInfo>>.Create;
  
  if Item is TJclDebugInfoTD32 then
    begin
      Image := GetBase(Item);

      For nIndex := 0 to Image.TD32Scanner.SourceModuleCount-1 do
        begin
          srcModule := Image.TD32Scanner.SourceModules[nIndex];
          strName := String(Image.TD32Scanner.Names[srcModule.NameIndex]);
          lstProcs := TList<TJclTD32ProcSymbolInfo>.Create;

          for nSeg := 0 to srcModule.SegmentCount-1 do
            begin
              nSearchStart := srcModule.Segment[nSeg].StartOffset;
              nSearchEnd   := srcModule.Segment[nSeg].EndOffset;

              nStart := ProcBinarySearch(Image, nSearchStart);
              if nStart <> -1 then
                begin
                  for nProc := nStart to Image.TD32Scanner.ProcSymbolCount-1 do
                    begin
                      procInfo := Image.TD32Scanner.ProcSymbols[nProc];
                      if (procInfo.Offset < Cardinal(nSearchEnd)) then
                        lstProcs.Add(procInfo);
                    end;
                end;
            end;
          Result.AddOrSetValue(strName, lstProcs);
          
          Writeln(Format('SourceModule %s has %d procedures.', [strName, lstProcs.Count]));
        end;
    end;
end;

function ClassifyProcByModule(Item: TJclDebugInfoSource; moduleBaseAddr : Uint64): TDictionary<String, TList<TJclTD32ProcSymbolInfo>>;
var
  Image        : TJclPeBorTD32Image;
  nIndex       : Integer;
  nSeg         : Integer;
  nSearchStart : Integer;
  nSearchEnd   : Integer;
  nStart       : Integer;
  strName      : String;
  modInfo      : TJclTD32ModuleInfo;
  lstProcs     : TList<TJclTD32ProcSymbolInfo>;
  procInfo     : TJclTD32ProcSymbolInfo;
  nProc        : Integer;
begin
  Result := TDictionary<String, TList<TJclTD32ProcSymbolInfo>>.Create;
  
  if Item is TJclDebugInfoTD32 then
    begin
      Image := GetBase(Item);
      For nIndex := 0 to Image.TD32Scanner.ModuleCount-1 do
        begin
          modInfo := Image.TD32Scanner.Modules[nIndex];
          strName := String(Image.TD32Scanner.Names[modInfo.NameIndex]);
          lstProcs := TList<TJclTD32ProcSymbolInfo>.Create;

          for nSeg := 0 to modInfo.SegmentCount-1 do
            begin
              nSearchStart := modInfo.Segment[nSeg].Offset;
              nSearchEnd   := modInfo.Segment[nSeg].Offset + modInfo.Segment[nSeg].Size;

              nStart := ProcBinarySearch(Image, nSearchStart);
              if nStart <> -1 then
                begin
                  for nProc := nStart to Image.TD32Scanner.ProcSymbolCount-1 do
                    begin
                      procInfo := Image.TD32Scanner.ProcSymbols[nProc];
                      if (procInfo.Offset < Cardinal(nSearchEnd)) then
                        lstProcs.Add(procInfo);
                    end;
                end;
            end;
          Result.AddOrSetValue(strName, lstProcs);
          
          //Writeln(Format('Module %s has %d procedures.', [strName, lstProcs.Count]));
        end;
    end;
end;

function CreateDebugInfoWithTD32(const Module : HMODULE): TJclDebugInfoSource;
var
  nIndex : Integer;
begin
  if not Assigned(g_InfoSourceClassList) then
    begin
      g_InfoSourceClassList := TList.Create;
      g_InfoSourceClassList.Add(Pointer(TJclDebugInfoTD32));
    end;
  Result := nil;
  for nIndex := 0 to g_InfoSourceClassList.Count-1 do
    begin
      Result := TJclDebugInfoSourceClass(g_InfoSourceClassList.Items[nIndex]).Create(Module);
      try
        if Result.InitializeSource then
          Break
        else
          FreeAndNil(Result);
      except
        Result.Free;
        raise;
      end;
    end;
end;

function LoadModuleProcDebugInfoForModule(Module : HMODULE; var Image : TJclPeBorTD32Image): TDictionary<String, TList<TJclTD32ProcSymbolInfo>>;
var
  Item    : TJclDebugInfoSource;
  modInfo : MODULEINFO;
begin
  Item := CreateDebugInfoWithTD32(Module);

  GetModuleInformation(GetCurrentProcess, Module, @modInfo, sizeof(modInfo));

  if (Item <> nil) and (Item is TJclDebugInfoTD32) then
    begin
      Image := GetBase(Item);
      Result := ClassifyProcByModule(Item, Uint64(modInfo.lpBaseOfDll));
    end
  else
    Result := nil;
end;

procedure InstrumentProcs(lstProcs : TList<TInstrumentedProc>);
var
  pProcAddr : Pointer;
  modInfo   : MODULEINFO;
  strName   : String;
  nLowProc  : Uint64;
  nHighProc : Uint64;
  nSize     : Uint64;
  nLastAddr : Uint64;
  pDhTable  : Pointer;
  nIndex    : Integer;
  ipInfo    : TInstrumentedProc;
  Module    : HMODULE;
begin
  if not g_bUdisLoaded then
    Exit;

  OutputDebugString('------------------- Instrumenting procedures ---------------------');

  Module := GetModuleHandle(nil);
  GetModuleInformation(GetCurrentProcess, Module, @modInfo, sizeof(modInfo));

  // Find lowest and highest address to make the hash table
  nLowProc := $FFFFFFFFFFFFFFFF;
  nHighProc := 0;
  for ipInfo in lstProcs do
    begin
      pProcAddr := PByte(Uint64(modInfo.lpBaseOfDll) + ipInfo.procInfo.Offset + c_nModuleCodeOffset);

      if Uint64(pProcAddr) < nLowProc then
        nLowProc := Uint64(pProcAddr);
      if Uint64(pProcAddr) > nHighProc then
        nHighProc := Uint64(pProcAddr);
    end;

  // After finding it allocate the memory needed
  if (nLowProc <> $FFFFFFFFFFFFFFFF) and (nHighProc <> 0) and (nHighProc > nLowProc) then
    begin
      nSize := nHighProc - nLowProc;
      pDhTable := AllocMem(nSize + 2 * sizeof(TProfileAnchor));
      pDhTable := PByte(pDhTable) + sizeof(TProfileAnchor);
      ZeroMemory(pDhTable, nSize + 2 * sizeof(TProfileAnchor));
      InitializeDHProfilerTable(pDhTable, Int64(pDhTable) - Int64(nLowProc));

      SetLength(g_DHArrProcedures, lstProcs.Count);
      ZeroMemory(@g_DHArrProcedures[0], Length(g_DHArrProcedures) * sizeof(g_DHArrProcedures[0]));

      nLastAddr := $7FFFFFFFFFFFFFFF;
      for nIndex := lstProcs.Count-1 downto 0 do
        begin
          ipInfo := lstProcs[nIndex];
          pProcAddr := PByte(Uint64(modInfo.lpBaseOfDll) + ipInfo.procInfo.Offset + c_nModuleCodeOffset);
          strName := ipInfo.strName;            

          if (nLastAddr - Uint64(pProcAddr)) >= sizeof(TProfileAnchor) then
            begin
              g_DHArrProcedures[nIndex] := pProcAddr;

              OutputDebugString(PWidechar('Instrumenting function ' + strName + '{' + IntToStr(nIndex) + '}'));
              InstrumentFunction(strName, pProcAddr, ipInfo.procInfo.Size, PProfileAnchor(Int64(pDhTable) + Int64(pProcAddr) - Int64(nLowProc)));
            end
          else
            begin
              OutputDebugString(PWidechar('Could not instrument function ' + strName + ' too small ' + Uint64(pProcAddr).ToString + ' ' + nLastAddr.ToString));
            end;

          nLastAddr := UInt64(pProcAddr);
        end;
    end;

  OutputDebugString('End of instrumentation');
end;

procedure InstrumentModuleProcs;
var
  dcProcsByModule : TDictionary<String, TList<TJclTD32ProcSymbolInfo>>;
  lstProcs  : TList<TJclTD32ProcSymbolInfo>;
  Image     : TJclPeBorTD32Image;
  procInfo  : TJclTD32ProcSymbolInfo;
  pProcAddr : Pointer;
  Module    : HMODULE;
  modInfo   : MODULEINFO;
  strName   : String;
  nLowProc  : Uint64;
  nHighProc : Uint64;
  nSize     : Uint64;
  nLastAddr : Uint64;
  pDhTable  : Pointer;
  nIndex    : Integer;
begin
  if not g_bUdisLoaded then
    Exit;

  OutputDebugString('------------------- Instrumenting Module procedures ---------------------');

  Module := GetModuleHandle(nil);
  dcProcsByModule := LoadModuleProcDebugInfoForModule(Module, Image);
  GetModuleInformation(GetCurrentProcess, Module, @modInfo, sizeof(modInfo));

  if (dcProcsByModule <> nil) and dcProcsByModule.TryGetValue('AntiPessimizerDelphi', lstProcs) then
    begin
      // Find lowest and highest address to make the hash table
      nLowProc := $FFFFFFFFFFFFFFFF;
      nHighProc := 0;
      for procInfo in lstProcs do
        begin
          pProcAddr := PByte(Uint64(modInfo.lpBaseOfDll) + procInfo.Offset + c_nModuleCodeOffset);

          if Uint64(pProcAddr) < nLowProc then
            nLowProc := Uint64(pProcAddr);
          if Uint64(pProcAddr) > nHighProc then
            nHighProc := Uint64(pProcAddr);
        end;

      // After finding it allocate the memory needed
      if (nLowProc <> $FFFFFFFFFFFFFFFF) and (nHighProc <> 0) and (nHighProc > nLowProc) then
        begin
          nSize := nHighProc - nLowProc;
          pDhTable := AllocMem(nSize + 2 * sizeof(TProfileAnchor));
          pDhTable := PByte(pDhTable) + sizeof(TProfileAnchor);
          ZeroMemory(pDhTable, nSize + 2 * sizeof(TProfileAnchor));
          InitializeDHProfilerTable(pDhTable, Int64(pDhTable) - Int64(nLowProc));

          SetLength(g_DHArrProcedures, lstProcs.Count);
          ZeroMemory(@g_DHArrProcedures[0], Length(g_DHArrProcedures) * sizeof(g_DHArrProcedures[0]));

          nLastAddr := $7FFFFFFFFFFFFFFF;
          for nIndex := lstProcs.Count-1 downto 0 do
            begin
              procInfo := lstProcs[nIndex];
              pProcAddr := PByte(Uint64(modInfo.lpBaseOfDll) + procInfo.Offset + c_nModuleCodeOffset);
              strName := String(Image.TD32Scanner.Names[procInfo.NameIndex]);

              if (nLastAddr - Uint64(pProcAddr)) >= sizeof(TProfileAnchor) then
                begin
                  g_DHArrProcedures[nIndex] := pProcAddr;

                  OutputDebugString(PWidechar('Instrumenting function ' + strName + '{' + IntToStr(nIndex) + '}'));
                  InstrumentFunction(strName, pProcAddr, procInfo.Size, PProfileAnchor(Int64(pDhTable) + Int64(pProcAddr) - Int64(nLowProc)));
                end
              else
                begin
                  OutputDebugString(PWidechar('Could not instrument function ' + strName + ' too small ' + Uint64(pProcAddr).ToString + ' ' + nLastAddr.ToString));
                end;

              nLastAddr := UInt64(pProcAddr);
            end;
        end;
    end;
  OutputDebugString('End of instrumentation');
end;

procedure PrintRegisters(ExceptionInfo : PEXCEPTION_POINTERS);
begin
  LogDebug('Exception=%x at %p RCX=%x RAX=%x RSP=%x RBP=%x', [ExceptionInfo.ExceptionRecord.ExceptionCode,
    ExceptionInfo.ExceptionRecord.ExceptionAddress,
    ExceptionInfo.ContextRecord.Rcx,
    ExceptionInfo.ContextRecord.Rax,
    ExceptionInfo.ContextRecord.Rsp,
    ExceptionInfo.ContextRecord.Rbp]);
end;

procedure PrintDebugStack(ExceptionInfo : PEXCEPTION_POINTERS);
var
  lstStack : TJclStackInfoList;
  lstStrings : TStringList;
  nIndex : Integer;
  nStackCount : Word;
  BackTrace : array [0..63] of Pointer;
  locInfo : TJclLocationInfo;
begin
  nStackCount := RtlCaptureStackBackTrace(0, 64, @BackTrace[0], nil);
  LogDebug('Stack count=%d', [nStackCount]);

  for nIndex := 0 to nStackCount-1 do
    begin
      locInfo := GetLocationInfo(BackTrace[nIndex]);
      LogDebug('%p %s:%d', [BackTrace[nIndex], locInfo.ProcedureName, locInfo.LineNumber]);
      //LogDebug('%p', [BackTrace[nIndex]]);
    end;
  {
  lstStack := JclCreateStackList(True, 0, nil);

  LogDebug('Stack=%p', [lstStack]);
  LogDebug('Stack size=%d', [lstStack.Count]);
  for nIndex := 0 to lstStack.Count-1 do
    begin
      LogDebug('%x', [lstStack.Items[nIndex].CallerAddr]);
    end;

  lstStrings := TStringList.Create;
  lstStack.AddToStrings(lstStrings, False, False, True);
  LogDebug('2', []);
  LogDebug(' %s', [lstStrings.Text]);
  LogDebug('3', []);
  }

  //ExitProcess(1);
end;

function ExeLoaderSendAllModules(pipe : THandle): TDictionary<String, TJclTD32ProcSymbolInfo>;
var
  dcProcsByModule : TDictionary<String, TList<TJclTD32ProcSymbolInfo>>;
  Image     : TJclPeBorTD32Image;
  Module    : HMODULE;
  modInfo   : MODULEINFO;
  Item      : TPair<String, TList<TJclTD32ProcSymbolInfo>>;
  writer    : TBinaryWriter;
  stream    : TMemoryStream;
  nWritten  : Cardinal;
  nIndex    : Integer;
  strName   : String;
  nStart    : Uint64;
begin
  if not g_bUdisLoaded then
    Exit(nil);

  OutputDebugString('------------------- ExeLoaderSendAllModules ---------------------');

  Module := GetModuleHandle(nil);
  nStart := ReadTimeStamp;

  dcProcsByModule := LoadModuleProcDebugInfoForModule(Module, Image);
  LogDebug('LoadModuleProcDebugInfoForModule elapsed=%f ms', [CyclesToMs(ReadTimeStamp - nStart)]);

  GetModuleInformation(GetCurrentProcess, Module, @modInfo, sizeof(modInfo));

  stream := TMemoryStream.Create;
  writer := TBinaryWriter.Create(stream, TEncoding.UTF8);

  writer.Write(Integer(-1));
  writer.Write(Integer(ctRequestProcedures));

  Result := TDictionary<String, TJclTD32ProcSymbolInfo>.Create;

  for Item in dcProcsByModule do
    begin
      //OutputDebugString(PWidechar(Item.Key + ' Count=' + IntToStr(Item.Value.Count)));
      writer.Write(Item.Key);
      writer.Write(Integer(Item.Value.Count));
      for nIndex := 0 to Item.Value.Count-1 do
        begin
          strName := ProcNameFromSymbolInfo(Image, Item.Value[nIndex]);
          Result.AddOrSetValue(strName, Item.Value[nIndex]);
          writer.Write(strName);
          writer.Write(PeBorUnmangleName(strName));
          writer.Write(Cardinal(Item.Value[nIndex].Offset));
          writer.Write(Cardinal(Item.Value[nIndex].Size));
        end;
    end;

  PCardinal(PByte(stream.Memory))^ := stream.Position - sizeof(Cardinal);

  OutputDebugString(PWidechar('Sending ' + IntToStr(dcProcsByModule.Count) + ' modules ' + IntToStr(stream.Size) + ' bytes written'));

  WriteFile(pipe, PByte(stream.Memory)^, stream.Size, nWritten, nil);

  writer.Free;
  stream.Free;
end;

procedure LoadVectoredExceptionHandling;
begin
  g_hKernel := LoadLibrary('kernel32.dll');
  if g_hKernel <> 0 then
    begin
      @AddVectoredExceptionHandler := GetProcAddress(g_hKernel, 'AddVectoredExceptionHandler');
      if @AddVectoredExceptionHandler <> nil then
        AddVectoredExceptionHandler(1, @ExceptionHandler);
      @RemoveVectoredExceptionHandler := GetProcAddress(g_hKernel, 'RemoveVectoredExceptionHandler');
      @RtlCaptureStackBackTrace := GetProcAddress(g_hKernel, 'RtlCaptureStackBackTrace');
    end;
end;

initialization
  LoadVectoredExceptionHandling;

end.
