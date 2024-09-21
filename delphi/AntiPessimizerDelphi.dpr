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
  TWorker = class(TThread)
    procedure Execute; override;
  end;
  TestBase = class
    function TestProc: Integer; virtual;
  end;
  TestClass = class(TestBase)
    function TestProc: Integer; override;
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

procedure TestIntOverflow;
var
  nIndex : Integer;
  nValue : Int64;
begin
  nValue := 1;
  nValue := 1;
  nValue := 1;
  nValue := 1;
  nValue := 1;
  nValue := 1;
  nValue := 1;

    For nIndex := 0 to 1000-1 do
      begin
        nValue := nValue * 2;
      end;

end;

procedure LevelException0;
var
  nNonsense : Integer;
begin
  nNonsense := 5;
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  //RaiseException($EDFADE, 0, 0, nil);
  TestIntOverflow;
  //raise Exception.Create('Foo');
end;

procedure LevelException1;
var
  nNonsense : Integer;
begin
  nNonsense := 5;
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  LevelException0;
end;

procedure LevelException2;
var
  nNonsense : Integer;
begin
  nNonsense := 5;
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  try
    LevelException1;
  finally
    Writeln('Do shit');
  end;
end;

procedure LevelException3;
var
  nNonsense : Integer;
begin
  nNonsense := 5;
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  LevelException2;
end;

procedure LevelException4;
var
  nNonsense : Integer;
begin
  nNonsense := 5;
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  try
    LevelException3;
    Writeln('Damn did not handle it!');
  except
    Writeln('Handled exception');
  end;
end;

procedure LevelException5;
var
  nNonsense : Integer;
begin
  nNonsense := 5;
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  LevelException4;
end;

procedure TestFunction;
begin
  LevelException5;
end;

procedure TestThreads;
var
  tw1 : TWorker;
  tw2 : TWorker;
begin
  tw1 := TWorker.Create;
  tw2 := TWorker.Create;

  while True do
    begin
      PrintDHProfilerResults;
      Writeln('Hello');
      Sleep(1000);
    end;

  tw1.WaitFor;
  tw2.WaitFor;
end;

procedure UselessProc1;
var
  nNonsense : Integer;
begin
  nNonsense := 5;
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);

  for var nIndex := 0 to 100000 - 1 do
     Inc(nNonsense, 5);
end;

procedure UselessProc2;
var
  nNonsense : Integer;
begin
  nNonsense := 5;
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);

  for var nIndex := 0 to 1000000 - 1 do
     Inc(nNonsense, 5);

  ProfilerClearResults;
end;

begin
  g_AntipessimizerGuiWindow := FindWindow('AntiPessimizerClass', nil);
  InstrumentModuleProcs;

  UselessProc1;
  UselessProc2;

  //UselessProc2;

  //TestThreads;
  //TestFunction;
  //TestRegisterCaller;
  PrintDHProfilerResults;
end.


