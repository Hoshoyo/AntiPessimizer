program AntiPessimizer;
{$APPTYPE CONSOLE}
{$R *.res}
uses
  System.SysUtils,
  Windows,
  System.Generics.Collections,
  JCLDebug,
  JclSysinfo,
  RTTI,
  JclTD32,
  System.Classes,
  StrUtils,
  Udis86 in 'Udis86.pas';

var
  FClockFrequency : Int64;
  g_InfoSourceClassList : TList = nil;

  ExecutableBuffer : array [0..31] of Byte;
  ExecutableBufferPtr : Pointer;

type
  TestBase = class
    function TestProc: Integer; virtual;
  end;
  TestClass = class(TestBase)
    function TestProc: Integer; override;
  end;
  TAnchor = record
    nStart : Int64;
    nElapsed : Int64;
    nHitCount : Int64;
    strName : String;
  end;

function TestBase.TestProc: Integer;
begin
  Writeln('test base');
  Result := 33;
end;
function TestClass.TestProc: Integer;
begin
  try
    Writeln('test');
    Sleep(100);
    Result := 34;//PInteger(0)^;
  except
    Result := 22;
  end;
end;

function GetRTClock: Int64;
var
  nClock : Int64;
begin
  if QueryPerformanceCounter(nClock)
    then Result := Round(nClock / FClockFrequency * 1000 * 1000 * 1000)
    else Result := 0;
end;

// ------------------------------------------------------

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

procedure TestJump;
var
  arFoo : array [0..256] of Integer;
begin
  Writeln('Jumped');
  arFoo[127] := 32;
end;

var
  EpilogueJump : Pointer;
  AtAddr       : Pointer;
  g_dcFunctions : TDictionary<Pointer, TAnchor>;

procedure SaveTimeStart(pAddr : Pointer);
var
  aValue : TAnchor;
begin
  if g_dcFunctions.TryGetValue(pAddr, aValue) then
    begin
      aValue.nStart := GetRTClock;
      Inc(aValue.nHitCount);
      g_dcFunctions.AddOrSetValue(pAddr, aValue);
    end;
end;

procedure SaveTimeEnd(pAddr : Pointer);
var
  aValue : TAnchor;
begin
  if g_dcFunctions.TryGetValue(pAddr, aValue) then
    begin
      aValue.nElapsed := aValue.nElapsed + GetRTClock - aValue.nStart;
      g_dcFunctions.AddOrSetValue(pAddr, aValue);
    end;
end;

procedure HookEpilogue;
asm
  .noframe
  sub rsp, 32
  mov rcx, AtAddr
  call SaveTimeEnd
  add rsp, 32

  mov rcx, qword ptr[EpilogueJump] // Use rcx since rax is the return value
  jmp rcx
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

  mov qword ptr[EpilogueJump], rax // save the old return address

  lea rax, HookEpilogue
  mov qword ptr[rsp+8], rax // mov new address as return

  pop rax  // This is where we are called from

  // Whatever it needs to be done do it here
    // Naive implementation for now
    push rcx
    push rdx
    push r8
    push r9
    push r11

    mov rcx, rax  // rax is the base address of the function called after executing the first 15 bytes
    sub rcx, 15   // rcx here is the base address of the called function
    mov AtAddr, rcx
    add r10, rax  // go back to the position after the buffered execution
    push r10

    sub rsp, 32
    call SaveTimeStart
    add rsp, 32

    pop r10
    pop r11
    pop r9
    pop r8
    pop rdx
    pop rcx

  jmp r11
end;

procedure SerializeDebugInfo(Item: TJclDebugInfoSource);
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
  pMem : Pointer;
