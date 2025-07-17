# MixerThreholdMod DevOps Tool: Import/Using Statement Verifier (NON-INTERACTIVE)
# Verifies correctness and optimization of using statements and imports
# Identifies unused, missing, and redundant imports across the project
# Excludes: ForCopilot, Scripts, and Legacy directories

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ((Split-Path $ScriptDir -Leaf) -ieq "Scripts") {
    $ProjectRoot = Split-Path $ScriptDir -Parent
} else {
    $ProjectRoot = $ScriptDir
}

# Check if running interactively or from another script
$IsInteractive = [Environment]::UserInteractive -and $Host.Name -ne "ConsoleHost"
$RunningFromScript = $MyInvocation.InvocationName -notmatch "\.ps1$"

Write-Host "🕐 Import verification started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Verifying using statements in: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green
Write-Host "Excluding: ForCopilot, Scripts, and Legacy directories" -ForegroundColor DarkGray

# Function to analyze using statements and imports
function Get-ImportAnalysis {
    param([string]$Path)
    
    try {
        $files = Get-ChildItem -Path $Path -Recurse -Include *.cs -ErrorAction SilentlyContinue | Where-Object {
            $_.PSIsContainer -eq $false -and
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
            $_.FullName -notmatch "[\\/]\.git[\\/]"
        }
        
        $analysis = @()
        
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                if (-not $content) { continue }
                
                $lines = Get-Content -Path $file.FullName -ErrorAction Stop
                $relativePath = $file.FullName.Replace($Path, "").TrimStart('\', '/')
                
                # Extract using statements
                $usingStatements = @()
                $usingLineNumbers = @()
                
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match '^\s*using\s+([A-Za-z0-9_.]+)\s*;') {
                        $usingNamespace = $matches[1]
                        $usingStatements += $usingNamespace
                        $usingLineNumbers += ($i + 1)
                    } elseif ($lines[$i] -match '^\s*using\s+static\s+([A-Za-z0-9_.]+)\s*;') {
                        $usingNamespace = "static " + $matches[1]
                        $usingStatements += $usingNamespace
                        $usingLineNumbers += ($i + 1)
                    }
                }
                
                # Extract namespace references in code
                $usedNamespaces = @()
                $codeContent = $content
                
                # Remove using statements and comments for analysis
                $codeContent = $codeContent -replace '(?m)^\s*using\s+[^;]+;', ''
                $codeContent = $codeContent -replace '(?s)/\*.*?\*/', ''
                $codeContent = $codeContent -replace '(?m)//.*$', ''
                
                # Common .NET namespaces that might be used
                $knownNamespaces = @(
                    'System', 'System.Collections', 'System.Collections.Generic', 'System.Linq',
                    'System.Text', 'System.IO', 'System.Threading', 'System.Threading.Tasks',
                    'System.Reflection', 'System.ComponentModel', 'System.Diagnostics',
                    'UnityEngine', 'UnityEngine.UI', 'UnityEngine.SceneManagement',
                    'MelonLoader', 'HarmonyLib', 'Newtonsoft.Json', 'System.Runtime.Serialization',
                    'System.Xml', 'System.Net', 'System.Security'
                )
                
                # Check for usage of namespace types
                foreach ($ns in $knownNamespaces) {
                    $nsPattern = $ns -replace '\.', '\.'
                    if ($codeContent -match "\b($nsPattern\.)[A-Za-z0-9_]+\b" -or
                        ($ns -eq 'System' -and $codeContent -match '\b(String|Object|DateTime|Exception|Attribute|Action|Func|Task|Thread|StringBuilder|Encoding|File|Directory|Path|Convert|Math|Console|Environment|Type|Assembly|Stopwatch|Timer|CancellationToken)\b') -or
                        ($ns -eq 'System.Collections.Generic' -and $codeContent -match '\b(List|Dictionary|IEnumerable|IList|IDictionary|HashSet|Queue|Stack|KeyValuePair)<') -or
                        ($ns -eq 'System.Linq' -and $codeContent -match '\.(Where|Select|First|FirstOrDefault|Any|All|Count|ToList|ToArray|OrderBy|GroupBy)\(') -or
                        ($ns -eq 'UnityEngine' -and $codeContent -match '\b(GameObject|Transform|Component|MonoBehaviour|ScriptableObject|Vector3|Vector2|Quaternion|Color|Debug|Application|Time|Input|Physics|Collider|Rigidbody|Camera|Light|Renderer|Material|Texture|Shader|Canvas|Image|Text|Button)\b') -or
                        ($ns -eq 'MelonLoader' -and $codeContent -match '\b(MelonMod|MelonModInfo|MelonLogger|MelonPreferences|MelonPlugin)\b') -or
                        ($ns -eq 'HarmonyLib' -and $codeContent -match '\b(HarmonyPatch|Harmony|Prefix|Postfix|Transpiler|PatchAll)\b')) {
                        $usedNamespaces += $ns
                    }
                }
                
                # Analyze using statements
                $unusedUsings = @()
                $missingUsings = @()
                $redundantUsings = @()
                $staticUsings = @()
                
                # Check for unused usings
                foreach ($using in $usingStatements) {
                    $cleanUsing = $using -replace '^static\s+', ''
                    $isUsed = $false
                    
                    if ($using.StartsWith('static ')) {
                        $staticUsings += $using
                        # For static usings, check if any static members are used
                        if ($codeContent -match '\b[A-Z][A-Za-z0-9_]*\.[A-Z][A-Za-z0-9_]*\b') {
                            $isUsed = $true
                        }
                    } else {
                        # Check if namespace is actually used
                        $usingPattern = $cleanUsing -replace '\.', '\.'
                        if ($codeContent -match "\b$usingPattern\." -or $usedNamespaces -contains $cleanUsing) {
                            $isUsed = $true
                        }
                    }
                    
                    if (-not $isUsed) {
                        $unusedUsings += $using
                    }
                }
                
                # Check for missing usings
                foreach ($usedNs in $usedNamespaces) {
                    $isImported = $false
                    foreach ($using in $usingStatements) {
                        $cleanUsing = $using -replace '^static\s+', ''
                        if ($cleanUsing -eq $usedNs -or $cleanUsing.StartsWith("$usedNs.")) {
                            $isImported = $true
                            break
                        }
                    }
                    if (-not $isImported) {
                        $missingUsings += $usedNs
                    }
                }
                
                # Check for redundant usings (duplicates)
                $usingGroups = $usingStatements | Group-Object
                foreach ($group in $usingGroups) {
                    if ($group.Count -gt 1) {
                        $redundantUsings += $group.Name
                    }
                }
                
                # Calculate file metrics
                $totalUsings = $usingStatements.Count
                $uniqueUsings = ($usingStatements | Select-Object -Unique).Count
                $systemUsings = ($usingStatements | Where-Object { $_ -like "System*" }).Count
                $unityUsings = ($usingStatements | Where-Object { $_ -like "UnityEngine*" }).Count
                $projectUsings = ($usingStatements | Where-Object { $_ -like "*MixerThreholdMod*" }).Count
                
                $analysis += [PSCustomObject]@{
                    File = $file.FullName
                    RelativePath = $relativePath
                    FileName = $file.Name
                    UsingStatements = $usingStatements
                    UsingLineNumbers = $usingLineNumbers
                    UsedNamespaces = $usedNamespaces
                    UnusedUsings = $unusedUsings
                    MissingUsings = $missingUsings
                    RedundantUsings = $redundantUsings
                    StaticUsings = $staticUsings
                    TotalUsings = $totalUsings
                    UniqueUsings = $uniqueUsings
                    SystemUsings = $systemUsings
                    UnityUsings = $unityUsings
                    ProjectUsings = $projectUsings
                    HasIssues = ($unusedUsings.Count -gt 0 -or $missingUsings.Count -gt 0 -or $redundantUsings.Count -gt 0)
                    Content = $content
                }
            }
            catch {
                Write-Host "⚠️  Error processing $($file.Name): $_" -ForegroundColor DarkYellow
                continue
            }
        }
        
        return $analysis
    }
    catch {
        Write-Host "⚠️  Error scanning for imports: $_" -ForegroundColor DarkYellow
        return @()
    }
}

