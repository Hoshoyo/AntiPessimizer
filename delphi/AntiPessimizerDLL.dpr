library AntiPessimizerDLL;
uses
  Windows,
  System.SysUtils,
  JCLDebug,
  JCLTd32,
  RTTI,
  System.Classes,
  CoreProfiler in 'CoreProfiler.pas',
  ExeLoader in 'ExeLoader.pas',
  Udis86 in 'Udis86.pas';

{$R *.res}

var
  g_InfoSourceClassList : TList = nil;

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

function CreateDebugInfoWithTD32(const Module : HMODULE): TJclDebugInfoSource;
var
  nIndex : Integer;
  Image : TJclPeBorTD32Image;
  srcModule : TJclTD32SourceModuleInfo;
  strName : String;
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
  Image := GetBase(Result);
  OutputDebugString(PWidechar('MODULE COUNT=' + IntToStr(Image.TD32Scanner.ModuleCount)));

  For nIndex := 0 to Image.TD32Scanner.SourceModuleCount-1 do
    begin
      srcModule := Image.TD32Scanner.SourceModules[nIndex];
      strName := Image.TD32Scanner.Names[srcModule.NameIndex];
      OutputDebugString(PWidechar('Module=' + strName));
    end;
end;

function Worker(pParam : Pointer): DWORD; stdcall;
begin
  while true do
    begin
      OutputDebugString(PWidechar('Debug Thread ' + IntToStr(GetCurrentThreadID)));
      PrintDHProfilerResults;
      Sleep(1000);
    end;
end;

function GetCurrentDir: String;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  GetCurrentDirectory(MAX_PATH, Buffer);
  Result := String(Buffer);
end;

var
  thID : DWORD;
begin
  OutputDebugString('AntiPessimizerStartup');
  OutputDebugString(PWidechar('AntiPessimizer started on ' + GetCurrentDir));
  CreateThread(nil, 0, @Worker, nil, 0, thID);
end.
