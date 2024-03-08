unit CoreProfiler;

interface
uses
  SyncObjs,
  Windows,
  Classes;

const
  c_ProfilerStackSize = 1024*128;  // 128kb

type
  TProfileBucket = record
    nElapsedExclusive : Uint64;
    nElapsedInclusive : Uint64;
    strName           : String;
  end;

  TProfileAnchor = record
    nElapsedExclusive : UInt64;
    nElapsedInclusive : UInt64;
    nHitCount         : UInt64;
    arNextAnchors     : array of TProfileAnchor;
    nThreadID         : Integer;
    strName           : String;
  end;
  PProfileAnchor = ^TProfileAnchor;

  TProfileBlock = record
    nParentIndex       : Integer;
    nAnchorIndex       : Integer;
    nSecondIndex       : Integer;
    nParentSecondIndex : Integer;
    nStartTime         : Uint64;
    nPrevTimeInclusive : Uint64;
    ptrReturnTarget    : Pointer;
  end;
  PProfileBlock = ^TProfileBlock;

  // Direct hashing
  TDHProfileBlock = record
    pParentAnchor      : PProfileAnchor;
    pAnchor            : PProfileAnchor;
    nStartTime         : Uint64;
    nPrevTimeInclusive : Uint64;
    ptrReturnTarget    : Pointer;
    ptrLastHookJump    : Pointer;
  end;
  PDHProfileBlock = ^TDHProfileBlock;

  TDHProfilerStack = record
    pbBlocks    : array [0..c_ProfilerStackSize-1] of TDHProfileBlock;
    nAddrOffset : Int64;
    nAtIndex    : Integer;
    nThreadID   : Cardinal;
  end;

  // This record needs to be 32 bytes long
  TThrTranslate = record
    pEpilogueJmp : Pointer;  // Needs to be the first address, this is used in HookJump
    pLastHookJmp : PPointer; // Needs to be the second addresss
    nThreadIndex : Integer;
    nRes         : Integer;
    pPatchRsp    : Pointer; // Address where we need to patch the rsp when an exception occurs
  end;

  procedure DHEnterProfileBlock(nAddr : Pointer);
  function  DHExitProfileBlock: Pointer;
  function  DHExitProfileBlockException: Pointer;
  function  DHUnwindExceptionBlock(HookEpilogue: Pointer; EstablisherFrame: NativeUInt; ContextRecord: Pointer; DispatcherContext: Pointer): Pointer;
  function  DHUnwindEveryStack: Pointer;
  procedure InitializeDHProfilerTable(pAnchor : Pointer; nOffsetFromModuleBase : Int64);
  procedure ProfilerSerializeResults(stream : TMemoryStream; writer : TBinaryWriter; bName : Boolean);
  procedure PrintLengthOfAnchors;
  function  CyclesToMs(nCycles : Int64): Double;

  procedure PrintDHProfilerResults;

var
  EpilogueJump : Pointer; // TODO(psv): Make it Thread safe
  g_DHArrProcedures  : array of Pointer;
  g_Pipe : THandle;
  g_ThreadID : Integer = 0;
  g_ThreadTranslateT : array [0..1024*1024-1] of TThrTranslate; // ThreadID translation table (supports 1 million threads)
  g_CriticalSectionAnchorAllocation : TCriticalSection;

implementation
uses
  JclDebug,
  ExeLoader,
  JclPeImage,
  Utils,
  SysUtils;

var
  g_DHTableProfiler  : Pointer;           // This table is the hashtable for the anchors, the offsets correspond directly to addresses
  g_DHProfileStack   : array [0..63] of TDHProfilerStack;  // The memory used as a stack to keep in flight profiling data

  g_ThreadAllocIndex : Integer;
  g_nCyclesPerSecond : Int64;

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


procedure InitializeDHProfilerTable(pAnchor : Pointer; nOffsetFromModuleBase : Int64);
var
  nIndex : Integer;
