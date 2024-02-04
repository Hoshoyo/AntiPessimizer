unit CoreProfiler;

interface
uses
  Classes;

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
  end;
  PDHProfileBlock = ^TDHProfileBlock;

  TDHProfilerStack = record
    pbBlocks    : array [0..c_ProfilerStackSize-1] of TDHProfileBlock;
    nAddrOffset : Int64;
    nAtIndex    : Integer;
  end;

  procedure DHEnterProfileBlock(nAddr : Pointer);
  function  DHExitProfileBlock: Pointer;
  function  DHExitProfileBlockException: Pointer;
  procedure InitializeDHProfilerTable(pAnchor : Pointer; nOffsetFromModuleBase : Int64);
  procedure ProfilerSerializeResults(stream : TMemoryStream);

  procedure PrintDHProfilerResults;

var
  EpilogueJump : Pointer; // TODO(psv): Make it Thread safe
  g_DHArrProcedures  : array of Pointer;
  g_Pipe : THandle;
  g_ThreadID : Integer = 0;

implementation
uses
  JclPeImage,
  Utils,
  Windows,
  SysUtils;

var
  g_DHTableProfiler  : Pointer;
  g_DHProfileStack   : TDHProfilerStack;
  g_nCyclesPerSecond : Int64;


procedure InitializeDHProfilerTable(pAnchor : Pointer; nOffsetFromModuleBase : Int64);
begin
  g_DHProfileStack.pbBlocks[0].pAnchor := PProfileAnchor(PByte(pAnchor) - sizeof(TProfileAnchor));
  g_DHProfileStack.pbBlocks[0].pParentAnchor := PProfileAnchor(PByte(pAnchor) - sizeof(TProfileAnchor));
  g_DHTableProfiler := pAnchor;
  g_DHProfileStack.nAddrOffset := nOffsetFromModuleBase;
  g_DHProfileStack.nAtIndex := 0;
end;

// Direct hashed anchored profiler

procedure DHEnterProfileBlock(nAddr : Pointer);
var
  pBlock       : PDHProfileBlock;
  nAtIdx       : Integer;
begin
  if g_ThreadID = 0 then
    g_ThreadID := GetCurrentThreadID
  else if g_ThreadID <> GetCurrentThreadID then
    LogDebug('ANOTHER THREAD !!!!', []);

  Inc(g_DHProfileStack.nAtIndex);
  nAtIdx := g_DHProfileStack.nAtIndex;

  pBlock := @g_DHProfileStack.pbBlocks[nAtIdx];
  pBlock.pParentAnchor := g_DHProfileStack.pbBlocks[nAtIdx-1].pParentAnchor;
  pBlock.pAnchor := PProfileAnchor(PByte(nAddr) + g_DHProfileStack.nAddrOffset);
  pBlock.ptrReturnTarget := EpilogueJump;

  //LogDebug('Entering block AtIdx=%d Name=%s ThreadID=%d', [nAtIdx, pBlock.pAnchor.strName, GetCurrentThreadId]);
  //OutputDebugString(Pwidechar(Format('Entered index %d Addr=%p Anchor=%p', [nAtIdx, nAddr, pBlock.pAnchor])));

  pBlock.nPrevTimeInclusive := pBlock.pAnchor.nElapsedInclusive;
  pBlock.nStartTime := ReadTimeStamp;
end;

function DHExitProfileBlock: Pointer;
var
  nAtIdx      : Integer;
  pBlock      : PDHProfileBlock;
  nElapsed    : Uint64;
begin
  if g_ThreadID <> GetCurrentThreadID then
    begin
      LogDebug('ANOTHER THREAD AT EXIT BLOCK!!!!', []);
      Exit(nil);
    end;

  nElapsed := ReadTimeStamp;

  nAtIdx := g_DHProfileStack.nAtIndex;
  pBlock := @g_DHProfileStack.pbBlocks[nAtIdx];
  Dec(g_DHProfileStack.nAtIndex);

  //LogDebug('Exiting block AtIdx=%d', [nAtIdx]);

  nElapsed := nElapsed - pBlock.nStartTime;

  pBlock.pParentAnchor.nElapsedExclusive := pBlock.pParentAnchor.nElapsedExclusive - nElapsed;
  pBlock.pAnchor.nElapsedExclusive := pBlock.pAnchor.nElapsedExclusive + nElapsed;
  pBlock.pAnchor.nElapsedInclusive := pBlock.nPrevTimeInclusive + nElapsed;

  //OutputDebugString(Pwidechar(Format('Leaving index %d Anchor=%p RetTarget=%p', [nAtIdx, pBlock.pAnchor, pBlock.ptrReturnTarget])));

  Inc(pBlock.pAnchor.nHitCount);

  Result := pBlock.ptrReturnTarget;
end;

function DHExitProfileBlockException: Pointer;
begin
  if g_DHProfileStack.nAtIndex = 0 then
    Exit(nil);
  Result := DHExitProfileBlock;
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
  prAnchor : PProfileAnchor;
begin
  for nIndex := 0 to Length(g_DHArrProcedures)-1 do
    begin
      if g_DHArrProcedures[nIndex] = nil then
        continue;
      prAnchor := PProfileAnchor(PByte(g_DHArrProcedures[nIndex]) + g_DHProfileStack.nAddrOffset);
      if prAnchor.nHitCount > 0 then
        begin
          Writeln(
            'DH [' + IntToStr(nIndex) + '] ' +
            'Name=' + prAnchor.strName + #9 +
            //' Addr ' + Uint64(g_TableProfiler[nIndex][nIndex2].nKey).ToString + #9 +
            ' Exclusive=' + CyclesToMs(prAnchor.nElapsedExclusive).ToString + ' ms.' +
            ' w/children=' + CyclesToMs(prAnchor.nElapsedInclusive).ToString + ' ms.' +
            ' HitCount='  + prAnchor.nHitCount.ToString);
        end;
    end;
end;

procedure ProfilerSerializeResults(stream : TMemoryStream);
var
  nIndex    : Integer;
  prAnchor  : PProfileAnchor;
  writer    : TBinaryWriter;
  nStartPos : Integer;
  nCount    : Cardinal;
begin
  writer := TBinaryWriter.Create(stream, TEncoding.UTF8);

  nCount := 0;
  nStartPos := stream.Position;
  writer.Write(Integer(-1));

  writer.Write(g_nCyclesPerSecond);

  for nIndex := 0 to Length(g_DHArrProcedures)-1 do
    begin
      if g_DHArrProcedures[nIndex] = nil then
        continue;
      prAnchor := PProfileAnchor(PByte(g_DHArrProcedures[nIndex]) + g_DHProfileStack.nAddrOffset);
      if prAnchor.nHitCount > 0 then
        begin
          Inc(nCount);
          writer.Write(PeBorUnmangleName(prAnchor.strName));
          //writer.Write(prAnchor.strName);
          writer.Write(prAnchor.nElapsedExclusive);
          writer.Write(prAnchor.nElapsedInclusive);
          writer.Write(prAnchor.nHitCount);
        end;
    end;

  PCardinal(PByte(stream.Memory) + nStartPos)^ := nCount;

  writer.Free;
end;

initialization
  CallibrateTimeStamp;
end.
