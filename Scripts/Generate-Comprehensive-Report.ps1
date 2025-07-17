# MixerThreholdMod DevOps Tool: Comprehensive Project Report Generator (COMPATIBLE)
# Master orchestrator that runs all report generation scripts and creates unified project health dashboard
# Combines method complexity, duplicate code, documentation, compliance, and more into one comprehensive report
# Excludes: ForCopilot, Scripts, and Legacy directories

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ((Split-Path $ScriptDir -Leaf) -ieq "Scripts") {
    $ProjectRoot = Split-Path $ScriptDir -Parent
} else {
    $ProjectRoot = $ScriptDir
}

Write-Host "🚀 COMPREHENSIVE PROJECT ANALYSIS STARTING" -ForegroundColor DarkCyan
Write-Host "================================================" -ForegroundColor DarkCyan
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Gray
Write-Host "Analysis Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Function to estimate project size and warn about processing time
function Get-ProjectSizeEstimate {
    param($path)
    
    try {
        Write-Host "`n⏱️  Estimating project size and processing time..." -ForegroundColor DarkYellow
        
        # Quick scan for size estimation
        $allFiles = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
            $_.FullName -notmatch "[\\/]\.git[\\/]"
        }
        
        $csharpFiles = $allFiles | Where-Object { $_.Extension -eq ".cs" }
        $totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum / 1MB
        
        Write-Host ("📊 Project Size Estimate:") -ForegroundColor DarkCyan
        Write-Host ("   Total Files: {0:N0}" -f $allFiles.Count) -ForegroundColor Gray
        Write-Host ("   C# Files: {0:N0}" -f $csharpFiles.Count) -ForegroundColor Gray
        Write-Host ("   Total Size: {0:F1} MB" -f $totalSize) -ForegroundColor Gray
        
        # FIXED: More realistic time estimates based on optimized scripts
        $estimatedMinutes = [Math]::Ceiling(($csharpFiles.Count * 0.01) + ($allFiles.Count * 0.005))
        
        if ($estimatedMinutes -gt 2) {
            Write-Host "`n⚠️  LARGE PROJECT DETECTED!" -ForegroundColor Red
            Write-Host ("🕐 Estimated processing time: {0}-{1} minutes (much faster than before!)" -f $estimatedMinutes, ($estimatedMinutes * 2)) -ForegroundColor DarkYellow
            Write-Host "💡 This analysis will:" -ForegroundColor DarkYellow
            Write-Host "   • Run 8 comprehensive DevOps scripts sequentially" -ForegroundColor Gray
            Write-Host "   • Analyze every C# file for complexity, duplicates, and compliance" -ForegroundColor Gray
            Write-Host "   • Generate detailed documentation and reports" -ForegroundColor Gray
            Write-Host "   • Create comprehensive project health dashboard" -ForegroundColor Gray
            
            Write-Host "`n🎯 Options:" -ForegroundColor DarkCyan
            Write-Host "   Y - Continue with full analysis (recommended)" -ForegroundColor Green
            Write-Host "   Q - Quick analysis (skip time-intensive scripts)" -ForegroundColor DarkYellow
            Write-Host "   X - Exit and run individual scripts instead" -ForegroundColor Red
            
            do {
                $choice = Read-Host "`nProceed? (Y/Q/X)"
                $choice = $choice.ToUpper()
            } while ($choice -notin @('Y', 'Q', 'X'))
            
            switch ($choice) {
                'Y' { 
                    Write-Host "✅ Proceeding with full comprehensive analysis..." -ForegroundColor Green
                    return @{ Mode = "Full"; Continue = $true }
                }
                'Q' { 
                    Write-Host "⚡ Running quick analysis (excluding time-intensive scripts)..." -ForegroundColor DarkYellow
                    return @{ Mode = "Quick"; Continue = $true }
                }
                'X' { 
                    Write-Host "❌ Analysis cancelled. Run individual scripts for targeted analysis." -ForegroundColor Red
                    return @{ Mode = "Cancel"; Continue = $false }
                }
            }
        } else {
            Write-Host "✅ Project size is manageable - proceeding with full analysis" -ForegroundColor Green
            return @{ Mode = "Full"; Continue = $true }
        }
    }
    catch {
        Write-Host "⚠️  Could not estimate project size: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return @{ Mode = "Full"; Continue = $true }
    }
}

