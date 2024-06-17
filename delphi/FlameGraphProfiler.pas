unit FlameGraphProfiler;

interface
uses
  SyncObjs,
  Windows,
  Generics.Collections,
  Classes;

const
  c_ProfilerStackSize = 1024*128;  // 128kb

type
  TFlameGraphOperation = (fgoNone = 0, fgoEnterBlock = 1, fgoExitBlock = 2);

  // Direct hashing
  TFlameProfileBlock = record
    ptrReturnTarget    : Pointer;
    ptrLastHookJump    : Pointer;
    ptrAddr            : Pointer;
  end;
  PFlameProfileBlock = ^TFlameProfileBlock;

  TFlameProfilerStack = record
    pbBlocks    : array [0..c_ProfilerStackSize-1] of TFlameProfileBlock;
    nAddrOffset : Int64;
    nAtIndex    : Integer;
    nThreadID   : Cardinal;
    bUnwinding  : Boolean;
  end;

  // This record needs to be 32 bytes long
  TThrTranslate = record
    pEpilogueJmp : Pointer;  // Needs to be the first address, this is used in HookJump
    pLastHookJmp : PPointer; // Needs to be the second addresss
    nThreadIndex : Integer;
    nRes         : Integer;
    pPatchRsp    : Pointer; // Address where we need to patch the rsp when an exception occurs
  end;

  procedure FlameEnterProfileBlock(nAddr : Pointer);
  function  FlameExitProfileBlock: Pointer;
  function  FlameUnwindExceptionBlock(HookEpilogue: Pointer; EstablisherFrame: NativeUInt; ContextRecord: Pointer; DispatcherContext: Pointer): Pointer;
  function  FlameUnwindEveryStack: Pointer;
  procedure InitializeFlameProfilerTable(pAnchor : Pointer; nOffsetFromModuleBase : Int64);

implementation
uses
  JclDebug,
  ExeLoader,
  JclPeImage,
  Utils,
  SysUtils;

var
  g_ThreadTranslateT : array [0..1024*1024-1] of TThrTranslate; // ThreadID translation table (supports 1 million threads)
  g_FlameProfileStack   : array [0..63] of TFlameProfilerStack;  // The memory used as a stack to keep in flight profiling data

  g_ThreadAllocIndex : Integer;
  g_nCyclesPerSecond : Int64;

  g_fFlameGraphStream : TMemoryStream;
  g_fFlameGraphFile   : TFileStream;
  g_wFlameGraphWriter : TBinaryWriter;

{$IFDEF MSWINDOWS}
type
  PRuntimeFunction = ^TRuntimeFunction;
  TRuntimeFunction = record
    FunctionStart: LongWord;
    FunctionEnd: LongWord;
    UnwindInfo: LongWord;
  end;
  PExecptionRoutine = Pointer;
  PUnwindHistoryTable = Pointer;
  PDispatcherContext = ^TDispatcherContext;
  TDispatcherContext = record
    ControlPc:        NativeUInt;           //  0 $00
    ImageBase:        NativeUInt;           //  8 $08
    FunctionEntry:    PRuntimeFunction;     // 16 $10
    EstablisherFrame: NativeUInt;           // 24 $18
    TargetIp:         NativeUInt;           // 32 $20
    ContextRecord:    PContext;             // 40 $28
    LanguageHandler:  PExecptionRoutine;    // 48 $30
    HandlerData:      Pointer;              // 56 $38
    HistoryTable:     PUnwindHistoryTable;  // 64 $40
    ScopeIndex:       UInt32;               // 72 $48
    _Fill0:           UInt32;               // 76 $4c
  end;                                      // 80 $50
{$ENDIF}

{$OVERFLOWCHECKS OFF}

procedure InitializeFlameProfilerTable(pAnchor : Pointer; nOffsetFromModuleBase : Int64);
var
  nIndex : Integer;
