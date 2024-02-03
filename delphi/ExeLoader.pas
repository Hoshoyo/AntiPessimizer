unit ExeLoader;

//{$DEFINE MEASURE_HOOKING_TIME 1}

interface
uses
  Udis86,
  JclTD32,
  Generics.Collections,
  Windows;

type
  TAnchorBuffer = array [0..63] of Byte;
  PAnchorBuffer = ^TAnchorBuffer;

  TInstrumentedProc = record
    strName  : String;
    procInfo : TJclTD32ProcSymbolInfo;
  end;

  function ProfilerCycleTime: String;
  function  ExeLoaderSendAllModules(pipe : THandle): TDictionary<String, TJclTD32ProcSymbolInfo>;
  procedure InstrumentModuleProcs;
  procedure InstrumentProcs(lstProcs : TList<TInstrumentedProc>);

implementation
uses
  JclPeImage,
  psAPI,
  CoreProfiler,
  JCLDebug,
  RTTI,
  Classes,
  Character,
  SysUtils,
  StrUtils;
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

const
  c_nModuleCodeOffset = $1000;

var
  AddVectoredExceptionHandler : function (nFirst : ULONG; pHandler : Pointer): PVOID; stdcall;
  g_hKernel : THandle;
  g_InfoSourceClassList : TList = nil;
  g_LastHookedJump : PPointer = nil;
{$IFDEF MEASURE_HOOKING_TIME}
  g_StartRdtsc : Uint64;
  g_GlobalHitCount : Integer = 0;
  g_SumHookTime : UInt64;
{$ENDIF}

procedure HookEpilogue;
asm
  .noframe
  push rax
  sub rsp, 40
  //call ExitProfileBlock  // Returns the address where we need to jump back
  call DHExitProfileBlock  // Returns the address where we need to jump back
  add rsp, 40
  mov rcx, rax // Use rcx since rax is the return value

  pop rax
  jmp rcx
end;

procedure HookEpilogueException;
asm
  .noframe
  sub rsp, 40
  //call ExitProfileBlock
  call DHExitProfileBlock
  add rsp, 40
end;

procedure HookJump;
asm
  .noframe
  mov r11, rax

{$IFDEF MEASURE_HOOKING_TIME}
  mov r10, rdx
  rdtsc
  shl rdx, 32
  or rax, rdx
  mov g_StartRdtsc, rax
  mov rdx, r10
{$ENDIF}

  mov rax, qword ptr[rsp+8]
  mov r10, r11
  shl r11, 8
  shr r11, 8
  shr r10, 56

  mov qword ptr[EpilogueJump], rax // save the old return address

  lea rax, HookEpilogue
  mov qword ptr[rsp+8], rax // mov new address as return

  pop rax  // This is where we are called from

  mov g_LastHookedJump, rsp

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
    //call EnterProfileBlock
    call DHEnterProfileBlock
    add rsp, 40

    pop r10
    pop r11
    pop r9
    pop r8
    pop rdx
    pop rcx

{$IFDEF MEASURE_HOOKING_TIME}
  push rdx
  rdtsc
  shl rdx, 32
  or rax, rdx
  mov rdx, r11
  add g_GlobalHitCount, 1
  sub rax, g_StartRdtsc
  add g_SumHookTime, rax
  pop rdx
{$ENDIF}

  jmp r11
end;

function ProfilerCycleTime: String;
begin
{$IFDEF MEASURE_HOOKING_TIME}
  Result := (g_SumHookTime / g_GlobalHitCount).ToString;
{$ENDIF}
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
  pAnchor.ptrExecBuffer := pExecBuffer;
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
      Dispose(pExecBuffer);
      OutputDebugString(PWideChar('Could not instrument function ' + strName + ', reason=' + UdErrorToStr(udErr)));
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
          
          Writeln(Format('Module %s has %d procedures.', [strName, lstProcs.Count]));
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

  {$IFDEF ANTIPESSIMIZER_DELPHI}
  if (dcProcsByModule <> nil) and dcProcsByModule.TryGetValue('AntiPessimizerDelphi', lstProcs) then
  {$ELSE}
  if (dcProcsByModule <> nil) and dcProcsByModule.TryGetValue('GdiExample', lstProcs) then
  {$ENDIF}
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

function ExceptionHandler(ExceptionInfo : PEXCEPTION_POINTERS): LONG; stdcall;
begin
  OutputDebugString('VectoredExceptionHandler!');
  HookEpilogueException;
  g_LastHookedJump^ := EpilogueJump;
  Result := 0;
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
begin
  if not g_bUdisLoaded then
    Exit(nil);

  OutputDebugString('------------------- ExeLoaderSendAllModules ---------------------');

  Module := GetModuleHandle(nil);
  dcProcsByModule := LoadModuleProcDebugInfoForModule(Module, Image);
  GetModuleInformation(GetCurrentProcess, Module, @modInfo, sizeof(modInfo));

  stream := TMemoryStream.Create;
  writer := TBinaryWriter.Create(stream, TEncoding.UTF8);

  Result := TDictionary<String, TJclTD32ProcSymbolInfo>.Create;

  for Item in dcProcsByModule do
    begin
      OutputDebugString(PWidechar(Item.Key + ' Count=' + IntToStr(Item.Value.Count)));
      writer.Write(Item.Key);
      writer.Write(Integer(Item.Value.Count));
      for nIndex := 0 to Item.Value.Count-1 do
        begin
          strName := ProcNameFromSymbolInfo(Image, Item.Value[nIndex]);
          Result.AddOrSetValue(strName, Item.Value[nIndex]);
          writer.Write(strName);
          writer.Write(PeBorUnmangleName(strName));
        end;
    end;

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
    end;
end;

initialization
  LoadVectoredExceptionHandling;

end.
