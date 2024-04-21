unit CoreProfiler;

interface
uses
  SyncObjs,
  Windows,
  Generics.Collections,
  Classes;

const
  c_ProfilerStackSize = 1024*128;  // 128kb
  c_AnchorBundleCount = 8;

type
  TProfileBucket = record
    nElapsedExclusive : Uint64;
    nElapsedInclusive : Uint64;
    strName           : String;
  end;

  PAnchorBundle = ^TAnchorBundle;

  TProfileAnchor = record
    nElapsedExclusive : UInt64;
    nElapsedInclusive : UInt64;
    nHitCount         : UInt64;
    ptrNextAnchors    : PAnchorBundle;
    nThreadID         : Integer;
    nLine             : Integer;
    strName           : String;
    pAddr             : Pointer;
  end;
  PProfileAnchor = ^TProfileAnchor;

  TAnchorBundle = record
    arAnchors   : array [0..c_AnchorBundleCount-1] of TProfileAnchor;
    nFirstIndex : Cardinal;
    ptrNext     : PAnchorBundle;
  end;

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

  procedure DHEnterProfileBlock(nAddr : Pointer);
  function  DHExitProfileBlock: Pointer;
  function  DHUnwindExceptionBlock(HookEpilogue: Pointer; EstablisherFrame: NativeUInt; ContextRecord: Pointer; DispatcherContext: Pointer): Pointer;
  function  DHUnwindEveryStack: Pointer;
  procedure InitializeDHProfilerTable(pAnchor : Pointer; nOffsetFromModuleBase : Int64);
  procedure ProfilerSerializeResults(stream : TMemoryStream; writer : TBinaryWriter; bName : Boolean);
  procedure ProfilerClearResults;
  function  CyclesToMs(nCycles : Int64): Double;

  procedure PrintDHProfilerResults;

var
  g_DHArrProcedures  : array of Pointer;
  g_Pipe : THandle;
  g_ThreadTranslateT : array [0..1024*1024-1] of TThrTranslate; // ThreadID translation table (supports 1 million threads)
  g_AntipessimizerGuiWindow : HWND;

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

{$OVERFLOWCHECKS OFF}

procedure InitializeDHProfilerTable(pAnchor : Pointer; nOffsetFromModuleBase : Int64);
var
  nIndex : Integer;
begin
  g_DHProfileStack[0].pbBlocks[0].pAnchor := PProfileAnchor(PByte(pAnchor) - sizeof(TProfileAnchor));
  g_DHProfileStack[0].pbBlocks[0].pParentAnchor := PProfileAnchor(PByte(pAnchor) - sizeof(TProfileAnchor));
  g_DHTableProfiler := pAnchor;
  g_DHProfileStack[0].nAddrOffset := nOffsetFromModuleBase;
  g_DHProfileStack[0].nAtIndex := 0;
  for nIndex := 0 to Length(g_DHProfileStack)-1 do
    g_DHProfileStack[nIndex].nAtIndex := 0;

  ZeroMemory(@g_ThreadTranslateT[0], sizeof(g_ThreadTranslateT));
  For nIndex := 0 to Length(g_ThreadTranslateT)-1 do
    g_ThreadTranslateT[nIndex].nThreadIndex := -1;
  LogDebug('### InitializeDHProfilerTable ### OffsetFromModuleBase=%x', [nOffsetFromModuleBase]);
end;

function FindAnchor(bundle : PAnchorBundle; nIndex : Cardinal): PProfileAnchor;
begin
  Result := nil;
  while bundle <> nil do
    begin
      if (nIndex >= bundle.nFirstIndex) and (nIndex < (bundle.nFirstIndex + c_AnchorBundleCount)) then
        begin
          Result := @bundle.arAnchors[nIndex mod c_AnchorBundleCount];
          Exit(Result);
        end;

      bundle := bundle.ptrNext;
    end;
end;

function FindOrAllocateAnchor(var profAnchor : TProfileAnchor; var poutAnchor : PProfileAnchor; nIndex : Integer): Integer;
var
  pBundle : PAnchorBundle;
  pAnchor : PProfileAnchor;
  bundle  : PAnchorBundle;
  bPrev   : PAnchorBundle;
