# MixerThreholdMod DevOps Tool: XML Documentation Generator (NON-INTERACTIVE)
# Generates comprehensive XML documentation for all public APIs
# Creates structured XML output with code examples and usage patterns
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

Write-Host "🕐 XML documentation generation started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Generating XML documentation for: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green
Write-Host "Excluding: ForCopilot, Scripts, and Legacy directories" -ForegroundColor DarkGray

# Function to extract public members and generate XML documentation
function Get-PublicMembersForXmlDocs {
    param([string]$Path)
    
    try {
        $files = Get-ChildItem -Path $Path -Recurse -Include *.cs -ErrorAction SilentlyContinue | Where-Object {
            $_.PSIsContainer -eq $false -and
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
            $_.FullName -notmatch "[\\/]\.git[\\/]"
        }
        
        $members = @()
        
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                if (-not $content -or $content.Length -lt 100) { continue }
                
                $lines = Get-Content -Path $file.FullName -ErrorAction Stop
                
                # Extract namespace
                $namespace = "Unknown"
                if ($content -match 'namespace\s+([A-Za-z0-9_.]+)') {
                    $namespace = $matches[1]
                }
                
                # Simplified patterns for public members
                $patterns = @{
                    'Class' = '(?m)^\s*public\s+(?:static\s+|abstract\s+|sealed\s+)*class\s+([A-Za-z0-9_<>]+)'
                    'Method' = '(?m)^\s*public\s+(?:static\s+|virtual\s+|override\s+|async\s+)*(?:Task<[^>]+>|Task|void|[A-Za-z0-9_<>\[\]]+)\s+([A-Za-z0-9_]+)\s*\([^)]*\)'
                    'Property' = '(?m)^\s*public\s+(?:static\s+)*([A-Za-z0-9_<>\[\]]+)\s+([A-Za-z0-9_]+)\s*\{\s*(?:get|set)'
                    'Field' = '(?m)^\s*public\s+(?:static\s+|readonly\s+)*([A-Za-z0-9_<>\[\]]+)\s+([A-Za-z0-9_]+)\s*(?:=|;)'
                }
                
                foreach ($type in $patterns.Keys) {
                    $matches = [regex]::Matches($content, $patterns[$type], [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    
                    foreach ($match in $matches) {
                        $memberName = if ($type -eq 'Class') { $match.Groups[1].Value } else { $match.Groups[2].Value }
                        $memberType = if ($type -eq 'Class') { "" } else { $match.Groups[1].Value }
                        $lineNumber = ($content.Substring(0, $match.Index) -split "``n").Count
                        
                        # Skip auto-generated and common members
                        if ($memberName -match '^(get_|set_|add_|remove_)' -or 
                            $memberName -eq 'ToString' -or 
                            $memberName -eq 'GetHashCode' -or 
                            $memberName -eq 'Equals') {
                            continue
                        }
                        
                        # Extract existing documentation
                        $existingDoc = ""
                        $startLine = [Math]::Max(0, $lineNumber - 10)
                        for ($i = $lineNumber - 2; $i -ge $startLine; $i--) {
                            if ($i -ge 0 -and $i -lt $lines.Count) {
                                if ($lines[$i] -match '^\s*///\s*(.*)') {
                                    $docLine = $matches[1].Trim()
                                    if ($docLine -notmatch '^</?summary>|^</?param|^</?returns') {
                                        $existingDoc = $docLine + " " + $existingDoc
                                    }
                                } elseif ($lines[$i] -match '^\s*$' -or $lines[$i] -match '^\s*\[') {
                                    continue
                                } else {
                                    break
                                }
                            }
                        }
                        
                        $members += [PSCustomObject]@{
                            File = $file.FullName
                            FileName = $file.Name
                            Namespace = $namespace
                            Type = $type
                            Name = $memberName
                            MemberType = $memberType
                            LineNumber = $lineNumber
                            ExistingDoc = $existingDoc.Trim()
                            FullDeclaration = $match.Value.Trim()
                        }
                    }
                }
            }
            catch {
                Write-Host "⚠️  Error processing $($file.Name): $_" -ForegroundColor DarkYellow
                continue
            }
        }
        
        return $members
    }
    catch {
        Write-Host "⚠️  Error scanning for members: $_" -ForegroundColor DarkYellow
        return @()
    }
}