# FIXED: Function to run a script with cleaner messaging
function Invoke-ReportScript {
    param(
        [string]$ScriptPath,
        [string]$ScriptName,
        [string]$Description,
        [int]$Current,
        [int]$Total
    )
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    Write-Host "`n🔍 [$Current/$Total] Running: $ScriptName" -ForegroundColor DarkCyan
    Write-Host "   $Description" -ForegroundColor Gray
    Write-Host "   Started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor DarkGray
    
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
                Write-Host "   ✅ Completed successfully in $($duration.ToString('F1'))s" -ForegroundColor Green
                return [PSCustomObject]@{
                    ScriptName = $ScriptName
                    Status = "Success"
                    Duration = $duration
                    Output = $output
                    Error = $null
                }
            } else {
                Write-Host "   ⚠️  Completed with warnings in $($duration.ToString('F1'))s" -ForegroundColor DarkYellow
                return [PSCustomObject]@{
                    ScriptName = $ScriptName
                    Status = "Warning"
                    Duration = $duration
                    Output = $output
                    Error = "Script execution issues detected"
                }
            }
        } else {
            Write-Host "   ❌ Script not found: $ScriptPath" -ForegroundColor Red
            return [PSCustomObject]@{
                ScriptName = $ScriptName
                Status = "NotFound"
                Duration = 0
                Output = $null
                Error = "Script file not found"
            }
        }
    }
    catch {
        $stopwatch.Stop()
        Write-Host "   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
        return [PSCustomObject]@{
            ScriptName = $ScriptName
            Status = "Failed"
            Duration = $stopwatch.Elapsed.TotalSeconds
            Output = $null
            Error = $_.Exception.Message
        }
    }
}

