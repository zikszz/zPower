@echo off
chcp 65001 >nul
mode con: cols=70 lines=43
call :SET_WINDOW

:: Check if running as administrator
:CHECK_ADMINISTRATOR
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
    
    :: This part will call UAC to "Run as administrator"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    
    :: Exit directly from the script (which does not have admin rights)
    exit
)

:: If the script gets here, it means it is ALREADY running as Administrator.
:: Hardware and OS Detection
:DETECT_HARDWARE
cls
echo  Detecting Hardware info...

:: CPU Info
for /f "usebackq tokens=*" %%A in (`powershell -NoProfile -Command "Get-CimInstance Win32_Processor | Select-Object -ExpandProperty Name"`) do set "CPU_MODEL=%%A"
for /f "tokens=*" %%a in ('powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors"') do set "CPU_THREADS=%%a"
:: OS Info
for /f "tokens=4-6 delims=. " %%i in ('ver') do set WIN_BUILD=%%k
if %WIN_BUILD% GEQ 22000 (
    set OS_NAME=Windows 11
    set GAME_MODE_VALUE=1
    set GAME_MODE_TARGET=ON
) else (
    set OS_NAME=Windows 10
    set GAME_MODE_VALUE=0
    set GAME_MODE_TARGET=OFF
)

:: GPU Info
:: Default Value
set "GPU_MODEL_DETAIL=Basic Display Adapter"
set "OPTIMIZE_GPU=UNKNOWN"

:: Check for NVIDIA
:: method 1: Check GPU name for NVIDIA keywords
powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name" | findstr /i "NVIDIA" >nul
if %errorlevel% equ 0 (
    set "OPTIMIZE_GPU=NVIDIA"
    for /f "usebackq tokens=*" %%N in (`powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -ExpandProperty Name | Select-Object -First 1"`) do set "GPU_MODEL_DETAIL=%%N"
    goto :HARDWARE_DONE
)
:: method 2: Check PNPDeviceID for NVIDIA vendor ID (VEN_10DE)
for /f "tokens=*" %%A in ('powershell -NoProfile -Command "$gpus = Get-CimInstance Win32_VideoController; foreach($gpu in $gpus) { if($gpu.PNPDeviceID -match 'VEN_10DE') { $gpu.Name; break } }"') do (
    if not "%%A"=="" (
        set "OPTIMIZE_GPU=NVIDIA"
        set "GPU_MODEL_DETAIL=%%A"
        goto :HARDWARE_DONE
    )
)

:: Check for AMD
:: method 1: Check GPU name for AMD/ATI/Radeon keywords
powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name" | findstr /i "AMD Radeon ATI" >nul
if %errorlevel% equ 0 (
    set "OPTIMIZE_GPU=AMD"
    for /f "usebackq tokens=*" %%A in (`powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'AMD' -or $_.Name -match 'Radeon' -or $_.Name -match 'ATI' } | Select-Object -ExpandProperty Name | Select-Object -First 1"`) do set "GPU_MODEL_DETAIL=%%A"
    goto :HARDWARE_DONE
)
::method 2: Check PNPDeviceID for AMD vendor ID (VEN_1002)
for /f "tokens=*" %%A in ('powershell -NoProfile -Command "$gpus = Get-CimInstance Win32_VideoController; foreach($gpu in $gpus) { if($gpu.PNPDeviceID -match 'VEN_1002') { $gpu.Name; break } }"') do (
    if not "%%A"=="" (
        set "OPTIMIZE_GPU=AMD"
        set "GPU_MODEL_DETAIL=%%A"
        goto :HARDWARE_DONE
    )
)

