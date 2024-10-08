unit ExeLoader;

//{$DEFINE DEBUG_STACK_PRINT}
//{$DEFINE PRINT_INSTRUMENTATION}

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
  TCommandType = (ctEnd = 0, ctRequestProcedures = 1, ctInstrumetProcedures = 2, ctProfilingData = 3, ctProfilingDataNoName = 4, ctClearResults = 5);
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
  procedure PatchProcedure(ptrProcAddr : PByte; ptrNewProcAddr : PByte);
  procedure HookedExceptionHandler;

  procedure PrintDebugStack(ExceptionInfo : PEXCEPTION_POINTERS);
  procedure PrintRegisters(ExceptionInfo : PEXCEPTION_POINTERS);
  procedure PrintDebugFullStack;

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
  push rsi
  push rdi

  sub rsp, 40
  call DHExitProfileBlock  // Returns the address where we need to jump back
  add rsp, 40

  pop rdi
  pop rsi
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

procedure HookJump;
asm
  .noframe
  // TODO(psv): Only setup the return address if we were called from a call

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
    push rsi
    push rdi
    {
    sub rsp, 224
    movdqu [rsp + 0], xmm0
    movdqu [rsp + 16], xmm1
    movdqu [rsp + 32], xmm2
    movdqu [rsp + 48], xmm3
    movdqu [rsp + 64], xmm4
    movdqu [rsp + 80], xmm5
    movdqu [rsp + 96], xmm8
    movdqu [rsp + 112], xmm9  // 128
    movdqu [rsp + 128], xmm10 // 144
    movdqu [rsp + 144], xmm11 // 160
    movdqu [rsp + 160], xmm12 // 176
    movdqu [rsp + 176], xmm13 // 192
    movdqu [rsp + 192], xmm14 // 208
    movdqu [rsp + 208], xmm15 // 224
    }

    mov rcx, rax  // rax is the base address of the function called after executing the first 15 bytes
    sub rcx, 15   // rcx here is the base address of the called function
    add r10, rax  // go back to the position after the buffered execution
    push r10

    {
    push rcx
    sub rsp, 40
    mov rcx, g_AntipessimizerGuiWindow
    mov rdx, 1024
    lea r8, qword ptr [rsp+$60]
    mov r9, qword ptr gs:[$30]
    mov r9d, dword ptr [r9+$48]
    or r9, $200000
    call SendMessage
    add rsp, 40
    pop rcx    
    }

    sub rsp, 40
    call DHEnterProfileBlock
    add rsp, 40

    pop r10
    
    {
    movdqu [rsp + 0], xmm0
    movdqu [rsp + 16], xmm1
    movdqu [rsp + 32], xmm2
    movdqu [rsp + 48], xmm3
    movdqu [rsp + 64], xmm4
    movdqu [rsp + 80], xmm5
    movdqu [rsp + 96], xmm8
    movdqu [rsp + 112], xmm9  // 128
    movdqu [rsp + 128], xmm10 // 144
    movdqu [rsp + 144], xmm11 // 160
    movdqu [rsp + 160], xmm12 // 176
    movdqu [rsp + 176], xmm13 // 192
    movdqu [rsp + 192], xmm14 // 208
    movdqu [rsp + 208], xmm15 // 224
    add rsp, 224        
    }
    pop rdi    
    pop rsi
    pop r11
    pop r9
    pop r8
    pop rdx
    pop rcx

  jmp r11
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

function InstrumentFunction(strName : String; nLine : Integer; pProcAddr : PByte; nSize : Cardinal; pAnchor : PProfileAnchor): Boolean;
var
  pExecBuffer : PAnchorBuffer;
  nOldProtect : DWORD;
  nToSave     : Cardinal;
  udErr       : TUdisDisasmError;