begin
  nIndex := nIndex - 1;
  Result := nIndex;

  pAnchor := FindAnchor(profAnchor.ptrNextAnchors, nIndex);
  if pAnchor = nil then
    begin
      pBundle := AllocMem(sizeof(TAnchorBundle));
      ZeroMemory(pBundle, sizeof(TAnchorBundle));
      pBundle.nFirstIndex := (nIndex div c_AnchorBundleCount) * c_AnchorBundleCount;
      pBundle.ptrNext := nil;
      pAnchor := @pBundle.arAnchors[nIndex mod c_AnchorBundleCount];

      if profAnchor.ptrNextAnchors = nil then
        begin
          // Insert at the beginning since there is no other link in the chain
          InterlockedCompareExchangePointer(Pointer(profAnchor.ptrNextAnchors), Pointer(pBundle), nil);
          if Pointer(profAnchor.ptrNextAnchors) = Pointer(pBundle) then
            begin
              // Success, we were able to perform the allocation, return the value
              poutAnchor := pAnchor;
              Exit(nIndex + 1);
            end
          else
            begin
              // Somebody else managed to allocate it first, try it again
              Dispose(pBundle);
              Exit(-1);
            end;
        end
      else
        begin
          bundle := profAnchor.ptrNextAnchors;

          if bundle.nFirstIndex > pBundle.nFirstIndex then
            begin
              // Insert at the beginning
              pBundle.ptrNext := profAnchor.ptrNextAnchors;
              InterlockedCompareExchangePointer(Pointer(profAnchor.ptrNextAnchors), Pointer(pBundle), pBundle.ptrNext);
              if Pointer(profAnchor.ptrNextAnchors) = Pointer(pBundle) then
                begin
                  // Success, we were able to perform the allocation, return the value
                  poutAnchor := pAnchor;
                  Exit(nIndex + 1);
                end
              else
                begin
                  // Somebody else managed to allocate it first, try it again
                  Dispose(pBundle);
                  Exit(-1);
                end;
            end;

          bPrev := nil;

          // Need to find where to insert
          while bundle <> nil do
            begin
              if (bundle.nFirstIndex > pBundle.nFirstIndex) then
                begin
                  // Insert before this one
                  pBundle.ptrNext := bPrev.ptrNext;
                  InterlockedCompareExchangePointer(Pointer(bPrev.ptrNext), Pointer(pBundle), pBundle.ptrNext);
                  if Pointer(bPrev.ptrNext) = Pointer(pBundle) then
                    begin
                      // Success, we were able to perform the allocation, return the value
                      poutAnchor := pAnchor;
                      Exit(nIndex + 1);
                    end
                  else
                    begin
                      // Somebody else managed to allocate it first, try it again
                      Dispose(pBundle);
                      Exit(-1);
                    end;
                end;

              if bundle.ptrNext = nil then
                begin
                  // Insert at the end
                  InterlockedCompareExchangePointer(Pointer(bundle.ptrNext), Pointer(pBundle), nil);
                  if Pointer(bundle.ptrNext) = Pointer(pBundle) then
                    begin
                      // Success, we were able to perform the allocation, return the value
                      poutAnchor := pAnchor;
                      Exit(nIndex + 1);
                    end
                  else
                    begin
                      // Somebody else managed to allocate it first, try it again
                      Dispose(pBundle);
                      Exit(-1);
                    end;
                end;
              bPrev  := bundle;
              bundle := bundle.ptrNext;
            end;
        end;
    end
  else
    begin
      poutAnchor := pAnchor;
      Result := nIndex + 1;
    end;
end;

