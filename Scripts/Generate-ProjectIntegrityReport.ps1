# MixerThreholdMod DevOps Tool: Project Integrity Report Generator (NON-INTERACTIVE)
# Analyzes project files for missing references, broken dependencies, and structural issues
# Validates .csproj, .sln files and checks assembly references for .NET 4.8.1 compatibility
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

Write-Host "🕐 Project integrity analysis started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Analyzing project integrity in: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green

# Function to find project and solution files
function Find-ProjectFiles {
    try {
        $projectFiles = @{
            Solutions = @()
            Projects = @()
            Configs = @()
            Packages = @()
        }
        
        # Find solution files
        $solutionFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Filter "*.sln" -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]"
        }
        $projectFiles.Solutions = $solutionFiles
        
        # Find project files
        $csprojFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Filter "*.csproj" -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]"
        }
        $projectFiles.Projects = $csprojFiles
        
        # Find config files
        $configFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Include "*.config", "app.config", "web.config" -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]"
        }
        $projectFiles.Configs = $configFiles
        
        # Find package files
        $packageFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Include "packages.config", "*.props", "*.targets" -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]"
        }
        $projectFiles.Packages = $packageFiles
        
        return $projectFiles
    }
    catch {
        Write-Host "⚠️  Error finding project files: $_" -ForegroundColor DarkYellow
        return @{
            Solutions = @()
            Projects = @()
            Configs = @()
            Packages = @()
        }
    }
}

# Function to analyze solution file
function Analyze-SolutionFile {
    param($solutionFile)
    
    try {
        $content = Get-Content -Path $solutionFile.FullName -Raw -ErrorAction Stop
        $issues = @()
        $projectReferences = @()
        
        # Parse project references from solution
        $projectMatches = [regex]::Matches($content, 'Project\("\{[^}]+\}"\)\s*=\s*"([^"]+)",\s*"([^"]+)",\s*"\{([^}]+)\}"')
        
        foreach ($match in $projectMatches) {
            $projectName = $match.Groups[1].Value
            $projectPath = $match.Groups[2].Value
            $projectGuid = $match.Groups[3].Value
            
            # Check if project file exists
            $fullProjectPath = Join-Path (Split-Path $solutionFile.FullName -Parent) $projectPath
            $projectExists = Test-Path $fullProjectPath
            
            $projectReferences += [PSCustomObject]@{
                Name = $projectName
                Path = $projectPath
                FullPath = $fullProjectPath
                Guid = $projectGuid
                Exists = $projectExists
            }
            
            if (-not $projectExists) {
                $issues += "Missing project file: $projectPath"
            }
        }
        
        # Check for solution configuration issues
        if ($content -match 'GlobalSection\(SolutionConfigurationPlatforms\)') {
            # Solution has configurations - good
        } else {
            $issues += "No solution configuration platforms found"
        }
        
        # Check for UTF-8 BOM issues in solution file
        $bytes = [System.IO.File]::ReadAllBytes($solutionFile.FullName)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $issues += "Solution file has UTF-8 BOM (may cause issues)"
        }
        
        return [PSCustomObject]@{
            File = $solutionFile.FullName
            RelativePath = $solutionFile.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
            FileName = $solutionFile.Name
            ProjectReferences = $projectReferences
            Issues = $issues
            IsValid = $issues.Count -eq 0
        }
    }
    catch {
        return [PSCustomObject]@{
            File = $solutionFile.FullName
            RelativePath = $solutionFile.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
            FileName = $solutionFile.Name
            ProjectReferences = @()
            Issues = @("Failed to parse solution file: $_")
            IsValid = $false
        }
    }
}