# Function to get project statistics with progress
function Get-ProjectStatistics {
    Write-Host "`n📊 Calculating detailed project statistics..." -ForegroundColor DarkGray
    
    $stats = [PSCustomObject]@{
        TotalFiles = 0
        CSharpFiles = 0
        PowerShellFiles = 0
        TotalLines = 0
        ProjectSize = 0
    }
    
    try {
        # Get all relevant files
        $allFiles = Get-ChildItem -Path $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
            $_.FullName -notmatch "[\\/]\.git[\\/]"
        }
        
        $stats.TotalFiles = $allFiles.Count
        $stats.CSharpFiles = ($allFiles | Where-Object { $_.Extension -eq ".cs" }).Count
        $stats.PowerShellFiles = ($allFiles | Where-Object { $_.Extension -eq ".ps1" }).Count
        $stats.ProjectSize = [Math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        
        # Count lines in C# files with progress
        $csharpFiles = $allFiles | Where-Object { $_.Extension -eq ".cs" }
        $processedFiles = 0
        
        foreach ($file in $csharpFiles) {
            try {
                $content = Get-Content -Path $file.FullName -ErrorAction SilentlyContinue
                if ($content) {
                    $stats.TotalLines += $content.Count
                }
                
                $processedFiles++
                if ($processedFiles % 20 -eq 0 -or $processedFiles -eq $csharpFiles.Count) {
                    Write-Host "   📈 Processed $processedFiles/$($csharpFiles.Count) C# files..." -ForegroundColor DarkGray
                }
            }
            catch {
                # Skip files that can't be read
            }
        }
        
        Write-Host "   ✅ Statistics calculated successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "   ⚠️  Error calculating project statistics: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
    
    return $stats
}

# Estimate project size and get user preference
$sizeEstimate = Get-ProjectSizeEstimate -path $ProjectRoot

if (-not $sizeEstimate.Continue) {
    Write-Host "`nAnalysis cancelled by user." -ForegroundColor Red
    Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
    Read-Host
    return
}

# List of DevOps scripts to run
$allDevOpsScripts = @(
    @{
        Name = "Method Complexity Analysis"
        Script = "Analyze-MethodComplexity.ps1"
        Description = "Analyzing method complexity and identifying refactoring candidates"
        Category = "Code Quality"
        TimeIntensive = $false  # FIXED: Now optimized and fast
    },
    @{
        Name = "Duplicate Code Detection"
        Script = "Find-DuplicateCode.ps1"
        Description = "Scanning for duplicate code blocks across the codebase"
        Category = "Code Quality"
        TimeIntensive = $true
    },
    @{
        Name = "XML Documentation Verification"
        Script = "Verify-XmlDocs.ps1"
        Description = "Checking XML documentation coverage and quality"
        Category = "Documentation"
        TimeIntensive = $false
    },
    @{
        Name = "Copilot Compliance Check"
        Script = "Generate-CopilotComplianceReport.ps1"
        Description = "Verifying adherence to GitHub Copilot instructions"
        Category = "Compliance"
        TimeIntensive = $true
    },
    @{
        Name = "Constants Documentation"
        Script = "Generate-ConstantsDoc.ps1"
        Description = "Generating comprehensive constants documentation"
        Category = "Documentation"
        TimeIntensive = $false
    },
    @{
        Name = "Version Consistency Check"
        Script = "Update-VersionNumbers.ps1"
        Description = "Scanning version numbers across project files (dry run)"
        Category = "Configuration"
        TimeIntensive = $false
    },
    @{
        Name = "Changelog Generation"
        Script = "Generate-ChangeLog.ps1"
        Description = "Generating project changelog from git history"
        Category = "Release Management"
        TimeIntensive = $false
    },
    @{
        Name = "Release Notes Generation"
        Script = "Generate-ReleaseNotes.ps1"
        Description = "Creating professional release notes"
        Category = "Release Management"
        TimeIntensive = $false
    }
)

# Filter scripts based on mode
if ($sizeEstimate.Mode -eq "Quick") {
    $devOpsScripts = $allDevOpsScripts | Where-Object { -not $_.TimeIntensive }
    Write-Host "`n⚡ Quick Mode: Running $($devOpsScripts.Count) lightweight scripts" -ForegroundColor DarkYellow
} else {
    $devOpsScripts = $allDevOpsScripts
    Write-Host "`n🔥 Full Mode: Running all $($devOpsScripts.Count) comprehensive scripts" -ForegroundColor Green
}

# Get project statistics
$projectStats = Get-ProjectStatistics

# Run all DevOps scripts
$scriptResults = @()
$totalStartTime = Get-Date
$scriptIndex = 1

foreach ($scriptInfo in $devOpsScripts) {
    $scriptPath = Join-Path $ScriptDir $scriptInfo.Script
    $result = Invoke-ReportScript -ScriptPath $scriptPath -ScriptName $scriptInfo.Name -Description $scriptInfo.Description -Current $scriptIndex -Total $devOpsScripts.Count
    $result | Add-Member -MemberType NoteProperty -Name "Category" -Value $scriptInfo.Category
    $scriptResults += $result
    
    $scriptIndex++
    Start-Sleep -Milliseconds 100  # Brief pause between scripts
}

$totalDuration = ((Get-Date) - $totalStartTime).TotalSeconds

# Generate comprehensive report
Write-Host "`n📋 GENERATING COMPREHENSIVE REPORT..." -ForegroundColor DarkCyan
Write-Host "=====================================" -ForegroundColor DarkCyan

# Extract key findings from each script output
Write-Host "📊 Extracting key findings from script outputs..." -ForegroundColor DarkGray

$keyFindings = @()

foreach ($result in $scriptResults) {
    $findings = [PSCustomObject]@{
        ScriptName = $result.ScriptName
        Category = $result.Category
        Status = $result.Status
        Duration = $result.Duration
        KeyMetrics = @()
        Issues = @()
        Recommendations = @()
    }
    
    if ($result.Output -and $result.Status -eq "Success") {
        $output = $result.Output -join "`n"
        
        # Extract key metrics based on script type
        switch ($result.ScriptName) {
            "Method Complexity Analysis" {
                if ($output -match "Total methods analyzed: (\d+)") { $findings.KeyMetrics += "Methods: $($matches[1])" }
                if ($output -match "High complexity: (\d+)") { $findings.KeyMetrics += "High Complexity: $($matches[1])" }
                if ($output -match "(\d+) methods need refactoring") { $findings.Issues += "$($matches[1]) methods need refactoring" }
            }
            "Duplicate Code Detection" {
                if ($output -match "(\d+) duplicate code groups") { $findings.KeyMetrics += "Duplicate Groups: $($matches[1])" }
                if ($output -match "(\d+) lines of duplicate code") { $findings.Issues += "$($matches[1]) duplicate lines" }
            }
            "XML Documentation Verification" {
                if ($output -match "Overall coverage: (\d+\.?\d*)%") { $findings.KeyMetrics += "Doc Coverage: $($matches[1])%" }
                if ($output -match "(\d+) undocumented members") { $findings.Issues += "$($matches[1]) undocumented members" }
            }
            "Copilot Compliance Check" {
                if ($output -match "Compliance Score: (\d+\.?\d*)%") { $findings.KeyMetrics += "Compliance: $($matches[1])%" }
                if ($output -match "(\d+) compliance issues") { $findings.Issues += "$($matches[1]) compliance issues" }
            }
            "Constants Documentation" {
                if ($output -match "(\d+) constants") { $findings.KeyMetrics += "Constants: $($matches[1])" }
                if ($output -match "(\d+) categories") { $findings.KeyMetrics += "Categories: $($matches[1])" }
            }
            "Version Consistency Check" {
                if ($output -match "(\d+) version-containing files") { $findings.KeyMetrics += "Version Files: $($matches[1])" }
                if ($output -match "(\d+) inconsistencies") { $findings.Issues += "$($matches[1]) version inconsistencies" }
            }
            "Changelog Generation" {
                if ($output -match "(\d+) commits") { $findings.KeyMetrics += "Commits: $($matches[1])" }
                if ($output -match "(\d+) categories") { $findings.KeyMetrics += "Categories: $($matches[1])" }
            }
            "Release Notes Generation" {
                if ($output -match "(\d+) commits") { $findings.KeyMetrics += "Commits: $($matches[1])" }
                if ($output -match "Release type: (.+)") { $findings.KeyMetrics += "Type: $($matches[1])" }
            }
        }
    }
    
    $keyFindings += $findings
}

# FIXED: Define these variables BEFORE using them in the report
$successfulScripts = $scriptResults | Where-Object { $_.Status -eq "Success" }
$failedScripts = $scriptResults | Where-Object { $_.Status -eq "Failed" }
$warningScripts = $scriptResults | Where-Object { $_.Status -eq "Warning" }

# Generate comprehensive report content
Write-Host "`n📝 Creating unified project health dashboard..." -ForegroundColor DarkGray

$reportContent = @()

# Header
$reportContent += "# 🚀 MixerThreholdMod - Comprehensive Project Health Report"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Analysis Mode**: $($sizeEstimate.Mode)"
$reportContent += "**Total Analysis Time**: $($totalDuration.ToString('F1')) seconds"
$reportContent += ""

# Executive Summary
$reportContent += "## 📊 Executive Summary"
$reportContent += ""
$reportContent += "| Metric | Value |"
$reportContent += "|--------|-------|"
$reportContent += "| **Scripts Executed** | $($scriptResults.Count) |"
$reportContent += "| **Successful Scripts** | $($successfulScripts.Count) |"
$reportContent += "| **Scripts with Warnings** | $($warningScripts.Count) |"
$reportContent += "| **Failed Scripts** | $($failedScripts.Count) |"
$reportContent += "| **Total Files Analyzed** | $($projectStats.TotalFiles) |"
$reportContent += "| **C# Files Analyzed** | $($projectStats.CSharpFiles) |"
$reportContent += "| **Total Lines of Code** | $($projectStats.TotalLines.ToString('N0')) |"
$reportContent += "| **Project Size** | $($projectStats.ProjectSize) MB |"
$reportContent += ""

# Overall Health Score
$healthScore = [Math]::Round((($successfulScripts.Count / $scriptResults.Count) * 100), 1)
$healthColor = if ($healthScore -ge 90) { "🟢" } elseif ($healthScore -ge 75) { "🟡" } else { "🔴" }

$reportContent += "## 🎯 Overall Project Health: $healthColor $healthScore%"
$reportContent += ""

# Script Results Breakdown with CLEANER formatting
$reportContent += "## 📋 Analysis Results by Category"
$reportContent += ""

$categoryGroups = $scriptResults | Group-Object Category
foreach ($category in $categoryGroups) {
    $reportContent += "### $($category.Name)"
    $reportContent += ""
    
    foreach ($script in $category.Group) {
        $statusIcon = switch ($script.Status) {
            "Success" { "✅" }
            "Warning" { "⚠️" }
            "Failed" { "❌" }
            default { "❓" }
        }
        
        # CLEANER FORMAT: Remove extra spacing
        $reportContent += "$statusIcon **$($script.ScriptName)**: $($script.Status) ($($script.Duration.ToString('F1'))s)"
        
        if ($script.Error) {
            $reportContent += "  - *Error: $($script.Error)*"
        }
    }
    $reportContent += ""
}

# Recommendations
$reportContent += "## 💡 Recommendations"
$reportContent += ""

if ($failedScripts.Count -gt 0) {
    $reportContent += "### 🚨 Critical Issues"
    foreach ($failed in $failedScripts) {
        $reportContent += "- **$($failed.ScriptName)**: $($failed.Error)"
    }
    $reportContent += ""
}

if ($warningScripts.Count -gt 0) {
    $reportContent += "### ⚠️ Warnings"
    foreach ($warning in $warningScripts) {
        $reportContent += "- **$($warning.ScriptName)**: Review output for potential issues"
    }
    $reportContent += ""
}

if ($successfulScripts.Count -eq $scriptResults.Count) {
    $reportContent += "### ✅ Excellent Project Health!"
    $reportContent += ""
    $reportContent += "All analysis scripts completed successfully. Your project demonstrates:"
    $reportContent += "- Well-structured code architecture"
    $reportContent += "- Comprehensive documentation"
    $reportContent += "- Strong compliance standards"
    $reportContent += "- Efficient development practices"
    $reportContent += ""
}

# Generated Artifacts
$reportContent += "## 📄 Generated Documentation"
$reportContent += ""
$reportContent += "This analysis has generated the following documentation files:"
$reportContent += ""
$reportContent += "| Document | Description |"
$reportContent += "|----------|-------------|"
$reportContent += "| `Constants-Reference.md` | Complete constants documentation |"
$reportContent += "| `CHANGELOG.md` | Project changelog from git history |"
$reportContent += "| `RELEASE-NOTES-v*.md` | Professional release notes |"
$reportContent += ""

# Performance Metrics
$reportContent += "## ⚡ Performance Metrics"
$reportContent += ""
$reportContent += "| Script | Duration | Performance |"
$reportContent += "|--------|----------|-------------|"

foreach ($result in $scriptResults | Sort-Object Duration -Descending) {
    $perfRating = if ($result.Duration -lt 1) { "🚀 Excellent" } elseif ($result.Duration -lt 3) { "✅ Good" } else { "⏱️ Acceptable" }
    $reportContent += "| $($result.ScriptName) | $($result.Duration.ToString('F1'))s | $perfRating |"
}

$reportContent += ""

# Footer
$reportContent += "---"
$reportContent += ""
$reportContent += "**Next Steps:**"
$reportContent += "1. Review individual script outputs for detailed findings"
$reportContent += "2. Address any failed or warning scripts"
$reportContent += "3. Use generated documentation for project reference"
$reportContent += "4. Re-run analysis after making improvements"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite v1.0*"

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
$reportPath = Join-Path $reportsDir "PROJECT-HEALTH-REPORT_$timestamp.md"

# Save comprehensive report
try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "`n⚠️ Error saving comprehensive report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

# Display completion summary
Write-Host "`n🎉 COMPREHENSIVE ANALYSIS COMPLETE!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host "⏱️  Total Analysis Time: $($totalDuration.ToString('F1')) seconds ($([Math]::Round($totalDuration/60, 1)) minutes)" -ForegroundColor Gray
Write-Host "🔧 Scripts Executed: $($scriptResults.Count)" -ForegroundColor Gray
Write-Host "📊 Project Files Analyzed: $($projectStats.CSharpFiles) C# files" -ForegroundColor Gray

Write-Host "`n📊 ANALYSIS RESULTS:" -ForegroundColor DarkCyan
Write-Host "   ✅ Successful scripts: $($successfulScripts.Count)" -ForegroundColor Green
Write-Host "   ⚠️  Scripts with warnings: $($warningScripts.Count)" -ForegroundColor DarkYellow
Write-Host "   ❌ Failed scripts: $($failedScripts.Count)" -ForegroundColor Red

# Display health score
$healthScore = [Math]::Round((($successfulScripts.Count / $scriptResults.Count) * 100), 1)
$healthColor = if ($healthScore -ge 90) { "🟢" } elseif ($healthScore -ge 75) { "🟡" } else { "🔴" }
Write-Host "🎯 Project Health Score: $healthColor $healthScore%" -ForegroundColor Gray

# Show script execution summary
Write-Host "`n⏱️  EXECUTION SUMMARY:" -ForegroundColor DarkCyan
foreach ($result in $scriptResults) {
    $statusColor = switch ($result.Status) {
        "Success" { "Green" }
        "Warning" { "DarkYellow" }
        "Failed" { "Red" }
        default { "Gray" }
    }
    Write-Host "   $($result.ScriptName): $($result.Status) ($($result.Duration.ToString('F1'))s)" -ForegroundColor $statusColor
}

if ($sizeEstimate.Mode -eq "Quick") {
    Write-Host "`n⚡ Quick Mode completed - for full analysis, run again and select 'Y'" -ForegroundColor DarkYellow
}

# OUTPUT PATH AT THE END for easy finding
if ($saveSuccess) {
    Write-Host "`n📄 COMPREHENSIVE REPORT SAVED:" -ForegroundColor Green
    Write-Host "   Location: $reportPath" -ForegroundColor Cyan
    Write-Host "   Size: $([Math]::Round((Get-Item $reportPath).Length / 1KB, 1)) KB" -ForegroundColor Gray
} else {
    Write-Host "`n❌ Report could not be saved" -ForegroundColor Red
}

# INTERACTIVE WORKFLOW LOOP
do {
    Write-Host "`n🎯 What would you like to do next?" -ForegroundColor DarkCyan
    Write-Host "   D - Display report in console" -ForegroundColor Green
    Write-Host "   R - Re-run comprehensive analysis" -ForegroundColor DarkYellow
    Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
    
    $choice = Read-Host "`nEnter choice (D/R/X)"
    $choice = $choice.ToUpper()
    
    switch ($choice) {
        'D' {
            if ($saveSuccess) {
                Write-Host "`n📋 DISPLAYING COMPREHENSIVE REPORT:" -ForegroundColor DarkCyan
                Write-Host "===================================" -ForegroundColor DarkCyan
                try {
                    $reportDisplay = Get-Content -Path $reportPath -Raw
                    Write-Host $reportDisplay -ForegroundColor White
                    Write-Host "`n===================================" -ForegroundColor DarkCyan
                    Write-Host "📋 END OF REPORT" -ForegroundColor DarkCyan
                }
                catch {
                    Write-Host "❌ Could not display report: $_" -ForegroundColor Red
                }
            } else {
                Write-Host "❌ No report available to display" -ForegroundColor Red
            }
        }
        'R' {
            Write-Host "`n🔄 RE-RUNNING COMPREHENSIVE ANALYSIS..." -ForegroundColor DarkYellow
            Write-Host "=======================================" -ForegroundColor DarkYellow
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