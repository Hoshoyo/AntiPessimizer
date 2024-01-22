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

  procedure LoadModuleDebugInfoForCurrentModule;
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
  EpilogueJump : Pointer;

procedure HookEpilogue;
asm
  .noframe
  sub rsp, 32
  call ExitProfileBlock
  add rsp, 32

  mov rcx, qword ptr[EpilogueJump] // Use rcx since rax is the return value
  jmp rcx
end;

procedure HookEpilogueException;
asm
  .noframe
  sub rsp, 32
  call ExitProfileBlock
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
    call EnterProfileBlock
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

procedure InstrumentFunction(strName : String; pProcAddr : PByte; nSize : Cardinal);
var
  pAnchor     : PProfileAnchor;
  pExecBuffer : PAnchorBuffer;
  nOldProtect : DWORD;
  nToSave     : Cardinal;
begin
  pAnchor := FindAnchor(pProcAddr);
  New(pExecBuffer);
  pAnchor.ptrExecBuffer := pExecBuffer;

  VirtualProtect(Pointer(pExecBuffer), sizeof(TAnchorBuffer), PAGE_EXECUTE_READWRITE, nOldProtect);

  nToSave := UdisDisasmAtLeastAndPatchRelatives(pProcAddr, nSize, 15, PByte(pExecBuffer), sizeof(TAnchorBuffer));

  if (nToSave >= 15) and (nToSave <= Cardinal(Length(pExecBuffer^))) then
    begin
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

procedure SerializeDebugInfo(Item: TJclDebugInfoSource; moduleBaseAddr : Uint64);
var
  nIndex      : Integer;
  Image       : TJclPeBorTD32Image;
  procInfo    : TJclTD32ProcSymbolInfo;
  srcModule   : TJclTD32SourceModuleInfo;
  modInfo     : TJclTD32ModuleInfo;
  strName     : String;
  nOffset     : Cardinal;
  nSize       : Cardinal;
  nOldProtect : DWORD;
  nSeg        : Integer;
  strSearchModule : String;
  nSearchStart : Cardinal;
  nSearchEnd   : Cardinal;
  nToSave      : Cardinal;
  pProcAddr    : PByte;
  aAnchor      : TAnchor;
begin
  strSearchModule := 'AntiPessimizer.dpr';
  nSearchStart := 0;
  nSearchEnd := 0;

  if Item is TJclDebugInfoTD32 then
    begin
      Image := GetBase(Item);
      For nIndex := 0 to Image.TD32Scanner.SourceModuleCount-1 do
        begin
          srcModule := Image.TD32Scanner.SourceModules[nIndex];
          Writeln('Source=' + Image.TD32Scanner.Names[srcModule.NameIndex]);
          for nSeg := 0 to srcModule.SegmentCount-1 do
            begin
              //Writeln(Format('  %x -> %x', [srcModule.Segment[nSeg].StartOffset, srcModule.Segment[nSeg].EndOffset]));
              if ContainsText(Image.TD32Scanner.Names[srcModule.NameIndex], strSearchModule) then
                begin
                  nSearchStart := srcModule.Segment[nSeg].StartOffset;
                  nSearchEnd   := srcModule.Segment[nSeg].EndOffset;
                end;
            end;
        end;

      VirtualProtect(Pointer(moduleBaseAddr + nSearchStart + c_nModuleCodeOffset), nSearchEnd - nSearchStart, PAGE_EXECUTE_READWRITE, nOldProtect);

      for nIndex := 0 to Image.TD32Scanner.ModuleCount-1 do
        begin
          modInfo := Image.TD32Scanner.Modules[nIndex];
          Writeln('Source=' + Image.TD32Scanner.Names[modInfo.NameIndex]);
        end;

      For nIndex := 0 to Image.TD32Scanner.ProcSymbolCount-1 do
        begin
          procInfo := Image.TD32Scanner.ProcSymbols[nIndex];
          strName := Image.TD32Scanner.Names[procInfo.NameIndex];
          nOffset := procInfo.Offset;
          nSize   := procInfo.Size;

          if ContainsText(strName, 'TestProc') then
            begin
              Writeln('Proc=' + strName + ' Offset=' + IntToStr(nOffset));
              pProcAddr := PByte(moduleBaseAddr + nOffset + c_nModuleCodeOffset);

              InstrumentFunction(strName, pProcAddr, nSize);
            end;
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

procedure LoadModuleDebugInfoForCurrentModule;
var
  Item    : TJclDebugInfoSource;
  Module  : HMODULE;
  modInfo : MODULEINFO;
begin
  Module := GetModuleHandle(nil);
  Item := CreateDebugInfoWithTD32(Module);

  GetModuleInformation(GetCurrentProcess, Module, @modInfo, sizeof(modInfo));

  if Item <> nil then
    ClassifyProcByModule(Item, Uint64(modInfo.lpBaseOfDll));
    //ClassifyProcBySourceModule(Item, Uint64(modInfo.lpBaseOfDll));
    //SerializeDebugInfo(Item, Uint64(modInfo.lpBaseOfDll));
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

end.