# Function to analyze project file
function Analyze-ProjectFile {
    param($projectFile)
    
    try {
        [xml]$projectXml = Get-Content -Path $projectFile.FullName -ErrorAction Stop
        $issues = @()
        $references = @()
        $packageReferences = @()
        $projectReferences = @()
        
        # Check target framework
        $targetFramework = $projectXml.Project.PropertyGroup.TargetFramework
        $targetFrameworkVersion = $projectXml.Project.PropertyGroup.TargetFrameworkVersion
        
        if ($targetFramework) {
            if ($targetFramework -ne "net481" -and $targetFramework -ne "net48") {
                $issues += "Target framework '$targetFramework' may not be .NET 4.8.1 compatible"
            }
        } elseif ($targetFrameworkVersion) {
            if ($targetFrameworkVersion -ne "v4.8.1" -and $targetFrameworkVersion -ne "v4.8") {
                $issues += "Target framework version '$targetFrameworkVersion' may not be .NET 4.8.1 compatible"
            }
        } else {
            $issues += "No target framework specified"
        }
        
        # Analyze assembly references
        $referenceNodes = $projectXml.SelectNodes("//Reference")
        foreach ($refNode in $referenceNodes) {
            $include = $refNode.GetAttribute("Include")
            $hintPath = $refNode.HintPath
            
            $refAnalysis = [PSCustomObject]@{
                Name = $include
                HintPath = $hintPath
                Exists = $true
                Type = "Assembly"
            }
            
            if ($hintPath) {
                $fullHintPath = Join-Path (Split-Path $projectFile.FullName -Parent) $hintPath
                $refAnalysis.Exists = Test-Path $fullHintPath
                $refAnalysis.FullPath = $fullHintPath
                
                if (-not $refAnalysis.Exists) {
                    $issues += "Missing assembly reference: $hintPath"
                }
            }
            
            $references += $refAnalysis
        }
        
        # Analyze package references (modern SDK-style)
        $packageNodes = $projectXml.SelectNodes("//PackageReference")
        foreach ($packageNode in $packageNodes) {
            $include = $packageNode.GetAttribute("Include")
            $version = $packageNode.GetAttribute("Version")
            
            $packageReferences += [PSCustomObject]@{
                Name = $include
                Version = $version
                Type = "Package"
            }
        }
        
        # Analyze project references
        $projectRefNodes = $projectXml.SelectNodes("//ProjectReference")
        foreach ($projRefNode in $projectRefNodes) {
            $include = $projRefNode.GetAttribute("Include")
            $fullRefPath = Join-Path (Split-Path $projectFile.FullName -Parent) $include
            $refExists = Test-Path $fullRefPath
            
            $projectReferences += [PSCustomObject]@{
                Name = [System.IO.Path]::GetFileNameWithoutExtension($include)
                Path = $include
                FullPath = $fullRefPath
                Exists = $refExists
                Type = "Project"
            }
            
            if (-not $refExists) {
                $issues += "Missing project reference: $include"
            }
        }
        
        # Check for common .NET 4.8.1 compatibility issues
        $assemblyName = $projectXml.Project.PropertyGroup.AssemblyName
        $outputType = $projectXml.Project.PropertyGroup.OutputType
        
        # Check for problematic NuGet packages for .NET 4.8.1
        $problematicPackages = @("System.Text.Json", "Microsoft.Bcl.AsyncInterfaces")
        foreach ($package in $packageReferences) {
            if ($problematicPackages -contains $package.Name) {
                $issues += "Package '$($package.Name)' may have .NET 4.8.1 compatibility issues"
            }
        }
        
        # Check project file encoding
        $encoding = "Unknown"
        try {
            $bytes = [System.IO.File]::ReadAllBytes($projectFile.FullName)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $encoding = "UTF-8 with BOM"
                $issues += "Project file has UTF-8 BOM (may cause issues)"
            } else {
                $encoding = "UTF-8"
            }
        }
        catch {
            $encoding = "Error detecting"
        }
        
        return [PSCustomObject]@{
            File = $projectFile.FullName
            RelativePath = $projectFile.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
            FileName = $projectFile.Name
            AssemblyName = $assemblyName
            OutputType = $outputType
            TargetFramework = if ($targetFramework) { $targetFramework } else { $targetFrameworkVersion }
            AssemblyReferences = $references
            PackageReferences = $packageReferences
            ProjectReferences = $projectReferences
            Encoding = $encoding
            Issues = $issues
            IsValid = $issues.Count -eq 0
        }
    }
    catch {
        return [PSCustomObject]@{
            File = $projectFile.FullName
            RelativePath = $projectFile.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
            FileName = $projectFile.Name
            AssemblyName = "Unknown"
            OutputType = "Unknown"
            TargetFramework = "Unknown"
            AssemblyReferences = @()
            PackageReferences = @()
            ProjectReferences = @()
            Encoding = "Unknown"
            Issues = @("Failed to parse project file: $_")
            IsValid = $false
        }
    }
}

