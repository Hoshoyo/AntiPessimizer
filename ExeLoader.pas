unit ExeLoader;

//{$DEFINE MEASURE_HOOKING_TIME 1}

interface
uses
  Udis86,
  Generics.Collections,
  Windows;

type
  TAnchorBuffer = array [0..63] of Byte;
  PAnchorBuffer = ^TAnchorBuffer;
  TAnchor = record
    nStart      : Int64;
    nElapsed    : Int64;
    nHitCount   : Int64;
    strName     : String;
    pExecBuffer : PAnchorBuffer;
  end;

  function ProfilerCycleTime: String;

implementation
uses
  psAPI,
  CoreProfiler,
  JclTD32,
  JCLDebug,
  RTTI,
  Classes,
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
  g_StartRdtsc : Uint64;
  g_GlobalHitCount : Integer = 0;
  g_SumHookTime : UInt64;

procedure HookEpilogue;
asm
  .noframe
  push rax
  sub rsp, 32
  //call ExitProfileBlock  // Returns the address where we need to jump back
  call DHExitProfileBlock  // Returns the address where we need to jump back
  add rsp, 32
  mov rcx, rax // Use rcx since rax is the return value

  pop rax
  jmp rcx
end;

procedure HookEpilogueException;
asm
  .noframe
  sub rsp, 32
  //call ExitProfileBlock
  call DHExitProfileBlock
  add rsp, 32
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

    sub rsp, 32
    //call EnterProfileBlock
    call DHEnterProfileBlock
    add rsp, 32

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
begin
  New(pExecBuffer);
  pAnchor.ptrExecBuffer := pExecBuffer;
  pAnchor.strName := strName;

  VirtualProtect(Pointer(pExecBuffer), sizeof(TAnchorBuffer), PAGE_EXECUTE_READWRITE, nOldProtect);

  nToSave := UdisDisasmAtLeastAndPatchRelatives(pProcAddr, nSize, 15, PByte(pExecBuffer), sizeof(TAnchorBuffer));

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

function ClassifyProcBySourceModule(Item: TJclDebugInfoSource; moduleBaseAddr : Uint64): TDictionary<String, TList<TJclTD32ProcSymbolInfo>>;
var
  Image        : TJclPeBorTD32Image;
  nIndex       : Integer;
  nSeg         : Integer;
  nSearchStart : Integer;
  nSearchEnd   : Integer;
  nStart       : Integer;
  strName      : String;
  strProc      : String;
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
          strName := Image.TD32Scanner.Names[srcModule.NameIndex];
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
                      if (procInfo.Offset < nSearchEnd) then                   
                        lstProcs.Add(procInfo);
                    end;
                end;
            end;
          Result.AddOrSetValue(strName, lstProcs);
          
          Writeln(Format('SourceModule %s has %d procedures.', [strName, lstProcs.Count]));
          {if lstProcs.Count < 10 then
            begin
              for nProc := 0 to lstProcs.Count-1 do
                begin
                  strProc := Image.TD32Scanner.Names[lstProcs[nProc].NameIndex];
                  Writeln('  Procedure=' + strProc);
                end;
            end;
          }
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
  strProc      : String;
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
          strName := Image.TD32Scanner.Names[modInfo.NameIndex];
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
                      if (procInfo.Offset < nSearchEnd) then                   
                        lstProcs.Add(procInfo);
                    end;
                end;
            end;
          Result.AddOrSetValue(strName, lstProcs);
          
          Writeln(Format('Module %s has %d procedures.', [strName, lstProcs.Count]));
          {
          if lstProcs.Count < 10 then
            begin
              for nProc := 0 to lstProcs.Count-1 do
                begin
                  strProc := Image.TD32Scanner.Names[lstProcs[nProc].NameIndex];
                  Writeln('  Procedure=' + strProc);
                end;
            end;
          }
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
  procInfo : TJclTD32ProcSymbolInfo;
  pProcAddr : Pointer;
  lstProcs : TList<TJclTD32ProcSymbolInfo>;
  strName : String;
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
  Module := GetModuleHandle(nil);
  dcProcsByModule := LoadModuleProcDebugInfoForModule(Module, Image);
  GetModuleInformation(GetCurrentProcess, Module, @modInfo, sizeof(modInfo));

  if (dcProcsByModule <> nil) and dcProcsByModule.TryGetValue('AntiPessimizer', lstProcs) then
    begin
      nLowProc := $FFFFFFFFFFFFFFFF;
      nHighProc := 0;
      for procInfo in lstProcs do
        begin
          pProcAddr := PByte(Uint64(modInfo.lpBaseOfDll) + procInfo.Offset + c_nModuleCodeOffset);

          if Uint64(pProcAddr) < nLowProc then
            nLowProc := Uint64(pProcAddr);
          if Uint64(pProcAddr) > nHighProc then
            nHighProc := Uint64(pProcAddr);

          //InstrumentFunction(strName, pProcAddr, procInfo.Size, FindAnchor(pProcAddr));
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
          nIndex := 0;
          for procInfo in lstProcs do
            begin
              pProcAddr := PByte(Uint64(modInfo.lpBaseOfDll) + procInfo.Offset + c_nModuleCodeOffset);
              strName := Image.TD32Scanner.Names[procInfo.NameIndex];
              g_DHArrProcedures[nIndex] := pProcAddr;
              Inc(nIndex);
              if (Uint64(pProcAddr) - nLastAddr) >= sizeof(TProfileAnchor) then
                InstrumentFunction(strName, pProcAddr, procInfo.Size, PProfileAnchor(Int64(pDhTable) + Int64(pProcAddr) - Int64(nLowProc)));

              nLastAddr := UInt64(pProcAddr);
            end;
        end;
    end;
end;

function ExceptionHandler(ExceptionInfo : PEXCEPTION_POINTERS): LONG; stdcall;
begin
  HookEpilogueException;
  g_LastHookedJump^ := EpilogueJump;
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
  InstrumentModuleProcs;

end.