begin
  g_DHProfileStack[0].pbBlocks[0].pAnchor := PProfileAnchor(PByte(pAnchor) - sizeof(TProfileAnchor));
  g_DHProfileStack[0].pbBlocks[0].pParentAnchor := PProfileAnchor(PByte(pAnchor) - sizeof(TProfileAnchor));
  g_DHTableProfiler := pAnchor;
  g_DHProfileStack[0].nAddrOffset := nOffsetFromModuleBase;
  g_DHProfileStack[0].nAtIndex := 0;

  ZeroMemory(@g_ThreadTranslateT[0], sizeof(g_ThreadTranslateT));
  For nIndex := 0 to Length(g_ThreadTranslateT)-1 do
    g_ThreadTranslateT[nIndex].nThreadIndex := -1;
  LogDebug('### InitializeDHProfilerTable ### OffsetFromModuleBase=%x', [nOffsetFromModuleBase]);
end;

// Direct hashed anchored profiler

function GetLocationFromThreadID(nAddr : Pointer; nThreadID : Integer; var pAnchor : PProfileAnchor; var pEpilogueJmp : Pointer): Integer;
var
  nIndex   : Integer;
  nPrevLen : Integer;
begin
  pEpilogueJmp := g_ThreadTranslateT[nThreadID].pEpilogueJmp;

  if g_ThreadTranslateT[nThreadID].nThreadIndex <> -1 then
    begin
      // Already allocated
      pAnchor := PProfileAnchor(PByte(nAddr) + g_DHProfileStack[0].nAddrOffset);
      nIndex := g_ThreadTranslateT[nThreadID].nThreadIndex;
    end
  else
    begin
      // Need to allocate
      nIndex := InterlockedAdd(g_ThreadAllocIndex, 1) - 1;
      g_ThreadTranslateT[nThreadID].nThreadIndex := nIndex;
      pAnchor := PProfileAnchor(PByte(nAddr) + g_DHProfileStack[0].nAddrOffset);
      g_DHProfileStack[nIndex].nThreadID := nThreadID;
      if nIndex = 0 then
        begin
          pAnchor.nThreadID := nThreadID;
        end;
    end;

  if nIndex > 0 then
    begin
      nPrevLen := Length(pAnchor.arNextAnchors);
      // This is not the first thread, allocate the slot at the Thread index
      if nPrevLen < nIndex then
        begin
          // TODO(psv): This is not thread safe at all
          SetLength(pAnchor.arNextAnchors, nIndex);
          //LogDebug('%s Thread %d setting length %d to anchor %p OldAddr=%p NewAddr=%p', [DateTimeToStr(Now), nThreadID, nIndex, pAnchor, nOldAddr, @pAnchor.arNextAnchors[0]]);
          ZeroMemory(@pAnchor.arNextAnchors[nPrevLen], sizeof(pAnchor.arNextAnchors[0]) * nIndex-nPrevLen);
          pAnchor.arNextAnchors[nIndex-1].strName := PProfileAnchor(PByte(nAddr) + g_DHProfileStack[0].nAddrOffset).strName;
          pAnchor.arNextAnchors[nIndex-1].nThreadID := nThreadID;
        end;
      pAnchor := @pAnchor.arNextAnchors[nIndex-1];
    end;

  Result := nIndex;
end;

procedure DHEnterProfileBlock(nAddr : Pointer);
var
  pBlock        : PDHProfileBlock;
  nAtIdx        : Integer;
  nThrIdx       : Integer;
  pAnchor       : PProfileAnchor;
  pEpilogueJmp  : Pointer;
  nCurrThreadID : Cardinal;
begin
  nCurrThreadID := GetCurrentThreadID;
  nThrIdx := GetLocationFromThreadID(nAddr, nCurrThreadID, pAnchor, pEpilogueJmp);

  Inc(g_DHProfileStack[nThrIdx].nAtIndex);
  nAtIdx := g_DHProfileStack[nThrIdx].nAtIndex;

  pBlock := @g_DHProfileStack[nThrIdx].pbBlocks[nAtIdx];
  pBlock.pParentAnchor := g_DHProfileStack[nThrIdx].pbBlocks[nAtIdx-1].pAnchor;
  pBlock.pAnchor := pAnchor;
  pBlock.ptrReturnTarget := pEpilogueJmp;
  pBlock.ptrLastHookJump := g_ThreadTranslateT[nCurrThreadID].pLastHookJmp;

  LogDebug(' Enter - ThreadIndex=%d ThreadID=%d AtIdx=%d Block=%p %d %s', [nThrIdx, GetCurrentThreadID, nAtIdx, pBlock, GetCurrentThreadID, pBlock.pAnchor.strName]);

  pBlock.nPrevTimeInclusive := pBlock.pAnchor.nElapsedInclusive;
  pBlock.nStartTime := ReadTimeStamp;
