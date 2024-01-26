unit CoreProfiler;

interface

const
  c_ProfilerStackSize = 1024*64;  // 64 kB

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
    ptrExecBuffer     : Pointer;
    strName           : String;
  end;
  PProfileAnchor = ^TProfileAnchor;

  // Indirect Hashing
  THashEntry = record
    nHash    : Int64;
    nKey     : Pointer;
    prAnchor : TProfileAnchor;
  end;
  PHashEntry = ^THashEntry;
  THashEntryArr = array [0..3] of THashEntry;

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

  TProfilerStack = record
    pbBlocks : array [0..c_ProfilerStackSize-1] of TProfileBlock;
    nAtIndex : Integer;
  end;

  // Direct hashing
  TDHProfileBlock = record
    pParentAnchor      : PProfileAnchor;
    pAnchor            : PProfileAnchor;
    nStartTime         : Uint64;
    nPrevTimeInclusive : Uint64;
    ptrReturnTarget    : Pointer;
  end;
  PDHProfileBlock = ^TDHProfileBlock;

  TDHProfilerStack = record
    pbBlocks    : array [0..c_ProfilerStackSize-1] of TDHProfileBlock;
    nAddrOffset : Int64;
    nAtIndex    : Integer;
  end;

  procedure EnterProfileBlock(nAddr : Pointer);
  function  ExitProfileBlock: Pointer;
  function  FindAnchor(nAddr : Pointer): PProfileAnchor;

  procedure DHEnterProfileBlock(nAddr : Pointer);
  function  DHExitProfileBlock: Pointer;
  procedure InitializeDHProfilerTable(pAnchor : Pointer; nOffsetFromModuleBase : Int64);

  procedure PrintProfilerResults;
  procedure PrintDHProfilerResults;

var
  EpilogueJump : Pointer; // TODO(psv): Make it Thread safe
  g_DHArrProcedures  : array of Pointer;

implementation
uses
  Utils,
  Windows,
  SysUtils;

var
  g_TableProfiler    : array of THashEntryArr;
  g_DHTableProfiler  : Pointer;
  g_ProfileStack     : TProfilerStack;
  g_DHProfileStack   : TDHProfilerStack;
  g_nCyclesPerSecond : Int64;

procedure InitializeGlobalProfilerTable(nCountEntries : Integer);
begin
  SetLength(g_TableProfiler, nCountEntries * 8);
  ZeroMemory(@g_TableProfiler[0], Length(g_TableProfiler) * sizeof(g_TableProfiler[0]));

  ZeroMemory(@g_ProfileStack.pbBlocks[0], Length(g_ProfileStack.pbBlocks) * sizeof(g_ProfileStack.pbBlocks[0]));
  g_ProfileStack.nAtIndex := 0;
end;

procedure InitializeDHProfilerTable(pAnchor : Pointer; nOffsetFromModuleBase : Int64);
begin
  g_DHProfileStack.pbBlocks[0].pAnchor := PProfileAnchor(PByte(pAnchor) - sizeof(TProfileAnchor));
  g_DHProfileStack.pbBlocks[0].pParentAnchor := PProfileAnchor(PByte(pAnchor) - sizeof(TProfileAnchor));
  g_DHTableProfiler := pAnchor;
  g_DHProfileStack.nAddrOffset := nOffsetFromModuleBase;
end;

function FindAnchor(nAddr : Pointer): PProfileAnchor;
var
  nIndex       : Integer;
  nAnchorIndex : Integer;
  ptHashEntry  : PHashEntry;
begin
  Result := nil;
  nAnchorIndex := CalculateAnchorIndex(13, HashPointer(nAddr));  
  ptHashEntry := @g_TableProfiler[nAnchorIndex][0];
  if ptHashEntry.nKey = nil then
    begin
      ptHashEntry.nKey := nAddr;
      Result := @ptHashEntry.prAnchor;
    end
  else
    begin        
      for nIndex := 1 to Length(g_TableProfiler[nAnchorIndex])-1 do
        begin
          ptHashEntry := @g_TableProfiler[nAnchorIndex][nIndex];
          if ptHashEntry.nKey = nAddr then
            begin
              Result := @ptHashEntry.prAnchor;
              Break;
            end;            
        end;
    end;
end;

procedure EnterProfileBlock(nAddr : Pointer);
var
  pBlock       : PProfileBlock;
  pAnchor      : PProfileAnchor;
  ptHashEntry  : PHashEntry;
  nAtIdx       : Integer;
  nIndex       : Integer;
begin
  Inc(g_ProfileStack.nAtIndex);
  nAtIdx := g_ProfileStack.nAtIndex;

  pBlock := @g_ProfileStack.pbBlocks[nAtIdx];
  pBlock.nParentIndex := g_ProfileStack.pbBlocks[nAtIdx-1].nAnchorIndex;
  pBlock.nParentSecondIndex := g_ProfileStack.pbBlocks[nAtIdx-1].nSecondIndex;
  pBlock.nAnchorIndex := CalculateAnchorIndex(13, HashPointer(nAddr));  
  pBlock.ptrReturnTarget := EpilogueJump;
  ptHashEntry := @g_TableProfiler[pBlock.nAnchorIndex][0];

  if ptHashEntry.nKey = nAddr then
    begin
      pBlock.nSecondIndex := 0;
      pAnchor := @ptHashEntry.prAnchor;
    end
  else
    begin
      Assert(ptHashEntry.nKey <> nil);     
      for nIndex := 1 to Length(g_TableProfiler[pBlock.nAnchorIndex])-1 do
        begin
          ptHashEntry := @g_TableProfiler[pBlock.nAnchorIndex][nIndex];
          if ptHashEntry.nKey = nAddr then
            begin
              pAnchor := @ptHashEntry.prAnchor;
              pBlock.nSecondIndex := nIndex;
              Break;
            end;            
        end;
    end;

  pBlock.nPrevTimeInclusive := pAnchor.nElapsedInclusive;
  pBlock.nStartTime := ReadTimeStamp;
