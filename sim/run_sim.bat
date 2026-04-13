@echo off
REM ===========================================================================
REM  UART Simulation Script (Icarus Verilog)
REM  Usage: run_sim.bat
REM ===========================================================================

echo ============================================
echo   UART Verilog Simulation
echo ============================================
echo.

REM Compile
echo [1/3] Compiling...
iverilog -Wall -g2012 -o uart_sim.vvp ^
    rtl\baud_rate_gen.v ^
    rtl\uart_tx.v ^
    rtl\uart_rx.v ^
    rtl\uart_top.v ^
    tb\uart_tb.v

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Compilation failed!
    pause
    exit /b 1
)
echo [OK] Compilation successful.
echo.

REM Simulate
echo [2/3] Running simulation...
vvp uart_sim.vvp
echo.

REM Open waveform (optional)
echo [3/3] Waveform file generated: uart_tb.vcd
echo       Open with: gtkwave uart_tb.vcd
echo.
echo ============================================
echo   Done!
echo ============================================
pause