end;

function DHExitProfileBlock: Pointer;
var
  nAtIdx      : Integer;
  nThrIndex   : Integer;
  pBlock      : PDHProfileBlock;
  nElapsed    : Uint64;
begin
  nElapsed := ReadTimeStamp;

  try
    nThrIndex := g_ThreadTranslateT[GetCurrentThreadID].nThreadIndex;
    if nThrIndex = -1 then
      Exit(0);

    nAtIdx := g_DHProfileStack[nThrIndex].nAtIndex;
    pBlock := @g_DHProfileStack[nThrIndex].pbBlocks[nAtIdx];
    Dec(g_DHProfileStack[nThrIndex].nAtIndex);

    nElapsed := nElapsed - pBlock.nStartTime;

    if pBlock.pParentAnchor <> nil then
      pBlock.pParentAnchor.nElapsedExclusive := pBlock.pParentAnchor.nElapsedExclusive - nElapsed;
    pBlock.pAnchor.nElapsedExclusive := pBlock.pAnchor.nElapsedExclusive + nElapsed;
    pBlock.pAnchor.nElapsedInclusive := pBlock.nPrevTimeInclusive + nElapsed;

    //LogDebug(' Exit - ThreadIndex=%d AtIdx=%d Block=%p ThreadID=%d Anchor=%p', [nThrIndex, nAtIdx, pBlock, GetCurrentThreadID, pBlock.pAnchor]);

    Inc(pBlock.pAnchor.nHitCount);

    Result := pBlock.ptrReturnTarget;
  except
    on E: Exception do
      begin
        LogDebug('DHExitProfileBlock Exception=%s Stack=%s CurrentThreadID=%d', [E.Message, E.StackTrace, GetCurrentThreadID]);
        LogDebug(' Exit - ThreadIndex=%d AtIdx=%d Block=%p ThreadID=%d Anchor=%p', [nThrIndex, nAtIdx, pBlock, GetCurrentThreadID, pBlock.pAnchor]);
      end;
  end;
end;

function DHExitProfileBlockException: Pointer;
var
  nThrIndex    : Integer;
  pLastHookJmp : PPointer;
  pBlock       : PDHProfileBlock;
  nAtIdx       : Integer;
begin
  nThrIndex := g_ThreadTranslateT[GetCurrentThreadID].nThreadIndex;
  //LogDebug('DHExitProfileBlockException ThreadIndex=%d, nAtIndex=%d CurrentThreadID=%d', [nThrIndex, g_DHProfileStack[nThrIndex].nAtIndex, GetCurrentThreadID]);
  if (nThrIndex = -1) or (g_DHProfileStack[nThrIndex].nAtIndex = 0) then
    begin
      Exit(nil);
    end;
  Result := DHExitProfileBlock;
  nAtIdx := g_DHProfileStack[nThrIndex].nAtIndex + 1;
  pBlock := @g_DHProfileStack[nThrIndex].pbBlocks[nAtIdx];

  pLastHookJmp := pBlock.ptrLastHookJump;
  if pLastHookJmp <> nil then
    pLastHookJmp^ := Result;
end;

function DHUnwindEveryStack: Pointer;
var
  nThrIndex    : Integer;
  pLastHookJmp : PPointer;
  pBlock       : PDHProfileBlock;
  nAtIdx       : Integer;