begin
  g_FlameProfileStack[0].nAddrOffset := nOffsetFromModuleBase;
  g_FlameProfileStack[0].nAtIndex := 0;
  for nIndex := 0 to Length(g_FlameProfileStack)-1 do
    g_FlameProfileStack[nIndex].nAtIndex := 0;

  ZeroMemory(@g_ThreadTranslateT[0], sizeof(g_ThreadTranslateT));
  For nIndex := 0 to Length(g_ThreadTranslateT)-1 do
    g_ThreadTranslateT[nIndex].nThreadIndex := -1;
  LogDebug('### InitializeFlameProfilerTable ### OffsetFromModuleBase=%x', [nOffsetFromModuleBase]);

  g_fFlameGraphStream := TMemoryStream.Create;
  g_wFlameGraphWriter := TBinaryWriter.Create(g_fFlameGraphStream, TEncoding.Unicode, false);
  g_fFlameGraphFile   := TFileStream.Create('out.flame', fmOpenWrite or fmCreate or fmShareDenyWrite);
end;

function GetLocationFromThreadID(nAddr : Pointer; nThreadID : Integer; var pEpilogueJmp : Pointer): Integer;
var
  nIndex   : Integer;
begin
  pEpilogueJmp := g_ThreadTranslateT[nThreadID].pEpilogueJmp;

  if g_ThreadTranslateT[nThreadID].nThreadIndex <> -1 then
    begin
      // Already allocated
      nIndex := g_ThreadTranslateT[nThreadID].nThreadIndex;
    end
  else
    begin
      // Need to allocate
      nIndex := InterlockedAdd(g_ThreadAllocIndex, 1) - 1;
      g_ThreadTranslateT[nThreadID].nThreadIndex := nIndex;
      g_FlameProfileStack[nIndex].nThreadID := nThreadID;
    end;

  Result := nIndex;
end;

procedure FlameEnterProfileBlock(nAddr : Pointer);
var
  pBlock        : PFlameProfileBlock;
  nAtIdx        : Integer;
  nThrIdx       : Integer;
  pEpilogueJmp  : Pointer;
  nCurrThreadID : Cardinal;
begin
  nCurrThreadID := GetCurrentThreadID;
  nThrIdx := GetLocationFromThreadID(nAddr, nCurrThreadID, pEpilogueJmp);

  Inc(g_FlameProfileStack[nThrIdx].nAtIndex);
  nAtIdx := g_FlameProfileStack[nThrIdx].nAtIndex;

  pBlock := @g_FlameProfileStack[nThrIdx].pbBlocks[nAtIdx];
  pBlock.ptrAddr := nAddr;

  g_wFlameGraphWriter.Write(Integer(fgoEnterBlock));
  g_wFlameGraphWriter.Write(Cardinal(nCurrThreadID));
  g_wFlameGraphWriter.Write(nAtIdx);
  g_wFlameGraphWriter.Write(Uint64(nAddr));

  LogDebug('Enter %p', [nAddr]);

  g_wFlameGraphWriter.Write(ReadTimeStamp);
end;

function FlameExitProfileBlock: Pointer;
var
  nAtIdx        : Integer;
  nThrIndex     : Integer;
  pBlock        : PFlameProfileBlock;
  nElapsed      : Uint64;
  nCurrThreadID : Cardinal;
begin
  nElapsed := ReadTimeStamp;

  try
    nCurrThreadID := GetCurrentThreadID;
    nThrIndex := g_ThreadTranslateT[nCurrThreadID].nThreadIndex;
    if nThrIndex = -1 then
      Exit(nil);

    nAtIdx := g_FlameProfileStack[nThrIndex].nAtIndex;
    pBlock := @g_FlameProfileStack[nThrIndex].pbBlocks[nAtIdx];

    g_wFlameGraphWriter.Write(Integer(fgoExitBlock));
    g_wFlameGraphWriter.Write(Cardinal(nCurrThreadID));
    g_wFlameGraphWriter.Write(nAtIdx);
    g_wFlameGraphWriter.Write(nElapsed);

    Dec(g_FlameProfileStack[nThrIndex].nAtIndex);

    LogDebug('Exit %p', [pBlock.ptrAddr]);

    Result := pBlock.ptrReturnTarget;
  except
    on E: Exception do
      begin
        LogDebug('FlameExitProfileBlock Exception=%s Stack=%s CurrentThreadID=%d', [E.Message, E.StackTrace, GetCurrentThreadID]);
        Result := nil;
      end;
  end;
