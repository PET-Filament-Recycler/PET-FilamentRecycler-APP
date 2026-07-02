$adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    Write-Error "adb not found at $adb"
    exit 1
}

$package = "com.example.petfr"
$permissions = @(
    "android.permission.BLUETOOTH_SCAN",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.ACCESS_FINE_LOCATION"
)

foreach ($permission in $permissions) {
    & $adb shell pm grant $package $permission
    Write-Host "Granted $permission"
}