begin
  nThrIndex := g_ThreadTranslateT[GetCurrentThreadID].nThreadIndex;
  nAtIdx := g_DHProfileStack[nThrIndex].nAtIndex;

  if (nThrIndex = -1) or (nAtIdx = 0) then
    begin
      Exit(nil);
    end;

  while nAtIdx > 0 do
    begin
      pBlock := @g_DHProfileStack[nThrIndex].pbBlocks[nAtIdx];
      pLastHookJmp := pBlock.ptrLastHookJump;
      if pLastHookJmp <> nil then
        pLastHookJmp^ := pBlock.ptrReturnTarget;
      Dec(nAtIdx)
    end;
  Result := nil;
end;

function DHUnwindExceptionBlock(HookEpilogue: Pointer; EstablisherFrame: NativeUInt; ContextRecord: Pointer; DispatcherContext: Pointer): Pointer;
var
  pContext     : PDispatcherContext;
  ptrStart     : PByte;
  ptrEnd       : PByte;
  nThrIndex    : Integer;
  nAtIdx       : Integer;
  nIndex       : Integer;
  pBlock       : PDHProfileBlock;
  pLastHookJmp : PPointer;
begin
  pContext := PDispatcherContext(DispatcherContext);
  ptrStart := PByte(pContext.ImageBase + pContext.FunctionEntry.FunctionStart);
  ptrEnd := PByte(pContext.ImageBase + pContext.FunctionEntry.FunctionEnd);

  nThrIndex := g_ThreadTranslateT[GetCurrentThreadID].nThreadIndex;
  nAtIdx := g_DHProfileStack[nThrIndex].nAtIndex;

  for nIndex := nAtIdx downto 0 do
    begin
      nAtIdx := -1;
      pBlock := @g_DHProfileStack[nThrIndex].pbBlocks[nIndex];
      pLastHookJmp := pBlock.ptrLastHookJump;

      if pLastHookJmp = nil then
        Break;

      if (PByte(pLastHookJmp^) >= ptrStart) and (PByte(pLastHookJmp^) <= ptrEnd) then
        begin
          nAtIdx := nIndex - 1;
          Break;
        end;

      DHExitProfileBlock;
    end;

  if nAtIdx <> -1 then
    begin
      for nIndex := nAtIdx downto 0 do
        begin
          if pLastHookJmp <> nil then
            pLastHookJmp^ := HookEpilogue;
        end;
    end;
end;

function CyclesToMs(nCycles : Int64): Double;
begin
  Result := (nCycles / g_nCyclesPerSecond) * 1000.0;
end;

function GetRTClock(nFreq : Int64): Int64;
var
  nClock : Int64;
begin
  if QueryPerformanceCounter(nClock)
    then Result := Round(nClock / nFreq * 1000 * 1000 * 1000)
    else Result := 0;
end;

procedure CallibrateTimeStamp;
const
  c_100MilliSecond = 100000000;
var
  nFreq           : Int64;
  nStart          : Int64;
  nTimeStamp      : Int64;
  nStartTimeStamp : Int64;
begin
  QueryPerformanceFrequency(nFreq);
  nStart := GetRTClock(nFreq);
  nStartTimeStamp := ReadTimeStamp;
  nTimeStamp := 0;
  while (GetRTClock(nFreq) - nStart) < c_100MilliSecond do
    nTimeStamp := ReadTimeStamp;

  g_nCyclesPerSecond := (nTimeStamp - nStartTimeStamp) * 10;
end;

procedure PrintDHProfilerResults;
var
  nIndex   : Integer;
  nThrIdx  : Integer;
  prAnchor : PProfileAnchor;
  pRootAnchor : PProfileAnchor;
begin
  for nIndex := 0 to Length(g_DHArrProcedures)-1 do
    begin
      if g_DHArrProcedures[nIndex] = nil then
        continue;
        
      prAnchor := PProfileAnchor(PByte(g_DHArrProcedures[nIndex]) + g_DHProfileStack[0].nAddrOffset);
      pRootAnchor := prAnchor;
      For nThrIdx := 0 to g_ThreadAllocIndex do
        begin
          if prAnchor.nHitCount > 0 then
            begin
              Writeln(
                'ThreadID [' + IntToStr(g_DHProfileStack[nThrIdx].nThreadID) + '] ' +
                'Name=' + PeBorUnmangleName(prAnchor.strName) + #9 +
                //' Addr ' + Uint64(g_TableProfiler[nIndex][nIndex2].nKey).ToString + #9 +
                ' Exclusive=' + CyclesToMs(prAnchor.nElapsedExclusive).ToString + ' ms.' +
                ' w/children=' + CyclesToMs(prAnchor.nElapsedInclusive).ToString + ' ms.' +
                ' HitCount='  + prAnchor.nHitCount.ToString);
            end;
          if (nThrIdx >= 0) and (Length(pRootAnchor.arNextAnchors) > 0) and (nThrIdx < Length(pRootAnchor.arNextAnchors)) then
            begin
              prAnchor := @pRootAnchor.arNextAnchors[nThrIdx];
            end
          else
            Break;
        end;
    end;
  Writeln;