begin
  strSearchModule := 'AntiPessimizer.dpr';
  nSearchStart := 0;
  nSearchEnd := 0;

  g_dcFunctions := TDictionary<Pointer, TAnchor>.Create;

  if Item is TJclDebugInfoTD32 then
    begin
      Image := GetBase(Item);
      For nIndex := 0 to Image.TD32Scanner.SourceModuleCount-1 do
        begin
          srcModule := Image.TD32Scanner.SourceModules[nIndex];
          Writeln('Source=' + Image.TD32Scanner.Names[srcModule.NameIndex]);
          for nSeg := 0 to srcModule.SegmentCount-1 do
            begin
              Writeln(Format('  %x -> %x', [srcModule.Segment[nSeg].StartOffset, srcModule.Segment[nSeg].EndOffset]));
              if ContainsText(Image.TD32Scanner.Names[srcModule.NameIndex], strSearchModule) then
                begin

                  nSearchStart := srcModule.Segment[nSeg].StartOffset;
                  nSearchEnd   := srcModule.Segment[nSeg].EndOffset;
                end;
            end;
        end;

      VirtualProtect(Pointer($401000 + nSearchStart), nSearchEnd - nSearchStart, PAGE_EXECUTE_READWRITE, nOldProtect);
      VirtualProtect(Pointer(@ExecutableBuffer[0]), Sizeof(ExecutableBuffer), PAGE_EXECUTE_READWRITE, nOldProtect);
      ExecutableBufferPtr := Pointer(@ExecutableBuffer[0]);

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

          if (nOffset >= nSearchStart) and ((nOffset + nSize) <= nSearchEnd) then
            begin
              Writeln('Proc=' + Image.TD32Scanner.Names[procInfo.NameIndex] + ' Offset=' + IntToStr(nOffset) +
                Format('FirstBytes= %x, %x, %x, %x', [
                  PByte($400000 + nOffset + $1000)^,
                  PByte($400000 + nOffset + $1001)^,
                  PByte($400000 + nOffset + $1002)^,
                  PByte($400000 + nOffset + $1003)^,
                  PByte($400000 + nOffset + $1004)^]));
            end;

          if ContainsText(strName, 'TestProc') then
            begin

              Writeln('Proc=' + strName + ' Offset=' + IntToStr(nOffset));
              pProcAddr := PByte($400000 + nOffset + $1000);

              nToSave := UdisDisasmAtLeast(PByte($400000 + nOffset + $1000), nSize, 15);

              if (nToSave >= 15) and (nToSave <= Length(ExecutableBuffer)) then
                begin
                  CopyMemory(@ExecutableBuffer[0], pProcAddr, nToSave);
                  ExecutableBuffer[nToSave + 0] := $41; // jmp r10
                  ExecutableBuffer[nToSave + 1] := $ff;
                  ExecutableBuffer[nToSave + 2] := $e2;

                  aAnchor.nStart := 0;
                  aAnchor.nElapsed := 0;
                  aAnchor.nHitCount := 0;
                  aAnchor.strName := strName;
                  g_dcFunctions.AddOrSetValue(pProcAddr, aAnchor);

                  // mov rax imm64
                  // jmp HookJump
                  pProcAddr[0] := $48;  // 1 -> 1
                  pProcAddr[1] := $B8;  // 2 -> 2
                  PUint64(pProcAddr + 2)^ := Uint64(@ExecutableBuffer[0]); // 8 -> 10
                  pProcAddr[9] := Byte(nToSave - 15);  // 2 -> 2
                  pProcAddr[$A] := $E8; // 1 -> 11
                  PCardinal(pProcAddr + $B)^ := Cardinal(Int64(@HookJump) - Int64(pProcAddr + $B + 4)); // 4 -> 15
                end;
            end;
        end;
    end;
end;

procedure TestFunction;
var
  DebugInfoList : TJclDebugInfoList;
  Item : TJclDebugInfoSource;
  tc : TestClass;
begin
  Item := CreateDebugInfoWithTD32(CachedModuleFromAddr(@TestFunction));
  tc := TestClass.Create;

  if Item <> nil then
    SerializeDebugInfo(Item);

  tc.TestProc;
  tc.TestProc;
end;

procedure DumpDictionary;
var
  Item : TPair<Pointer, TAnchor>;
begin
  for Item in g_dcFunctions do
    begin
      if Item.Value.nElapsed > 0 then
        Writeln(
          'Name=' + Item.Value.strName +
          ' Addr=' + Uint64(Item.Key).ToString +
          ' HitCount=' + IntToStr(Item.Value.nHitCount) +
          ' Elapsed=' + (Item.Value.nElapsed / 1000000.0).ToString + ' ms.');
    end;
end;

procedure TimeFunct;
begin
  var nStart := GetRTClock;
  TestFunction;
  DumpDictionary;
  //Writeln('Elapsed=' + ((GetRTClock - nStart) / 1000000.0).ToString);
end;

begin
  QueryPerformanceFrequency(FClockFrequency);
  TimeFunct;
end.


