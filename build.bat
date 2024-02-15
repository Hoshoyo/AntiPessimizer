@echo off

pushd Win64\Debug
call cl /nologo /I../../include /I../../src/imgui /Zi ../../src/*.cpp ../../src/*.c ../../src/imgui/*.cpp /Fe:AntiPessimizer.exe /link kernel32.lib d3d11.lib Comdlg32.lib
popd
