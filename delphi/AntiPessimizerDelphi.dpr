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

procedure LevelException0;
var
  nNonsense : Integer;
begin
  nNonsense := 5;
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  Inc(nNonsense, nNonsense + 5);
  RaiseException($EDFADE, 0, 0, nil);
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

procedure TestFunction;
begin
  LevelException4;
end;

begin
  g_AntipessimizerGuiWindow := FindWindow('AntiPessimizerClass', nil);
  InstrumentModuleProcs;

  TestFunction;
  //TestRegisterCaller;
  PrintDHProfilerResults;
end.