:: Check for INTEL
:: method 1: Check GPU name for Intel keywords
powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name" | findstr /i "Intel" >nul
if %errorlevel% equ 0 (
    set "OPTIMIZE_GPU=INTEL"
    for /f "usebackq tokens=*" %%I in (`powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'Intel' } | Select-Object -ExpandProperty Name | Select-Object -First 1"`) do set "GPU_MODEL_DETAIL=%%I"
    goto :HARDWARE_DONE
)
:: method 2: Check PNPDeviceID for Intel vendor ID (VEN_8086)
for /f "tokens=*" %%A in ('powershell -NoProfile -Command "$gpus = Get-CimInstance Win32_VideoController; foreach($gpu in $gpus) { if($gpu.PNPDeviceID -match 'VEN_8086') { $gpu.Name; break } }"') do (
    if not "%%A"=="" (
        set "OPTIMIZE_GPU=INTEL"
        set "GPU_MODEL_DETAIL=%%A"
        goto :HARDWARE_DONE
    )
)

:HARDWARE_DONE
:: Clean up CPU model string (remove extra spaces)
set "CPU_MODEL=%CPU_MODEL:  = %"

:: Determine CPU Type
echo "%CPU_MODEL%" | findstr /i "AMD" >nul && set CPU_TYPE=AMD
echo "%CPU_MODEL%" | findstr /i "Intel" >nul && set CPU_TYPE=INTEL

:: RAM Detection
for /f "tokens=*" %%A in ('powershell -NoProfile -Command "[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)"') do set RAM_GB=%%A
if not defined RAM_GB set RAM_GB=8
if %RAM_GB% lss 4 set RAM_GB=4
if %RAM_GB% gtr 128 set RAM_GB=128

:: Storage Type Detection
set "STORAGE_TYPE=UNKNOWN"

:: Method 1: MediaType from Get-PhysicalDisk (most accurate)
for /f "tokens=*" %%A in ('powershell -NoProfile -Command "try { $disk = Get-Partition -DriveLetter C | Get-Disk; $phys = $disk | Get-PhysicalDisk -ErrorAction Stop; $phys.MediaType } catch { '' }" 2^>nul') do set "STORAGE_TYPE=%%A"

:: Method 2: BusType + RotationalSpeed ​​(fallback if MediaType is empty)
if "%STORAGE_TYPE%"=="" (
    for /f "tokens=*" %%A in ('powershell -NoProfile -Command "try { $disk = Get-Partition -DriveLetter C | Get-Disk; $bus = $disk.BusType; $rot = $disk.RotationalSpeed; if ($bus -eq 'NVMe' -or ($bus -eq 'SATA' -and $rot -eq 0)) { 'SSD' } elseif ($rot -gt 0) { 'HDD' } else { '' } } catch { '' }" 2^>nul') do set "STORAGE_TYPE=%%A"
)

:: Method 3: Keyword in FriendlyName (backup if both methods above fail)
if "%STORAGE_TYPE%"=="" (
    for /f "tokens=*" %%A in ('powershell -NoProfile -Command "try { $disk = Get-Partition -DriveLetter C | Get-Disk; $model = $disk.FriendlyName; if ($model -match 'SSD|NVMe|Solid|M\\.2') { 'SSD' } else { 'HDD' } } catch { '' }" 2^>nul') do set "STORAGE_TYPE=%%A"
)

:: Method 4: If all else fails, leave it UNKNOWN (user will be guided manually in the menu)
if "%STORAGE_TYPE%"=="" set "STORAGE_TYPE=UNKNOWN"

setlocal enabledelayedexpansion                                 goto DOWNLOAD_RESOURCES

goto STARTUP_RESTORE_CHECK

:STARTUP_RESTORE_CHECK
cls
color 0E
echo.
echo     ───────────────────────────────────
echo                 SAFETY CHECK
echo     ───────────────────────────────────
echo.
echo     It is highly recommended to create a Restore Point
echo     before applying any optimizations.
echo.
echo     Would you like to create a System Restore Point now?
echo.
set /p start_rp="Select option (Y/N): "

if /i "%start_rp%"=="N" goto MAIN_MENU
if /i "%start_rp%"=="Y" goto STARTUP_CREATE_RP

echo Invalid selection
echo Press any key to continue...
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

powershell -Command "Checkpoint-Computer -Description 'TGO Restore Point' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop" >nul