// Direct hashed anchored profiler
function GetLocationFromThreadID(nAddr : Pointer; nThreadID : Integer; var pAnchor : PProfileAnchor; var pEpilogueJmp : Pointer): Integer;
var
  nIndex   : Integer;
  pResAnchor : PProfileAnchor;
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
      pResAnchor := nil;
      while FindOrAllocateAnchor(pAnchor^, pResAnchor, nIndex) < 0 do;

      if pResAnchor = nil then
        LogDebug('Error could not create anchorfor ThreadIndex %d', [nIndex])
      else
        begin
          pAnchor := pResAnchor;
          if pAnchor.pAddr = nil then
            begin
              pAnchor.strName := PProfileAnchor(PByte(nAddr) + g_DHProfileStack[0].nAddrOffset).strName;
              pAnchor.pAddr := PProfileAnchor(PByte(nAddr) + g_DHProfileStack[0].nAddrOffset).pAddr;
              pAnchor.nThreadID := nThreadID;
            end;
        end;
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

  //LogDebug(' Enter - ThreadIndex=%d ThreadID=%d AtIdx=%d Block=%p %d %s', [nThrIdx, GetCurrentThreadID, nAtIdx, pBlock, GetCurrentThreadID, pBlock.pAnchor.strName]);
  //SendMessage(g_AntipessimizerGuiWindow, 1024, WPARAM(nAddr), $200000 or GetCurrentThreadID);

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
      Exit(nil);

    nAtIdx := g_DHProfileStack[nThrIndex].nAtIndex;
    pBlock := @g_DHProfileStack[nThrIndex].pbBlocks[nAtIdx];

    //SendMessage(g_AntipessimizerGuiWindow, 1024, WPARAM(pBlock.pAnchor.pAddr), $100000 or GetCurrentThreadID);
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
        //LogDebug(' Exit - ThreadIndex=%d AtIdx=%d Block=%p ThreadID=%d Anchor=%p', [nThrIndex, nAtIdx, pBlock, GetCurrentThreadID, pBlock.pAnchor]);
        Result := nil;
      end;
  end;
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
  g_DHProfileStack[nThrIndex].bUnwinding := True;

  if (nThrIndex = -1) or (nAtIdx <= 0) then
    begin
      Exit(nil);
    end;

  while nAtIdx >= 0 do
    begin
      pBlock := @g_DHProfileStack[nThrIndex].pbBlocks[nAtIdx];
      pLastHookJmp := pBlock.ptrLastHookJump;
      if pLastHookJmp <> nil then
        begin
          pLastHookJmp^ := pBlock.ptrReturnTarget;
          //SendMessage(g_AntipessimizerGuiWindow, 1024, WPARAM(pLastHookJmp), $100000 or GetCurrentThreadID);
        end;
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
  bFound       : Boolean;
begin
  Result := nil;
  pContext := PDispatcherContext(DispatcherContext);
  ptrStart := PByte(pContext.ImageBase + pContext.FunctionEntry.FunctionStart);
  ptrEnd := PByte(pContext.ImageBase + pContext.FunctionEntry.FunctionEnd);

  nThrIndex := g_ThreadTranslateT[GetCurrentThreadID].nThreadIndex;
  if nThrIndex < 0 then
    Exit(nil);
  nAtIdx := g_DHProfileStack[nThrIndex].nAtIndex;
  if nAtIdx < 0 then
    Exit(nil);

  if g_DHProfileStack[nThrIndex].bUnwinding then
    g_DHProfileStack[nThrIndex].bUnwinding := False
  else
    Exit(nil);

  //SendMessage(g_AntipessimizerGuiWindow, 1024, nThrIndex, nAtIdx);

  bFound := False;
  for nIndex := nAtIdx downto 0 do
    begin
      nAtIdx := -1;
      pBlock := @g_DHProfileStack[nThrIndex].pbBlocks[nIndex];
      pLastHookJmp := pBlock.ptrLastHookJump;

      if pLastHookJmp = nil then
        Break;

      //SendMessage(g_AntipessimizerGuiWindow, 1024, WPARAM(pLastHookJmp^), $1000);
      //DHExitProfileBlock;

      if (PByte(pLastHookJmp^) >= ptrStart) and (PByte(pLastHookJmp^) <= ptrEnd) then
        begin
          nAtIdx := nIndex - 1;
          bFound := True;
          Break;
        end;
    end;

  if (nAtIdx <> -1) and bFound then
    begin
      for nIndex := g_DHProfileStack[nThrIndex].nAtIndex downto 0 do
        begin
          if nIndex < nAtIdx then
            begin          
              pBlock := @g_DHProfileStack[nThrIndex].pbBlocks[nIndex];
              pLastHookJmp := pBlock.ptrLastHookJump;

              if pLastHookJmp <> nil then
                begin
                  //SendMessage(g_AntipessimizerGuiWindow, 1024, WPARAM(pLastHookJmp^), 1000);
                  pLastHookJmp^ := HookEpilogue;
                end;
            end
          else
            DHExitProfileBlock;
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
  bundle   : PAnchorBundle;
  nBundleIndex : Integer;
begin
  for nIndex := 0 to Length(g_DHArrProcedures)-1 do
    begin
      if g_DHArrProcedures[nIndex] = nil then
        continue;
        
      prAnchor := PProfileAnchor(PByte(g_DHArrProcedures[nIndex]) + g_DHProfileStack[0].nAddrOffset);

      nBundleIndex := 0;
      nThrIdx := 0;
      bundle := prAnchor.ptrNextAnchors;

      repeat
        repeat
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

          if bundle <> nil then
            begin
              if nBundleIndex < c_AnchorBundleCount then
                begin
                  prAnchor := @bundle.arAnchors[nBundleIndex];
                  Inc(nBundleIndex);
                end
              else
                begin
                  bundle := bundle.ptrNext;
                  if bundle <> nil then
                    begin
                      nBundleIndex := 0;
                      prAnchor := @bundle.arAnchors[nBundleIndex];
                    end;
                end;
              if bundle <> nil then
                nThrIdx := nBundleIndex + Integer(bundle.nFirstIndex);
            end
          else
            prAnchor := nil;
        until prAnchor = nil;
      until bundle = nil;
    end;
  Writeln;