begin
  Result := False;
  New(pExecBuffer);

  // Use this to test relative moves within the first 15 bytes,
  // this guarantees the allocation will be in the first 4GB
  // of the addressable range.
  {
  if g_pMem = nil then
    begin
      g_pMem := VirtualAlloc(Pointer($70000000), 1024 * 1024, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
    end;
  pExecBuffer := g_pMem;
  g_pMem := PByte(g_pMem) + sizeof(TAnchorBuffer);
  }

{$IFDEF PRINT_INSTRUMENTATION}
  OutputDebugString(Pwidechar(Format('Instrumenting Execbuffer=%p Function=%s Addr=%p Anchor=%p', [pExecBuffer, strName, pProcAddr, pAnchor])));
{$ENDIF}

  VirtualProtect(Pointer(pExecBuffer), sizeof(TAnchorBuffer), PAGE_EXECUTE_READWRITE, nOldProtect);

  udErr := UdisDisasmAtLeastAndPatchRelatives(pProcAddr, nSize, 15, PByte(pExecBuffer), sizeof(TAnchorBuffer), nToSave);
  if udErr = udErrNone then
    begin
      if (nToSave >= 15) and (nToSave <= Cardinal(Length(pExecBuffer^))) then
        begin
          udErr := UdisCheckJumpback(PByte(pProcAddr) + nToSave, nSize - nToSave);
          if udErr <> udErrNone then
            begin
              LogDebug('UdisCheckJumpback: Could not instrument function %s, reason: %s', [strName, UdErrorToStr(udErr)]);
              Exit;
            end;

          // These have to be here, since if there is no space, we can't write
          // this fields in the anchor.
          pAnchor.nThreadID := -1;
          pAnchor.strName := strName;
          pAnchor.pAddr := pProcAddr;
          pAnchor.nLine := nLine;

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
          Result := True;
        end;
    end
  else
    begin
    {$IFDEF PRINT_INSTRUMENTATION}
      OutputDebugString(PWideChar('InstrumentFunction: Could not instrument function ' + strName + ', reason=' + UdErrorToStr(udErr)));
    {$ENDIF}
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
  nHigh := Image.TD32Scanner.ProcSymbolCount-1;

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
  nTimeStart   : UInt64;
  nElapsed     : UInt64;
  nProcCount   : Int64;
  pProcAddr    : Pointer;
  bFoundExceptionHandler : Boolean;
begin
  Result := TDictionary<String, TList<TJclTD32ProcSymbolInfo>>.Create;
  nTimeStart := ReadTimeStamp;
  nProcCount := 0;
  bFoundExceptionHandler := False;
  nElapsed := 0;

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

              //if nStart > 0 then
                nStart := ProcBinarySearch(Image, nSearchStart);

              if nStart <> -1 then
                begin
                  for nProc := nStart to Image.TD32Scanner.ProcSymbolCount-1 do
                    begin
                      procInfo := Image.TD32Scanner.ProcSymbols[nProc];
                      if (procInfo.Offset < Cardinal(nSearchEnd)) then
                        begin
                          lstProcs.Add(procInfo);

                          if not bFoundExceptionHandler then
                            begin
                              strName := Image.TD32Scanner.Names[procInfo.NameIndex];
                              if strName.StartsWith('_ZN6System23_DelphiExceptionHandler') then // '_ZN6System23_DelphiExceptionHandlerEPNS_16TExceptionRecordEyPvS2_' then
                                begin
                                  bFoundExceptionHandler := True;
                                  pProcAddr := PByte(moduleBaseAddr + procInfo.Offset + c_nModuleCodeOffset);
                                  LogDebug('ClassifyProcByModule: Found exception handler at address %p', [pProcAddr]);
                                  PatchProcedure(pProcAddr, @HookedExceptionHandler);
                                end;                          
                            end;
                        end
                      else
                        Break;
                    end;
                end;
            end;

          Result.AddOrSetValue(strName, lstProcs);
          Inc(nProcCount, lstProcs.Count);
        end;
      nElapsed := nElapsed + (ReadTimeStamp - nTimeStart);
      LogDebug('ClassifyProcByModule elapsed: %f ms ProcedureCount=%d ModuleCount=%d', [CyclesToMs(Int64(nElapsed)), nProcCount, Image.TD32Scanner.ModuleCount]);
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
  Result := nil;
  Item := CreateDebugInfoWithTD32(Module);

  GetModuleInformation(GetCurrentProcess, Module, @modInfo, sizeof(modInfo));

  try
  if (Item <> nil) and (Item is TJclDebugInfoTD32) then
    begin
      Image := GetBase(Item);
      Result := ClassifyProcByModule(Item, Uint64(modInfo.lpBaseOfDll));
    end
  else
    Result := nil;
  except
    on E: Exception do
      LogDebug('LoadModuleProcDebugInfoForModule Exception=%s', [E.Message]);
  end;
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

  LogDebug('------------------- Instrumenting procedures --------------------- %d', [lstProcs.Count]);

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
  LogDebug('LowAddr=%x HighAddr=%x', [nLowProc, nHighProc]);
  if (nLowProc <> $FFFFFFFFFFFFFFFF) and (nHighProc <> 0) and (nHighProc > nLowProc) then
    begin
      nSize := nHighProc - nLowProc;
      pDhTable := AllocMem(nSize + 2 * sizeof(TProfileAnchor));
      ZeroMemory(pDhTable, nSize + 2 * sizeof(TProfileAnchor));
      pDhTable := PByte(pDhTable) + sizeof(TProfileAnchor);

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
              if not InstrumentFunction(strName, 0, pProcAddr, ipInfo.procInfo.Size, PProfileAnchor(Int64(pDhTable) + Int64(pProcAddr) - Int64(nLowProc))) then
                g_DHArrProcedures[nIndex] := nil;
            end
          else
            begin
              //OutputDebugString(PWidechar('Could not instrument function ' + strName + ' too small ' + Uint64(pProcAddr).ToString + ' ' + nLastAddr.ToString));
            end;

          nLastAddr := UInt64(pProcAddr);
        end;
    end;

  OutputDebugString('End of instrumentation');
end;

procedure HookedExceptionHandler;
asm
.noframe
  mov r11, rax
  shl r11, 8
  shr r11, 8
  shr rax, 56
  mov r10, qword ptr[rsp]
  add r10, rax
  add rsp, 8

  // Do here whatever needs to be done to unwind stuff

    push rsp
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    sub rsp, 40
    lea rcx, HookEpilogue
    call DHUnwindExceptionBlock  // Returns the address where we need to jump back
    add rsp, 40

    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rsp

  jmp r11
end;

procedure PatchProcedure(ptrProcAddr : PByte; ptrNewProcAddr : PByte);
type
  TBuffer = array [0..32] of Byte;
  PBuffer = ^TBuffer;
var
  pBuf : PBuffer;
  nBytesDisassembled : Cardinal;
  nOldProtect : DWORD;
begin
  New(pBuf);
  VirtualProtect(Pointer(pBuf), sizeof(TBuffer), PAGE_EXECUTE_READWRITE, nOldProtect);

  if UdisDisasmAtLeastAndPatchRelatives(ptrProcAddr, sizeof(TBuffer), 15, PByte(pBuf), sizeof(TBuffer), nBytesDisassembled) = udErrNone then
    begin
      LogDebug('PatchingProcedure %p to %p', [ptrProcAddr, ptrNewProcAddr]);

      VirtualProtect(Pointer(ptrProcAddr), nBytesDisassembled, PAGE_EXECUTE_READWRITE, nOldProtect);
      // 15 bytes in total
      // mov rax imm64
      // jmp ptrNewProcAddr
      ptrProcAddr[0] := $48;
      ptrProcAddr[1] := $B8;
      PUint64(ptrProcAddr + 2)^ := Uint64(pBuf);
      ptrProcAddr[9] := Byte(nBytesDisassembled - 15);
      ptrProcAddr[$A] := $E8;
      PCardinal(ptrProcAddr + $B)^ := Cardinal(Int64(ptrNewProcAddr) - Int64(ptrProcAddr + $B + 4));
    end
  else
    LogDebug('Fail to Patch procedure',[]);
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

              if not strName.StartsWith('_ZN20Antipessimizerdelphi') then
                Continue;

              if (nLastAddr - Uint64(pProcAddr)) >= sizeof(TProfileAnchor) then
                begin
                  g_DHArrProcedures[nIndex] := pProcAddr;

                  OutputDebugString(PWidechar('Instrumenting function ' + strName + '{' + IntToStr(nIndex) + '}'));
                  if not InstrumentFunction(strName, 0, pProcAddr, procInfo.Size, PProfileAnchor(Int64(pDhTable) + Int64(pProcAddr) - Int64(nLowProc))) then
                    g_DHArrProcedures[nIndex] := nil;
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
  nIndex : Integer;
  nStackCount : Word;
  BackTrace : array [0..128] of Pointer;
  locInfo : TJclLocationInfo;
begin
  nStackCount := RtlCaptureStackBackTrace(0, 128, @BackTrace[0], nil);
  LogDebug('Stack count=%d', [nStackCount]);

  for nIndex := 0 to nStackCount-1 do
    begin
      locInfo := GetLocationInfo(BackTrace[nIndex]);
      LogDebug('[%d] %p %s:%d', [nIndex, BackTrace[nIndex], locInfo.ProcedureName, locInfo.LineNumber]);
      //LogDebug('%p', [BackTrace[nIndex]]);
    end;
  LogDebug('=== Finished dumping stack === ', []);
end;

procedure PrintDebugFullStack;
var
  nIndex : Integer;
  nStackCount : Word;
  BackTrace : array [0..63] of Pointer;
  locInfo : TJclLocationInfo;
begin
  //JclLastExceptionStack
  nStackCount := RtlCaptureStackBackTrace(0, 64, @BackTrace[0], nil);
  LogDebug('Stack count=%d', [nStackCount]);

  for nIndex := 0 to nStackCount-1 do
    begin
      locInfo := GetLocationInfo(BackTrace[nIndex]);
      LogDebug('%p %s:%d', [BackTrace[nIndex], locInfo.ProcedureName, locInfo.LineNumber]);
    end;
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

function ExceptionHandler(ExceptionInfo : PEXCEPTION_POINTERS): LONG; stdcall;
begin
  DHUnwindEveryStack;

  Result := 0;
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
