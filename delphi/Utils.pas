unit Utils;

interface

function GenerateRandomSeed: Uint64;
function GenerateRandomNumber: Uint64;
function HashPointer(pAddr : Pointer): Uint64;
function CalculateAnchorIndex(nPow2 : Integer; nHash : Uint64): Integer;
function ReadTimeStamp: Uint64;
function GetCurrentDir: String;

implementation
uses
  Windows;
var
  g_RandomSeed : Int64;

function ReadTimeStamp: Uint64;
asm
.noframe
  rdtsc
  shl rdx, 32
  or rax, rdx
end;

function GenerateRandomSeed: Uint64;
asm
  .noframe
  db $48 // rdseed rax
  db $0F
  db $C7
  db $F8
end;

function GenerateRandomNumber: Uint64;
asm
  .noframe
  db $48 // rdrand rax
  db $0F
  db $C7
  db $F0
end;

function HashPointer(pAddr : Pointer): Uint64;
asm
.noframe
  movq xmm1, g_RandomSeed
  movq xmm0, pAddr

  aesdec xmm0, xmm1
  pxor xmm0, xmm1
  aesdec xmm0, xmm0

  movq rax, xmm0
end;

function CalculateAnchorIndex(nPow2 : Integer; nHash : Uint64): Integer;
asm
  xor rax, rax
  not rax
  shl rax, cl
  not rax
  and rax, nHash
end;

function GetCurrentDir: String;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  GetCurrentDirectory(MAX_PATH, Buffer);
  Result := String(Buffer);
end;

initialization
  //while g_RandomSeed = 0 do
  //  g_RandomSeed := GenerateRandomSeed;
  g_RandomSeed := Int64(10890402341074030334);

end.
