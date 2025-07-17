# MixerThreholdMod DevOps Menu Launcher
# A PowerShell-based categorized menu for launching DevOps scripts with prefix-based organization
# Groups scripts by their filename patterns for better organization and user experience

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ((Split-Path $ScriptDir -Leaf) -ieq "Scripts") {
    $ProjectRoot = Split-Path $ScriptDir -Parent
} else {
    $ProjectRoot = $ScriptDir
}

# Function to categorize scripts by prefix and patterns
function Get-CategorizedScripts {
    param($ScriptDirectory)
    
    # Get all .ps1 scripts excluding this menu script
    $allScripts = Get-ChildItem -Path $ScriptDirectory -Filter "*.ps1" | 
        Where-Object { $_.Name -ne "DevOps-Menu.ps1" } | 
        Sort-Object Name
    
    # Define script categories with their patterns and metadata
    $categories = @{
        "🛡️ Corruption & Integrity Scanning" = @{
            Patterns = @("Generate-Corruption-Report.ps1", "Generate-SyntaxValidationReport.ps1", "Generate-ImportVerificationReport.ps1", 
                        "Generate-ConflictMarkersReport.ps1", "Generate-FileEncodingReport.ps1", "Generate-ProjectIntegrityReport.ps1")
            Icon = "🛡️"
            Color = "Red"
            Description = "Critical corruption detection, syntax validation, and project integrity tools"
        }
        "📊 Comprehensive Analysis" = @{
            Patterns = @("Generate-Comprehensive-Report.ps1", "Generate-XmlDocumentationReport.ps1", "Generate-NamespaceAuditReport.ps1")
            Icon = "📊"
            Color = "Magenta"
            Description = "High-level project analysis with corruption detection and comprehensive reporting tools"
        }
        "🔍 Code Quality & Standards" = @{
            Patterns = @("Generate-MethodComplexityReport.ps1", "Generate-DuplicateCodeReport.ps1", "Generate-CopilotComplianceReport.ps1", 
                        "Generate-ConstantsAuditReport.ps1")
            Icon = "🔍"
            Color = "DarkGreen"
            Description = "Code quality analysis, complexity metrics, and standards compliance"
        }
        "📝 Documentation & Maintenance" = @{
            Patterns = @("Generate-XmlDocs.ps1", "Generate-ConstantsDocs.ps1", "Generate-ChangeLog.ps1", "Generate-ReleaseNotes.ps1")
            Icon = "📝"
            Color = "DarkGreen"
            Description = "Documentation generation and project maintenance tools"
        }
        "🚀 Build & Version Management" = @{
            Patterns = @("Generate-BuildErrorReport.ps1", "Update-VersionNumbers.ps1")
            Icon = "🚀"
            Color = "Cyan"
            Description = "Build analysis and version management tools"
        }
        "🌿 Git & Source Control" = @{
            Patterns = @("Git-SignAllCommits.ps1")
            Icon = "🌿"
            Color = "Cyan"
            Description = "Git operations and source control management utilities"
        }
        "🔧 Development Tools" = @{
            Patterns = @()  # Catch-all for uncategorized scripts
            Icon = "🔧"
            Color = "Gray"
            Description = "Miscellaneous development utilities and tools"
        }
    }
    
    # Categorize scripts
    $categorizedScripts = @{}
    
    foreach ($categoryName in $categories.Keys) {
        $categorizedScripts[$categoryName] = @{
            Scripts = @()
            Metadata = $categories[$categoryName]
        }
    }
    
    foreach ($script in $allScripts) {
        $assigned = $false
        
        # Check each category for explicit pattern matches
        foreach ($categoryName in $categories.Keys) {
            $patterns = $categories[$categoryName].Patterns
            
            # Skip catch-all category for now
            if ($patterns.Count -eq 0) { continue }
            
            foreach ($pattern in $patterns) {
                if ($script.Name -eq $pattern -or $script.Name -like $pattern) {
                    $categorizedScripts[$categoryName].Scripts += $script
                    $assigned = $true
                    break
                }
            }
            
            if ($assigned) { break }
        }
        
        # If not assigned to any specific category, put in "Development Tools"
        if (-not $assigned) {
            $categorizedScripts["🔧 Development Tools"].Scripts += $script
        }
    }
    
    # Remove empty categories
    $result = @{}
    foreach ($categoryName in $categorizedScripts.Keys) {
        if ($categorizedScripts[$categoryName].Scripts.Count -gt 0) {
            $result[$categoryName] = $categorizedScripts[$categoryName]
        }
    }
    
    return $result
}

