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

procedure PrintAStatement;
begin
  Writeln('Hello World');
end;

function TestBase.TestProc: Integer;
begin
  //Writeln('test base');
  Result := 33;
end;
function TestClass.TestProc: Integer;
begin
  //Writeln('test');
  Result := 32;
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
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax

  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
  push rax
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
  nValue := PInteger(0)^;
end;

procedure CatchException;
{$IFDEF CRASH_EARLY}
var
  nValue : Integer;
{$ENDIF}
begin
{$IFDEF CRASH_EARLY}
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

// ------------------------------------------------------

procedure TestJump;
var
  arFoo : array [0..256] of Integer;
begin
  Writeln('Jumped');
  arFoo[127] := 32;
end;

procedure TestFunction;
var
  tc : TestClass;
  tb : TestBase;
  nIndex: Integer;
begin
  tc := TestClass.Create;
  tb := TestBase.Create;

  //RelativeMovTest;

  JustBeSlow;

  CatchException;

  for nIndex := 0 to 10000 do
    begin
      tc.TestProc;
      tb.TestProc;
      tc.TestProc;
      tc.TestProc;
      tc.TestProc;
      tc.TestProc;
      tc.TestProc;
      tc.TestProc;
      tc.TestProc;
    end;
  PrintAStatement;
end;

var
  lstStack : TJclStackInfoList;
  nValue : Integer;
  strList : TStringList;
begin
  InstrumentModuleProcs;

  TestFunction;
  //PrintProfilerResults;
  PrintDHProfilerResults;

  Writeln('Profiler took ' + ProfilerCycleTime + ' cycles on average');
end.


