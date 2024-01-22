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
  ExeLoader in 'ExeLoader.pas',
  CoreProfiler in 'CoreProfiler.pas',
  Utils in 'Utils.pas';

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

begin
  TestFunction;
  PrintProfilerResults;
end.