if %errorlevel% neq 0 (
    cls
    call :WRITE_LOG "Safety check failed to created"
    color 0C
    echo.
    echo     [FAILED] Could not create restore point.
    echo     System Restore might be disabled by Group Policy or disk is full.
    echo.
    echo     Proceeding to Main Menu without Restore Point...
    timeout /t 3 >nul
) else (
    cls
    call :WRITE_LOG "Safety check successfully created"
    color 0A
    echo.
    echo     [SUCCESS] Restore point created successfully!
    echo.
    echo     Proceeding to Main Menu...
    timeout /t 3 >nul
)

reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" /v SystemRestorePointCreationFrequency /f >nul 2>&1

goto MAIN_MENU

:PRINT_HEADER
cls
color 0B
echo.
echo          ███████╗██████╗  ██████╗ ██╗    ██╗███████╗██████╗ 
echo          ╚══███╔╝██╔══██╗██╔═══██╗██║    ██║██╔════╝██╔══██╗
echo            ███╔╝ ██████╔╝██║   ██║██║ █╗ ██║█████╗  ██████╔╝
echo           ███╔╝  ██╔═══╝ ██║   ██║██║███╗██║██╔══╝  ██╔══██╗
echo          ███████╗██║     ╚██████╔╝╚███╔███╔╝███████╗██║  ██║
echo          ╚══════╝╚═╝      ╚═════╝  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝                                              
echo.
color 0F
echo                             zPower v1.0
echo     ─────────────────────────────────────────────────────────────
echo        -  OS: %OS_NAME%
echo        -  CPU: %CPU_MODEL%
echo        -  GPU: %GPU_MODEL_DETAIL%
echo        -  RAM: %RAM_GB%GB
echo        -  DISK TYPE: %STORAGE_TYPE%
echo     ─────────────────────────────────────────────────────────────
echo.
goto :eof

:MAIN_MENU
call :PRINT_HEADER
title zPower v1.0
color 0F
echo.
echo     [1]  Clean All Temporary Files
echo     [2]  Disk Optimization                 (Detected: %STORAGE_TYPE%)
echo.
echo     [L]  View Log
echo     [C]  Changelog
echo     [E]  Exit
echo.
set /p choice="Select option: "

if "%choice%"=="1" goto CLEAN_TEMP
if "%choice%"=="2" goto DISK_OPTIMIZATION_MENU
if /i "%choice%"=="L" goto VIEW_LOG
if /i "%choice%"=="C" goto CHANGELOG
if /i "%choice%"=="E" exit

echo Invalid selection
echo Press any key to continue...
pause >nul
goto MAIN_MENU

:: ============================================================================
:: KUNCI UKURAN WINDOW (BOX 70x43, buffer = window)
:: ============================================================================
:SET_WINDOW
powershell -NoProfile -Command ^
 "$w=70; $h=43;" ^
 "$ui=(Get-Host).UI.RawUI;" ^
 "$ui.BufferSize = New-Object System.Management.Automation.Host.Size($w,$h);" ^
 "$ui.WindowSize = New-Object System.Management.Automation.Host.Size($w,$h);" 2>nul
exit /b

:: ============================================================================
:: VIEW LOG
:: ============================================================================
:VIEW_LOG
if not exist "C:\TGO\logs" mkdir "C:\TGO\logs" >nul 2>&1
if not exist "C:\TGO\logs\TGO_Log.txt" (
    echo No log file found yet. Run optimizations first.
    echo Press any key to continue...
    pause >nul
    goto MAIN_MENU
)
start "" notepad "C:\TGO\logs\TGO_Log.txt"
goto MAIN_MENU

:: ============================================================================
:: CLEAN TEMPORARY FILES
:: ============================================================================
:CLEAN_TEMP
title Clean All Temporary Files
call :PRINT_HEADER
color 0E
echo     CLEAN ALL TEMPORARY FILES
echo.
echo     This may take a few minutes.
echo     Please wait...
echo.

:: Flush DNS cache
echo     [0/8] Flushing DNS cache...
echo.
ipconfig /flushdns >nul 2>&1

