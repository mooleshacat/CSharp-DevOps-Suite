# MixerThreholdMod DevOps Tool: ULTIMATE CORRUPTION DETECTOR (INFINITY SCAN)
# Master corruption detection orchestrator that runs ALL corruption-related analysis scripts
# Detects merge conflicts, encoding issues, project integrity, build errors, and file corruption
# The ULTIMATE guardian against codebase corruption and structural damage
# Excludes: ForCopilot, Scripts, and Legacy directories

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ((Split-Path $ScriptDir -Leaf) -ieq "Scripts") {
    $ProjectRoot = Split-Path $ScriptDir -Parent
} else {
    $ProjectRoot = $ScriptDir
}

Write-Host "🛡️  ULTIMATE CORRUPTION DETECTION STARTING" -ForegroundColor Red
Write-Host "=============================================" -ForegroundColor Red
Write-Host "🔍 INFINITY SCAN MODE: DETECTING ALL CORRUPTION TYPES" -ForegroundColor DarkRed
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Gray
Write-Host "Scan Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Function to estimate corruption scan complexity
function Get-CorruptionScanEstimate {
    param($path)
    
    try {
        Write-Host "`n🔬 Analyzing project for corruption detection complexity..." -ForegroundColor DarkYellow
        
        # Quick scan for corruption-prone files
        $allFiles = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
            $_.FullName -notmatch "[\\/]\.git[\\/]"
        }
        
        $textFiles = $allFiles | Where-Object { 
            $_.Extension -match "^\.(cs|txt|md|json|xml|config|yaml|yml|ini|log|ps1|bat|cmd|sh|sln|csproj)$" 
        }
        $projectFiles = $allFiles | Where-Object { 
            $_.Extension -match "^\.(sln|csproj|config)$" 
        }
        $totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum / 1MB
        
        Write-Host ("🚨 CORRUPTION SCAN SCOPE:") -ForegroundColor Red
        Write-Host ("   Total Files: {0:N0}" -f $allFiles.Count) -ForegroundColor Gray
        Write-Host ("   Text Files (encoding scan): {0:N0}" -f $textFiles.Count) -ForegroundColor Gray
        Write-Host ("   Project Files (integrity scan): {0:N0}" -f $projectFiles.Count) -ForegroundColor Gray
        Write-Host ("   Total Size: {0:F1} MB" -f $totalSize) -ForegroundColor Gray
        
        # Corruption scan is generally fast but thorough
        $estimatedMinutes = [Math]::Ceiling(($textFiles.Count * 0.008) + ($projectFiles.Count * 0.05))
        
        if ($estimatedMinutes -gt 3) {
            Write-Host "`n⚠️  LARGE PROJECT DETECTED!" -ForegroundColor Red
            Write-Host ("🕐 Estimated corruption scan time: {0}-{1} minutes" -f $estimatedMinutes, ($estimatedMinutes * 1.5)) -ForegroundColor DarkYellow
            Write-Host "🛡️  ULTIMATE CORRUPTION SCAN will:" -ForegroundColor Red
            Write-Host "   • Scan ALL files for encoding corruption and BOM issues" -ForegroundColor Gray
            Write-Host "   • Detect merge conflict markers and orphaned conflicts" -ForegroundColor Gray
            Write-Host "   • Analyze project integrity and missing references" -ForegroundColor Gray
            Write-Host "   • Perform build error analysis and triage" -ForegroundColor Gray
            Write-Host "   • Generate comprehensive corruption health dashboard" -ForegroundColor Gray
            
            Write-Host "`n🎯 Corruption Detection Options:" -ForegroundColor Red
            Write-Host "   Y - FULL INFINITY SCAN (recommended for complete corruption detection)" -ForegroundColor Green
            Write-Host "   Q - Quick corruption check (basic file integrity only)" -ForegroundColor DarkYellow
            Write-Host "   X - Exit and run individual corruption scanners" -ForegroundColor Red
            
            do {
                $choice = Read-Host "`nProceed with ULTIMATE CORRUPTION DETECTION? (Y/Q/X)"
                $choice = $choice.ToUpper()
            } while ($choice -notin @('Y', 'Q', 'X'))
            
            switch ($choice) {
                'Y' { 
                    Write-Host "🛡️  INITIATING FULL INFINITY CORRUPTION SCAN..." -ForegroundColor Red
                    return @{ Mode = "Infinity"; Continue = $true }
                }
                'Q' { 
                    Write-Host "⚡ Running quick corruption check..." -ForegroundColor DarkYellow
                    return @{ Mode = "Quick"; Continue = $true }
                }
                'X' { 
                    Write-Host "❌ Corruption scan cancelled. Run individual scripts for targeted analysis." -ForegroundColor Red
                    return @{ Mode = "Cancel"; Continue = $false }
                }
            }
        } else {
            Write-Host "✅ Project size is manageable - proceeding with FULL INFINITY SCAN" -ForegroundColor Green
            return @{ Mode = "Infinity"; Continue = $true }
        }
    }
    catch {
        Write-Host "⚠️  Could not estimate corruption scan complexity: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return @{ Mode = "Infinity"; Continue = $true }
    }
}

