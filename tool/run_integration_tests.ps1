param(
    [string]$DeviceId = "",
    [switch]$BleFlow
)

$ErrorActionPreference = "Stop"
$adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
$package = "com.example.petfr"
$permissions = @(
    "android.permission.BLUETOOTH_SCAN",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.ACCESS_FINE_LOCATION"
)

if (-not (Test-Path $adb)) {
    Write-Error "adb not found at $adb"
}

function Grant-BlePermissions {
    foreach ($permission in $permissions) {
        & $adb shell pm grant $package $permission 2>$null | Out-Null
    }
}

$grantJob = Start-Job -ScriptBlock {
    param($adbPath, $pkg, $perms)
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        foreach ($permission in $perms) {
            & $adbPath shell pm grant $pkg $permission 2>$null | Out-Null
        }
        Start-Sleep -Milliseconds 800
    }
} -ArgumentList $adb, $package, $permissions

try {
    $deviceArg = @()
    if ($DeviceId) {
        $deviceArg = @("-d", $DeviceId)
    }

    $targets = @("integration_test/smoke_test.dart")
    if ($BleFlow) {
        $targets += "integration_test/ble_flow_test.dart"
    }

    foreach ($target in $targets) {
        Write-Host "Running $target ..."
        $args = @("test", $target) + $deviceArg
        if ($target -like "*ble_flow*") {
            $args += "--dart-define=RUN_BLE_INTEGRATION=true"
        }
        flutter @args
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
        Grant-BlePermissions
    }
}
finally {
    Stop-Job $grantJob -ErrorAction SilentlyContinue
    Remove-Job $grantJob -Force -ErrorAction SilentlyContinue
}