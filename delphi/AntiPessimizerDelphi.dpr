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

procedure PrintAStatement;
var
  t : TestClass;
  nValue2 : Integer;
begin
  Inc(nValue2);
  Inc(nValue2);
  Inc(nValue2);
  Writeln('PrintAStatement');
  t := TestClass.Create;

  Sleep(100);
  //InternalSleep(200);
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
  PrintAStatement;


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
  hKernel : THandle;
begin
  hKernel := LoadLibrary('kernel32.dll');
  if hKernel <> 0 then
    @GetThreadDescription := GetProcAddress(hKernel, 'GetThreadDescription');
  
  InstrumentModuleProcs;

  TestFunction;
  PrintDHProfilerResults;
end.