# Function to run corruption detection script with enhanced messaging
function Invoke-CorruptionScript {
    param(
        [string]$ScriptPath,
        [string]$ScriptName,
        [string]$Description,
        [string]$CorruptionType,
        [int]$Current,
        [int]$Total
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    Write-Host "`n🔍 [$Current/$Total] SCANNING: $ScriptName" -ForegroundColor Red
    Write-Host "   🛡️  $Description" -ForegroundColor Gray
    Write-Host "   🎯 Detecting: $CorruptionType" -ForegroundColor DarkGray
    Write-Host "   🕐 Started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor DarkGray
    
    try {
        if (Test-Path $ScriptPath) {
            try {
                # Execute script with error capture
                $output = & powershell.exe -ExecutionPolicy Bypass -File $ScriptPath 2>&1
                $success = $LASTEXITCODE -eq 0
            }
            catch {
                $output = $_.Exception.Message
                $success = $false
            }
            
            $stopwatch.Stop()
            $duration = $stopwatch.Elapsed.TotalSeconds
            
            if ($success) {
                Write-Host "   ✅ CORRUPTION SCAN COMPLETE in $($duration.ToString('F1'))s" -ForegroundColor Green
                return [PSCustomObject]@{
                    ScriptName = $ScriptName
                    CorruptionType = $CorruptionType
                    Status = "Success"
                    Duration = $duration
                    Output = $output
                    Error = $null
                }
            } else {
                Write-Host "   ⚠️  SCAN COMPLETED WITH WARNINGS in $($duration.ToString('F1'))s" -ForegroundColor DarkYellow
                return [PSCustomObject]@{
                    ScriptName = $ScriptName
                    CorruptionType = $CorruptionType
                    Status = "Warning"
                    Duration = $duration
                    Output = $output
                    Error = "Script execution issues detected"
                }
            }
        } else {
            Write-Host "   ❌ CORRUPTION SCANNER NOT FOUND: $ScriptPath" -ForegroundColor Red
            return [PSCustomObject]@{
                ScriptName = $ScriptName
                CorruptionType = $CorruptionType
                Status = "NotFound"
                Duration = 0
                Output = $null
                Error = "Corruption scanner script not found"
            }
        }
    }
    catch {
        $stopwatch.Stop()
        Write-Host "   💥 CORRUPTION SCAN FAILED: $($_.Exception.Message)" -ForegroundColor Red
        return [PSCustomObject]@{
            ScriptName = $ScriptName
            CorruptionType = $CorruptionType
            Status = "Failed"
            Duration = $stopwatch.Elapsed.TotalSeconds
            Output = $null
            Error = $_.Exception.Message
        }
    }
}

# Function to get corruption statistics
function Get-CorruptionStatistics {
    Write-Host "`n📊 Calculating corruption-prone file statistics..." -ForegroundColor DarkGray
    
    $stats = [PSCustomObject]@{
        TotalFiles = 0
        TextFiles = 0
        ProjectFiles = 0
        ConfigFiles = 0
        SourceFiles = 0
        TotalSize = 0
        RiskLevel = "Unknown"
    }
    
    try {
        # Get all files for corruption analysis
        $allFiles = Get-ChildItem -Path $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
            $_.FullName -notmatch "[\\/]\.git[\\/]"
        }
        
        $stats.TotalFiles = $allFiles.Count
        $stats.TextFiles = ($allFiles | Where-Object { 
            $_.Extension -match "^\.(cs|txt|md|json|xml|config|yaml|yml|ini|log|ps1|bat|cmd|sh)$" 
        }).Count
        $stats.ProjectFiles = ($allFiles | Where-Object { 
            $_.Extension -match "^\.(sln|csproj)$" 
        }).Count
        $stats.ConfigFiles = ($allFiles | Where-Object { 
            $_.Extension -match "^\.(config|xml|json|ini)$" 
        }).Count
        $stats.SourceFiles = ($allFiles | Where-Object { 
            $_.Extension -match "^\.(cs|cpp|h|js|ts|py)$" 
        }).Count
        $stats.TotalSize = [Math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        
        # Determine corruption risk level
        if ($stats.SourceFiles -gt 100 -or $stats.ProjectFiles -gt 5) {
            $stats.RiskLevel = "HIGH"
        } elseif ($stats.SourceFiles -gt 50 -or $stats.ProjectFiles -gt 2) {
            $stats.RiskLevel = "MEDIUM"
        } else {
            $stats.RiskLevel = "LOW"
        }
        
        Write-Host "   ✅ Corruption statistics calculated successfully" -ForegroundColor Green
        Write-Host "   🚨 Corruption Risk Level: $($stats.RiskLevel)" -ForegroundColor $(if ($stats.RiskLevel -eq "HIGH") { "Red" } elseif ($stats.RiskLevel -eq "MEDIUM") { "DarkYellow" } else { "Green" })
    }
    catch {
        Write-Host "   ⚠️  Error calculating corruption statistics: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
    
    return $stats
}

# Estimate corruption scan complexity
$scanEstimate = Get-CorruptionScanEstimate -path $ProjectRoot

if (-not $scanEstimate.Continue) {
    Write-Host "`nCorruption scan cancelled by user." -ForegroundColor Red
    Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
    Read-Host
    return
}

# ULTIMATE CORRUPTION DETECTION SCRIPTS - The complete arsenal
$allCorruptionScripts = @(
    @{
        Name = "Merge Conflict Detection"
        Script = "Generate-ConflictMarkersReport.ps1"
        Description = "Scanning for merge conflict markers and orphaned conflicts"
        CorruptionType = "Git Merge Conflicts & Repository Corruption"
        Critical = $true
        Quick = $true
    },
    @{
        Name = "File Encoding Corruption Analysis"
        Script = "Generate-FileEncodingReport.ps1"
        Description = "Detecting encoding corruption, BOM issues, and character problems"
        CorruptionType = "File Encoding & Character Corruption"
        Critical = $true
        Quick = $true
    },
    @{
        Name = "Project Integrity Verification"
        Script = "Generate-ProjectIntegrityReport.ps1"
        Description = "Analyzing project structure, missing references, and broken dependencies"
        CorruptionType = "Project Structure & Reference Corruption"
        Critical = $true
        Quick = $false
    },
    @{
        Name = "Build Error Analysis"
        Script = "Generate-BuildErrorReport.ps1"
        Description = "Performing compilation analysis and detecting build corruption"
        CorruptionType = "Build System & Compilation Corruption"
        Critical = $true
        Quick = $false
    },
    @{
        Name = "Duplicate Code Detection"
        Script = "Generate-DuplicateCodeReport.ps1"
        Description = "Identifying duplicate code blocks that may indicate copy corruption"
        CorruptionType = "Code Duplication & Copy-Paste Corruption"
        Critical = $false
        Quick = $false
    }
)

# Filter scripts based on scan mode
if ($scanEstimate.Mode -eq "Quick") {
    $corruptionScripts = $allCorruptionScripts | Where-Object { $_.Quick }
    Write-Host "`n⚡ Quick Corruption Check: Running $($corruptionScripts.Count) essential scanners" -ForegroundColor DarkYellow
} else {
    $corruptionScripts = $allCorruptionScripts
    Write-Host "`n🛡️  INFINITY SCAN MODE: Running ALL $($corruptionScripts.Count) corruption detectors" -ForegroundColor Red
}

# Get corruption statistics
$corruptionStats = Get-CorruptionStatistics

# Execute all corruption detection scripts
$corruptionResults = @()
$totalStartTime = Get-Date
$scriptIndex = 1

Write-Host "`n🚨 INITIATING ULTIMATE CORRUPTION DETECTION..." -ForegroundColor Red
Write-Host "===============================================" -ForegroundColor Red

foreach ($scriptInfo in $corruptionScripts) {
    $scriptPath = Join-Path $ScriptDir $scriptInfo.Script
    $result = Invoke-CorruptionScript -ScriptPath $scriptPath -ScriptName $scriptInfo.Name -Description $scriptInfo.Description -CorruptionType $scriptInfo.CorruptionType -Current $scriptIndex -Total $corruptionScripts.Count
    $result | Add-Member -MemberType NoteProperty -Name "Critical" -Value $scriptInfo.Critical
    $corruptionResults += $result
    
    $scriptIndex++
    Start-Sleep -Milliseconds 200  # Brief pause for dramatic effect
}

$totalDuration = ((Get-Date) - $totalStartTime).TotalSeconds

# Generate ULTIMATE CORRUPTION REPORT
Write-Host "`n🛡️  GENERATING ULTIMATE CORRUPTION REPORT..." -ForegroundColor Red
Write-Host "=============================================" -ForegroundColor Red

# Analyze corruption findings
Write-Host "🔬 Analyzing corruption patterns and extracting critical findings..." -ForegroundColor DarkRed

$corruptionFindings = @()
$criticalCorruption = @()
$totalCorruptionIssues = 0

foreach ($result in $corruptionResults) {
    $findings = [PSCustomObject]@{
        ScriptName = $result.ScriptName
        CorruptionType = $result.CorruptionType
        Status = $result.Status
        Duration = $result.Duration
        Critical = $result.Critical
        IssuesFound = 0
        CriticalIssues = 0
        Severity = "CLEAN"
        KeyMetrics = @()
        CorruptionDetails = @()
    }
    
    if ($result.Output -and $result.Status -eq "Success") {
        $output = $result.Output -join "`n"
        
        # Extract corruption-specific metrics
        switch ($result.ScriptName) {
            "Merge Conflict Detection" {
                if ($output -match "Real conflicts found: (\d+)") { 
                    $conflicts = [int]$matches[1]
                    $findings.IssuesFound = $conflicts
                    $findings.KeyMetrics += "Real Conflicts: $conflicts"
                    if ($conflicts -gt 0) {
                        $findings.Severity = "CRITICAL"
                        $findings.CriticalIssues = $conflicts
                        $criticalCorruption += "🚨 $conflicts merge conflicts detected"
                    }
                }
                if ($output -match "Suspicious markers found: (\d+)") { 
                    $suspicious = [int]$matches[1]
                    $findings.KeyMetrics += "Suspicious Markers: $suspicious"
                    if ($suspicious -gt 0) {
                        $findings.CorruptionDetails += "$suspicious suspicious conflict markers"
                    }
                }
            }
            "File Encoding Corruption Analysis" {
                if ($output -match "Critical issues: (\d+)") { 
                    $critical = [int]$matches[1]
                    $findings.CriticalIssues = $critical
                    $findings.KeyMetrics += "Critical Encoding Issues: $critical"
                    if ($critical -gt 0) {
                        $findings.Severity = "CRITICAL"
                        $criticalCorruption += "🚨 $critical critical encoding corruption issues"
                    }
                }
                if ($output -match "High priority: (\d+)") { 
                    $high = [int]$matches[1]
                    $findings.IssuesFound += $high
                    $findings.KeyMetrics += "High Priority: $high"
                    if ($high -gt 0 -and $findings.Severity -eq "CLEAN") {
                        $findings.Severity = "HIGH"
                    }
                }
                if ($output -match "Files with BOM: (\d+)") { 
                    $bom = [int]$matches[1]
                    $findings.KeyMetrics += "BOM Files: $bom"
                    if ($bom -gt 0) {
                        $findings.CorruptionDetails += "$bom files with potential BOM issues"
                    }
                }
            }
            "Project Integrity Verification" {
                if ($output -match "Critical issues: (\d+)") { 
                    $critical = [int]$matches[1]
                    $findings.CriticalIssues = $critical
                    $findings.KeyMetrics += "Critical Integrity Issues: $critical"
                    if ($critical -gt 0) {
                        $findings.Severity = "CRITICAL"
                        $criticalCorruption += "🚨 $critical critical project integrity issues"
                    }
                }
                if ($output -match "High priority: (\d+)") { 
                    $high = [int]$matches[1]
                    $findings.IssuesFound += $high
                    $findings.KeyMetrics += "High Priority: $high"
                }
                if ($output -match "Orphaned files: (\d+)") { 
                    $orphaned = [int]$matches[1]
                    $findings.KeyMetrics += "Orphaned Files: $orphaned"
                    if ($orphaned -gt 0) {
                        $findings.CorruptionDetails += "$orphaned orphaned files detected"
                    }
                }
            }
            "Build Error Analysis" {
                if ($output -match "Failed builds: (\d+)") { 
                    $failed = [int]$matches[1]
                    $findings.CriticalIssues = $failed
                    $findings.KeyMetrics += "Failed Builds: $failed"
                    if ($failed -gt 0) {
                        $findings.Severity = "CRITICAL"
                        $criticalCorruption += "🚨 $failed build failures detected"
                    }
                }
                if ($output -match "Unique errors: (\d+)") { 
                    $errors = [int]$matches[1]
                    $findings.IssuesFound = $errors
                    $findings.KeyMetrics += "Build Errors: $errors"
                }
            }
            "Duplicate Code Detection" {
                if ($output -match "duplicate code groups found: (\d+)") { 
                    $duplicates = [int]$matches[1]
                    $findings.IssuesFound = $duplicates
                    $findings.KeyMetrics += "Duplicate Groups: $duplicates"
                    if ($duplicates -gt 10) {
                        $findings.Severity = "MEDIUM"
                        $findings.CorruptionDetails += "$duplicates duplicate code groups (potential copy corruption)"
                    }
                }
            }
        }
    }
    
    $totalCorruptionIssues += $findings.IssuesFound + $findings.CriticalIssues
    $corruptionFindings += $findings
}

# Calculate corruption health metrics
$successfulScans = $corruptionResults | Where-Object { $_.Status -eq "Success" }
$failedScans = $corruptionResults | Where-Object { $_.Status -eq "Failed" }
$warningScans = $corruptionResults | Where-Object { $_.Status -eq "Warning" }

$criticalCorruptionCount = ($corruptionFindings | Where-Object { $_.Severity -eq "CRITICAL" }).Count
$highCorruptionCount = ($corruptionFindings | Where-Object { $_.Severity -eq "HIGH" }).Count
$mediumCorruptionCount = ($corruptionFindings | Where-Object { $_.Severity -eq "MEDIUM" }).Count

# Generate ULTIMATE CORRUPTION REPORT content
Write-Host "`n📝 Creating ULTIMATE CORRUPTION HEALTH DASHBOARD..." -ForegroundColor DarkRed

$reportContent = @()

# Header with dramatic styling
$reportContent += "# 🛡️ ULTIMATE CORRUPTION DETECTION REPORT"
$reportContent += "## 🚨 INFINITY SCAN RESULTS - COMPLETE CORRUPTION ANALYSIS"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Scan Mode**: $($scanEstimate.Mode)"
$reportContent += "**Total Scan Time**: $($totalDuration.ToString('F1')) seconds"
$reportContent += "**Corruption Risk Level**: $($corruptionStats.RiskLevel)"
$reportContent += ""

# CORRUPTION THREAT LEVEL
$corruptionThreatLevel = if ($criticalCorruptionCount -gt 0) { 
    "🚨 CRITICAL THREAT" 
} elseif ($highCorruptionCount -gt 0) { 
    "⚠️ HIGH THREAT" 
} elseif ($mediumCorruptionCount -gt 0) { 
    "📝 MEDIUM THREAT" 
} else { 
    "✅ MINIMAL THREAT" 
}

$reportContent += "## 🚨 CORRUPTION THREAT LEVEL: $corruptionThreatLevel"
$reportContent += ""

if ($criticalCorruption.Count -gt 0) {
    $reportContent += "### 💥 CRITICAL CORRUPTION DETECTED:"
    foreach ($critical in $criticalCorruption) {
        $reportContent += "- $critical"
    }
    $reportContent += ""
}

# Executive Corruption Summary
$reportContent += "## 📊 Corruption Detection Summary"
$reportContent += ""
$reportContent += "| Metric | Value | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| **Corruption Scanners Executed** | $($corruptionResults.Count) | - |"
$reportContent += "| **Successful Scans** | $($successfulScans.Count) | $(if ($successfulScans.Count -eq $corruptionResults.Count) { "✅ All Complete" } else { "⚠️ Some Issues" }) |"
$reportContent += "| **Failed Scans** | $($failedScans.Count) | $(if ($failedScans.Count -eq 0) { "✅ None" } else { "❌ Action Required" }) |"
$reportContent += "| **Critical Corruption Types** | $criticalCorruptionCount | $(if ($criticalCorruptionCount -eq 0) { "✅ None" } else { "🚨 IMMEDIATE ACTION" }) |"
$reportContent += "| **High Severity Issues** | $highCorruptionCount | $(if ($highCorruptionCount -eq 0) { "✅ None" } else { "⚠️ Review Required" }) |"
$reportContent += "| **Total Corruption Issues** | $totalCorruptionIssues | $(if ($totalCorruptionIssues -eq 0) { "🎉 CLEAN CODEBASE" } else { "📝 Issues Found" }) |"
$reportContent += "| **Files Analyzed** | $($corruptionStats.TotalFiles) | - |"
$reportContent += "| **Source Files at Risk** | $($corruptionStats.SourceFiles) | - |"
$reportContent += "| **Project Files Checked** | $($corruptionStats.ProjectFiles) | - |"
$reportContent += ""

# Corruption Health Score
$corruptionHealthScore = if ($totalCorruptionIssues -eq 0 -and $criticalCorruptionCount -eq 0) { 
    100 
} else { 
    [Math]::Max(0, 100 - ($criticalCorruptionCount * 20) - ($highCorruptionCount * 10) - ($mediumCorruptionCount * 5))
}

$healthIcon = if ($corruptionHealthScore -ge 95) { "🟢" } elseif ($corruptionHealthScore -ge 80) { "🟡" } else { "🔴" }
$reportContent += "## 🎯 CORRUPTION HEALTH SCORE: $healthIcon $corruptionHealthScore%"
$reportContent += ""

# Detailed Corruption Analysis
$reportContent += "## 🔬 Detailed Corruption Analysis"
$reportContent += ""

foreach ($finding in $corruptionFindings | Sort-Object { if ($_.Severity -eq "CRITICAL") { 1 } elseif ($_.Severity -eq "HIGH") { 2 } else { 3 } }) {
    $statusIcon = switch ($finding.Status) {
        "Success" { if ($finding.Severity -eq "CRITICAL") { "🚨" } elseif ($finding.Severity -eq "HIGH") { "⚠️" } elseif ($finding.Severity -eq "MEDIUM") { "📝" } else { "✅" } }
        "Warning" { "⚠️" }
        "Failed" { "❌" }
        default { "❓" }
    }
    
    $reportContent += "### $statusIcon $($finding.ScriptName)"
    $reportContent += ""
    $reportContent += "**Corruption Type**: $($finding.CorruptionType)"
    $reportContent += "**Severity**: $($finding.Severity)"
    $reportContent += "**Scan Duration**: $($finding.Duration.ToString('F1'))s"
    $reportContent += "**Critical Issues**: $($finding.CriticalIssues)"
    $reportContent += "**Total Issues**: $($finding.IssuesFound)"
    $reportContent += ""
    
    if ($finding.KeyMetrics.Count -gt 0) {
        $reportContent += "**Key Metrics**:"
        foreach ($metric in $finding.KeyMetrics) {
            $reportContent += "- $metric"
        }
        $reportContent += ""
    }
    
    if ($finding.CorruptionDetails.Count -gt 0) {
        $reportContent += "**Corruption Details**:"
        foreach ($detail in $finding.CorruptionDetails) {
            $reportContent += "- $detail"
        }
        $reportContent += ""
    }
}

# Action Plan
$reportContent += "## 🎯 CORRUPTION MITIGATION ACTION PLAN"
$reportContent += ""

if ($criticalCorruptionCount -gt 0) {
    $reportContent += "### 🚨 IMMEDIATE CRITICAL ACTION REQUIRED"
    $reportContent += ""
    $reportContent += "**CRITICAL CORRUPTION DETECTED** - Project integrity at risk!"
    $reportContent += ""
    $reportContent += "**Immediate Steps:**"
    $reportContent += "1. **🛡️ STOP DEVELOPMENT** - Do not commit any changes until corruption is resolved"
    $reportContent += "2. **💾 BACKUP PROJECT** - Create full project backup before making changes"
    $reportContent += "3. **🔧 FIX CRITICAL ISSUES** - Address all critical corruption immediately"
    $reportContent += "4. **✅ VERIFY INTEGRITY** - Re-run corruption scan to confirm fixes"
    $reportContent += ""
    
    foreach ($critical in $criticalCorruption) {
        $reportContent += "- $critical"
    }
    $reportContent += ""
} elseif ($highCorruptionCount -gt 0) {
    $reportContent += "### ⚠️ HIGH PRIORITY CORRUPTION FIXES"
    $reportContent += ""
    $reportContent += "**HIGH SEVERITY CORRUPTION** - Should be addressed soon"
    $reportContent += ""
    $reportContent += "1. **🔍 REVIEW ISSUES** - Examine all high severity corruption findings"
    $reportContent += "2. **📝 PLAN FIXES** - Create remediation plan for identified issues"
    $reportContent += "3. **🔧 IMPLEMENT FIXES** - Address corruption systematically"
    $reportContent += "4. **🛡️ PREVENT RECURRENCE** - Implement safeguards against future corruption"
    $reportContent += ""
} else {
    $reportContent += "### ✅ EXCELLENT CORRUPTION RESISTANCE!"
    $reportContent += ""
    $reportContent += "**CORRUPTION-FREE CODEBASE** - Your project demonstrates excellent integrity!"
    $reportContent += ""
    $reportContent += "**Maintenance Recommendations:**"
    $reportContent += "1. **🔄 REGULAR SCANS** - Run corruption detection before major releases"
    $reportContent += "2. **🛡️ PREVENTION** - Continue following best practices for file handling"
    $reportContent += "3. **📚 EDUCATION** - Share corruption prevention knowledge with team"
    $reportContent += "4. **⚡ MONITORING** - Include corruption checks in CI/CD pipeline"
}

# Best Practices for Corruption Prevention
$reportContent += ""
$reportContent += "## 🛡️ Corruption Prevention Best Practices"
$reportContent += ""
$reportContent += "### File System Corruption Prevention"
$reportContent += "- Use UTF-8 encoding without BOM for source files"
$reportContent += "- Implement consistent line ending handling (LF or CRLF)"
$reportContent += "- Avoid manual file editing that could introduce encoding issues"
$reportContent += "- Use proper Git configuration for text file handling"
$reportContent += ""
$reportContent += "### Project Structure Integrity"
$reportContent += "- Maintain consistent project references"
$reportContent += "- Use NuGet package management instead of manual DLL references"
$reportContent += "- Keep solution files synchronized with project structure"
$reportContent += "- Validate project integrity after major structural changes"
$reportContent += ""
$reportContent += "### Merge Conflict Prevention"
$reportContent += "- Pull frequently from main branch to minimize conflicts"
$reportContent += "- Use feature branches for isolated development"
$reportContent += "- Communicate about shared file modifications"
$reportContent += "- Set up proper merge tools and conflict resolution workflows"

# Scan Performance
$reportContent += ""
$reportContent += "## ⚡ Corruption Scan Performance"
$reportContent += ""
$reportContent += "| Scanner | Duration | Status | Efficiency |"
$reportContent += "|---------|----------|--------|------------|"

foreach ($result in $corruptionResults | Sort-Object Duration -Descending) {
    $efficiency = if ($result.Duration -lt 2) { "🚀 Excellent" } elseif ($result.Duration -lt 5) { "✅ Good" } else { "⏱️ Acceptable" }
    $statusIcon = switch ($result.Status) {
        "Success" { "✅" }
        "Warning" { "⚠️" }
        "Failed" { "❌" }
        default { "❓" }
    }
    $reportContent += "| $($result.ScriptName) | $($result.Duration.ToString('F1'))s | $statusIcon $($result.Status) | $efficiency |"
}

$reportContent += ""

# Generated Reports
$reportContent += "## 📄 Generated Corruption Analysis Reports"
$reportContent += ""
$reportContent += "This corruption scan has generated detailed reports in the `Reports/` directory:"
$reportContent += ""
$reportContent += "| Report Type | File Pattern | Purpose |"
$reportContent += "|-------------|--------------|---------|"
$reportContent += "| **Merge Conflicts** | `CONFLICT-MARKERS-REPORT_*.md` | Detailed conflict analysis |"
$reportContent += "| **File Encoding** | `FILE-ENCODING-REPORT_*.md` | Encoding corruption analysis |"
$reportContent += "| **Project Integrity** | `PROJECT-INTEGRITY-REPORT_*.md` | Structure integrity analysis |"
$reportContent += "| **Build Errors** | `BUILD-ERROR-REPORT_*.md` | Compilation issue analysis |"
$reportContent += "| **Duplicate Code** | `DUPLICATE-CODE-REPORT_*.md` | Code duplication analysis |"
$reportContent += ""

# Footer
$reportContent += "---"
$reportContent += ""
$reportContent += "## 🛡️ CORRUPTION GUARD SUMMARY"
$reportContent += ""
$reportContent += "**Corruption Threat Level**: $corruptionThreatLevel"
$reportContent += "**Health Score**: $healthIcon $corruptionHealthScore%"
$reportContent += "**Scan Completeness**: $($successfulScans.Count)/$($corruptionResults.Count) scanners successful"
$reportContent += ""
$reportContent += "**Next Actions:**"
if ($criticalCorruptionCount -gt 0) {
    $reportContent += "1. 🚨 **URGENT**: Address critical corruption immediately"
    $reportContent += "2. 💾 **BACKUP**: Secure project state before making changes"
    $reportContent += "3. 🔧 **FIX**: Resolve all identified corruption issues"
    $reportContent += "4. ✅ **VERIFY**: Re-run scan to confirm fixes"
} else {
    $reportContent += "1. 📊 **REVIEW**: Examine individual corruption reports for details"
    $reportContent += "2. 🛡️ **MAINTAIN**: Continue corruption prevention practices"
    $reportContent += "3. 🔄 **MONITOR**: Include regular corruption scans in workflow"
    $reportContent += "4. 📚 **EDUCATE**: Share corruption prevention knowledge"
}
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - ULTIMATE CORRUPTION DETECTOR*"
$reportContent += "*Protecting your codebase from all forms of corruption since 2025*"

# Create Reports directory if it doesn't exist
$reportsDir = Join-Path $ProjectRoot "Reports"
if (-not (Test-Path $reportsDir)) {
    try {
        New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
        Write-Host "`n📁 Created Reports directory: $reportsDir" -ForegroundColor Green
    }
    catch {
        Write-Host "`n⚠️ Could not create Reports directory, using project root" -ForegroundColor DarkYellow
        $reportsDir = $ProjectRoot
    }
}

# Generate timestamp for unique report names
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "ULTIMATE-CORRUPTION-REPORT_$timestamp.md"

# Save ULTIMATE CORRUPTION REPORT
try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "`n⚠️ Error saving ULTIMATE CORRUPTION REPORT: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

# Display ULTIMATE completion summary
Write-Host "`n🛡️  ULTIMATE CORRUPTION DETECTION COMPLETE!" -ForegroundColor Red
Write-Host "=============================================" -ForegroundColor Red
Write-Host "⏱️  Total Scan Time: $($totalDuration.ToString('F1')) seconds ($([Math]::Round($totalDuration/60, 1)) minutes)" -ForegroundColor Gray
Write-Host "🔍 Corruption Scanners Executed: $($corruptionResults.Count)" -ForegroundColor Gray
Write-Host "📊 Files Analyzed for Corruption: $($corruptionStats.TotalFiles)" -ForegroundColor Gray
Write-Host "🎯 Corruption Health Score: $healthIcon $corruptionHealthScore%" -ForegroundColor Gray

Write-Host "`n🚨 CORRUPTION DETECTION RESULTS:" -ForegroundColor Red
Write-Host "   ✅ Successful scans: $($successfulScans.Count)" -ForegroundColor Green
Write-Host "   ⚠️  Scans with warnings: $($warningScans.Count)" -ForegroundColor DarkYellow
Write-Host "   ❌ Failed scans: $($failedScans.Count)" -ForegroundColor Red
Write-Host "   🚨 Critical corruption types: $criticalCorruptionCount" -ForegroundColor Red
Write-Host "   📊 Total corruption issues: $totalCorruptionIssues" -ForegroundColor $(if ($totalCorruptionIssues -eq 0) { "Green" } else { "DarkYellow" })

# Display corruption threat level
Write-Host "`n🛡️  CORRUPTION THREAT ASSESSMENT:" -ForegroundColor Red
Write-Host "   $corruptionThreatLevel" -ForegroundColor $(if ($corruptionThreatLevel.Contains("CRITICAL")) { "Red" } elseif ($corruptionThreatLevel.Contains("HIGH")) { "DarkYellow" } else { "Green" })

if ($criticalCorruption.Count -gt 0) {
    Write-Host "`n💥 CRITICAL CORRUPTION DETECTED:" -ForegroundColor Red
    foreach ($critical in $criticalCorruption | Select-Object -First 3) {
        Write-Host "   $critical" -ForegroundColor Red
    }
    if ($criticalCorruption.Count -gt 3) {
        Write-Host "   ... and $($criticalCorruption.Count - 3) more critical issues" -ForegroundColor DarkGray
    }
}

# Show scan execution summary
Write-Host "`n⏱️  CORRUPTION SCANNER PERFORMANCE:" -ForegroundColor Red
foreach ($result in $corruptionResults) {
    $statusColor = switch ($result.Status) {
        "Success" { "Green" }
        "Warning" { "DarkYellow" }
        "Failed" { "Red" }
        default { "Gray" }
    }
    $corruptionIndicator = if ($corruptionFindings | Where-Object { $_.ScriptName -eq $result.ScriptName -and $_.Severity -eq "CRITICAL" }) {
        "🚨"
    } elseif ($corruptionFindings | Where-Object { $_.ScriptName -eq $result.ScriptName -and $_.Severity -eq "HIGH" }) {
        "⚠️"
    } else {
        "✅"
    }
    Write-Host "   $corruptionIndicator $($result.ScriptName): $($result.Status) ($($result.Duration.ToString('F1'))s)" -ForegroundColor $statusColor
}

if ($scanEstimate.Mode -eq "Quick") {
    Write-Host "`n⚡ Quick corruption check completed - for full INFINITY SCAN, run again and select 'Y'" -ForegroundColor DarkYellow
}

# OUTPUT PATH AT THE END for easy finding
if ($saveSuccess) {
    Write-Host "`n📄 ULTIMATE CORRUPTION REPORT SAVED:" -ForegroundColor Red
    Write-Host "   Location: $reportPath" -ForegroundColor Cyan
    Write-Host "   Size: $([Math]::Round((Get-Item $reportPath).Length / 1KB, 1)) KB" -ForegroundColor Gray
} else {
    Write-Host "`n❌ ULTIMATE CORRUPTION REPORT could not be saved" -ForegroundColor Red
}

# INTERACTIVE WORKFLOW LOOP
do {
    Write-Host "`n🎯 What would you like to do next?" -ForegroundColor Red
    Write-Host "   D - Display ULTIMATE CORRUPTION REPORT in console" -ForegroundColor Green
    Write-Host "   R - Re-run ULTIMATE CORRUPTION DETECTION" -ForegroundColor DarkYellow
    Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
    
    $choice = Read-Host "`nEnter choice (D/R/X)"
    $choice = $choice.ToUpper()
    
    switch ($choice) {
        'D' {
            if ($saveSuccess) {
                Write-Host "`n🛡️  DISPLAYING ULTIMATE CORRUPTION REPORT:" -ForegroundColor Red
                Write-Host "===========================================" -ForegroundColor Red
                try {
                    $reportDisplay = Get-Content -Path $reportPath -Raw
                    Write-Host $reportDisplay -ForegroundColor White
                    Write-Host "`n===========================================" -ForegroundColor Red
                    Write-Host "🛡️  END OF ULTIMATE CORRUPTION REPORT" -ForegroundColor Red
                }
                catch {
                    Write-Host "❌ Could not display ULTIMATE CORRUPTION REPORT: $_" -ForegroundColor Red
                }
            } else {
                Write-Host "❌ No ULTIMATE CORRUPTION REPORT available to display" -ForegroundColor Red
            }
        }
        'R' {
            Write-Host "`n🔄 RE-RUNNING ULTIMATE CORRUPTION DETECTION..." -ForegroundColor DarkYellow
            Write-Host "===============================================" -ForegroundColor DarkYellow
            & $MyInvocation.MyCommand.Path
            return
        }
        'X' {
            Write-Host "`n👋 Returning to DevOps menu..." -ForegroundColor Gray
            return
        }
        default {
            Write-Host "❌ Invalid choice. Please enter D, R, or X." -ForegroundColor Red
        }
    }
} while ($choice -notin @('X'))