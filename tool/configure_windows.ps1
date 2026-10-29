# Adjusts the Windows project that `flutter create` generates.
$ErrorActionPreference = 'Stop'

# The program is called F-Locker.exe
$cmake = 'windows/CMakeLists.txt'
(Get-Content $cmake) -replace 'set\(BINARY_NAME "f_locker"\)', 'set(BINARY_NAME "F-Locker")' | Set-Content $cmake

# Window title
$main = 'windows/runner/main.cpp'
(Get-Content $main) -replace 'L"f_locker"', 'L"F-Locker"' | Set-Content $main

Select-String -Path $cmake -Pattern 'BINARY_NAME'
Select-String -Path $main -Pattern 'F-Locker'