end;

function ExitProfileBlock: Pointer;
var
  nAtIdx      : Integer;
  pBlock      : PProfileBlock;
  pAnchor     : PProfileAnchor;
  pParent     : PProfileAnchor;
  nElapsed    : Uint64;
begin
  nElapsed := ReadTimeStamp;

  nAtIdx := g_ProfileStack.nAtIndex;
  pBlock := @g_ProfileStack.pbBlocks[nAtIdx];
  Dec(g_ProfileStack.nAtIndex);

  nElapsed := nElapsed - pBlock.nStartTime;

  pAnchor := @g_TableProfiler[pBlock.nAnchorIndex][pBlock.nParentSecondIndex].prAnchor;  
  pParent := @g_TableProfiler[pBlock.nParentIndex][pBlock.nSecondIndex].prAnchor;

  pParent.nElapsedExclusive := pParent.nElapsedExclusive - nElapsed;
  pAnchor.nElapsedExclusive := pAnchor.nElapsedExclusive + nElapsed;
  pAnchor.nElapsedInclusive := pBlock.nPrevTimeInclusive + nElapsed;

  Inc(pAnchor.nHitCount);

  Result := pBlock.ptrReturnTarget;
end;

// Direct hashed anchored profiler

procedure DHEnterProfileBlock(nAddr : Pointer);
var
  pBlock       : PDHProfileBlock;
  nAtIdx       : Integer;
begin
  Inc(g_DHProfileStack.nAtIndex);
  nAtIdx := g_DHProfileStack.nAtIndex;

  pBlock := @g_DHProfileStack.pbBlocks[nAtIdx];
  pBlock.pParentAnchor := g_DHProfileStack.pbBlocks[nAtIdx-1].pParentAnchor;
  pBlock.pAnchor := PProfileAnchor(PByte(nAddr) + g_DHProfileStack.nAddrOffset);
  pBlock.ptrReturnTarget := EpilogueJump;

  pBlock.nPrevTimeInclusive := pBlock.pAnchor.nElapsedInclusive;
  pBlock.nStartTime := ReadTimeStamp;
end;

function DHExitProfileBlock: Pointer;
var
  nAtIdx      : Integer;
  pBlock      : PDHProfileBlock;
  nElapsed    : Uint64;
begin
  nElapsed := ReadTimeStamp;

  nAtIdx := g_DHProfileStack.nAtIndex;
  pBlock := @g_DHProfileStack.pbBlocks[nAtIdx];
  Dec(g_DHProfileStack.nAtIndex);

  nElapsed := nElapsed - pBlock.nStartTime;

  pBlock.pParentAnchor.nElapsedExclusive := pBlock.pParentAnchor.nElapsedExclusive - nElapsed;
  pBlock.pAnchor.nElapsedExclusive := pBlock.pAnchor.nElapsedExclusive + nElapsed;
  pBlock.pAnchor.nElapsedInclusive := pBlock.nPrevTimeInclusive + nElapsed;

  Inc(pBlock.pAnchor.nHitCount);

  Result := pBlock.ptrReturnTarget;
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

procedure PrintProfilerResults;
var
  nIndex   : Integer;
  nIndex2  : Integer;
  prAnchor : PProfileAnchor;
begin
  CallibrateTimeStamp;
  for nIndex := 0 to Length(g_TableProfiler)-1 do
    begin
      for nIndex2 := 0 to Length(g_TableProfiler[nIndex])-1 do
        begin
          if g_TableProfiler[nIndex][nIndex2].prAnchor.nHitCount > 0 then
            begin
              prAnchor := @g_TableProfiler[nIndex][nIndex2].prAnchor;
              Writeln(
                'Name=' + prAnchor.strName + #9 +
                //' Addr ' + Uint64(g_TableProfiler[nIndex][nIndex2].nKey).ToString + #9 +            
                ' Exclusive=' + CyclesToMs(prAnchor.nElapsedExclusive).ToString + ' ms.' +
                ' w/children=' + CyclesToMs(prAnchor.nElapsedInclusive).ToString + ' ms.' +
                ' HitCount='  + prAnchor.nHitCount.ToString);
            end;
        end;
    end;
end;

procedure PrintDHProfilerResults;
var
  nIndex   : Integer;
  nIndex2  : Integer;
  prAnchor : PProfileAnchor;
begin
  CallibrateTimeStamp;

  for nIndex := 1 to Length(g_DHArrProcedures)-1 do
    begin
      if g_DHArrProcedures[nIndex] = nil then
        continue;
      prAnchor := PProfileAnchor(PByte(g_DHArrProcedures[nIndex]) + g_DHProfileStack.nAddrOffset);
      if prAnchor.nHitCount > 0 then
        begin
          Writeln(
            '[' + IntToStr(nIndex) + '] ' +
            'Name=' + prAnchor.strName + #9 +
            //' Addr ' + Uint64(g_TableProfiler[nIndex][nIndex2].nKey).ToString + #9 +
            ' Exclusive=' + CyclesToMs(prAnchor.nElapsedExclusive).ToString + ' ms.' +
            ' w/children=' + CyclesToMs(prAnchor.nElapsedInclusive).ToString + ' ms.' +
            ' HitCount='  + prAnchor.nHitCount.ToString);
        end;
    end;
end;

initialization
  InitializeGlobalProfilerTable(1024);
end.