# Function to generate XML documentation template
function New-XmlDocTemplate {
    param($Member)
    
    $xmlDoc = @()
    
    switch ($Member.Type) {
        'Class' {
            $xmlDoc += "/// <summary>"
            if ($Member.ExistingDoc) {
                $xmlDoc += "/// $($Member.ExistingDoc)"
            } else {
                $xmlDoc += "/// Provides functionality for [describe purpose]."
            }
            $xmlDoc += "/// </summary>"
            $xmlDoc += "/// <remarks>"
            $xmlDoc += "/// Thread Safety: [Specify thread safety requirements]"
            $xmlDoc += "/// .NET 4.8.1 Compatibility: [Note any specific requirements]"
            $xmlDoc += "/// Unity Integration: [Describe Unity main thread considerations]"
            $xmlDoc += "/// </remarks>"
        }
        'Method' {
            $xmlDoc += "/// <summary>"
            if ($Member.ExistingDoc) {
                $xmlDoc += "/// $($Member.ExistingDoc)"
            } else {
                $xmlDoc += "/// [Describe what this method does]"
            }
            $xmlDoc += "/// </summary>"
            
            # Extract parameters from method declaration
            if ($Member.FullDeclaration -match '\(([^)]*)\)') {
                $params = $matches[1]
                if ($params.Trim()) {
                    $paramList = $params -split ',' | ForEach-Object { $_.Trim() }
                    foreach ($param in $paramList) {
                        if ($param -match '(\w+)\s+(\w+)(?:\s*=.*)?$') {
                            $paramName = $matches[2]
                            # FIXED: Use double backticks for proper escaping
                            $xmlDoc += "/// <param name=````$paramName````>[Describe parameter purpose]</param>"
                        }
                    }
                }
            }
            
            # Add return documentation if not void
            if ($Member.FullDeclaration -notmatch '\s+void\s+') {
                $xmlDoc += "/// <returns>[Describe return value]</returns>"
            }
            
            $xmlDoc += "/// <remarks>"
            $xmlDoc += "/// Thread Safety: [Safe/Unsafe - specify requirements]"
            $xmlDoc += "/// Performance: [Any performance considerations]"
            $xmlDoc += "/// </remarks>"
        }
        'Property' {
            $xmlDoc += "/// <summary>"
            if ($Member.ExistingDoc) {
                $xmlDoc += "/// $($Member.ExistingDoc)"
            } else {
                $xmlDoc += "/// Gets or sets [describe property purpose]."
            }
            $xmlDoc += "/// </summary>"
            $xmlDoc += "/// <value>[Describe the property value and constraints]</value>"
        }
        'Field' {
            $xmlDoc += "/// <summary>"
            if ($Member.ExistingDoc) {
                $xmlDoc += "/// $($Member.ExistingDoc)"
            } else {
                $xmlDoc += "/// [Describe field purpose and usage]."
            }
            $xmlDoc += "/// </summary>"
        }
    }
    
    return $xmlDoc
}

Write-Host "``n📂 Scanning for public members..." -ForegroundColor DarkGray
$members = Get-PublicMembersForXmlDocs -Path $ProjectRoot

Write-Host "📊 Found $($members.Count) public members for documentation" -ForegroundColor Gray