end;

procedure ProfilerSerializeResults(stream : TMemoryStream; writer : TBinaryWriter; bName : Boolean);
var
  nIndex    : Integer;
  prAnchor  : PProfileAnchor;
  nStartPos : Integer;
  nCount    : Cardinal;
  nThrIdx   : Integer;
  pRootAnchor : PProfileAnchor;
begin
  try
  nCount := 0;
  nStartPos := stream.Position;
  writer.Write(Integer(-1));

  writer.Write(g_nCyclesPerSecond);

  for nIndex := 0 to Length(g_DHArrProcedures)-1 do
    begin
      if g_DHArrProcedures[nIndex] = nil then
        continue;

      prAnchor := PProfileAnchor(PByte(g_DHArrProcedures[nIndex]) + g_DHProfileStack[0].nAddrOffset);
      pRootAnchor := prAnchor;      

      For nThrIdx := 0 to g_ThreadAllocIndex do
        begin
          if prAnchor.nHitCount > 0 then
            begin
              Inc(nCount);
              //writer.Write(PeBorUnmangleName(prAnchor.strName));
              if bName  then
                writer.Write(prAnchor.strName);

              writer.Write(Uint64(prAnchor));
              writer.Write(g_DHProfileStack[nThrIdx].nThreadID);
              writer.Write(prAnchor.nElapsedExclusive);
              writer.Write(prAnchor.nElapsedInclusive);
              writer.Write(prAnchor.nHitCount);
            end;          
          if (nThrIdx >= 0) and (Length(pRootAnchor.arNextAnchors) > 0) and (nThrIdx < Length(pRootAnchor.arNextAnchors)) then
            prAnchor := @pRootAnchor.arNextAnchors[nThrIdx]
          else
            Break;
        end;
    end;

  PCardinal(PByte(stream.Memory) + nStartPos)^ := nCount;
  except
    on E: Exception do
      begin
        LogDebug('Serializing result Exception=%s Anchor=%p Stack=%s', [E.Message, prAnchor, E.StackTrace]);
        LogDebug('AddrOffset=%x %p %d %p %d %d', [ g_DHProfileStack[0].nAddrOffset, PByte(g_DHArrProcedures[nIndex]), prAnchor.nHitCount, g_DHArrProcedures[nIndex], nThrIdx, Length(pRootAnchor.arNextAnchors)]);
      end;
  end;
end;

procedure PrintLengthOfAnchors;
var
  nIndex    : Integer;
  prAnchor  : PProfileAnchor;
  nStartPos : Integer;
  nCount    : Cardinal;
  nThrIdx   : Integer;
  pRootAnchor : PProfileAnchor;
begin
  nCount := 0;
  LogDebug('-------- Procedure Count= %d', [Length(g_DHArrProcedures)]);
  for nIndex := 0 to Length(g_DHArrProcedures)-1 do
    begin
      if g_DHArrProcedures[nIndex] = nil then
        continue;

      prAnchor := PProfileAnchor(PByte(g_DHArrProcedures[nIndex]) + g_DHProfileStack[0].nAddrOffset);
      pRootAnchor := prAnchor;
      LogDebug('Anchor=%p Lenght=%d', [g_DHArrProcedures[nIndex], Length(pRootAnchor.arNextAnchors)]);      
    end;
end;

initialization
  ZeroMemory(@g_DHProfileStack[0], sizeof(g_DHProfileStack));
  CallibrateTimeStamp;
end.
