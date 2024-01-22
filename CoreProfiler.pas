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
  end;
  PProfileBlock = ^TProfileBlock;

  TProfilerStack = record
    pbBlocks : array [0..c_ProfilerStackSize-1] of TProfileBlock;
    nAtIndex : Integer;
  end;

  procedure EnterProfileBlock(nAddr : Pointer);
  procedure ExitProfileBlock;
  procedure PrintProfilerResults;
  function  FindAnchor(nAddr : Pointer): PProfileAnchor;

implementation
uses
  Utils,
  Windows,
  SysUtils;

var
  g_TableProfiler    : array of THashEntryArr;
  g_ProfileStack     : TProfilerStack;
  g_nCyclesPerSecond : Int64;

procedure InitializeGlobalProfilerTable(nCountEntries : Integer);
begin
  SetLength(g_TableProfiler, nCountEntries * 8);
  ZeroMemory(@g_TableProfiler[0], Length(g_TableProfiler) * sizeof(g_TableProfiler[0]));

  ZeroMemory(@g_ProfileStack.pbBlocks[0], Length(g_ProfileStack.pbBlocks) * sizeof(g_ProfileStack.pbBlocks[0]));
  g_ProfileStack.nAtIndex := 0;
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
  nParentIndex : Integer;
  nAnchorIndex : Integer;
  nIndex       : Integer;
begin
  Inc(g_ProfileStack.nAtIndex);
  nAtIdx := g_ProfileStack.nAtIndex;

  pBlock := @g_ProfileStack.pbBlocks[nAtIdx];
  pBlock.nParentIndex := g_ProfileStack.pbBlocks[nAtIdx-1].nAnchorIndex;
  pBlock.nParentSecondIndex := g_ProfileStack.pbBlocks[nAtIdx-1].nSecondIndex;
  pBlock.nAnchorIndex := CalculateAnchorIndex(13, HashPointer(nAddr));  
  ptHashEntry := @g_TableProfiler[pBlock.nAnchorIndex][0];

  if ptHashEntry.nKey = nAddr then
    begin
      pBlock.nSecondIndex := 0;
      pAnchor := @ptHashEntry.prAnchor;
    end
  else
    begin    
      if ptHashEntry.nKey = nil then
        begin
          ptHashEntry.nKey := nAddr;
          pBlock.nSecondIndex := 0;
          pAnchor := @ptHashEntry.prAnchor;
        end
      else
        begin        
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
    end;

  pBlock.nPrevTimeInclusive := pAnchor.nElapsedInclusive;
  pBlock.nStartTime := ReadTimeStamp;
end;

procedure ExitProfileBlock;
var
  nAtIdx      : Integer;
  ptHashEntry : PHashEntry;
  pBlock      : PProfileBlock;
  pAnchor     : PProfileAnchor;
  pParent     : PProfileAnchor;
  nElapsed    : Uint64;
  nIndex      : Integer;
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

initialization
  InitializeGlobalProfilerTable(1024);
end.
