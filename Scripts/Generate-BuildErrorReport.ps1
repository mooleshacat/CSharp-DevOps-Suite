# MixerThreholdMod DevOps Tool: Build Error Report Generator (ENHANCED VERSION)
# Performs dotnet build, captures errors, and triages them by criticality
# ENHANCED: Shows relative file paths with line/column numbers for better navigation
# SMART WARNING DISPLAY: Hides warnings when errors exist, shows when error-free
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

Write-Host "🕐 Build error analysis started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Analyzing build errors in: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 ENHANCED VERSION - Smart warning display with error priority focus" -ForegroundColor Green

# Function to safely extract filename from potentially malformed paths
function Get-SafeFileName {
    param($filePath)
    
    try {
        if ([string]::IsNullOrEmpty($filePath)) {
            return "Unknown"
        }
        
        # Try normal GetFileName first
        return [System.IO.Path]::GetFileName($filePath)
    }
    catch {
        try {
            # Fallback 1: manually extract filename after last slash/backslash
            $lastSlash = $filePath.LastIndexOfAny(@('\', '/'))
            if ($lastSlash -ge 0 -and $lastSlash -lt $filePath.Length - 1) {
                return $filePath.Substring($lastSlash + 1)
            }
            
            # Fallback 2: return sanitized path
            $sanitized = $filePath -replace '[<>:"|?*]', '_'
            return "File_$sanitized"
        }
        catch {
            # Ultimate fallback: return safe identifier
            return "InvalidPath_$(Get-Random)"
        }
    }
}

# NEW FUNCTION: Extract relative file path from absolute path for better readability
function Get-RelativeFilePath {
    param($fullPath, $projectRoot)
    
    try {
        if ([string]::IsNullOrEmpty($fullPath) -or [string]::IsNullOrEmpty($projectRoot)) {
            return "Unknown"
        }
        
        # Normalize paths to handle different slash types
        $normalizedFull = $fullPath -replace '/', '\'
        $normalizedRoot = $projectRoot -replace '/', '\'
        
        # Ensure project root ends with backslash for proper matching
        if (-not $normalizedRoot.EndsWith('\')) {
            $normalizedRoot += '\'
        }
        
        # Extract relative path
        if ($normalizedFull.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $normalizedFull.Substring($normalizedRoot.Length)
            
            # Remove project directory name if present (e.g., "MixerThreholdMod-1_0_0\")
            if ($relativePath -match '^[^\\]+\\(.+)$') {
                return $matches[1]  # Return everything after first directory
            } else {
                return $relativePath
            }
        } else {
            # Fallback: just return filename if path resolution fails
            return [System.IO.Path]::GetFileName($fullPath)
        }
    }
    catch {
        # Ultimate fallback: return safe filename
        return Get-SafeFileName -filePath $fullPath
    }
}

# Function to find project files
function Find-ProjectFiles {
    try {
        # Look for .csproj, .sln files
        $projectFiles = @()
        
        # Find solution files first (preferred)
        $solutionFiles = Get-ChildItem -Path $ProjectRoot -Filter "*.sln" -ErrorAction SilentlyContinue
        if ($solutionFiles.Count -gt 0) {
            $projectFiles += $solutionFiles | Select-Object -First 1  # Use first solution file
        }
        
        # If no solution, look for .csproj files
        if ($projectFiles.Count -eq 0) {
            $csprojFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Filter "*.csproj" -ErrorAction SilentlyContinue | Where-Object {
                $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]"
            }
            $projectFiles += $csprojFiles
        }
        
        return $projectFiles
    }
    catch {
        Write-Host "⚠️  Error finding project files: $_" -ForegroundColor DarkYellow
        return @()
    }
}

# Function to parse build errors (ENHANCED VERSION - FIXED DUPLICATE PROCESSING)
function Parse-BuildErrors {
    param($buildOutput)
    
    $errors = @()
    $warnings = @()
    $messages = @()
    $parsingErrors = @()
    
    try {
        Write-Host "   🔍 Parsing $($buildOutput.Count) lines of build output..." -ForegroundColor DarkGray
        
        foreach ($line in $buildOutput) {
            if (-not $line) { continue }
            
            try {
                # Parse MSBuild/dotnet error format: file(line,column): error/warning CODE: message
                if ($line -match '^(.+?)\((\d+),(\d+)\):\s*(error|warning)\s+([A-Z0-9]+):\s*(.+)$') {
                    $file = $matches[1]
                    $lineNum = [int]$matches[2]
                    $column = [int]$matches[3]
                    $severity = $matches[4]
                    $code = $matches[5]
                    $message = $matches[6].Trim()
                    
                    # ENHANCED: Extract relative file path with line/column formatting
                    $safeFileName = Get-SafeFileName -filePath $file
                    $relativeFilePath = Get-RelativeFilePath -fullPath $file -projectRoot $ProjectRoot
                    $formattedLocation = "$relativeFilePath (Line: $lineNum / Char: $column)"
                    
                    $parsedError = [PSCustomObject]@{
                        File = $file
                        FileName = $safeFileName
                        RelativePath = $relativeFilePath           # NEW: Relative path
                        FormattedLocation = $formattedLocation     # NEW: Formatted location string
                        Line = $lineNum
                        Column = $column
                        Severity = $severity
                        Code = $code
                        Message = $message
                        FullLine = $line
                        Criticality = Get-ErrorCriticality -severity $severity -code $code -message $message
                    }
                    
                    if ($severity -eq "error") {
                        $errors += $parsedError
                    } else {
                        $warnings += $parsedError
                    }
                }
                # Parse general error messages without file location
                elseif ($line -match '(error|warning)\s+([A-Z0-9]+):\s*(.+)') {
                    $severity = $matches[1]
                    $code = $matches[2]
                    $message = $matches[3].Trim()
                    
                    $parsedError = [PSCustomObject]@{
                        File = ""
                        FileName = "General"
                        RelativePath = "General"
                        FormattedLocation = "General $severity (no specific location)"
                        Line = 0
                        Column = 0
                        Severity = $severity
                        Code = $code
                        Message = $message
                        FullLine = $line
                        Criticality = Get-ErrorCriticality -severity $severity -code $code -message $message
                    }
                    
                    if ($severity -eq "error") {
                        $errors += $parsedError
                    } else {
                        $warnings += $parsedError
                    }
                }
                # FIXED: Enhanced pattern matching for build failures
                elseif ($line -match '(Build FAILED|Build succeeded|Build FAILED with errors|failed with \d+ error|Restore complete)') {
                    $messages += $line
                }
                # FIXED: Catch lines that indicate errors but don't match standard patterns
                elseif ($line -match '(error|Error|ERROR)' -and $line -notmatch '(0 Error|no error)') {
                    $messages += "POTENTIAL_ERROR: $line"
                }
            }
            catch {
                $parsingErrors += "Error parsing line '$line': $_"
            }
        }
        
        # ENHANCED: Log parsing statistics
        Write-Host "   📊 Parsed: $($errors.Count) errors, $($warnings.Count) warnings, $($parsingErrors.Count) parsing issues" -ForegroundColor DarkGray
        
        if ($parsingErrors.Count -gt 0) {
            Write-Host "   ⚠️  $($parsingErrors.Count) lines failed to parse (see detailed report)" -ForegroundColor DarkYellow
        }
        
        return [PSCustomObject]@{
            Errors = $errors
            Warnings = $warnings
            Messages = $messages
            ParsingErrors = $parsingErrors
            TotalErrors = $errors.Count
            TotalWarnings = $warnings.Count
            ParseSuccessful = $true
        }
    }
    catch {
        Write-Host "   🚨 CRITICAL: Build output parsing completely failed: $_" -ForegroundColor Red
        Write-Host "   📋 This indicates a serious script issue - manual review required!" -ForegroundColor DarkYellow
        
        # Return failure state with error indicator
        return [PSCustomObject]@{
            Errors = @()
            Warnings = @()
            Messages = @("CRITICAL_PARSING_FAILURE: $_")
            ParsingErrors = @($_)
            TotalErrors = -1  # Special flag indicating complete parsing failure
            TotalWarnings = 0
            ParseSuccessful = $false
        }
    }
}

# Function to execute dotnet build (FIXED VERSION - NO DOUBLE PARSING)
function Invoke-DotNetBuild {
    param($projectFile)
    
    try {
        Write-Host "   🔨 Building project: $($projectFile.Name)" -ForegroundColor Gray
        
        Push-Location $ProjectRoot
        
        # Execute dotnet build and capture ALL output
        $buildOutput = & dotnet build $projectFile.FullName --verbosity normal 2>&1 | ForEach-Object { $_.ToString() }
        $buildExitCode = $LASTEXITCODE
        
        Pop-Location
        
        # FIXED: Return raw output without parsing here (parsing happens later)
        return [PSCustomObject]@{
            ExitCode = $buildExitCode
            Output = $buildOutput
            Success = ($buildExitCode -eq 0)  # Simple success check based on exit code only
            ProjectFile = $projectFile.FullName
            ProjectName = $projectFile.BaseName
            ExitCodeSuccess = ($buildExitCode -eq 0)
        }
    }
    catch {
        Write-Host "   ⚠️  Error executing build: $_" -ForegroundColor DarkYellow
        Pop-Location
        return [PSCustomObject]@{
            ExitCode = -1
            Output = @("Build execution failed: $_")
            Success = $false
            ProjectFile = $projectFile.FullName
            ProjectName = $projectFile.BaseName
            ExitCodeSuccess = $false
        }
    }
}

# Function to determine error criticality (ENHANCED)
function Get-ErrorCriticality {
    param($severity, $code, $message)
    
    # Critical errors that prevent compilation
    $criticalCodes = @(
        'CS0101',  # The namespace already contains a definition (DUPLICATE CONSTANTS ISSUE)
        'CS0103',  # Name does not exist in current context
        'CS0246',  # Type or namespace not found (SAVEDATA TYPE ISSUE)
        'CS0117',  # Does not contain a definition
        'CS1002',  # Syntax error
        'CS1513',  # } expected
        'CS0029',  # Cannot implicitly convert type
        'CS0118',  # Variable is used like a method
        'CS0019',  # Operator cannot be applied
        'CS0229'   # Ambiguity between members (DUPLICATE CONSTANTS ISSUE)
    )
    
    # High severity errors
    $highSeverityCodes = @(
        'CS0161',  # Not all code paths return a value
        'CS0162',  # Unreachable code detected
        'CS0168',  # Variable declared but never used
        'CS0219',  # Variable assigned but never used
        'CS0414'   # Field assigned but never used
    )
    
    # Project-specific critical patterns
    $criticalPatterns = @(
        'MelonLoader',
        'Thread',
        'async',
        'Task',
        'ConfigureAwait',
        'CancellationToken',
        'IL2CPP',
        'SaveDataType',
        'ModConstants',
        'duplicate',
        'already contains'
    )
    
    if ($severity -eq "error") {
        # Critical compilation errors
        if ($criticalCodes -contains $code) {
            return "CRITICAL"
        }
        
        # Project-specific critical errors
        foreach ($pattern in $criticalPatterns) {
            if ($message -match $pattern) {
                return "CRITICAL"
            }
        }
        
        # High severity errors
        if ($highSeverityCodes -contains $code) {
            return "HIGH"
        }
        
        # Default error severity
        return "MEDIUM"
    } else {
        # Warning severity
        if ($highSeverityCodes -contains $code) {
            return "MEDIUM"
        }
        return "LOW"
    }
}

# Function to consolidate duplicate errors (ENHANCED - WORKS FOR BOTH ERRORS AND WARNINGS)
function Consolidate-Errors {
    param($errors)
    
    try {
        if ($errors.Count -eq 0) {
            return @()
        }
        
        # Group errors/warnings by Code + Message (ignoring file location)
        $groupedErrors = $errors | Group-Object { "$($_.Code):$($_.Message)" }
        
        $consolidatedErrors = @()
        
        foreach ($group in $groupedErrors) {
            $firstError = $group.Group[0]
            $allLocations = $group.Group | Sort-Object File, Line
            
            $consolidatedError = [PSCustomObject]@{
                Code = $firstError.Code
                Message = $firstError.Message
                Severity = $firstError.Severity
                Criticality = $firstError.Criticality
                Occurrences = $group.Count
                Locations = $allLocations | ForEach-Object {
                    [PSCustomObject]@{
                        File = $_.File
                        FileName = $_.FileName
                        RelativePath = $_.RelativePath
                        FormattedLocation = $_.FormattedLocation    # NEW: Pre-formatted location
                        Line = $_.Line
                        Column = $_.Column
                    }
                }
                Files = ($allLocations | Select-Object -ExpandProperty FileName -Unique | Sort-Object) -join ", "
                # NEW: List all formatted locations for comprehensive error tracking
                AllLocations = ($allLocations | Select-Object -ExpandProperty FormattedLocation | Sort-Object) -join "`n         "
                FirstOccurrence = $firstError
            }
            
            $consolidatedErrors += $consolidatedError
        }
        
        return $consolidatedErrors | Sort-Object @{
            Expression = {
                switch ($_.Criticality) {
                    "CRITICAL" { 1 }
                    "HIGH" { 2 }
                    "MEDIUM" { 3 }
                    "LOW" { 4 }
                    default { 5 }
                }
            }
        }, Occurrences -Descending
    }
    catch {
        Write-Host "   ⚠️  Error consolidating errors: $_" -ForegroundColor DarkYellow
        return $errors
    }
}

# Helper function for error fix suggestions (ENHANCED)
function Get-ErrorFixSuggestion($code) {
    switch ($code) {
        'CS0101' { return "Remove duplicate class/namespace definitions - check for duplicate files" }
        'CS0103' { return "Check variable/method names and using statements" }
        'CS0246' { return "Add missing type definition or verify namespace imports" }
        'CS0117' { return "Check method/property exists in the specified type" }
        'CS0229' { return "Resolve ambiguous member references - likely duplicate constants" }
        'CS1002' { return "Review syntax - likely missing semicolon or brace" }
        'CS1513' { return "Add missing closing brace '}'" }
        'CS0029' { return "Add explicit type conversion or cast" }
        'CS0118' { return "Ensure correct usage syntax (method vs property)" }
        'CS0019' { return "Check operator compatibility with operand types" }
        'CS0161' { return "Ensure all code paths return a value" }
        'CS0162' { return "Remove or fix unreachable code" }
        'CS0105' { return "Remove duplicate using directives" }
        default { return "Review error message and fix according to compiler guidance" }
    }
}

# Main script execution
Write-Host "`n📂 Scanning for project files..." -ForegroundColor DarkGray
$projectFiles = Find-ProjectFiles

if ($projectFiles.Count -eq 0) {
    Write-Host "❌ No project files (.sln or .csproj) found!" -ForegroundColor Red
    Write-Host "Ensure you're running this script from a .NET project directory" -ForegroundColor DarkYellow
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

Write-Host "📊 Found $($projectFiles.Count) project file(s):" -ForegroundColor Gray
foreach ($project in $projectFiles) {
    Write-Host "   📄 $($project.Name)" -ForegroundColor Gray
}

# Check if dotnet CLI is available
try {
    $dotnetVersion = & dotnet --version 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ .NET CLI not found! Please install .NET SDK" -ForegroundColor Red
        if ($IsInteractive -and -not $RunningFromScript) {
            Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
            Read-Host
        }
        return
    }
    Write-Host "✅ .NET CLI version: $dotnetVersion" -ForegroundColor Green
}
catch {
    Write-Host "❌ .NET CLI not available: $_" -ForegroundColor Red
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

# Execute builds for each project
Write-Host "`n🔨 Executing dotnet build..." -ForegroundColor DarkCyan
$buildResults = @()

foreach ($project in $projectFiles) {
    $buildResult = Invoke-DotNetBuild -projectFile $project
    $buildResults += $buildResult
    
    # FIXED: Simple build status reporting (detailed analysis comes later)
    if ($buildResult.Success) {
        Write-Host "   ✅ $($project.Name): Build succeeded (exit code: $($buildResult.ExitCode))" -ForegroundColor Green
    } else {
        Write-Host "   ❌ $($project.Name): Build failed (exit code: $($buildResult.ExitCode))" -ForegroundColor Red
    }
}

# FIXED: Parse errors from all build results ONCE (no double parsing)
Write-Host "`n📊 Analyzing build output..." -ForegroundColor DarkGray
$allErrors = @()
$allWarnings = @()
$buildMessages = @()
$allParsingErrors = @()

foreach ($buildResult in $buildResults) {
    $parsed = Parse-BuildErrors -buildOutput $buildResult.Output
    $allErrors += $parsed.Errors
    $allWarnings += $parsed.Warnings
    $buildMessages += $parsed.Messages
    $allParsingErrors += $parsed.ParsingErrors
}

Write-Host "✅ Found $($allErrors.Count) errors and $($allWarnings.Count) warnings" -ForegroundColor Gray
if ($allParsingErrors.Count -gt 0) {
    Write-Host "⚠️  $($allParsingErrors.Count) parsing issues detected" -ForegroundColor DarkYellow
}

# Consolidate duplicate errors AND warnings
Write-Host "`n🔄 Consolidating duplicate errors..." -ForegroundColor DarkGray
$consolidatedErrors = Consolidate-Errors -errors $allErrors
$consolidatedWarnings = Consolidate-Errors -errors $allWarnings

Write-Host "✅ Consolidated to $($consolidatedErrors.Count) unique errors and $($consolidatedWarnings.Count) unique warnings" -ForegroundColor Gray

Write-Host "`n=== BUILD ERROR ANALYSIS REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

# FIXED: Enhanced build status assessment based on parsed results
$overallSuccess = $buildResults | Where-Object { $_.Success -and ($allErrors | Where-Object { $_.File -like "*$($_.ProjectName)*" }).Count -eq 0 }
$overallFailed = $buildResults | Where-Object { -not $_.Success -or ($allErrors | Where-Object { $_.File -like "*$($_.ProjectName)*" }).Count -gt 0 }

Write-Host "📊 Build Summary:" -ForegroundColor DarkCyan
Write-Host "   Projects built: $($buildResults.Count)" -ForegroundColor Gray
Write-Host "   Successful: $($overallSuccess.Count)" -ForegroundColor $(if ($overallSuccess.Count -eq $buildResults.Count) { "Green" } else { "DarkYellow" })
Write-Host "   Failed: $($overallFailed.Count)" -ForegroundColor $(if ($overallFailed.Count -eq 0) { "Green" } else { "Red" })
Write-Host "   Total errors: $($allErrors.Count) (consolidated: $($consolidatedErrors.Count))" -ForegroundColor $(if ($allErrors.Count -eq 0) { "Green" } else { "Red" })
Write-Host "   Total warnings: $($allWarnings.Count) (consolidated: $($consolidatedWarnings.Count))" -ForegroundColor $(if ($allWarnings.Count -eq 0) { "Green" } else { "DarkYellow" })

# ENHANCED: Error-priority display logic - errors take precedence
if ($consolidatedErrors.Count -gt 0 -or $overallFailed.Count -gt 0) {
    Write-Host "`n🚨 Build Errors Detected:" -ForegroundColor DarkCyan
    
    $criticalErrors = $consolidatedErrors | Where-Object { $_.Criticality -eq "CRITICAL" }
    $highErrors = $consolidatedErrors | Where-Object { $_.Criticality -eq "HIGH" }
    $mediumErrors = $consolidatedErrors | Where-Object { $_.Criticality -eq "MEDIUM" }
    
    if ($criticalErrors.Count -gt 0) {
        Write-Host "`n   🚨 CRITICAL ERRORS (Fix First):" -ForegroundColor Red
        foreach ($error in $criticalErrors | Select-Object -First 5) {
            Write-Host "      $($error.Code): $($error.Message)" -ForegroundColor Red
            Write-Host "         Occurrences: $($error.Occurrences) | Files: $($error.Files)" -ForegroundColor DarkGray
            Write-Host "         $($error.AllLocations)" -ForegroundColor Cyan
        }
        if ($criticalErrors.Count -gt 5) {
            Write-Host "      ... and $($criticalErrors.Count - 5) more critical errors" -ForegroundColor DarkGray
        }
    }
    
    if ($highErrors.Count -gt 0) {
        Write-Host "`n   ⚠️  HIGH PRIORITY ERRORS:" -ForegroundColor DarkYellow
        foreach ($error in $highErrors | Select-Object -First 3) {
            Write-Host "      $($error.Code): $($error.Message)" -ForegroundColor DarkYellow
            Write-Host "         Occurrences: $($error.Occurrences) | Files: $($error.Files)" -ForegroundColor DarkGray
            Write-Host "         $($error.AllLocations)" -ForegroundColor Yellow
        }
        if ($highErrors.Count -gt 3) {
            Write-Host "      ... and $($highErrors.Count - 3) more high priority errors" -ForegroundColor DarkGray
        }
    }
    
    if ($mediumErrors.Count -gt 0) {
        Write-Host "`n   📝 MEDIUM PRIORITY ERRORS:" -ForegroundColor Gray
        Write-Host "      $($mediumErrors.Count) errors - see detailed report for full list" -ForegroundColor Gray
    }
    
    # SMART WARNING LOGIC: Hide warnings when errors exist, just mention they exist
    if ($consolidatedWarnings.Count -gt 0) {
        Write-Host "`n   📋 Note: $($consolidatedWarnings.Count) warning types detected but hidden (fix errors first)" -ForegroundColor DarkGray
        Write-Host "      Warnings will be displayed once all errors are resolved" -ForegroundColor DarkGray
    }
    
} else {
    # FIXED: Only report success if everything checks out
    if ($overallFailed.Count -eq 0 -and $allErrors.Count -eq 0) {
        Write-Host "`n✅ NO BUILD ERRORS! Clean compilation achieved." -ForegroundColor Green
        
        # SMART WARNING LOGIC: Show warnings in detail when no errors exist
        if ($consolidatedWarnings.Count -gt 0) {
            Write-Host "`n⚠️  Build Warnings (Now that errors are fixed, focus on these):" -ForegroundColor DarkYellow
            $topWarnings = $consolidatedWarnings | Sort-Object Occurrences -Descending | Select-Object -First 5
            foreach ($warning in $topWarnings) {
                Write-Host "   • $($warning.Code): $($warning.Occurrences) occurrences" -ForegroundColor DarkYellow
                Write-Host "     $($warning.Message)" -ForegroundColor DarkGray
                if ($warning.AllLocations -and $warning.AllLocations.Length -gt 0) {
                    Write-Host "     $($warning.AllLocations)" -ForegroundColor DarkYellow
                }
            }
            if ($consolidatedWarnings.Count -gt 5) {
                Write-Host "   ... and $($consolidatedWarnings.Count - 5) more warning types (see detailed report)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "   🎉 Perfect! No warnings either - excellent code quality!" -ForegroundColor Green
        }
        
    } else {
        Write-Host "`n🚨 INCONSISTENT BUILD STATE DETECTED!" -ForegroundColor Red
        Write-Host "   Build may have succeeded but issues were found:" -ForegroundColor DarkYellow
        if ($overallFailed.Count -gt 0) {
            Write-Host "   • $($overallFailed.Count) project(s) reported as failed" -ForegroundColor Red
        }
        if ($allErrors.Count -gt 0) {
            Write-Host "   • $($allErrors.Count) error(s) detected in output" -ForegroundColor Red
        }
        Write-Host "   Manual verification strongly recommended!" -ForegroundColor DarkYellow
    }
}

# Quick recommendations
Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan

if ($overallFailed.Count -gt 0 -or $allErrors.Count -gt 0) {
    Write-Host "   🚨 IMMEDIATE: Fix build failures before proceeding" -ForegroundColor Red
    
    $criticalErrors = $consolidatedErrors | Where-Object { $_.Criticality -eq "CRITICAL" }
    $highErrors = $consolidatedErrors | Where-Object { $_.Criticality -eq "HIGH" }
    
    if ($criticalErrors.Count -gt 0) {
        Write-Host "   • Start with $($criticalErrors.Count) CRITICAL errors" -ForegroundColor Red
        Write-Host "   • Focus on duplicate definitions and missing types first" -ForegroundColor Red
    }
    
    if ($highErrors.Count -gt 0) {
        Write-Host "   • Address $($highErrors.Count) HIGH priority errors next" -ForegroundColor DarkYellow
    }
    
    if ($consolidatedWarnings.Count -gt 0) {
        Write-Host "   • After fixing errors, address $($consolidatedWarnings.Count) warning types for code quality" -ForegroundColor Gray
    }
} else {
    Write-Host "   ✅ All builds successful!" -ForegroundColor Green
    
    if ($consolidatedWarnings.Count -gt 0) {
        Write-Host "   • Consider addressing $($consolidatedWarnings.Count) warning types shown above" -ForegroundColor DarkYellow
        Write-Host "   • Warnings may indicate potential runtime issues" -ForegroundColor Gray
    } else {
        Write-Host "   • Excellent! No errors or warnings detected" -ForegroundColor Green
        Write-Host "   • Code is ready for deployment" -ForegroundColor Green
    }
}

Write-Host "   • Review detailed report for complete analysis" -ForegroundColor Gray
Write-Host "   • Run this analysis before committing code changes" -ForegroundColor Gray

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

# Generate detailed build error report (ENHANCED)
Write-Host "`n📝 Generating detailed build error report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "BUILD-ERROR-REPORT_$timestamp.md"

$reportContent = @()
$reportContent += "# Build Error Analysis Report (ENHANCED VERSION)"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Projects Built**: $($buildResults.Count)"
$reportContent += "**Build Status**: $(if ($overallFailed.Count -eq 0 -and $allErrors.Count -eq 0) { "✅ Success" } else { "❌ Failed ($($overallFailed.Count)/$($buildResults.Count))" })"
$reportContent += "**Total Errors**: $($allErrors.Count) (consolidated: $($consolidatedErrors.Count))"
$reportContent += "**Total Warnings**: $($allWarnings.Count) (consolidated: $($consolidatedWarnings.Count))"
$reportContent += "**Parsing Issues**: $($allParsingErrors.Count)"
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

if ($overallFailed.Count -eq 0 -and $allErrors.Count -eq 0) {
    $reportContent += "🎉 **BUILD SUCCESSFUL!** All projects compiled without errors."
    $reportContent += ""
    if ($consolidatedWarnings.Count -eq 0) {
        $reportContent += "Perfect compilation - no errors or warnings detected."
    } else {
        $reportContent += "Consider addressing $($consolidatedWarnings.Count) warning types for optimal code quality."
    }
} else {
    $reportContent += "❌ **BUILD FAILURES DETECTED** - Immediate action required."
    $reportContent += ""
    if ($allErrors.Count -gt 0) {
        $reportContent += "$($consolidatedErrors.Count) unique error types detected across $($overallFailed.Count) failed projects."
    }
}

$reportContent += ""
$reportContent += "| Metric | Value | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| **Projects Built** | $($buildResults.Count) | - |"
$reportContent += "| **Successful Builds** | $($overallSuccess.Count) | $(if ($overallSuccess.Count -eq $buildResults.Count) { "✅ All Passed" } else { "⚠️ Some Failed" }) |"
$reportContent += "| **Failed Builds** | $($overallFailed.Count) | $(if ($overallFailed.Count -eq 0) { "✅ None" } else { "❌ Action Required" }) |"
$reportContent += "| **Unique Errors** | $($consolidatedErrors.Count) | $(if ($consolidatedErrors.Count -eq 0) { "✅ None" } else { "🚨 Fix Required" }) |"
$reportContent += "| **Unique Warnings** | $($consolidatedWarnings.Count) | $(if ($consolidatedWarnings.Count -eq 0) { "✅ None" } elseif ($consolidatedWarnings.Count -le 5) { "📝 Few" } else { "⚠️ Many" }) |"

# Add criticality breakdown
if ($consolidatedErrors.Count -gt 0) {
    $criticalCount = ($consolidatedErrors | Where-Object { $_.Criticality -eq "CRITICAL" }).Count
    $highCount = ($consolidatedErrors | Where-Object { $_.Criticality -eq "HIGH" }).Count
    $mediumCount = ($consolidatedErrors | Where-Object { $_.Criticality -eq "MEDIUM" }).Count
    
    $reportContent += "| **Critical Errors** | $criticalCount | $(if ($criticalCount -eq 0) { "✅ None" } else { "🚨 Immediate Fix" }) |"
    $reportContent += "| **High Priority** | $highCount | $(if ($highCount -eq 0) { "✅ None" } else { "⚠️ Fix Soon" }) |"
    $reportContent += "| **Medium Priority** | $mediumCount | $(if ($mediumCount -eq 0) { "✅ None" } else { "📝 Review" }) |"
}

$reportContent += ""

# ENHANCED: Project build results
$reportContent += "## Project Build Results"
$reportContent += ""
$reportContent += "| Project | Status | Exit Code | Errors | Warnings |"
$reportContent += "|---------|--------|-----------|--------|----------|"

foreach ($buildResult in $buildResults) {
    $projectErrors = $allErrors | Where-Object { $_.File -like "*$($buildResult.ProjectName)*" }
    $projectWarnings = $allWarnings | Where-Object { $_.File -like "*$($buildResult.ProjectName)*" }
    
    $status = if ($buildResult.Success) { "✅ Success" } else { "❌ Failed" }
    
    $reportContent += "| ````$($buildResult.ProjectName)```` | $status | $($buildResult.ExitCode) | $($projectErrors.Count) | $($projectWarnings.Count) |"
}

$reportContent += ""

# ENHANCED: Detailed Error Analysis with formatted locations
if ($consolidatedErrors.Count -gt 0) {
    $reportContent += "## Detailed Error Analysis"
    $reportContent += ""
    
    # Group by criticality
    $errorsByCriticality = $consolidatedErrors | Group-Object Criticality | Sort-Object @{
        Expression = {
            switch ($_.Name) {
                "CRITICAL" { 1 }
                "HIGH" { 2 }
                "MEDIUM" { 3 }
                "LOW" { 4 }
                default { 5 }
            }
        }
    }
    
    foreach ($criticalityGroup in $errorsByCriticality) {
        $criticality = $criticalityGroup.Name
        $criticalityErrors = $criticalityGroup.Group
        
        $sectionIcon = switch ($criticality) {
            "CRITICAL" { "🚨" }
            "HIGH" { "⚠️" }
            "MEDIUM" { "📝" }
            "LOW" { "💭" }
            default { "📌" }
        }
        
        $reportContent += "### $sectionIcon $criticality Priority Errors ($($criticalityErrors.Count) types)"
        $reportContent += ""
        
        foreach ($error in $criticalityErrors | Sort-Object Occurrences -Descending) {
            $reportContent += "#### $($error.Code): $(if ($error.Message.Length -gt 80) { $error.Message.Substring(0, 77) + "..." } else { $error.Message })"
            $reportContent += ""
            $reportContent += "**Occurrences**: $($error.Occurrences) | **Files**: $($error.Files)"
            $reportContent += ""
            $reportContent += "**Error Details**: $($error.Message)"
            $reportContent += ""
            
            if ($error.Occurrences -le 10) {
                # Show all locations for small number of occurrences with enhanced formatting
                $reportContent += "**All Locations**:"
                $reportContent += ""
                foreach ($location in $error.Locations) {
                    if ($location.File) {
                        $reportContent += "- ````$($location.FormattedLocation)````"
                    } else {
                        $reportContent += "- General error (no specific location)"
                    }
                }
            } else {
                # Show sample locations for large number of occurrences
                $reportContent += "**Sample Locations** (showing first 5 of $($error.Occurrences)):"
                $reportContent += ""
                foreach ($location in $error.Locations | Select-Object -First 5) {
                    if ($location.File) {
                        $reportContent += "- ````$($location.FormattedLocation)````"
                    } else {
                        $reportContent += "- General error (no specific location)"
                    }
                }
                $reportContent += ""
                $reportContent += "*... and $($error.Occurrences - 5) more locations*"
            }
            $reportContent += ""
        }
    }
}

# ENHANCED: Detailed Warning Analysis - always included in detailed report
if ($consolidatedWarnings.Count -gt 0) {
    $reportContent += "## Detailed Warning Analysis"
    $reportContent += ""
    
    # Add note about smart display logic
    if ($consolidatedErrors.Count -gt 0) {
        $reportContent += "> **Note**: These warnings were hidden in console output due to existing errors. Fix errors first, then address warnings."
        $reportContent += ""
    }
    
    # Group by criticality
    $warningsByCriticality = $consolidatedWarnings | Group-Object Criticality | Sort-Object @{
        Expression = {
            switch ($_.Name) {
                "CRITICAL" { 1 }
                "HIGH" { 2 }
                "MEDIUM" { 3 }
                "LOW" { 4 }
                default { 5 }
            }
        }
    }
    
    foreach ($criticalityGroup in $warningsByCriticality) {
        $criticality = $criticalityGroup.Name
        $criticalityWarnings = $criticalityGroup.Group
        
        $sectionIcon = switch ($criticality) {
            "CRITICAL" { "🚨" }
            "HIGH" { "⚠️" }
            "MEDIUM" { "📝" }
            "LOW" { "💭" }
            default { "📌" }
        }
        
        $reportContent += "### $sectionIcon $criticality Priority Warnings ($($criticalityWarnings.Count) types)"
        $reportContent += ""
        
        foreach ($warning in $criticalityWarnings | Sort-Object Occurrences -Descending) {
            $reportContent += "#### $($warning.Code): $(if ($warning.Message.Length -gt 80) { $warning.Message.Substring(0, 77) + "..." } else { $warning.Message })"
            $reportContent += ""
            $reportContent += "**Occurrences**: $($warning.Occurrences) | **Files**: $($warning.Files)"
            $reportContent += ""
            $reportContent += "**Warning Details**: $($warning.Message)"
            $reportContent += ""
            
            if ($warning.Occurrences -le 10) {
                # Show all locations for small number of occurrences with enhanced formatting
                $reportContent += "**All Locations**:"
                $reportContent += ""
                foreach ($location in $warning.Locations) {
                    if ($location.File) {
                        $reportContent += "- ````$($location.FormattedLocation)````"
                    } else {
                        $reportContent += "- General warning (no specific location)"
                    }
                }
            } else {
                # Show sample locations for large number of occurrences
                $reportContent += "**Sample Locations** (showing first 5 of $($warning.Occurrences)):"
                $reportContent += ""
                foreach ($location in $warning.Locations | Select-Object -First 5) {
                    if ($location.File) {
                        $reportContent += "- ````$($location.FormattedLocation)````"
                    } else {
                        $reportContent += "- General warning (no specific location)"
                    }
                }
                $reportContent += ""
                $reportContent += "*... and $($warning.Occurrences - 5) more locations*"
            }
            $reportContent += ""
        }
    }
}

# Enhanced parsing issues section
if ($allParsingErrors.Count -gt 0) {
    $reportContent += "## Parsing Issues"
    $reportContent += ""
    $reportContent += "⚠️ **$($allParsingErrors.Count) lines failed to parse correctly**"
    $reportContent += ""
    $reportContent += "These issues may indicate:"
    $reportContent += "- Non-standard error formats"
    $reportContent += "- Build tool output changes"
    $reportContent += "- Character encoding problems"
    $reportContent += "- Path format issues"
    $reportContent += ""
    $reportContent += "**Sample Parsing Errors**:"
    $reportContent += ""
    foreach ($parseError in $allParsingErrors | Select-Object -First 5) {
        $reportContent += "- ````$parseError````"
    }
    if ($allParsingErrors.Count -gt 5) {
        $reportContent += "- *... and $($allParsingErrors.Count - 5) more parsing errors*"
    }
    $reportContent += ""
}

# Rest of report generation (fix priority guide, etc.)
if ($consolidatedErrors.Count -gt 0) {
    $reportContent += "## 🎯 Fix Priority Guide"
    $reportContent += ""
    
    $criticalErrors = $consolidatedErrors | Where-Object { $_.Criticality -eq "CRITICAL" }
    $highErrors = $consolidatedErrors | Where-Object { $_.Criticality -eq "HIGH" }
    
    if ($criticalErrors.Count -gt 0) {
        $reportContent += "### 🚨 IMMEDIATE (Critical Errors - $($criticalErrors.Count) types)"
        $reportContent += ""
        $reportContent += "These errors prevent compilation and must be fixed first:"
        $reportContent += ""
        
        foreach ($error in $criticalErrors | Select-Object -First 5) {
            $reportContent += "1. **$($error.Code)**: $($error.Message)"
            $reportContent += "   - **Fix**: $(Get-ErrorFixSuggestion -code $error.Code)"
            $reportContent += "   - **Locations**: $($error.Occurrences) occurrences in $($error.Files)"
            $reportContent += ""
        }
        
        if ($criticalErrors.Count -gt 5) {
            $reportContent += "*... and $($criticalErrors.Count - 5) more critical errors requiring immediate attention*"
            $reportContent += ""
        }
    }
    
    $reportContent += "### 📋 Recommended Fix Order"
    $reportContent += ""
    $reportContent += "1. **Remove duplicate files**: Fix CS0101 (duplicate definitions)"
    $reportContent += "2. **Add missing types**: Fix CS0246 (SaveDataType, etc.)"
    $reportContent += "3. **Clean using statements**: Fix CS0105 (duplicate usings)"
    $reportContent += "4. **Fix remaining syntax**: Address other compilation errors"
    $reportContent += "5. **Test build frequently**: Verify fixes don't introduce new issues"
    
    if ($consolidatedWarnings.Count -gt 0) {
        $reportContent += "6. **Address warnings**: Once error-free, improve code quality by fixing warnings"
    }
}

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Build Analysis**: Smart warning display prioritizes errors - warnings hidden in console when errors exist"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Build Error Report Generator (ENHANCED)*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 Build error analysis complete!" -ForegroundColor Green

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
        Write-Host "   R - Re-run build error analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING BUILD ERROR REPORT:" -ForegroundColor DarkCyan
                    Write-Host "==================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "`n==================================" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING BUILD ERROR ANALYSIS..." -ForegroundColor DarkYellow
                Write-Host "====================================" -ForegroundColor DarkYellow
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
    Write-Host "📄 Script completed - returning to caller" -ForegroundColor DarkGray
}