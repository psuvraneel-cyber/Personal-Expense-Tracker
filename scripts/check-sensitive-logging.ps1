# CI Safeguard Script: Check for raw Log.* calls in native Kotlin code (PowerShell version)

Write-Host "Checking native Kotlin layer for raw Log.* calls..."

$matches = Get-ChildItem -Path "android/app/src/main/kotlin" -Recurse -Filter "*.kt" |
    Where-Object { $_.Name -ne "SafeLog.kt" } |
    Select-String -Pattern "(?<!Safe)Log\.(d|i|w|e|v)\("

if ($matches) {
    Write-Host "[FAIL] Found raw Log.* calls in native Kotlin code:" -ForegroundColor Red
    $matches | ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber): $($_.Line)" }
    Write-Host "Please migrate all native logging to SafeLog object (com.pet.tracker.pet.SafeLog)." -ForegroundColor Red
    exit 1
} else {
    Write-Host "[PASS] No raw Log.* calls found in native Kotlin codebase." -ForegroundColor Green
    exit 0
}
