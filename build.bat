@echo off

pushd Win64\Release
rem call cl /nologo /I../../include /I../../src/imgui /Zi ../../src/*.cpp ../../src/*.c ../../src/imgui/*.cpp /Fe:AntiPessimizer.exe /link kernel32.lib d3d11.lib Comdlg32.lib winmm.lib shell32.lib
call cl /O2 /nologo /I../../include /I../../src/imgui /Zi ../../src/*.cpp ../../src/*.c ../../src/imgui/*.cpp /Fe:AntiPessimizer.exe /link kernel32.lib d3d11.lib Comdlg32.lib winmm.lib shell32.lib

popd