# Function to display the categorized menu
function Show-CategorizedMenu {
    param($CategorizedScripts)
    
    Clear-Host
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host " 🚀 MixerThreholdMod DevOps Suite v2.1 Enhanced" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""
    
    $totalScripts = 0
    foreach ($category in $CategorizedScripts.Values) {
        $totalScripts += $category.Scripts.Count
    }
    
    Write-Host "📊 Professional DevOps Tools: $totalScripts scripts across $($CategorizedScripts.Count) categories" -ForegroundColor Gray
    Write-Host "🆕 New: Syntax Validation, Import Verification, Namespace Audit" -ForegroundColor Green
    Write-Host ""
    
    $optionNumber = 1
    $scriptMap = @{}
    
    # Define category display order for better UX
    $categoryOrder = @(
        "🛡️ Corruption & Integrity Scanning",
        "📊 Comprehensive Analysis", 
        "🔍 Code Quality & Standards",
        "📝 Documentation & Maintenance",
        "🚀 Build & Version Management",
        "🌿 Git & Source Control",
        "🔧 Development Tools"
    )
    
    # Display each category in the defined order
    foreach ($categoryName in $categoryOrder) {
        if (-not $CategorizedScripts.ContainsKey($categoryName)) { continue }
        
        $category = $CategorizedScripts[$categoryName]
        $metadata = $category.Metadata
        
        # Category header with enhanced styling
        Write-Host "$categoryName" -ForegroundColor $metadata.Color
        Write-Host "   $($metadata.Description)" -ForegroundColor DarkGray
        Write-Host ""
        
        # Scripts in this category
        foreach ($script in $category.Scripts | Sort-Object Name) {
            $scriptMap[$optionNumber] = $script
            
            # Extract description from script if available
            $description = Get-ScriptDescription -ScriptPath $script.FullName -ScriptName $script.Name
            
            Write-Host "   $optionNumber. " -NoNewline -ForegroundColor Gray
            Write-Host $script.Name -NoNewline -ForegroundColor White
            
            if ($description) {
                Write-Host " - $description" -ForegroundColor DarkGray
            } else {
                Write-Host ""
            }
            
            $optionNumber++
        }
        Write-Host ""
    }
    
    # Special exit option
    Write-Host "🎯 Navigation:" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "   Q. " -NoNewline -ForegroundColor Gray
    Write-Host "Quit DevOps Suite" -ForegroundColor Red
    Write-Host ""
    
    return $scriptMap
}