:: Clean Windows temp files
echo     [1/8] Cleaning Windows temp files...
echo.
del /s /f /q "%windir%\Temp\*.*" >nul 2>&1
del /s /f /q "%windir%\*.bak" >nul 2>&1

:: Clean user temp files
echo     [2/8] Cleaning user temp files...
echo.
del /s /f /q "%temp%\*.*" >nul 2>&1
del /s /f /q "%systemdrive%\*.tmp" >nul 2>&1
del /s /f /q "%systemdrive%\*._mp" >nul 2>&1
del /s /f /q "%systemdrive%\*.log" >nul 2>&1
del /s /f /q "%systemdrive%\*.gid" >nul 2>&1
del /s /f /q "%systemdrive%\*.chk" >nul 2>&1
del /s /f /q "%systemdrive%\*.old" >nul 2>&1

:: Clean Windows logs
echo     [3/8] Cleaning specific system logs...
echo.
del /f /q "%SystemRoot%\Logs\CBS\CBS.log" >nul 2>&1
del /f /q "%SystemRoot%\Logs\DISM\DISM.log" >nul 2>&1

:: Clean thumbnail cache
echo     [4/8] Cleaning thumbnail cache...
echo.
del /s /f /q "%LocalAppData%\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1
del /s /f /q "%LocalAppData%\Microsoft\Windows\Explorer\*.db" >nul 2>&1
del /s /f /q "%LocalAppData%\D3DSCache\*.*" >nul 2>&1

:: Clean Windows Update cache
echo     [5/8] Cleaning Windows Update cache...
echo.
net stop wuauserv >nul 2>&1
net stop UsoSvc >nul 2>&1
net stop bits >nul 2>&1
net stop dosvc >nul 2>&1

rd /s /q "%windir%\ServiceProfiles\LocalService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" >nul 2>&1
rd /s /q "%windir%\SoftwareDistribution" >nul 2>&1
md "%windir%\SoftwareDistribution" >nul 2>&1

:: Clean recycle bin
echo     [6/8] Cleaning recycle bin...
echo.
powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1

echo     [7/8] Starting disk cleanup...
echo.

:: Use /WAIT to wait for cleanmgr.exe to finish
start "" /WAIT cleanmgr.exe

:: Run disk optimization
echo     [8/8] Running disk optimization...
powershell "Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue" >nul 2>&1

call :WRITE_LOG "Temporary files cleaned (DNS flush, temp, logs, thumbcache, update cache, recycle bin, disk cleanup, optimize C drive)"
echo.
call :PRINT_HEADER
color 0A
echo     [SUCCESS] Temporary files cleanup completed
echo.
echo     Back to Main Menu...
timeout /t 3 >nul
goto MAIN_MENU

:: ============================================================================
:: DISK OPTIMIZATION
:: ============================================================================
:DISK_OPTIMIZATION_MENU
title Disk Optimization
call :PRINT_HEADER
color 0F
echo     DISK OPTIMIZATION
echo.
echo     Detected Storage Type: %STORAGE_TYPE%
echo.
timeout /t 2 >nul

if /i "%STORAGE_TYPE%"=="SSD" (
    echo     SSD detected. Running automatic SSD optimization...
    timeout /t 3 >nul
    goto SSD_OPTIMIZATION
) else if /i "%STORAGE_TYPE%"=="HDD" (
    echo     HDD detected. Running automatic HDD optimization...
    timeout /t 3 >nul
    goto HDD_OPTIMIZATION
) else (
    echo     Could not auto-detect storage type.
    echo.
    echo     [1] HDD Optimization
    echo     [2] SSD Optimization
    echo     [B] Back to Main Menu
    echo.
    set /p disk_choice="Select option: "
    if "%disk_choice%"=="1" goto HDD_OPTIMIZATION
    if "%disk_choice%"=="2" goto SSD_OPTIMIZATION
    if /i "%disk_choice%"=="B" goto MAIN_MENU
    echo Invalid selection
    echo Press any key to continue...
    pause >nul
    goto DISK_OPTIMIZATION_MENU
)

