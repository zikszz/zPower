@echo off
chcp 65001 >nul
mode con: cols=79 lines=23

:: Check if running as administrator
fsutil dirty query %systemdrive% >nul
if %errorLevel% neq 0 (
    color 0C
    cls
    echo.
    echo [WARNING] Not running as administrator
    echo Some features may not work properly.
    echo Please run as Administrator for full functionality.
    echo.
    echo Restarting as Administrator...
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit
)

:DETECT_HARDWARE
cls
echo     Detecting Hardware info...

for /f "usebackq tokens=*" %%A in (`powershell -NoProfile -Command "Get-CimInstance Win32_Processor | Select-Object -ExpandProperty Name"`) do set "CPU_MODEL=%%A"
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors"') do set "CPU_THREADS=%%a"

for /f "tokens=4-6 delims=. " %%i in ('ver') do set WIN_BUILD=%%k
if %WIN_BUILD% GEQ 22000 (
    set OS_NAME=Windows 11
) else (
    set OS_NAME=Windows 10
)

set "GPU_MODEL_DETAIL=Basic Display Adapter"
set "OPTIMIZE_GPU=UNKNOWN"

powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name" | findstr /i "NVIDIA" >nul
if %errorlevel% equ 0 (
    set "OPTIMIZE_GPU=NVIDIA"
    for /f "usebackq tokens=*" %%N in (`powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -ExpandProperty Name | Select-Object -First 1"`) do set "GPU_MODEL_DETAIL=%%N"
    goto :HARDWARE_DONE
)
for /f "tokens=*" %%A in ('powershell -NoProfile -Command "$gpus = Get-CimInstance Win32_VideoController; foreach($gpu in $gpus) { if($gpu.PNPDeviceID -match 'VEN_10DE') { $gpu.Name; break } }"') do (
    if not "%%A"=="" ( set "OPTIMIZE_GPU=NVIDIA" & set "GPU_MODEL_DETAIL=%%A" & goto :HARDWARE_DONE )
)

powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name" | findstr /i "AMD Radeon ATI" >nul
if %errorlevel% equ 0 (
    set "OPTIMIZE_GPU=AMD"
    for /f "usebackq tokens=*" %%A in (`powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'AMD' -or $_.Name -match 'Radeon' -or $_.Name -match 'ATI' } | Select-Object -ExpandProperty Name | Select-Object -First 1"`) do set "GPU_MODEL_DETAIL=%%A"
    goto :HARDWARE_DONE
)
for /f "tokens=*" %%A in ('powershell -NoProfile -Command "$gpus = Get-CimInstance Win32_VideoController; foreach($gpu in $gpus) { if($gpu.PNPDeviceID -match 'VEN_1002') { $gpu.Name; break } }"') do (
    if not "%%A"=="" ( set "OPTIMIZE_GPU=AMD" & set "GPU_MODEL_DETAIL=%%A" & goto :HARDWARE_DONE )
)

powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name" | findstr /i "Intel" >nul
if %errorlevel% equ 0 (
    set "OPTIMIZE_GPU=INTEL"
    for /f "usebackq tokens=*" %%I in (`powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'Intel' } | Select-Object -ExpandProperty Name | Select-Object -First 1"`) do set "GPU_MODEL_DETAIL=%%I"
    goto :HARDWARE_DONE
)
for /f "tokens=*" %%A in ('powershell -NoProfile -Command "$gpus = Get-CimInstance Win32_VideoController; foreach($gpu in $gpus) { if($gpu.PNPDeviceID -match 'VEN_8086') { $gpu.Name; break } }"') do (
    if not "%%A"=="" ( set "OPTIMIZE_GPU=INTEL" & set "GPU_MODEL_DETAIL=%%A" & goto :HARDWARE_DONE )
)

:HARDWARE_DONE
set "CPU_MODEL=%CPU_MODEL:  = %"
echo "%CPU_MODEL%" | findstr /i "AMD" >nul && set CPU_TYPE=AMD
echo "%CPU_MODEL%" | findstr /i "Intel" >nul && set CPU_TYPE=INTEL

for /f "tokens=*" %%A in ('powershell -NoProfile -Command "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)"') do set RAM_GB=%%A
if not defined RAM_GB set RAM_GB=8
if %RAM_GB% lss 4 set RAM_GB=4
if %RAM_GB% gtr 128 set RAM_GB=128

