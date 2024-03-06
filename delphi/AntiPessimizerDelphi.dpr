program AntiPessimizerDelphi;
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
  Math,
  ExeLoader in 'ExeLoader.pas',
  CoreProfiler in 'CoreProfiler.pas',
  Utils in 'Utils.pas',
  Udis86 in 'Udis86.pas';

type
  TestBase = class
    function TestProc: Integer; virtual;
  end;
  TestClass = class(TestBase)
    function TestProc: Integer; override;
  end;

  TWorker = class(TThread)
    procedure Execute; override;
  end;


var
  GetThreadDescription : function (handle :THandle; pwName : PWideChar): HRESULT; stdcall;

procedure InternalSleep(nValue : Integer);
var
  t : TestClass;
  nValue2 : Integer;
begin
  nValue2 := 3;
  Inc(nValue2, nValue);
  Writeln('InternalSleep');
  t := TestClass.Create;
  Sleep(nValue);
end;

procedure PrintAStatement(nValue2 : Integer);
var
  t : TestClass;
begin
  while nValue2 < 20 do
    begin
      Inc(nValue2);
      Inc(nValue2);
      Inc(nValue2);
      Writeln('PrintAStatement');
      t := TestClass.Create;

      Sleep(100);
      //InternalSleep(200);
    end;
end;

procedure TestLoop(nCount : Integer);
asm
@BeginLoop:
  mov rax, 10
  mov rax, 10
  mov rax, 10
  mov rax, 10
  mov rax, 10
  mov rax, 10
  mov rax, 10
  mov rax, 10
  mov rax, 10
  mov rax, 10
  mov rax, 10
  mov rax, 10
//@BeginLoop // This should be possible
  dec rax
  loop @BeginLoop
end;

procedure BigJumpBack;
var
  t : TestClass;
  nValue2 : Integer;
begin
  nValue2 := 0;
  Inc(nValue2);
  Inc(nValue2);
  Inc(nValue2);
  Inc(nValue2);
  Inc(nValue2);
  Inc(nValue2);
  while nValue2 < 100 do
    begin
      Inc(nValue2);
      Inc(nValue2);
      Inc(nValue2);
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Sleep(100);
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
      Writeln('PrintAStatement');
    end;
end;

procedure TWorker.Execute;
var
  tc : TestClass;
   DebugName: PWideChar;
begin
  NameThreadForDebugging('Profit.' + Self.ClassName);   // RaiseException($406d1388)
  
  tc := TestClass.Create;
  while true do
    begin
      tc.TestProc;
      //Writeln(IntToStr(ThreadID));
    end;
end;

function TestBase.TestProc: Integer;
begin
  //Writeln('test base');
  Result := 33;
end;
function TestClass.TestProc: Integer;
begin
  Result := 45 * 32 + 123;
  Inc(Result);
  Dec(Result);

  if Result > 32655 then
    Result := Result div 3;
end;

function MoreInternal: Int64; stdcall;
begin
  Result := 45 * 32 + 123;
  Inc(Result);
  Dec(Result);

  if Result > 32655 then
    Result := Result div 3;
end;

function BeSlowInternal: Int64; stdcall;
begin
  Result := 45 * 32 + 123;
  Inc(Result, MoreInternal);
  Dec(Result);

  if Result > 32655 then
    Result := Result div 3;
end;

function RelativeMovTest: Int64;
asm
  .noframe
  //Vcl.Forms.pas.5214: M := TMonitor.Create;
  //000000000070544C 488B0D2D31FFFF   mov rcx,[rel $ffff312d]
  mov rcx, [rel $ffff312d]

  sub dword ptr [rel $000fa8c9],$01
  cmp dword ptr [rel $000fa8c2],-$01
  cmp dword ptr [rel $000fa8c2],-$01
  cmp dword ptr [rel $000fa8c2],-$01
  cmp dword ptr [rel $000fa8c2],-$01
  cmp dword ptr [rel $000fa8c2],-$01
  cmp dword ptr [rel $000fa8c2],-$01
  cmp dword ptr [rel $000fa8c2],-$01
  //00000000007A3DF0 832DC9A80F0001   sub dword ptr [rel $000fa8c9],$01
  //00000000007A3DF7 833DC2A80F00FF   cmp dword ptr [rel $000fa8c2],-$01
  //00000000007A3DFE C3               ret
end;