# Function to extract description from script header with enhanced patterns
function Get-ScriptDescription {
    param($ScriptPath, $ScriptName)
    
    try {
        # Special descriptions for enhanced/new scripts
        $descriptions = @{
            "Generate-Corruption-Report.ps1" = "ULTIMATE corruption detector - runs ALL corruption scanners (syntax, import, encoding, conflicts)"
            "Generate-Comprehensive-Report.ps1" = "Complete project analysis orchestrator - runs ALL DevOps tools INCLUDING corruption detection for unified dashboard"
            "Generate-SyntaxValidationReport.ps1" = "🆕 C# syntax validator - brackets, semicolons, strings, file truncation detection"
            "Generate-ImportVerificationReport.ps1" = "🆕 Using statement verifier - unused, missing, and broken import detection"
            "Generate-NamespaceAuditReport.ps1" = "🆕 Namespace alignment auditor - consistency and structure analysis"
            "Generate-XmlDocs.ps1" = "🆕 XML documentation generator - creates comprehensive API docs for all public members"
            "Generate-XmlDocumentationReport.ps1" = "XML documentation coverage analyzer - verifies doc completeness"
            "Generate-ConflictMarkersReport.ps1" = "Git merge conflict detector - finds orphaned and suspicious conflict markers"
            "Generate-FileEncodingReport.ps1" = "File encoding analyzer - detects BOM issues and character corruption"
            "Generate-ProjectIntegrityReport.ps1" = "Project structure validator - missing references and dependency analysis"
            "Generate-BuildErrorReport.ps1" = "Build failure analyzer - compilation error detection and triage"
            "Generate-MethodComplexityReport.ps1" = "Code complexity analyzer - cyclomatic complexity and maintainability metrics"
            "Generate-DuplicateCodeReport.ps1" = "Duplicate code detector - identifies copy-paste violations"
            "Generate-CopilotComplianceReport.ps1" = "GitHub Copilot compliance checker - validates AI coding standards"
            "Generate-ConstantsAuditReport.ps1" = "Constants usage auditor - tracks constant definitions and usage"
            "Generate-ConstantsDocs.ps1" = "Constants documentation generator - creates reference docs for all constants"
            "Generate-ChangeLog.ps1" = "Changelog generator - creates version history from git commits"
            "Generate-ReleaseNotes.ps1" = "Release notes generator - formats changes for release documentation"
            "Update-VersionNumbers.ps1" = "Version management tool - updates version numbers across project files"
            "Git-SignAllCommits.ps1" = "Git commit signer - applies cryptographic signatures to commits"
        }
        
        if ($descriptions.ContainsKey($ScriptName)) {
            return $descriptions[$ScriptName]
        }
        
        # Fallback to reading from file
        $firstFewLines = Get-Content -Path $ScriptPath -TotalCount 15 -ErrorAction SilentlyContinue
        
        foreach ($line in $firstFewLines) {
            # Look for description patterns in comments
            if ($line -match '^#\s*(.+)$' -and 
                $line -notmatch '^#\s*MixerThreholdMod' -and 
                $line -notmatch '^#\s*Excludes:' -and
                $line -notmatch '^#\s*\$' -and
                $line -notmatch '^#\s*(Master|Ultimate|Orchestrator)') {
                
                $description = $matches[1].Trim()
                
                # Enhanced description filtering
                if ($description.Length -gt 10 -and $description.Length -lt 100 -and
                    $description -notmatch '(DevOps Tool:|COMPATIBLE|VERSION)') {
                    return $description
                }
            }
        }
    }
    catch {
        # Ignore errors reading script files
    }
    
    return $null
}