# Function to analyze config files
function Analyze-ConfigFile {
    param($configFile)
    
    try {
        [xml]$configXml = Get-Content -Path $configFile.FullName -ErrorAction Stop
        $issues = @()
        $bindingRedirects = @()
        
        # Check binding redirects
        $bindingNodes = $configXml.SelectNodes("//bindingRedirect")
        foreach ($bindingNode in $bindingNodes) {
            $oldVersion = $bindingNode.GetAttribute("oldVersion")
            $newVersion = $bindingNode.GetAttribute("newVersion")
            
            $bindingRedirects += [PSCustomObject]@{
                OldVersion = $oldVersion
                NewVersion = $newVersion
            }
        }
        
        # Check .NET Framework version in config
        $startupNode = $configXml.configuration.startup
        if ($startupNode) {
            $supportedRuntime = $startupNode.supportedRuntime
            if ($supportedRuntime) {
                $version = $supportedRuntime.GetAttribute("version")
                if ($version -and $version -notmatch "v4\.[0-8]") {
                    $issues += "Supported runtime version '$version' may not be compatible with .NET 4.8.1"
                }
            }
        }
        
        # Check for XML formatting issues
        $content = Get-Content -Path $configFile.FullName -Raw
        if ($content -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]') {
            $issues += "Config file contains control characters"
        }
        
        return [PSCustomObject]@{
            File = $configFile.FullName
            RelativePath = $configFile.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
            FileName = $configFile.Name
            BindingRedirects = $bindingRedirects
            Issues = $issues
            IsValid = $issues.Count -eq 0
        }
    }
    catch {
        return [PSCustomObject]@{
            File = $configFile.FullName
            RelativePath = $configFile.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
            FileName = $configFile.Name
            BindingRedirects = @()
            Issues = @("Failed to parse config file: $_")
            IsValid = $false
        }
    }
}

# Function to check for orphaned files
function Find-OrphanedFiles {
    param($projectFiles, $solutions, $projects)
    
    try {
        $orphanedFiles = @()
        
        # Find .cs files that might not be included in projects
        $allCsFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Filter "*.cs" -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy|bin|obj)[\\/]"
        }
        
        foreach ($csFile in $allCsFiles) {
            $isIncluded = $false
            
            # Check if file is in any project directory
            foreach ($project in $projects) {
                $projectDir = Split-Path $project.File -Parent
                if ($csFile.FullName.StartsWith($projectDir)) {
                    $isIncluded = $true
                    break
                }
            }
            
            if (-not $isIncluded) {
                $orphanedFiles += [PSCustomObject]@{
                    File = $csFile.FullName
                    RelativePath = $csFile.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
                    Type = "Source Code"
                    Reason = "Not in any project directory"
                }
            }
        }
        
        return $orphanedFiles
    }
    catch {
        Write-Host "⚠️  Error finding orphaned files: $_" -ForegroundColor DarkYellow
        return @()
    }
}