function CallAtStartTest: Int64;
asm
  .noframe
  sub rsp, $28
  mov ecx, $5
  mov edx, $1
  call JclCheckWinVersion
  sub dword ptr [rel $000fa8c9],$01
  sub dword ptr [rel $000fa8c9],$01
  sub dword ptr [rel $000fa8c9],$01
  sub dword ptr [rel $000fa8c9],$01
  sub dword ptr [rel $000fa8c9],$01
  sub dword ptr [rel $000fa8c9],$01
end;

function JustBeSlow: Int64;
var
  nIndex: Integer;
  nSum : Int64;
begin
  nSum := 0;
  for nIndex := 0 to 100000 do
    nSum := nSum + BeSlowInternal;
  Result := nSum;
  nSum := nSum - 18578;
  Result := Math.Max(nSum, Result);
end;

procedure DoAnException;
var
  nValue : Integer;
begin
  nValue := 3;
  Inc(nValue);
  Dec(nValue);
  //nValue := PInteger(0)^;
  raise Exception.Create('Error Message');
end;

procedure CatchException;
{$IFNDEF CRASH_EARLY}
var
  nValue : Integer;
{$ENDIF}
begin
{$IFNDEF CRASH_EARLY}
  nValue := 3;
  Inc(nValue);
  Dec(nValue);
{$ENDIF}
  try
    DoAnException;
  except
    on E: Exception do
      Writeln(E.Message);
  end;
end;

procedure RaiseBack;
begin
  DoAnException;
end;

procedure ThirdLevel;
var
  nValue : Integer;
begin
  nValue := 3;
  Inc(nValue);
  Dec(nValue);
    Inc(nValue);
  Dec(nValue);
    Inc(nValue);
  Dec(nValue);
    Inc(nValue);
  Dec(nValue);
    Inc(nValue);
  Dec(nValue);
  try
  RaiseBack
  except
    Writeln('FInally');
    raise;
  end;
end;

// ------------------------------------------------------

procedure TestJump;
var
  arFoo : array [0..256] of Integer;
begin
  Writeln('Jumped');
  arFoo[127] := 32;
end;

procedure TestAsm;
asm
  mov r10, $1234
  mov qword ptr[rel 6], r10
  jmp [rel $0]
@foo:
  db $60
  db $3c
  db $fb
  db 0
  db 0
  db 0
  db 0
  db 0
  //$FB3C60
  //db $12
  //db $34
  //db $56
  //db $78
  //db $9A
  //db $BC
  //db $DE
  //db $F0
  inc rax
  inc rax
  inc rax
  inc rax
  inc rax
  inc rax
  inc rax
end;

procedure CondJumpAfterBlock;
asm
  sub rsp, $28
  mov rax, [rel $05f3bde5]
  cmp byte ptr [rax+$0c], $00
  jz @NextFoo
  mov rcx, 33
@NextFoo:
  mov rcx, 44
  mov rdx, 45
  mov rdx, 55
  ret
end;

procedure TestFunction;
var
  tc : TestClass;
  tb : TestBase;
  tw1 : TWorker;
  tw2 : TWorker;
  nOldProtect : DWORD;
begin
  //RelativeMovTest;

  VirtualProtect(Pointer(@TestAsm), sizeof(TAnchorBuffer), PAGE_EXECUTE_READWRITE, nOldProtect);
  VirtualProtect(Pointer(@CondJumpAfterBlock), sizeof(TAnchorBuffer), PAGE_EXECUTE_READWRITE, nOldProtect);

  try
    CondJumpAfterBlock;
    TestAsm;
    //ThirdLevel;
  except
    on E: Exception do
      Writeln('Foo');
  end;

  //TestUdis(@CallAtStartTest);

  //CallAtStartTest;

  //CatchException;
  TestLoop(20);
  PrintAStatement(10);
  BigJumpBack;

  JustBeSlow;

  //tc := TestClass.Create;
  //tb := TestBase.Create;

  tw1 := TWorker.Create;
  tw2 := TWorker.Create;

  while True do
    begin
      //PrintDHProfilerResults;
      Writeln('Hello');
      Sleep(1000);
    end;

  tw1.WaitFor;
  tw2.WaitFor;

end;

var
  hKernel : THandle;
begin
  hKernel := LoadLibrary('kernel32.dll');
  if hKernel <> 0 then
    @GetThreadDescription := GetProcAddress(hKernel, 'GetThreadDescription');
  
  InstrumentModuleProcs;

  TestFunction;
  //TestRegisterCaller;
  PrintDHProfilerResults;
end.