set "STORAGE_TYPE=UNKNOWN"
for /f "tokens=*" %%A in ('powershell -NoProfile -Command "try { $disk = Get-Partition -DriveLetter C | Get-Disk; $phys = $disk | Get-PhysicalDisk -ErrorAction Stop; $phys.MediaType } catch { '' }" 2^>nul') do set "STORAGE_TYPE=%%A"
if "%STORAGE_TYPE%"=="" (
    for /f "tokens=*" %%A in ('powershell -NoProfile -Command "try { $disk = Get-Partition -DriveLetter C | Get-Disk; $bus = $disk.BusType; $rot = $disk.RotationalSpeed; if ($bus -eq 'NVMe' -or ($bus -eq 'SATA' -and $rot -eq 0)) { 'SSD' } elseif ($rot -gt 0) { 'HDD' } else { '' } } catch { '' }" 2^>nul') do set "STORAGE_TYPE=%%A"
)
if "%STORAGE_TYPE%"=="" (
    for /f "tokens=*" %%A in ('powershell -NoProfile -Command "try { $disk = Get-Partition -DriveLetter C | Get-Disk; $model = $disk.FriendlyName; if ($model -match 'SSD|NVMe|Solid|M\.2') { 'SSD' } else { 'HDD' } } catch { '' }" 2^>nul') do set "STORAGE_TYPE=%%A"
)
if "%STORAGE_TYPE%"=="" set "STORAGE_TYPE=UNKNOWN"

setlocal enabledelayedexpansion

goto STARTUP_RESTORE_CHECK

:: ============================================================================
:: SAFETY CHECK
:: ============================================================================
:STARTUP_RESTORE_CHECK
cls
color 0E
echo.
echo     ─────────────────────────────────────────────────────────────────
echo                              SAFETY CHECK
echo     ─────────────────────────────────────────────────────────────────
echo.
echo     It is highly recommended to create a Restore Point
echo     before applying any optimizations.
echo.
echo     Would you like to create a System Restore Point now?
echo.
set /p start_rp="Select option (Y/N): "
if /i "%start_rp%"=="N" goto MAIN_MENU
if /i "%start_rp%"=="Y" goto STARTUP_CREATE_RP
echo Invalid selection. Press any key to continue...
pause >nul
goto STARTUP_RESTORE_CHECK

:STARTUP_CREATE_RP
cls
color 0E
echo.
echo     Preparing to create Restore Point...
echo.
echo     This may take a moment...
echo.
powershell -Command "Enable-ComputerRestore -Drive 'C:' -ErrorAction SilentlyContinue" >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v SystemRestorePointCreationFrequency /t REG_DWORD /d 0 /f >nul 2>&1
powershell -Command "Checkpoint-Computer -Description 'zPower Restore Point' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop" >nul

if %errorlevel% neq 0 (
    cls
    call :WRITE_LOG "Restore point creation FAILED"
    color 0C
    echo.
    echo     [FAILED] Could not create restore point.
    echo     System Restore might be disabled or disk is full.
    echo.
    echo     Proceeding to Main Menu without Restore Point...
    timeout /t 3 >nul
) else (
    cls
    call :WRITE_LOG "Restore point created successfully"
    color 0A
    echo.
    echo     [SUCCESS] Restore point created successfully!
    echo.
    echo     Proceeding to Main Menu...
    timeout /t 3 >nul
)
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v SystemRestorePointCreationFrequency /f >nul 2>&1

:: ============================================================================
:: MAIN MENU
:: ============================================================================
:MAIN_MENU
cls
:: Inisialisasi ANSI Escape Code
for /F "delims=#" %%E in ('"prompt #$E# & echo on & for %%b in (1) do rem"') do set "ESC=%%E"