# Function to categorize integrity issues
function Get-IntegrityIssueSeverity {
    param($issue, $fileType)
    
    # Critical issues
    if ($issue -match "Missing project file|Missing assembly reference|Missing project reference") {
        return "CRITICAL"
    }
    
    if ($issue -match "Failed to parse|No target framework") {
        return "CRITICAL"
    }
    
    # High severity
    if ($issue -match "compatibility issues|not be .NET 4.8.1 compatible") {
        return "HIGH"
    }
    
    if ($issue -match "UTF-8 BOM|control characters") {
        return "HIGH"
    }
    
    # Medium severity
    if ($issue -match "No solution configuration|Supported runtime version") {
        return "MEDIUM"
    }
    
    # Low severity
    return "LOW"
}

# Main script execution
Write-Host "`n📂 Scanning for project files..." -ForegroundColor DarkGray
$projectFiles = Find-ProjectFiles

$totalFiles = $projectFiles.Solutions.Count + $projectFiles.Projects.Count + $projectFiles.Configs.Count + $projectFiles.Packages.Count

if ($totalFiles -eq 0) {
    Write-Host "❌ No project files found for analysis!" -ForegroundColor Red
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

Write-Host "📊 Found project files:" -ForegroundColor Gray
Write-Host "   Solutions: $($projectFiles.Solutions.Count)" -ForegroundColor Gray
Write-Host "   Projects: $($projectFiles.Projects.Count)" -ForegroundColor Gray
Write-Host "   Configs: $($projectFiles.Configs.Count)" -ForegroundColor Gray
Write-Host "   Packages: $($projectFiles.Packages.Count)" -ForegroundColor Gray

# Analyze project integrity
Write-Host "`n🔍 Analyzing project integrity..." -ForegroundColor DarkCyan

$analysisResults = @{
    Solutions = @()
    Projects = @()
    Configs = @()
    OrphanedFiles = @()
}

$allIssues = @()

# Analyze solution files
if ($projectFiles.Solutions.Count -gt 0) {
    Write-Host "   📋 Analyzing $($projectFiles.Solutions.Count) solution files..." -ForegroundColor DarkGray
    foreach ($solution in $projectFiles.Solutions) {
        $analysis = Analyze-SolutionFile -solutionFile $solution
        $analysisResults.Solutions += $analysis
        
        foreach ($issue in $analysis.Issues) {
            $allIssues += [PSCustomObject]@{
                File = $analysis.RelativePath
                Issue = $issue
                Type = "Solution"
                Severity = Get-IntegrityIssueSeverity -issue $issue -fileType "Solution"
            }
        }
    }
}

# Analyze project files
if ($projectFiles.Projects.Count -gt 0) {
    Write-Host "   🔧 Analyzing $($projectFiles.Projects.Count) project files..." -ForegroundColor DarkGray
    foreach ($project in $projectFiles.Projects) {
        $analysis = Analyze-ProjectFile -projectFile $project
        $analysisResults.Projects += $analysis
        
        foreach ($issue in $analysis.Issues) {
            $allIssues += [PSCustomObject]@{
                File = $analysis.RelativePath
                Issue = $issue
                Type = "Project"
                Severity = Get-IntegrityIssueSeverity -issue $issue -fileType "Project"
            }
        }
    }
}

# Analyze config files
if ($projectFiles.Configs.Count -gt 0) {
    Write-Host "   ⚙️  Analyzing $($projectFiles.Configs.Count) config files..." -ForegroundColor DarkGray
    foreach ($config in $projectFiles.Configs) {
        $analysis = Analyze-ConfigFile -configFile $config
        $analysisResults.Configs += $analysis
        
        foreach ($issue in $analysis.Issues) {
            $allIssues += [PSCustomObject]@{
                File = $analysis.RelativePath
                Issue = $issue
                Type = "Config"
                Severity = Get-IntegrityIssueSeverity -issue $issue -fileType "Config"
            }
        }
    }
}

# Find orphaned files
Write-Host "   🔍 Searching for orphaned files..." -ForegroundColor DarkGray
$orphanedFiles = Find-OrphanedFiles -projectFiles $projectFiles -solutions $analysisResults.Solutions -projects $analysisResults.Projects
$analysisResults.OrphanedFiles = $orphanedFiles

foreach ($orphan in $orphanedFiles) {
    $allIssues += [PSCustomObject]@{
        File = $orphan.RelativePath
        Issue = "Orphaned file: $($orphan.Reason)"
        Type = "Orphaned"
        Severity = "LOW"
    }
}

Write-Host "✅ Analysis complete" -ForegroundColor Gray

# Categorize issues by severity
$criticalIssues = $allIssues | Where-Object { $_.Severity -eq "CRITICAL" }
$highIssues = $allIssues | Where-Object { $_.Severity -eq "HIGH" }
$mediumIssues = $allIssues | Where-Object { $_.Severity -eq "MEDIUM" }
$lowIssues = $allIssues | Where-Object { $_.Severity -eq "LOW" }

Write-Host "`n=== PROJECT INTEGRITY ANALYSIS REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

# Overall status
Write-Host "📊 Integrity Summary:" -ForegroundColor DarkCyan
Write-Host "   Files analyzed: $totalFiles" -ForegroundColor Gray
Write-Host "   Critical issues: $($criticalIssues.Count)" -ForegroundColor $(if ($criticalIssues.Count -eq 0) { "Green" } else { "Red" })
Write-Host "   High priority: $($highIssues.Count)" -ForegroundColor $(if ($highIssues.Count -eq 0) { "Green" } else { "Red" })
Write-Host "   Medium priority: $($mediumIssues.Count)" -ForegroundColor $(if ($mediumIssues.Count -eq 0) { "Green" } else { "DarkYellow" })
Write-Host "   Low priority: $($lowIssues.Count)" -ForegroundColor $(if ($lowIssues.Count -eq 0) { "Green" } else { "DarkYellow" })
Write-Host "   Orphaned files: $($orphanedFiles.Count)" -ForegroundColor $(if ($orphanedFiles.Count -eq 0) { "Green" } else { "DarkYellow" })

# Display critical issues
if ($criticalIssues.Count -gt 0) {
    Write-Host "`n🚨 CRITICAL PROJECT ISSUES:" -ForegroundColor Red
    foreach ($issue in $criticalIssues | Select-Object -First 8) {
        Write-Host "   • $($issue.File)" -ForegroundColor Red
        Write-Host "     └─ $($issue.Issue)" -ForegroundColor DarkGray
    }
    if ($criticalIssues.Count -gt 8) {
        Write-Host "   ... and $($criticalIssues.Count - 8) more critical issues" -ForegroundColor DarkGray
    }
}

# Display high priority issues
if ($highIssues.Count -gt 0) {
    Write-Host "`n⚠️  HIGH PRIORITY ISSUES:" -ForegroundColor DarkYellow
    foreach ($issue in $highIssues | Select-Object -First 5) {
        Write-Host "   • $($issue.File)" -ForegroundColor DarkYellow
        Write-Host "     └─ $($issue.Issue)" -ForegroundColor DarkGray
    }
    if ($highIssues.Count -gt 5) {
        Write-Host "   ... and $($highIssues.Count - 5) more high priority issues" -ForegroundColor DarkGray
    }
}

# Project structure overview
if ($analysisResults.Projects.Count -gt 0) {
    Write-Host "`n📋 Project Structure:" -ForegroundColor DarkCyan
    foreach ($project in $analysisResults.Projects | Select-Object -First 5) {
        $statusIcon = if ($project.IsValid) { "✅" } else { "❌" }
        Write-Host "   $statusIcon $($project.FileName) ($($project.TargetFramework))" -ForegroundColor Gray
        Write-Host "      Assembly: $($project.AssemblyName)" -ForegroundColor DarkGray
        Write-Host "      References: $($project.AssemblyReferences.Count) assemblies, $($project.PackageReferences.Count) packages" -ForegroundColor DarkGray
    }
    if ($analysisResults.Projects.Count -gt 5) {
        Write-Host "   ... and $($analysisResults.Projects.Count - 5) more projects" -ForegroundColor DarkGray
    }
}

# Quick recommendations
Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan

if ($criticalIssues.Count -gt 0) {
    Write-Host "   🚨 IMMEDIATE: Fix $($criticalIssues.Count) critical project integrity issues" -ForegroundColor Red
    Write-Host "   • Restore missing references and project files" -ForegroundColor Red
}

if ($highIssues.Count -gt 0) {
    Write-Host "   ⚠️  REVIEW: Address $($highIssues.Count) high priority compatibility issues" -ForegroundColor DarkYellow
    Write-Host "   • Verify .NET 4.8.1 compatibility of packages and settings" -ForegroundColor DarkYellow
}

$incompatibleProjects = $analysisResults.Projects | Where-Object { $_.Issues -match "not be .NET 4.8.1 compatible" }
if ($incompatibleProjects.Count -gt 0) {
    Write-Host "   🔧 UPDATE: $($incompatibleProjects.Count) projects need .NET 4.8.1 target framework" -ForegroundColor DarkYellow
}

if ($orphanedFiles.Count -gt 0) {
    Write-Host "   📝 CLEANUP: $($orphanedFiles.Count) orphaned files found" -ForegroundColor Gray
}

Write-Host "   • Ensure all projects target .NET Framework 4.8.1" -ForegroundColor Gray
Write-Host "   • Validate assembly references and package compatibility" -ForegroundColor Gray

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

# Generate detailed project integrity report using safe variable approach
Write-Host "`n📝 Generating detailed project integrity report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "PROJECT-INTEGRITY-REPORT_$timestamp.md"

# Build report using separate variables for PowerShell 5.1 compatibility
$reportTitle = "# Project Integrity Analysis Report"
$reportGenerated = "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportFilesAnalyzed = "**Files Analyzed**: $totalFiles"
$reportCriticalIssues = "**Critical Issues**: $($criticalIssues.Count)"
$reportHighIssues = "**High Priority Issues**: $($highIssues.Count)"
$reportMediumIssues = "**Medium Priority Issues**: $($mediumIssues.Count)"
$reportOrphanedFiles = "**Orphaned Files**: $($orphanedFiles.Count)"

$reportSummaryTitle = "## Executive Summary"

$summaryStatus = ""
if ($criticalIssues.Count -eq 0 -and $highIssues.Count -eq 0) {
    $summaryStatus = "✅ **PROJECT INTEGRITY EXCELLENT** - No critical structural issues detected."
} else {
    $summaryStatus = "⚠️ **PROJECT INTEGRITY ISSUES DETECTED** - Structural problems require attention."
}

$reportContent = @()
$reportContent += $reportTitle
$reportContent += ""
$reportContent += $reportGenerated
$reportContent += $reportFilesAnalyzed
$reportContent += $reportCriticalIssues
$reportContent += $reportHighIssues
$reportContent += $reportMediumIssues
$reportContent += $reportOrphanedFiles
$reportContent += ""
$reportContent += $reportSummaryTitle
$reportContent += ""
$reportContent += $summaryStatus
$reportContent += ""
$reportContent += "Project structure analysis for .NET 4.8.1 compatibility and integrity validation."
$reportContent += ""
$reportContent += "## Summary Statistics"
$reportContent += ""
$reportContent += "| Metric | Count | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| Total Files | $totalFiles | - |"
$reportContent += "| Solution Files | $($projectFiles.Solutions.Count) | $(if ($projectFiles.Solutions.Count -gt 0) { "✅ Found" } else { "⚠️ None" }) |"
$reportContent += "| Project Files | $($projectFiles.Projects.Count) | $(if ($projectFiles.Projects.Count -gt 0) { "✅ Found" } else { "❌ None" }) |"
$reportContent += "| Critical Issues | $($criticalIssues.Count) | $(if ($criticalIssues.Count -eq 0) { "✅ None" } else { "🚨 Action Required" }) |"
$reportContent += "| High Priority | $($highIssues.Count) | $(if ($highIssues.Count -eq 0) { "✅ None" } else { "⚠️ Review Needed" }) |"
$reportContent += "| Orphaned Files | $($orphanedFiles.Count) | $(if ($orphanedFiles.Count -eq 0) { "✅ None" } else { "📝 Cleanup Suggested" }) |"
$reportContent += ""

# Project Analysis - FIXED SECTION WITH PROPER BRACES
if ($analysisResults.Projects.Count -gt 0) {
    $reportContent += "## Project Analysis"
    $reportContent += ""
    
    foreach ($project in $analysisResults.Projects | Sort-Object FileName) {
        $statusIcon = if ($project.IsValid) { "✅" } else { "❌" }
        
        $reportContent += "### $statusIcon $($project.FileName)"
        $reportContent += ""
        $reportContent += "| Property | Value |"
        $reportContent += "|----------|-------|"
        $reportContent += "| Assembly Name | $($project.AssemblyName) |"
        $reportContent += "| Output Type | $($project.OutputType) |"
        $reportContent += "| Target Framework | $($project.TargetFramework) |"
        $reportContent += "| File Encoding | $($project.Encoding) |"
        $reportContent += "| Assembly References | $($project.AssemblyReferences.Count) |"
        $reportContent += "| Package References | $($project.PackageReferences.Count) |"
        $reportContent += "| Project References | $($project.ProjectReferences.Count) |"
        $reportContent += "| Issues | $($project.Issues.Count) |"
        $reportContent += ""
        
        if ($project.Issues.Count -gt 0) {
            $reportContent += "#### Issues"
            $reportContent += ""
            foreach ($issue in $project.Issues) {
                $severityIcon = switch (Get-IntegrityIssueSeverity -issue $issue -fileType "Project") {
                    "CRITICAL" { "🚨" }
                    "HIGH" { "⚠️" }
                    "MEDIUM" { "📝" }
                    default { "💭" }
                }
                $reportContent += "- $severityIcon $issue"
            }
            $reportContent += ""
        }
        
        # Show missing references - FIXED SECTION WITH PROPER BRACES
        $missingRefs = $project.AssemblyReferences | Where-Object { -not $_.Exists }
        if ($missingRefs.Count -gt 0) {
            $reportContent += "#### Missing Assembly References"
            $reportContent += ""
            foreach ($missingRef in $missingRefs) {
                $reportContent += "- $($missingRef.Name): $($missingRef.HintPath)"
            }
            $reportContent += ""
        }
        
        $missingProjRefs = $project.ProjectReferences | Where-Object { -not $_.Exists }
        if ($missingProjRefs.Count -gt 0) {
            $reportContent += "#### Missing Project References"
            $reportContent += ""
            foreach ($missingProjRef in $missingProjRefs) {
                $reportContent += "- $($missingProjRef.Name): $($missingProjRef.Path)"
            }
            $reportContent += ""
        }
    }
}

# Issues by Severity
if ($allIssues.Count -gt 0) {
    $reportContent += "## Issues by Severity"
    $reportContent += ""
    
    if ($criticalIssues.Count -gt 0) {
        $reportContent += "### 🚨 CRITICAL Priority ($($criticalIssues.Count) issues)"
        $reportContent += ""
        $reportContent += "| File | Issue | Type |"
        $reportContent += "|------|-------|------|"
        
        foreach ($issue in $criticalIssues | Select-Object -First 10) {
            $reportContent += "| $($issue.File) | $($issue.Issue) | $($issue.Type) |"
        }
        $reportContent += ""
    }
    
    if ($highIssues.Count -gt 0) {
        $reportContent += "### ⚠️ HIGH Priority ($($highIssues.Count) issues)"
        $reportContent += ""
        foreach ($issue in $highIssues | Select-Object -First 8) {
            $reportContent += "- **$($issue.File)**: $($issue.Issue)"
        }
        $reportContent += ""
    }
}

# .NET 4.8.1 Compatibility Analysis
$reportContent += "## .NET 4.8.1 Compatibility Analysis"
$reportContent += ""

$compatibleProjects = $analysisResults.Projects | Where-Object { 
    $_.TargetFramework -match "net48|v4\.8" 
}
$incompatibleProjects = $analysisResults.Projects | Where-Object { 
    $_.TargetFramework -notmatch "net48|v4\.8" -and $_.TargetFramework -ne "Unknown"
}

$reportContent += "| Compatibility | Projects | Status |"
$reportContent += "|---------------|----------|--------|"
$reportContent += "| Compatible | $($compatibleProjects.Count) | $(if ($compatibleProjects.Count -eq $analysisResults.Projects.Count) { "✅ All Compatible" } else { "📝 Partial" }) |"
$reportContent += "| Incompatible | $($incompatibleProjects.Count) | $(if ($incompatibleProjects.Count -eq 0) { "✅ None" } else { "⚠️ Needs Update" }) |"
$reportContent += ""

# Action Plan
$reportContent += "## Action Plan"
$reportContent += ""

if ($criticalIssues.Count -gt 0) {
    $reportContent += "### 🚨 IMMEDIATE ACTION REQUIRED"
    $reportContent += ""
    $reportContent += "Critical issues must be resolved before the project can build successfully:"
    $reportContent += ""
    $reportContent += "1. Restore Missing References: Fix broken assembly and project references"
    $reportContent += "2. Repair Project Files: Address corrupted or unparseable project files"
    $reportContent += "3. Update Solution: Ensure all projects are properly included in solutions"
    $reportContent += "4. Verify File Paths: Check that all referenced files exist at expected locations"
    $reportContent += ""
} else {
    $reportContent += "### ✅ MAINTENANCE MODE"
    $reportContent += ""
    $reportContent += "Excellent project integrity! Consider these optimizations:"
    $reportContent += ""
    $reportContent += "1. Regular Audits: Run this analysis before major releases"
    $reportContent += "2. Reference Cleanup: Review unused references periodically"
    $reportContent += "3. Documentation: Keep project documentation updated"
    $reportContent += ""
}

$reportContent += "## Best Practices"
$reportContent += ""
$reportContent += "1. .NET 4.8.1 Targeting: Ensure all projects target .NET Framework 4.8.1"
$reportContent += "2. Reference Management: Use NuGet packages over manual assembly references"
$reportContent += "3. Solution Organization: Keep all projects included in solution files"
$reportContent += "4. File Encoding: Use UTF-8 without BOM for project files"
$reportContent += "5. Regular Validation: Check project integrity after major changes"
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Project Integrity Report Generator*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 Project integrity analysis complete!" -ForegroundColor Green

# OUTPUT PATH AT THE END for easy finding
if ($saveSuccess) {
    Write-Host "`n📄 DETAILED REPORT SAVED:" -ForegroundColor Green
    Write-Host "   Location: $reportPath" -ForegroundColor Cyan
    Write-Host "   Size: $([Math]::Round((Get-Item $reportPath).Length / 1KB, 1)) KB" -ForegroundColor Gray
} else {
    Write-Host "`n⚠️ No detailed report generated" -ForegroundColor DarkYellow
}

# INTERACTIVE WORKFLOW LOOP (only when running standalone)
if ($IsInteractive -and -not $RunningFromScript) {
    do {
        Write-Host "`n🎯 What would you like to do next?" -ForegroundColor DarkCyan
        Write-Host "   D - Display report in console" -ForegroundColor Green
        Write-Host "   R - Re-run project integrity analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING PROJECT INTEGRITY REPORT:" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING PROJECT INTEGRITY ANALYSIS..." -ForegroundColor DarkYellow
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
    Write-Host "Project integrity analysis completed successfully" -ForegroundColor DarkGray
}