# Function to handle user selection with enhanced messaging
function Process-UserSelection {
    param($Choice, $ScriptMap, $CategorizedScripts)
    
    # Handle quit
    if ($Choice -ieq "Q") {
        Write-Host "👋 Exiting MixerThreholdMod DevOps Suite..." -ForegroundColor Gray
        return $false
    }
    
    # Handle numeric selection with enhanced error handling
    try {
        $choiceNum = [int]$Choice
        
        if ($choiceNum -ge 1 -and $choiceNum -le $ScriptMap.Count -and $ScriptMap.ContainsKey($choiceNum)) {
            $selectedScript = $ScriptMap[$choiceNum]
            
            # Enhanced messaging for different script types
            if ($selectedScript.Name -eq "Generate-Corruption-Report.ps1") {
                Write-Host ""
                Write-Host "🛡️  LAUNCHING ULTIMATE CORRUPTION DETECTOR: " -NoNewline -ForegroundColor Red
                Write-Host $selectedScript.Name -ForegroundColor Yellow
                Write-Host ""
                Write-Host "🚨 This enhanced script will:" -ForegroundColor Red
                Write-Host "   • Run ALL corruption detection scanners automatically" -ForegroundColor Gray
                Write-Host "   • Validate C# syntax integrity (brackets, semicolons, strings)" -ForegroundColor Gray
                Write-Host "   • Check import/using statement corruption" -ForegroundColor Gray
                Write-Host "   • Detect merge conflicts and encoding issues" -ForegroundColor Gray
                Write-Host "   • Analyze project structure integrity" -ForegroundColor Gray
                Write-Host "   • Generate comprehensive corruption health dashboard" -ForegroundColor Gray
                Write-Host ""
                Write-Host "💡 This is the ultimate guard against ALL forms of codebase corruption!" -ForegroundColor DarkYellow
                Write-Host ""
            } elseif ($selectedScript.Name -eq "Generate-Comprehensive-Report.ps1") {
                Write-Host ""
                Write-Host "📊 LAUNCHING COMPREHENSIVE PROJECT ANALYZER: " -NoNewline -ForegroundColor DarkCyan
                Write-Host $selectedScript.Name -ForegroundColor Yellow
                Write-Host ""
                Write-Host "📋 This orchestrator will:" -ForegroundColor DarkCyan
                Write-Host "   • Run ALL DevOps analysis tools automatically" -ForegroundColor Gray
                Write-Host "   • Include COMPLETE corruption detection suite" -ForegroundColor Gray
                Write-Host "   • Generate unified project health dashboard" -ForegroundColor Gray
                Write-Host "   • Provide comprehensive quality metrics" -ForegroundColor Gray
                Write-Host "   • Create detailed reports in Reports/ directory" -ForegroundColor Gray
                Write-Host ""
                Write-Host "💡 Perfect for complete project analysis with corruption detection!" -ForegroundColor DarkYellow
                Write-Host ""
            } elseif ($selectedScript.Name -match "(SyntaxValidation|ImportVerification|NamespaceAudit|XmlDocs)") {
                Write-Host ""
                Write-Host "🆕 LAUNCHING NEW ENHANCED TOOL: " -NoNewline -ForegroundColor Green
                Write-Host $selectedScript.Name -ForegroundColor Yellow
                Write-Host ""
                Write-Host "✨ This is a newly created/enhanced DevOps tool with advanced capabilities!" -ForegroundColor Green
                Write-Host ""
            } else {
                Write-Host ""
                Write-Host "🔍 Running DevOps Tool: " -NoNewline -ForegroundColor Gray
                Write-Host $selectedScript.Name -ForegroundColor Green
                Write-Host ""
            }
            
            try {
                # Execute the script with proper error handling
                & $selectedScript.FullName
                
                if ($selectedScript.Name -match "(Corruption|Comprehensive)") {
                    Write-Host ""
                    Write-Host "✅ High-level analysis completed successfully!" -ForegroundColor Green
                    Write-Host "📄 Detailed reports saved to Reports/ directory" -ForegroundColor Cyan
                } else {
                    Write-Host ""
                    Write-Host "✅ DevOps tool completed successfully!" -ForegroundColor Green
                }
            } catch {
                Write-Host "❌ Script execution error: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "📋 Stack trace: $($_.ScriptStackTrace)" -ForegroundColor DarkYellow
            }
        } else {
            Write-Host "❌ Invalid selection: $Choice (valid range: 1-$($ScriptMap.Count), Q)" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Invalid input format: $Choice (please enter a number or Q)" -ForegroundColor Red
    }
    
    return $true
}

# Main menu loop with enhanced error handling
function Start-DevOpsMenu {
    try {
        do {
            # Get categorized scripts
            $categorizedScripts = Get-CategorizedScripts -ScriptDirectory $ScriptDir
            
            if ($categorizedScripts.Count -eq 0) {
                Write-Host "❌ No PowerShell scripts found in Scripts folder!" -ForegroundColor Red
                Write-Host "Press ENTER to exit..." -ForegroundColor Gray -NoNewline
                Read-Host
                return
            }
            
            # Show menu and get user choice
            $scriptMap = Show-CategorizedMenu -CategorizedScripts $categorizedScripts
            
            Write-Host "Select a DevOps tool (1-$($scriptMap.Count)) or Q to quit: " -NoNewline -ForegroundColor Green
            $choice = Read-Host
            
            # Skip processing if user just pressed ENTER
            if ([string]::IsNullOrWhiteSpace($choice)) {
                Write-Host "⚠️  No selection made. Please choose a DevOps tool." -ForegroundColor DarkYellow
                Start-Sleep -Seconds 1
                continue
            }
            
            # Process the selection
            $continue = Process-UserSelection -Choice $choice.Trim() -ScriptMap $scriptMap -CategorizedScripts $categorizedScripts
            
            if ($continue) {
                Write-Host ""
                Write-Host "Press ENTER to return to DevOps Suite menu..." -ForegroundColor Gray -NoNewline
                Read-Host
            }
            
        } while ($continue)
        
    } catch {
        Write-Host "💥 Unexpected error in DevOps Suite: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "📋 Stack trace: $($_.ScriptStackTrace)" -ForegroundColor DarkYellow
        Write-Host "Press ENTER to exit..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
}

# Display startup banner
Write-Host ""
Write-Host "🚀 Initializing MixerThreholdMod DevOps Suite v2.1..." -ForegroundColor DarkCyan
Write-Host "🆕 Enhanced with Syntax Validation, Import Verification & Ultimate Corruption Detection" -ForegroundColor Green
Start-Sleep -Milliseconds 750

# Start the enhanced menu system
Start-DevOpsMenu