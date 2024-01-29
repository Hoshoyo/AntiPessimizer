@echo off

pushd Win64\Debug
call cl /nologo /Zi ../../src/*.c /Fe:AntiPessimizer.exe /link kernel32.lib
popd