end;

procedure ProfilerClearResults;
var
  nIndex       : Integer;
  nBundleIndex : Integer;
  nThrIdx      : Integer;
  prAnchor     : PProfileAnchor;
  bundle       : PAnchorBundle;
begin
  LogDebug('proc count %d', [Length(g_DHArrProcedures)]);
  for nIndex := 0 to Length(g_DHArrProcedures)-1 do
    begin
      if g_DHArrProcedures[nIndex] = nil then
        continue;

      prAnchor := PProfileAnchor(PByte(g_DHArrProcedures[nIndex]) + g_DHProfileStack[0].nAddrOffset);

      bundle := prAnchor.ptrNextAnchors;

      repeat
        repeat
          LogDebug('Clear %s %d', [prAnchor.strName, prAnchor.nElapsedExclusive]);
          prAnchor.nHitCount := 0;
          prAnchor.nElapsedExclusive := 0;
          prAnchor.nElapsedInclusive := 0;
          //prAnchor.nThreadID := -1;
          //prAnchor.pAddr := nil;

          if bundle <> nil then
            begin
              if nBundleIndex < c_AnchorBundleCount then
                begin
                  prAnchor := @bundle.arAnchors[nBundleIndex];
                  Inc(nBundleIndex);
                end
              else
                begin
                  bundle := bundle.ptrNext;
                  if bundle <> nil then
                    begin
                      nBundleIndex := 0;
                      prAnchor := @bundle.arAnchors[nBundleIndex];
                    end;
                end;
              if bundle <> nil then
                nThrIdx := nBundleIndex + Integer(bundle.nFirstIndex);
            end
          else
            prAnchor := nil;
        until prAnchor = nil;
      until bundle = nil;
    end;
end;

procedure ProfilerSerializeResults(stream : TMemoryStream; writer : TBinaryWriter; bName : Boolean);
var
  nIndex    : Integer;
  prAnchor  : PProfileAnchor;
  nStartPos : Integer;
  nCount    : Cardinal;
  nThrIdx   : Integer;
  pRootAnchor  : PProfileAnchor;
  bundle       : PAnchorBundle;
  nBundleIndex : Integer;
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

      nBundleIndex := 0;
      nThrIdx := 0;
      bundle := prAnchor.ptrNextAnchors;

      repeat
        repeat
          if prAnchor.nHitCount > 0 then
            begin
              Inc(nCount);

              if bName  then
                writer.Write(prAnchor.strName);

              writer.Write(Uint64(prAnchor));
              writer.Write(g_DHProfileStack[nThrIdx].nThreadID);
              writer.Write(prAnchor.nElapsedExclusive);
              writer.Write(prAnchor.nElapsedInclusive);
              writer.Write(prAnchor.nHitCount);
            end;

          if bundle <> nil then
            begin
              if nBundleIndex < c_AnchorBundleCount then
                begin
                  prAnchor := @bundle.arAnchors[nBundleIndex];
                  Inc(nBundleIndex);
                end
              else
                begin
                  bundle := bundle.ptrNext;
                  if bundle <> nil then
                    begin
                      nBundleIndex := 0;
                      prAnchor := @bundle.arAnchors[nBundleIndex];
                    end;
                end;
              if bundle <> nil then
                nThrIdx := nBundleIndex + Integer(bundle.nFirstIndex);
            end
          else
            prAnchor := nil;
        until prAnchor = nil;
      until bundle = nil;
    end;

  PCardinal(PByte(stream.Memory) + nStartPos)^ := nCount;

  //LogDebug('Stream size=%d %d', [PInteger(PByte(stream.Memory))^, PCardinal(PByte(stream.Memory) + nStartPos)^]);
  except
    on E: Exception do
      begin
        LogDebug('Serializing result Exception=%s Stack=%s', [E.Message, E.StackTrace]);
      end;
  end;
end;

initialization
  g_AntipessimizerGuiWindow := FindWindow('AntiPessimizerClass', nil);
  ZeroMemory(@g_DHProfileStack[0], sizeof(g_DHProfileStack));
  CallibrateTimeStamp;
end.
