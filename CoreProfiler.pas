unit CoreProfiler;

interface

const
  c_ProfilerStackSize = 1024*64;

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
    strName           : String;
  end;
  PProfileAnchor = ^TProfileAnchor;

  THashEntry = record
    nHash    : Int64;
    nKey     : Pointer;
    prAnchor : TProfileAnchor;
  end;

  TProfileBlock = record
    nParentIndex       : Integer;
    nAnchorIndex       : Integer;
    nStartTime         : Uint64;
    nPrevTimeInclusive : Uint64;
  end;
  PProfileBlock = ^TProfileBlock;

  TProfilerStack = record
    pbBlocks : array [0..c_ProfilerStackSize-1] of TProfileBlock;
    nAtIndex : Integer;
  end;

implementation
uses
  Utils,
  Windows,
  SysUtils;

var
  g_TableProfiler    : array of THashEntry;
  g_ProfileStack     : TProfilerStack;
  g_nCyclesPerSecond : Int64;

procedure InitializeGlobalProfilerTable(nCountEntries : Integer);
begin
  SetLength(g_TableProfiler, nCountEntries * 8);
  ZeroMemory(@g_TableProfiler[0], Length(g_TableProfiler) * sizeof(g_TableProfiler[0]));

  ZeroMemory(@g_ProfileStack.pbBlocks[0], Length(g_ProfileStack.pbBlocks) * sizeof(g_ProfileStack.pbBlocks[0]));
  g_ProfileStack.nAtIndex := 0;
end;

function CalculateAnchorIndex(nPow2 : Integer; nHash : Uint64): Integer;
asm
  xor rax, rax
  not rax
  shl rax, cl
  not rax
  and rax, nHash
end;

procedure EnterProfileBlock(nAddr : Pointer);
var
  pBlock       : PProfileBlock;
  pAnchor      : PProfileAnchor;
  nAtIdx       : Integer;
  nParentIndex : Integer;
  nAnchorIndex : Integer;
begin
  Inc(g_ProfileStack.nAtIndex);
  nAtIdx := g_ProfileStack.nAtIndex;

  pBlock := @g_ProfileStack.pbBlocks[nAtIdx];
  pBlock.nParentIndex := g_ProfileStack.pbBlocks[nAtIdx-1].nAnchorIndex;
  pBlock.nAnchorIndex := CalculateAnchorIndex(13, HashPointer(nAddr));
  pAnchor := @g_TableProfiler[pBlock.nAnchorIndex].prAnchor;
  g_TableProfiler[pBlock.nAnchorIndex].nKey := nAddr; // Not needed
  pBlock.nPrevTimeInclusive := pAnchor.nElapsedInclusive;
  pBlock.nStartTime := ReadTimeStamp;
end;

procedure ExitProfileBlock;
var
  nAtIdx   : Integer;
  pBlock   : PProfileBlock;
  pAnchor  : PProfileAnchor;
  pParent  : PProfileAnchor;
  nElapsed : Uint64;
begin
  nElapsed := ReadTimeStamp;

  nAtIdx := g_ProfileStack.nAtIndex;
  pBlock := @g_ProfileStack.pbBlocks[nAtIdx];
  Dec(g_ProfileStack.nAtIndex);

  nElapsed := nElapsed - pBlock.nStartTime;

  pAnchor := @g_TableProfiler[pBlock.nAnchorIndex].prAnchor;
  pParent := @g_TableProfiler[pBlock.nParentIndex].prAnchor;

  pParent.nElapsedExclusive := pParent.nElapsedExclusive - nElapsed;
  pAnchor.nElapsedExclusive := pAnchor.nElapsedExclusive + nElapsed;
  pAnchor.nElapsedInclusive := pBlock.nPrevTimeInclusive + nElapsed;

  Inc(pAnchor.nHitCount);
end;  

function CyclesToMs(nCycles : Int64): Double;
begin
  Result := (nCycles / g_nCyclesPerSecond) * 1000.0;
end;

procedure PrintProfilerResults;
var
  nIndex   : Integer;
  prAnchor : PProfileAnchor;
begin
  for nIndex := 0 to Length(g_TableProfiler)-1 do
    begin
      if g_TableProfiler[nIndex].prAnchor.nHitCount > 0 then
        begin
          prAnchor := @g_TableProfiler[nIndex].prAnchor;
          Writeln('Addr ' + Uint64(g_TableProfiler[nIndex].nKey).ToString + #9 +
            ' Inclusive=' + CyclesToMs(prAnchor.nElapsedInclusive).ToString + ' ms.' +
            ' Exclusive=' + CyclesToMs(prAnchor.nElapsedExclusive).ToString + ' ms.' +
            ' HitCount='  + prAnchor.nHitCount.ToString);
        end;
    end;
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

procedure TestHash;
var
  nIndex: Integer;
begin
  CallibrateTimeStamp;
  InitializeGlobalProfilerTable(1024);

  EnterProfileBlock(Pointer($123));
    Sleep(500);
    EnterProfileBlock(Pointer($1234));
      Sleep(1000);
      EnterProfileBlock(Pointer($123));
        Sleep(300);        
      ExitProfileBlock;
    ExitProfileBlock;
  ExitProfileBlock;

  PrintProfilerResults;
end;

initialization
  TestHash;
end.
