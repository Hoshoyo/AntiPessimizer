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
      Sleep(100);
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
  //00000000007A3DF0 832DC9A80F0001   sub dword ptr [rel $000fa8c9],$01
  //00000000007A3DF7 833DC2A80F00FF   cmp dword ptr [rel $000fa8c2],-$01
  //00000000007A3DFE C3               ret
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

  try
    //TestAsm;
    //ThirdLevel;
  except
    on E: Exception do
      Writeln('Foo');
  end;

  //CatchException;
  TestLoop(20);
  PrintAStatement(10);
  BigJumpBack;

  JustBeSlow;

  tc := TestClass.Create;
  tb := TestBase.Create;

  tw1 := TWorker.Create;
  tw2 := TWorker.Create;

  while True do
    begin
      PrintDHProfilerResults;
      Sleep(1000);
    end;

  tw1.WaitFor;
  tw2.WaitFor;

end;

var
  c_Constant : Int64 = $123456789ABCDEF;
  nJumpBack : Pointer;
  nPrevRsp : Pointer;
  c_Rax : Cardinal = 1;
  c_Rbx : Cardinal = 2;
  c_Rcx : Cardinal = 4;
  c_Rdx : Cardinal = 8;
  c_Rdi : Cardinal = 16;
  c_Rsi : Cardinal = 32;
  c_Rsp : Cardinal = 64;
  c_Rbp : Cardinal = 128;
  c_R8  : Cardinal = 256;
  c_R9  : Cardinal = 512;
  c_R10 : Cardinal = 1024;
  c_R11 : Cardinal = 2048;
  c_R12 : Cardinal = 4096;
  c_R13 : Cardinal = 8192;
  c_R14 : Cardinal = 16384;
  c_R15 : Cardinal = 32768;

  g_ErrorFlags : Cardinal = 0;

procedure FailPreserveCheck;
begin
  if g_ErrorFlags <> 0 then
    begin
      Writeln(Format('Failed to preserve registers %x', [g_ErrorFlags]));
      if (g_ErrorFlags and c_Rax) <> 0 then
        Writeln('RAX');        
      if (g_ErrorFlags and c_Rbx) <> 0 then
        Writeln('RBX');
      if (g_ErrorFlags and c_Rcx) <> 0 then
        Writeln('RCX');
      if (g_ErrorFlags and c_Rdx) <> 0 then
        Writeln('RDX');
      if (g_ErrorFlags and c_Rdi) <> 0 then
        Writeln('RDI');
      if (g_ErrorFlags and c_Rsi) <> 0 then
        Writeln('RSI');
      if (g_ErrorFlags and c_Rsp) <> 0 then
        Writeln('RSP');
      if (g_ErrorFlags and c_Rbp) <> 0 then
        Writeln('RBP');

      if (g_ErrorFlags and c_R8) <> 0 then
        Writeln('R8');        
      if (g_ErrorFlags and c_R9) <> 0 then
        Writeln('R9');
      if (g_ErrorFlags and c_R10) <> 0 then
        Writeln('R10');
      if (g_ErrorFlags and c_R11) <> 0 then
        Writeln('R11');
      if (g_ErrorFlags and c_R12) <> 0 then
        Writeln('R12');
      if (g_ErrorFlags and c_R13) <> 0 then
        Writeln('R13');
      if (g_ErrorFlags and c_R14) <> 0 then
        Writeln('R14');
      if (g_ErrorFlags and c_R15) <> 0 then
        Writeln('R15');
    end;
end;

procedure TestRegisterCallee;
asm
  NOP DWORD ptr [EAX + EAX*1]
  NOP DWORD ptr [EAX + EAX*1]
  NOP DWORD ptr [EAX + EAX*1]
  NOP DWORD ptr [EAX + EAX*1]
  NOP DWORD ptr [EAX + EAX*1]

  cmp rax, c_Constant
  mov eax, 0
  cmovne eax, c_Rax
  or g_ErrorFlags, eax

  cmp rbx, c_Constant
  cmovne eax, c_Rbx
  or g_ErrorFlags, eax

  cmp rcx, c_Constant
  cmovne eax, c_Rcx
  or g_ErrorFlags, eax

  cmp rdx, c_Constant
  cmovne eax, c_Rdx
  or g_ErrorFlags, eax

  cmp rdi, c_Constant
  cmovne eax, c_Rdi
  or g_ErrorFlags, eax

  cmp rsi, c_Constant
  cmovne eax, c_Rsi
  or g_ErrorFlags, eax

  cmp rsp, c_Constant
  cmovne eax, c_Rsp
  or g_ErrorFlags, eax

  cmp rbp, c_Constant
  cmovne eax, c_Rbp
  or g_ErrorFlags, eax

  cmp r8, c_Constant
  cmovne eax, c_R8
  or g_ErrorFlags, eax

  cmp r9, c_Constant
  cmovne eax, c_R9
  or g_ErrorFlags, eax

  cmp r10, c_Constant
  cmovne eax, c_R10
  or g_ErrorFlags, eax

  cmp r11, c_Constant
  cmovne eax, c_R11
  or g_ErrorFlags, eax

  cmp r12, c_Constant
  cmovne eax, c_R12
  or g_ErrorFlags, eax

  cmp r13, c_Constant
  cmovne eax, c_R13
  or g_ErrorFlags, eax

  cmp r14, c_Constant
  cmovne eax, c_R14
  or g_ErrorFlags, eax

  cmp r15, c_Constant
  cmovne eax, c_R15
  or g_ErrorFlags, eax

  // Go back
  call FailPreserveCheck
end;

// Callee saved = RBX, RBP, RDI, RSI, RSP, R12, R13, R14, and R15
procedure TestRegisterCaller;
asm
.noframe
  NOP DWORD ptr [EAX + EAX*1]
  NOP DWORD ptr [EAX + EAX*1]
  NOP DWORD ptr [EAX + EAX*1]
  NOP DWORD ptr [EAX + EAX*1]

  push rbx
  push rbp
  push rdi
  push rsi
  push rsp
  push r12
  push r13
  push r14
  push r15

  lea rax, @aftercall
  mov nJumpBack, rax

  mov nPrevRsp, rsp

  mov rax, c_Constant
  mov rbx, c_Constant
  mov rcx, c_Constant
  mov rdx, c_Constant
  mov rsi, c_Constant
  mov rdi, c_Constant
  mov rbp, c_Constant
  //mov rsp, c_Constant

  mov r8,  c_Constant
  mov r9,  c_Constant
  mov r10, c_Constant
  mov r11, c_Constant
  mov r12, c_Constant
  mov r13, c_Constant
  mov r14, c_Constant
  mov r15, c_Constant

  //jmp TestRegisterCallee
  call TestRegisterCallee
@aftercall:

  mov rsp, nPrevRsp

  pop r15
  pop r14
  pop r13
  pop r12
  pop rsp
  pop rsi
  pop rdi
  pop rbp
  pop rbx
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