if ($members.Count -eq 0) {
    Write-Host "⚠️  No public members found for XML documentation" -ForegroundColor DarkYellow
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "``nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

# Generate XML documentation
$xmlContent = @()

# XML Header with proper escaping
$xmlContent += "<?xml version=````1.0```` encoding=````utf-8````?>"
$xmlContent += "<doc>"
$xmlContent += "  <assembly>"
$xmlContent += "    <name>MixerThreholdMod</name>"
$xmlContent += "  </assembly>"
$xmlContent += "  <members>"
$xmlContent += ""

# Group by namespace and file
$namespaceGroups = $members | Group-Object Namespace | Sort-Object Name

foreach ($nsGroup in $namespaceGroups) {
    $xmlContent += "    <!-- Namespace: $($nsGroup.Name) -->"
    
    $fileGroups = $nsGroup.Group | Group-Object FileName | Sort-Object Name
    
    foreach ($fileGroup in $fileGroups) {
        $xmlContent += "    <!-- File: $($fileGroup.Name) -->"
        
        # Sort by type priority (Class first, then others)
        $sortedMembers = $fileGroup.Group | Sort-Object @{
            Expression = {
                switch ($_.Type) {
                    'Class' { 1 }
                    'Method' { 2 }
                    'Property' { 3 }
                    'Field' { 4 }
                    default { 5 }
                }
            }
        }, Name
        
        foreach ($member in $sortedMembers) {
            # Generate member name for XML
            $memberXmlName = switch ($member.Type) {
                'Class' { "T:$($member.Namespace).$($member.Name)" }
                'Method' { "M:$($member.Namespace).[ClassName].$($member.Name)" }
                'Property' { "P:$($member.Namespace).[ClassName].$($member.Name)" }
                'Field' { "F:$($member.Namespace).[ClassName].$($member.Name)" }
            }
            
            $xmlContent += "    <member name=````$memberXmlName````>"
            
            # Generate XML documentation template
            $xmlTemplate = New-XmlDocTemplate -Member $member
            foreach ($line in $xmlTemplate) {
                $xmlContent += "      $line"
            }
            
            $xmlContent += "    </member>"
            $xmlContent += ""
        }
    } # FIXED: Added missing closing brace for fileGroup loop
} # FIXED: Added missing closing brace for nsGroup loop

$xmlContent += "  </members>"
$xmlContent += "</doc>"

# Save XML documentation
$outputPath = Join-Path $ProjectRoot "MixerThreholdMod-API-Documentation.xml"

try {
    $xmlContent | Out-File -FilePath $outputPath -Encoding UTF8
    $savedSuccessfully = $true
}
catch {
    Write-Host "⚠️  Error saving XML documentation: $_" -ForegroundColor DarkYellow
    $savedSuccessfully = $false
}

# Generate markdown documentation as well
$markdownContent = @()
$markdownContent += "# MixerThreholdMod API Documentation"
$markdownContent += ""
$markdownContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$markdownContent += "**Public Members**: $($members.Count)"
$markdownContent += "**Namespaces**: $(($members | Select-Object -ExpandProperty Namespace -Unique).Count)"
$markdownContent += ""

$markdownContent += "## Table of Contents"
$markdownContent += ""

foreach ($nsGroup in $namespaceGroups) {
    $markdownContent += "- [$($nsGroup.Name)](#$(($nsGroup.Name -replace '\.', '').ToLower()))"
}

$markdownContent += ""

# Generate markdown sections
foreach ($nsGroup in $namespaceGroups) {
    $markdownContent += "## $($nsGroup.Name)"
    $markdownContent += ""
    
    $fileGroups = $nsGroup.Group | Group-Object FileName | Sort-Object Name
    
    foreach ($fileGroup in $fileGroups) {
        $markdownContent += "### $($fileGroup.Name)"
        $markdownContent += ""
        
        $typeGroups = $fileGroup.Group | Group-Object Type | Sort-Object @{
            Expression = {
                switch ($_.Name) {
                    'Class' { 1 }
                    'Method' { 2 }
                    'Property' { 3 }
                    'Field' { 4 }
                    default { 5 }
                }
            }
        }
        
        foreach ($typeGroup in $typeGroups) {
            $markdownContent += "#### $($typeGroup.Name)s"
            $markdownContent += ""
            
            foreach ($member in $typeGroup.Group | Sort-Object Name) {
                $markdownContent += "##### $($member.Name)"
                $markdownContent += ""
                $markdownContent += "**Type**: $($member.MemberType)"
                $markdownContent += "**Line**: $($member.LineNumber)"
                $markdownContent += ""
                
                if ($member.ExistingDoc) {
                    $markdownContent += "**Description**: $($member.ExistingDoc)"
                } else {
                    $markdownContent += "**Description**: *Documentation needed*"
                }
                $markdownContent += ""
                
                $markdownContent += "````````csharp"
                $markdownContent += $member.FullDeclaration
                $markdownContent += "````````"
                $markdownContent += ""
            }
        } # FIXED: Added missing closing brace for typeGroup loop
    } # FIXED: Added missing closing brace for fileGroup loop in markdown section
} # FIXED: Added missing closing brace for nsGroup loop in markdown section

# FIXED: Split problematic path assignment to avoid string termination issues
$markdownFileName = "MixerThreholdMod-API-Documentation.md"
$markdownPath = Join-Path $ProjectRoot $markdownFileName

try {
    $markdownContent | Out-File -FilePath $markdownPath -Encoding UTF8
    $markdownSaved = $true
}
catch {
    Write-Host "⚠️  Error saving markdown documentation: $_" -ForegroundColor DarkYellow
    $markdownSaved = $false
}

Write-Host "``n=== XML DOCUMENTATION GENERATION REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Generation completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

if ($savedSuccessfully) {
    Write-Host "✅ XML documentation generated successfully!" -ForegroundColor Green
    Write-Host "📄 XML documentation saved to: $outputPath" -ForegroundColor Cyan
} else {
    Write-Host "❌ Failed to save XML documentation" -ForegroundColor Red
}

if ($markdownSaved) {
    Write-Host "📄 Markdown documentation saved to: $markdownPath" -ForegroundColor Cyan
}

Write-Host "📊 Generated documentation for $($members.Count) public members" -ForegroundColor Gray

# Summary statistics
$typeStats = $members | Group-Object Type | Sort-Object Count -Descending
Write-Host "``n📋 Documentation Coverage:" -ForegroundColor DarkCyan
foreach ($typeStat in $typeStats) {
    Write-Host "   $($typeStat.Name): $($typeStat.Count) members" -ForegroundColor Gray
}

$documented = $members | Where-Object { $_.ExistingDoc }
$needsDoc = $members | Where-Object { -not $_.ExistingDoc }

Write-Host "``n💡 Documentation Status:" -ForegroundColor DarkCyan
Write-Host "   Already documented: $($documented.Count)" -ForegroundColor Green
Write-Host "   Needs documentation: $($needsDoc.Count)" -ForegroundColor $(if ($needsDoc.Count -eq 0) { "Green" } else { "DarkYellow" })

Write-Host "``n🚀 XML documentation generation complete!" -ForegroundColor Green

# INTERACTIVE WORKFLOW LOOP (only when running standalone)
if ($IsInteractive -and -not $RunningFromScript) {
    do {
        Write-Host "``n🎯 What would you like to do next?" -ForegroundColor DarkCyan
        Write-Host "   D - Display generated XML documentation structure" -ForegroundColor Green
        Write-Host "   R - Re-run XML documentation generation" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "``nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($savedSuccessfully) {
                    Write-Host "``n📋 DISPLAYING XML DOCUMENTATION STRUCTURE:" -ForegroundColor DarkCyan
                    Write-Host "=========================================" -ForegroundColor DarkCyan
                    try {
                        $xmlDisplay = Get-Content -Path $outputPath -TotalCount 50
                        $xmlDisplay | ForEach-Object { Write-Host $_ -ForegroundColor White }
                        Write-Host "``n... (showing first 50 lines)" -ForegroundColor DarkGray
                        Write-Host "``n=========================================" -ForegroundColor DarkCyan
                        Write-Host "📋 XML DOCUMENTATION STRUCTURE" -ForegroundColor DarkCyan
                    }
                    catch {
                        Write-Host "❌ Could not display XML documentation: $_" -ForegroundColor Red
                    }
                } else {
                    Write-Host "❌ No XML documentation available to display" -ForegroundColor Red
                }
            }
            'R' {
                Write-Host "``n🔄 RE-RUNNING XML DOCUMENTATION GENERATION..." -ForegroundColor DarkYellow
                Write-Host "===========================================" -ForegroundColor DarkYellow
                & $MyInvocation.MyCommand.Path
                return
            }
            'X' {
                Write-Host "``n👋 Returning to DevOps menu..." -ForegroundColor Gray
                return
            }
            default {
                Write-Host "❌ Invalid choice. Please enter D, R, or X." -ForegroundColor Red
            }
        }
    } while ($choice -notin @('X'))
} else {
    # FIXED: Proper string termination with double backticks
    Write-Host "📄 Script completed - returning to caller" -ForegroundColor DarkGray
}