:: ── Baris 1: blank (dari cls)
echo.
:: ── Baris 2-7: ASCII Banner zPower (pas 79 kolom, rata tengah)
echo %ESC%[96m       ███████╗██████╗  ██████╗ ██╗    ██╗███████╗██████╗ %ESC%[0m
echo %ESC%[96m       ╚══███╔╝██╔══██╗██╔═══██╗██║    ██║██╔════╝██╔══██╗%ESC%[0m
echo %ESC%[35m         ███╔╝ ██████╔╝██║   ██║██║ █╗ ██║█████╗  ██████╔╝%ESC%[0m
echo %ESC%[35m        ███╔╝  ██╔═══╝ ██║   ██║██║███╗██║██╔══╝  ██╔══██╗%ESC%[0m
echo %ESC%[94m       ███████╗██║     ╚██████╔╝╚███╔███╔╝███████╗██║  ██║%ESC%[0m
echo %ESC%[94m       ╚══════╝╚═╝      ╚═════╝  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝%ESC%[0m
:: ── Baris 8: subtitle
echo                             %ESC%[93m   zPower v1   %ESC%[0m
echo.
:: ── Baris 10: separator atas
echo     %ESC%[90m───────────────────────────────────────────────────────────────%ESC%[0m
:: ── Baris 11-15: hardware info
echo      %ESC%[97m OS   :%ESC%[0m %ESC%[92m%OS_NAME%%ESC%[0m
echo      %ESC%[97m CPU  :%ESC%[0m %ESC%[92m%CPU_MODEL%%ESC%[0m
echo      %ESC%[97m GPU  :%ESC%[0m %ESC%[92m%GPU_MODEL_DETAIL%%ESC%[0m
echo      %ESC%[97m RAM  :%ESC%[0m %ESC%[92m%RAM_GB% GB%ESC%[0m
echo      %ESC%[97m DISK :%ESC%[0m %ESC%[92m%STORAGE_TYPE%%ESC%[0m
:: ── Baris 16: separator bawah
echo     %ESC%[90m───────────────────────────────────────────────────────────────%ESC%[0m
echo.
:: ── Baris 18-19: menu options
echo            %ESC%[97m[1]%ESC%[0m %ESC%[93mClean All Temporary Files%ESC%[0m       %ESC%[97m[2]%ESC%[0m %ESC%[93mDisk Optimization%ESC%[0m
echo.
:: ── Baris 21: secondary options
echo            %ESC%[97m[L]%ESC%[0m %ESC%[90mView Log%ESC%[0m                        %ESC%[91m[E]%ESC%[0m %ESC%[91mExit%ESC%[0m
echo.
set /p choice="%ESC%[97m     >> Select option: %ESC%[0m"

if "%choice%"=="1" goto CLEAN_TEMP
if "%choice%"=="2" goto DISK_OPTIMIZATION_MENU
if /i "%choice%"=="L" goto VIEW_LOG
if /i "%choice%"=="E" exit

echo %ESC%[91m     Invalid selection!%ESC%[0m Press any key to continue...
pause >nul
goto MAIN_MENU

:: ============================================================================
:: VIEW LOG
:: ============================================================================
:VIEW_LOG
if not exist "C:\TGO\logs" mkdir "C:\TGO\logs" >nul 2>&1
if not exist "C:\TGO\logs\TGO_Log.txt" (
    echo No log file found yet. Run optimizations first.
    pause >nul
    goto MAIN_MENU
)
start "" notepad "C:\TGO\logs\TGO_Log.txt"
goto MAIN_MENU

:: ============================================================================
:: CLEAN TEMPORARY FILES
:: ============================================================================
:CLEAN_TEMP
title zPower - Clean Temporary Files
call :PRINT_HEADER
echo %ESC%[93m     CLEAN ALL TEMPORARY FILES%ESC%[0m
echo.
echo     This may take a few minutes. Please wait...
echo.

echo     %ESC%[90m[0/8]%ESC%[0m Flushing DNS cache...
ipconfig /flushdns >nul 2>&1

echo     %ESC%[90m[1/8]%ESC%[0m Cleaning Windows temp files...
del /s /f /q "%windir%\Temp\*.*" >nul 2>&1
del /s /f /q "%windir%\*.bak" >nul 2>&1

echo     %ESC%[90m[2/8]%ESC%[0m Cleaning user temp files...
del /s /f /q "%temp%\*.*" >nul 2>&1
del /s /f /q "%systemdrive%\*.tmp" >nul 2>&1
del /s /f /q "%systemdrive%\*._mp" >nul 2>&1
del /s /f /q "%systemdrive%\*.log" >nul 2>&1
del /s /f /q "%systemdrive%\*.gid" >nul 2>&1
del /s /f /q "%systemdrive%\*.chk" >nul 2>&1
del /s /f /q "%systemdrive%\*.old" >nul 2>&1

echo     %ESC%[90m[3/8]%ESC%[0m Cleaning system logs...
del /f /q "%SystemRoot%\Logs\CBS\CBS.log" >nul 2>&1
del /f /q "%SystemRoot%\Logs\DISM\DISM.log" >nul 2>&1

echo     %ESC%[90m[4/8]%ESC%[0m Cleaning thumbnail cache...
del /s /f /q "%LocalAppData%\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1
del /s /f /q "%LocalAppData%\Microsoft\Windows\Explorer\*.db" >nul 2>&1
del /s /f /q "%LocalAppData%\D3DSCache\*.*" >nul 2>&1

echo     %ESC%[90m[5/8]%ESC%[0m Cleaning Windows Update cache...
net stop wuauserv >nul 2>&1
net stop UsoSvc >nul 2>&1
net stop bits >nul 2>&1
net stop dosvc >nul 2>&1
rd /s /q "%windir%\ServiceProfiles\LocalService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" >nul 2>&1
rd /s /q "%windir%\SoftwareDistribution" >nul 2>&1
md "%windir%\SoftwareDistribution" >nul 2>&1

echo     %ESC%[90m[6/8]%ESC%[0m Cleaning recycle bin...
powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1

echo     %ESC%[90m[7/8]%ESC%[0m Running Disk Cleanup (GUI)...
start "" /WAIT cleanmgr.exe

echo     %ESC%[90m[8/8]%ESC%[0m Running disk optimization (ReTrim)...
powershell "Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue" >nul 2>&1

call :WRITE_LOG "Clean Temp: DNS flush, temp files, logs, thumbcache, update cache, recycle bin, disk cleanup, ReTrim"
echo.
call :PRINT_HEADER
echo %ESC%[92m     [SUCCESS] Temporary files cleanup completed!%ESC%[0m
echo.
echo     Returning to Main Menu...
timeout /t 3 >nul
goto MAIN_MENU

:: ============================================================================
:: DISK OPTIMIZATION
:: ============================================================================
:DISK_OPTIMIZATION_MENU
title zPower - Disk Optimization
call :PRINT_HEADER
echo %ESC%[93m     DISK OPTIMIZATION%ESC%[0m
echo.
echo     Detected Storage Type: %ESC%[92m%STORAGE_TYPE%%ESC%[0m
echo.
timeout /t 2 >nul

if /i "%STORAGE_TYPE%"=="SSD" (
    echo     SSD detected. Running SSD optimization...
    timeout /t 2 >nul
    goto SSD_OPTIMIZATION
) else if /i "%STORAGE_TYPE%"=="HDD" (
    echo     HDD detected. Running HDD optimization...
    timeout /t 2 >nul
    goto HDD_OPTIMIZATION
) else (
    echo     Could not auto-detect storage type. Please select:
    echo.
    echo     %ESC%[97m[1]%ESC%[0m HDD Optimization
    echo     %ESC%[97m[2]%ESC%[0m SSD Optimization
    echo     %ESC%[97m[B]%ESC%[0m Back to Main Menu
    echo.
    set /p disk_choice="     >> Select option: "
    if "!disk_choice!"=="1" goto HDD_OPTIMIZATION
    if "!disk_choice!"=="2" goto SSD_OPTIMIZATION
    if /i "!disk_choice!"=="B" goto MAIN_MENU
    echo Invalid selection. Press any key...
    pause >nul
    goto DISK_OPTIMIZATION_MENU
)

:HDD_OPTIMIZATION
call :PRINT_HEADER
echo %ESC%[93m     HDD OPTIMIZATION%ESC%[0m
echo.

echo     %ESC%[90m(1/4)%ESC%[0m Optimizing HDD Registry parameters...
for /f "delims=" %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-PnpDevice -Class DiskDrive -PresentOnly | ForEach-Object { $_.InstanceId }"') do (
    for /f "delims=" %%a in ("%%i") do set "diskid=%%a"
    set "diskpath=HKLM\SYSTEM\CurrentControlSet\Enum\!diskid!\Device Parameters\Disk"
    reg delete "!diskpath!" /v "UserWriteCacheSetting" /f >nul 2>&1
    reg add "!diskpath!" /v "CacheIsPowerProtected" /t REG_DWORD /d "1" /f >nul 2>&1
)

echo     %ESC%[90m(2/4)%ESC%[0m Applying NTFS filesystem tweaks...
fsutil behavior set memoryusage 2 >nul 2>&1
fsutil behavior set disablelastaccess 1 >nul 2>&1
fsutil behavior set disabledeletenotify 0 >nul 2>&1
fsutil behavior set encryptpagingfile 0 >nul 2>&1
fsutil behavior set mftzone 4 >nul 2>&1
fsutil behavior set disable8dot3 1 >nul 2>&1

echo     %ESC%[90m(3/4)%ESC%[0m Disabling Prefetcher...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnablePrefetcher /t REG_DWORD /d 0 /f >nul 2>&1

echo     %ESC%[90m(4/4)%ESC%[0m Disabling SysMain service...
sc config SysMain start=disabled >nul 2>&1
sc stop SysMain >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\SysMain" /v Start /t REG_DWORD /d 4 /f >nul 2>&1

call :WRITE_LOG "HDD Optimization: registry, NTFS tweaks, prefetcher disabled, SysMain disabled"
echo.
call :PRINT_HEADER
echo %ESC%[92m     [SUCCESS] HDD optimization completed!%ESC%[0m
echo.
echo     Returning to Main Menu...
timeout /t 5 >nul
goto MAIN_MENU

:SSD_OPTIMIZATION
call :PRINT_HEADER
echo %ESC%[93m     SSD OPTIMIZATION%ESC%[0
