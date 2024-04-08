@echo off

if not exist "Antipessimizer" mkdir Antipessimizer

copy Win64\Release\AntiPessimizer.exe Antipessimizer
copy Win64\Release\AntiPessimizerDLL.dll Antipessimizer
copy lib\udis86\libudis86.dll AntiPessimizer
copy imgui.ini Antipessimizer
tar.exe -a -c -f Antipessimizer/Antipessimizer.zip Antipessimizer