:HDD_OPTIMIZATION
call :PRINT_HEADER
color 0E
echo     Please wait...
echo.

echo     (Step 1/3) Optimizing HDD Registry parameters...
echo.
for /f "delims=" %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-PnpDevice -Class DiskDrive -PresentOnly | ForEach-Object { $_.InstanceId }"') do (
    for /f "delims=" %%a in ("%%i") do set "diskid=%%a"
    set "diskpath=HKLM\SYSTEM\CurrentControlSet\Enum\!diskid!\Device Parameters\Disk"
    
    reg delete "!diskpath!" /v "UserWriteCacheSetting" /f >nul 2>&1
    reg add "!diskpath!" /v "CacheIsPowerProtected" /t REG_DWORD /d "1" /f >nul 2>&1
)

echo     (Step 2/3) Applying NTFS filesystem tweaks...
echo.
fsutil behavior set memoryusage 2 >nul 2>&1
fsutil behavior set disablelastaccess 1 >nul 2>&1
fsutil behavior set disabledeletenotify 0 >nul 2>&1
fsutil behavior set encryptpagingfile 0 >nul 2>&1
fsutil behavior set mftzone 4 >nul 2>&1
fsutil behavior set disable8dot3 1 >nul 2>&1

echo     (Step 3/4) Disabling Prefetcher via Registry...
echo.
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnablePrefetcher /t REG_DWORD /d 0 /f >nul 2>&1

echo     (Step 4/4) Disabling SysMain service...
echo.
:: Via Service
sc config SysMain start=disabled >nul 2>&1
sc stop SysMain >nul 2>&1
:: Via Registry
reg add "HKLM\SYSTEM\CurrentControlSet\Services\SysMain" /v Start /t REG_DWORD /d 4 /f >nul 2>&1

call :WRITE_LOG "HDD optimization applied (registry, NTFS tweaks, prefetcher disabled, SysMain disabled)"
echo.
call :PRINT_HEADER
color 0A
echo     [SUCCESS] HDD optimization completed
echo.
echo     Back to Main Menu...
timeout /t 5 >nul
goto MAIN_MENU

:SSD_OPTIMIZATION
call :PRINT_HEADER
color 0E
echo     Please wait...
echo.

echo     (Step 1/3) Optimizing SSD Registry parameters...
echo.
for /f "delims=" %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-PnpDevice -Class DiskDrive -PresentOnly | ForEach-Object { $_.InstanceId }"') do (
    for /f "delims=" %%a in ("%%i") do set "diskid=%%a"
    set "diskpath=HKLM\SYSTEM\CurrentControlSet\Enum\!diskid!\Device Parameters\Disk"
    
    :: Eksekusi pembuatan folder Disk dan pengisian tweaks Cache
    reg add "!diskpath!" /v "UserWriteCacheSetting" /t REG_DWORD /d "1" /f >nul 2>&1
    reg add "!diskpath!" /v "CacheIsPowerProtected" /t REG_DWORD /d "1" /f >nul 2>&1
)

echo     (Step 2/3) Disabling SSD Power Saving features...
echo.
:: Storage/SD
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SD\IdleState\1" /v "IdleExitEnergyMicroJoules" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SD\IdleState\1" /v "IdleExitLatencyMs" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SD\IdleState\1" /v "IdlePowerMw" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SD\IdleState\1" /v "IdleTimeLengthMs" /t REG_DWORD /d "4294967295" /f >nul 2>&1

:: Storage/SSD (IdleState 1, 2, & 3)
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\1" /v "IdleExitEnergyMicroJoules" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\1" /v "IdleExitLatencyMs" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\1" /v "IdlePowerMw" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\1" /v "IdleTimeLengthMs" /t REG_DWORD /d "4294967295" /f >nul 2>&1

Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\2" /v "IdleExitEnergyMicroJoules" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\2" /v "IdleExitLatencyMs" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\2" /v "IdlePowerMw" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\2" /v "IdleTimeLengthMs" /t REG_DWORD /d "4294967295" /f >nul 2>&1

Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\3" /v "IdleExitEnergyMicroJoules" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\3" /v "IdleExitLatencyMs" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\3" /v "IdlePowerMw" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\Storage\SSD\IdleState\3" /v "IdleTimeLengthMs" /t REG_DWORD /d "4294967295" /f >nul 2>&1

