# Quick PowerShell Version Detection for DevOps Compatibility
# This script checks the current PowerShell version and capabilities

Write-Host "PowerShell Version Detection" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan

# Get version information
$version = $PSVersionTable.PSVersion
$edition = $PSVersionTable.PSEdition
$clr = $PSVersionTable.CLRVersion

Write-Host "PowerShell Version: $version" -ForegroundColor Green
Write-Host "Edition: $edition" -ForegroundColor Green  
Write-Host "CLR Version: $clr" -ForegroundColor Green
Write-Host "Host: $($Host.Name)" -ForegroundColor Green

# Test string parsing capabilities
Write-Host "`nTesting string parsing capabilities..." -ForegroundColor Yellow

$testPassed = $true

# Test 1: Basic string assignment
try {
    $test1 = "Basic string test"
    Write-Host "✅ Basic strings: PASS" -ForegroundColor Green
} catch {
    Write-Host "❌ Basic strings: FAIL" -ForegroundColor Red
    $testPassed = $false
}

# Test 2: Array string operations
try {
    $testArray = @()
    $testArray += "Line 1"
    $testArray += "Line 2"
    Write-Host "✅ Array operations: PASS" -ForegroundColor Green
} catch {
    Write-Host "❌ Array operations: FAIL" -ForegroundColor Red
    $testPassed = $false
}

# Test 3: Complex strings with numbers
try {
    $testComplex = "1. First item"
    Write-Host "✅ Numbered strings: PASS" -ForegroundColor Green
} catch {
    Write-Host "❌ Numbered strings: FAIL" -ForegroundColor Red
    $testPassed = $false
}

Write-Host "`nCompatibility Summary:" -ForegroundColor Cyan
if ($testPassed) {
    Write-Host "✅ PowerShell environment appears compatible" -ForegroundColor Green
} else {
    Write-Host "❌ PowerShell environment has limitations" -ForegroundColor Red
}

Write-Host "`nRecommended DevOps Script Patterns:" -ForegroundColor Cyan
Write-Host "• Use simple variable assignments" -ForegroundColor Gray
Write-Host "• Avoid complex string operations in arrays" -ForegroundColor Gray
Write-Host "• Separate variable creation from array operations" -ForegroundColor Gray
Write-Host "• Use basic PowerShell syntax patterns" -ForegroundColor Gray