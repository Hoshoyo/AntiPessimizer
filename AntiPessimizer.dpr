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
  ExeLoader in 'ExeLoader.pas';

type
  TestBase = class
    function TestProc: Integer; virtual;
  end;
  TestClass = class(TestBase)
    function TestProc: Integer; override;
  end;

function TestBase.TestProc: Integer;
begin
  Writeln('test base');
  Result := 33;
end;
function TestClass.TestProc: Integer;
begin
  Writeln('test');
  Sleep(100);
  Result := 32;//PInteger(0)^;
  Writeln('Crash!');
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
begin
  LoadModuleDebugInfoForCurrentModule;

  tc := TestClass.Create;
  tb := TestBase.Create;

  try
    tc.TestProc;
    tb.TestProc;
    tc.TestProc;
    tc.TestProc;
    tc.TestProc;
    tc.TestProc;
    tc.TestProc;
    tc.TestProc;
    tc.TestProc;
  except
    Writeln('Exception bro!');
  end;
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
  //var nStart := GetRTClock;
  TestFunction;
  DumpDictionary;
  //Writeln('Elapsed=' + ((GetRTClock - nStart) / 1000000.0).ToString);
end;

begin
  TimeFunct;
end.