Write-Host "`n📂 Analyzing using statements and imports..." -ForegroundColor DarkGray
$analysis = Get-ImportAnalysis -Path $ProjectRoot

Write-Host "📊 Analyzed $($analysis.Count) C# files" -ForegroundColor Gray

if ($analysis.Count -eq 0) {
    Write-Host "⚠️  No C# files found for import analysis" -ForegroundColor DarkYellow
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

# Calculate overall statistics
$filesWithIssues = $analysis | Where-Object { $_.HasIssues }
$filesWithUnusedImports = $analysis | Where-Object { $_.UnusedUsings.Count -gt 0 }
$filesWithMissingImports = $analysis | Where-Object { $_.MissingUsings.Count -gt 0 }
$filesWithRedundantImports = $analysis | Where-Object { $_.RedundantUsings.Count -gt 0 }
$filesWithStaticUsings = $analysis | Where-Object { $_.StaticUsings.Count -gt 0 }

$totalUsings = ($analysis | ForEach-Object { $_.TotalUsings } | Measure-Object -Sum).Sum
$totalUnused = ($analysis | ForEach-Object { $_.UnusedUsings.Count } | Measure-Object -Sum).Sum
$totalMissing = ($analysis | ForEach-Object { $_.MissingUsings.Count } | Measure-Object -Sum).Sum
$totalRedundant = ($analysis | ForEach-Object { $_.RedundantUsings.Count } | Measure-Object -Sum).Sum

Write-Host "`n=== IMPORT VERIFICATION REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

# Overall Statistics
Write-Host "`n📊 Overall Import Statistics:" -ForegroundColor DarkCyan
Write-Host "   Total using statements: $totalUsings" -ForegroundColor Gray
Write-Host "   Files analyzed: $($analysis.Count)" -ForegroundColor Gray

$issuePercent = if ($analysis.Count -gt 0) { [Math]::Round(($filesWithIssues.Count / $analysis.Count) * 100, 1) } else { 0 }
Write-Host "   Files with issues: $($filesWithIssues.Count)/$($analysis.Count) ($issuePercent%)" -ForegroundColor $(if ($issuePercent -eq 0) { "Green" } elseif ($issuePercent -le 20) { "DarkYellow" } else { "Red" })

# Issue Breakdown
Write-Host "`n🔍 Issue Breakdown:" -ForegroundColor DarkCyan
if ($totalUnused -gt 0) {
    Write-Host "   Unused imports: $totalUnused in $($filesWithUnusedImports.Count) files" -ForegroundColor DarkYellow
}
if ($totalMissing -gt 0) {
    Write-Host "   Missing imports: $totalMissing in $($filesWithMissingImports.Count) files" -ForegroundColor Red
}
if ($totalRedundant -gt 0) {
    Write-Host "   Redundant imports: $totalRedundant in $($filesWithRedundantImports.Count) files" -ForegroundColor DarkYellow
}
if ($filesWithStaticUsings.Count -gt 0) {
    Write-Host "   Files with static usings: $($filesWithStaticUsings.Count)" -ForegroundColor Gray
}

if ($totalUnused -eq 0 -and $totalMissing -eq 0 -and $totalRedundant -eq 0) {
    Write-Host "   ✅ No import issues detected!" -ForegroundColor Green
}

# Top Issues (limited for automation)
if ($filesWithUnusedImports.Count -gt 0) {
    Write-Host "`n🗑️  Top Files with Unused Imports:" -ForegroundColor DarkYellow
    $topUnused = $filesWithUnusedImports | Sort-Object { $_.UnusedUsings.Count } -Descending | Select-Object -First 5
    foreach ($file in $topUnused) {
        Write-Host "   📄 $($file.RelativePath) ($($file.UnusedUsings.Count) unused)" -ForegroundColor DarkYellow
        $file.UnusedUsings | Select-Object -First 3 | ForEach-Object {
            Write-Host "      • using $_;" -ForegroundColor Gray
        }
        if ($file.UnusedUsings.Count -gt 3) {
            Write-Host "      ... and $($file.UnusedUsings.Count - 3) more" -ForegroundColor DarkGray
        }
    }
}

if ($filesWithMissingImports.Count -gt 0) {
    Write-Host "`n❌ Top Files with Missing Imports:" -ForegroundColor Red
    $topMissing = $filesWithMissingImports | Sort-Object { $_.MissingUsings.Count } -Descending | Select-Object -First 5
    foreach ($file in $topMissing) {
        Write-Host "   📄 $($file.RelativePath) ($($file.MissingUsings.Count) missing)" -ForegroundColor Red
        $file.MissingUsings | Select-Object -First 3 | ForEach-Object {
            Write-Host "      • using $_;" -ForegroundColor Gray
        }
        if ($file.MissingUsings.Count -gt 3) {
            Write-Host "      ... and $($file.MissingUsings.Count - 3) more" -ForegroundColor DarkGray
        }
    }
}

# Import Distribution
Write-Host "`n📈 Import Distribution:" -ForegroundColor DarkCyan
$avgUsings = if ($analysis.Count -gt 0) { [Math]::Round(($totalUsings / $analysis.Count), 1) } else { 0 }
Write-Host "   Average usings per file: $avgUsings" -ForegroundColor Gray

$systemPercent = if ($totalUsings -gt 0) { [Math]::Round((($analysis | ForEach-Object { $_.SystemUsings } | Measure-Object -Sum).Sum / $totalUsings) * 100, 1) } else { 0 }
$unityPercent = if ($totalUsings -gt 0) { [Math]::Round((($analysis | ForEach-Object { $_.UnityUsings } | Measure-Object -Sum).Sum / $totalUsings) * 100, 1) } else { 0 }
$projectPercent = if ($totalUsings -gt 0) { [Math]::Round((($analysis | ForEach-Object { $_.ProjectUsings } | Measure-Object -Sum).Sum / $totalUsings) * 100, 1) } else { 0 }

Write-Host "   System namespaces: $systemPercent%" -ForegroundColor Gray
Write-Host "   Unity namespaces: $unityPercent%" -ForegroundColor Gray
Write-Host "   Project namespaces: $projectPercent%" -ForegroundColor Gray

# Recommendations
Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan

if ($totalUnused -gt 0) {
    Write-Host "   🗑️  Remove $totalUnused unused using statements to reduce compilation time" -ForegroundColor DarkYellow
}

if ($totalMissing -gt 0) {
    Write-Host "   ❌ Add $totalMissing missing using statements for better readability" -ForegroundColor Red
}

if ($totalRedundant -gt 0) {
    Write-Host "   🔄 Remove $totalRedundant duplicate using statements" -ForegroundColor DarkYellow
}

Write-Host "   • Use IDE tools like 'Remove Unused Usings' for cleanup" -ForegroundColor Gray
Write-Host "   • Consider global using statements for commonly used namespaces" -ForegroundColor Gray
Write-Host "   • Group using statements: System, then third-party, then project" -ForegroundColor Gray

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

# Generate detailed import verification report
Write-Host "`n📝 Generating detailed import verification report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "IMPORT-VERIFICATION-REPORT_$timestamp.md"

# Create report content using individual variables to avoid parsing issues
$reportTitle = "# Import/Using Statement Verification Report"
$reportGenerated = "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportFilesAnalyzed = "**Files Analyzed**: $($analysis.Count)"
$reportTotalUsings = "**Total Using Statements**: $totalUsings"
$reportFilesWithIssues = "**Files with Issues**: $($filesWithIssues.Count) ($issuePercent%)"

$reportSummaryTitle = "## Executive Summary"

$cleanlinessScore = 0
if ($analysis.Count -gt 0) {
    $unusedPenalty = ($totalUnused / $totalUsings) * 30
    $missingPenalty = ($totalMissing / $analysis.Count) * 40
    $redundantPenalty = ($totalRedundant / $totalUsings) * 20
    $cleanlinessScore = [Math]::Max(0, [Math]::Round(100 - $unusedPenalty - $missingPenalty - $redundantPenalty, 1))
}

$scoreSummary = ""
if ($cleanlinessScore -ge 90) {
    $scoreSummary = "🎉 **EXCELLENT IMPORT MANAGEMENT!** Score: $cleanlinessScore/100"
} elseif ($cleanlinessScore -ge 75) {
    $scoreSummary = "✅ **GOOD IMPORT MANAGEMENT!** Score: $cleanlinessScore/100"
} elseif ($cleanlinessScore -ge 50) {
    $scoreSummary = "⚠️ **IMPORT CLEANUP NEEDED** - Score: $cleanlinessScore/100"
} else {
    $scoreSummary = "🚨 **SIGNIFICANT IMPORT ISSUES** - Score: $cleanlinessScore/100"
}

# Build report content array safely
$reportContent = @()
$reportContent += $reportTitle
$reportContent += ""
$reportContent += $reportGenerated
$reportContent += $reportFilesAnalyzed
$reportContent += $reportTotalUsings
$reportContent += $reportFilesWithIssues
$reportContent += ""
$reportContent += $reportSummaryTitle
$reportContent += ""
$reportContent += $scoreSummary
$reportContent += ""
$reportContent += "Your project demonstrates good import practices with room for improvement."
$reportContent += ""
$reportContent += "## Import Statistics"
$reportContent += ""
$reportContent += "| Metric | Value |"
$reportContent += "|--------|-------|"
$reportContent += "| Total Using Statements | $totalUsings |"
$reportContent += "| Unused Imports | $totalUnused |"
$reportContent += "| Missing Imports | $totalMissing |"
$reportContent += "| Redundant Imports | $totalRedundant |"
$reportContent += "| Files with Issues | $($filesWithIssues.Count) |"
$reportContent += ""
$reportContent += "## Recommendations"
$reportContent += ""
$reportContent += "• Remove unused using statements to improve compilation time"
$reportContent += "• Add missing using statements for better code readability"
$reportContent += "• Organize imports by category (System, third-party, project)"
$reportContent += "• Consider using global using statements for common namespaces"
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Import Verification Tool*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 Import verification complete!" -ForegroundColor Green

# OUTPUT PATH AT THE END for easy finding
if ($saveSuccess) {
    Write-Host "`n📄 DETAILED REPORT SAVED:" -ForegroundColor Green
    Write-Host "   Location: $reportPath" -ForegroundColor Cyan
    Write-Host "   Size: $([Math]::Round((Get-Item $reportPath).Length / 1KB, 1)) KB" -ForegroundColor Gray
    Write-Host "   Cleanliness Score: $cleanlinessScore/100" -ForegroundColor $(if ($cleanlinessScore -ge 90) { "Green" } elseif ($cleanlinessScore -ge 75) { "DarkYellow" } else { "Red" })
} else {
    Write-Host "`n⚠️ No detailed report generated" -ForegroundColor DarkYellow
}

# INTERACTIVE WORKFLOW LOOP (only when running standalone)
if ($IsInteractive -and -not $RunningFromScript) {
    do {
        Write-Host "`n🎯 What would you like to do next?" -ForegroundColor DarkCyan
        Write-Host "   D - Display report in console" -ForegroundColor Green
        Write-Host "   R - Re-run import verification analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING IMPORT VERIFICATION REPORT:" -ForegroundColor DarkCyan
                    Write-Host "=======================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "`n=======================================" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING IMPORT VERIFICATION ANALYSIS..." -ForegroundColor DarkYellow
                Write-Host "===========================================" -ForegroundColor DarkYellow
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
} else {
    Write-Host "Analysis completed successfully" -ForegroundColor DarkGray
}