echo     (Step 3/3) Applying NTFS filesystem tweaks...
echo.
fsutil behavior set memoryusage 2 >nul 2>&1
fsutil behavior set disablelastaccess 1 >nul 2>&1
fsutil behavior set disabledeletenotify 0 >nul 2>&1
fsutil behavior set encryptpagingfile 0 >nul 2>&1
fsutil behavior set disable8dot3 1 >nul 2>&1

call :WRITE_LOG "SSD optimization applied (registry write cache enabled, power saving disabled, NTFS tweaks)"
echo.
call :PRINT_HEADER
color 0A
echo     [SUCCESS] SSD optimization completed
echo.
echo     Back to Main Menu...
timeout /t 5 >nul
goto MAIN_MENU

:: ============================================================================
:: MOUSE AND KEYBOARD OPTIMIZATION
:: ============================================================================
:MOUSE_KEYBOARD_MENU
title Mouse and Keyboard Optimization
call :PRINT_HEADER
color 0F
echo     MOUSE AND KEYBOARD OPTIMIZATION
echo.
echo     Detected Logical Processors: %CPU_THREADS% Threads
echo.
timeout /t 3 >nul

if %CPU_THREADS% GEQ 2 if %CPU_THREADS% LEQ 4 (
    echo     Low-tier CPU detected. Running Low optimization...
    timeout /t 5 >nul
    goto MK_LOW
)
if %CPU_THREADS% GEQ 6 if %CPU_THREADS% LEQ 12 (
    echo     Medium-tier CPU detected. Running Medium optimization...
    timeout /t 5 >nul
    goto MK_MEDIUM
)
if %CPU_THREADS% GEQ 16 if %CPU_THREADS% LEQ 32 (
    echo     High-tier CPU detected. Running High optimization...
    timeout /t 5 >nul
    goto MK_HIGH
)

:: ============================================================================
:: MANUAL INPUT FOR ANOMALIES OR UNKNOWN CPU
:: ============================================================================
echo     [WARNING] CPU anomaly or unknown thread count detected.
echo     Please select the optimization level manually:
echo.
echo     L - i3 / Ryzen 3 / Celeron / Athlon (Low)
echo     M - i5 / Ryzen 5 (Medium)
echo     H - i7 / i9 / Ryzen 7 / Ryzen 9 (High)
echo     R - Revert to Default
echo     B - Back to Main Menu
echo.
set /p mk_choice="Select optimization level: "

if /i "%mk_choice%"=="L" goto MK_LOW
if /i "%mk_choice%"=="M" goto MK_MEDIUM
if /i "%mk_choice%"=="H" goto MK_HIGH
if /i "%mk_choice%"=="R" goto MK_REVERT
if /i "%mk_choice%"=="B" goto MAIN_MENU

echo Invalid selection
echo Press any key to continue...
pause >nul
goto MOUSE_KEYBOARD_MENU

:: ============================================================================
:: CHANGELOG
:: ============================================================================
:CHANGELOG
title Changelog
call :PRINT_HEADER
color 0F
echo     CHANGELOG
echo.
echo     [v1.0]
echo       + Added Clean All Temporary Files Menu.
echo       + Added Disk Optimization Menu.
echo.

echo.
echo Press any key to continue...
pause >nul
goto MAIN_MENU

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================
goto :eof

:WRITE_LOG
if not exist "C:\zPower" mkdir "C:\zPower" >nul 2>&1
if not exist "C:\zPower\logs" mkdir "C:\zPower\logs" >nul 2>&1
echo [%date% %time:~0,8%] - %* >> "C:\zPower\logs\zPower_Log.txt"
goto :eof