unit Udis86;

interface
uses Windows;

type
  UdRec = record
    udReserved : array [0..584-1] of Byte;
  end;
  PUdRec = ^UdRec;

var
  UdInit           : procedure (ud : PUdRec); stdcall;
  UdSetMode        : procedure (ud : PUdRec; nMode : Byte); stdcall;
  UdSetInputBuffer : procedure (ud : PUdRec; pBuffer : PByte; nSize : SIZE_T); stdcall;
  UdDisassemble    : function  (ud : PUdRec): Cardinal; stdcall;

  function UdisDisasmAtLeast(pAt : Pointer; nBufferSize : Cardinal; nByteCountToDisasm : Cardinal): Cardinal;

implementation

var
  hUdis : THandle;

function UdisDisasmAtLeast(pAt : Pointer; nBufferSize : Cardinal; nByteCountToDisasm : Cardinal): Cardinal;
var
  ud : UdRec;
  nBytesDisassembled : Cardinal;
begin
  UdInit(@ud);
  UdSetMode(@ud, 64);
  UdSetInputBuffer(@ud, pAt, nBufferSize);

  nBytesDisassembled := 0;
  while (nBytesDisassembled < nByteCountToDisasm) do
    begin
      nBytesDisassembled := nBytesDisassembled + UdDisassemble(@ud);
    end;
  Result := nBytesDisassembled;
end;

procedure LoadUdis;
begin
  hUdis := LoadLibrary('libudis.dll');
  if hUdis <> 0 then
    begin
      @UdInit := GetProcAddress(hUdis, 'ud_init');
      @UdSetMode := GetProcAddress(hUdis, 'ud_set_mode');
      @UdSetInputBuffer := GetProcAddress(hUdis, 'ud_set_input_buffer');
      @UdDisassemble := GetProcAddress(hUdis, 'ud_disassemble');
    end;
end;

initialization
  LoadUdis;

end.