end;

function FlameUnwindEveryStack: Pointer;
var
  nThrIndex    : Integer;
  pLastHookJmp : PPointer;
  pBlock       : PFlameProfileBlock;
  nAtIdx       : Integer;
begin
  nThrIndex := g_ThreadTranslateT[GetCurrentThreadID].nThreadIndex;
  nAtIdx := g_FlameProfileStack[nThrIndex].nAtIndex;
  g_FlameProfileStack[nThrIndex].bUnwinding := True;

  if (nThrIndex = -1) or (nAtIdx <= 0) then
    Exit(nil);

  while nAtIdx >= 0 do
    begin
      pBlock := @g_FlameProfileStack[nThrIndex].pbBlocks[nAtIdx];
      pLastHookJmp := pBlock.ptrLastHookJump;
      if pLastHookJmp <> nil then
        pLastHookJmp^ := pBlock.ptrReturnTarget;
      Dec(nAtIdx)
    end;
  Result := nil;
end;

function FlameUnwindExceptionBlock(HookEpilogue: Pointer; EstablisherFrame: NativeUInt; ContextRecord: Pointer; DispatcherContext: Pointer): Pointer;
var
  pContext     : PDispatcherContext;
  ptrStart     : PByte;
  ptrEnd       : PByte;
  nThrIndex    : Integer;
  nAtIdx       : Integer;
  nIndex       : Integer;
  pBlock       : PFlameProfileBlock;
  pLastHookJmp : PPointer;
  bFound       : Boolean;
begin
  Result := nil;
  pContext := PDispatcherContext(DispatcherContext);
  ptrStart := PByte(pContext.ImageBase + pContext.FunctionEntry.FunctionStart);
  ptrEnd := PByte(pContext.ImageBase + pContext.FunctionEntry.FunctionEnd);

  nThrIndex := g_ThreadTranslateT[GetCurrentThreadID].nThreadIndex;
  if nThrIndex < 0 then
    Exit(nil);
  nAtIdx := g_FlameProfileStack[nThrIndex].nAtIndex;
  if nAtIdx < 0 then
    Exit(nil);

  if g_FlameProfileStack[nThrIndex].bUnwinding then
    g_FlameProfileStack[nThrIndex].bUnwinding := False
  else
    Exit(nil);

  bFound := False;
  for nIndex := nAtIdx downto 0 do
    begin
      nAtIdx := -1;
      pBlock := @g_FlameProfileStack[nThrIndex].pbBlocks[nIndex];
      pLastHookJmp := pBlock.ptrLastHookJump;

      if pLastHookJmp = nil then
        Break;

      if (PByte(pLastHookJmp^) >= ptrStart) and (PByte(pLastHookJmp^) <= ptrEnd) then
        begin
          nAtIdx := nIndex - 1;
          bFound := True;
          Break;
        end;
    end;

  if (nAtIdx <> -1) and bFound then
    begin
      for nIndex := g_FlameProfileStack[nThrIndex].nAtIndex downto 0 do
        begin
          if nIndex < nAtIdx then
            begin
              pBlock := @g_FlameProfileStack[nThrIndex].pbBlocks[nIndex];
              pLastHookJmp := pBlock.ptrLastHookJump;

              if pLastHookJmp <> nil then
                pLastHookJmp^ := HookEpilogue;
            end
          else
            FlameExitProfileBlock;
        end;
    end;
end;

procedure DumpFlameGraphToFile;
var
  nPos : Integer;
begin
  nPos := g_fFlameGraphStream.Position;
  g_fFlameGraphStream.Seek(0, soBeginning);
  g_fFlameGraphFile.CopyFrom(g_fFlameGraphStream, nPos);
  g_fFlameGraphStream.Seek(0, soBeginning);
end;

initialization

end.
