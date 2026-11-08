param(
    [Parameter(Mandatory = $false)]
    [string]$TargetObsidianVault = "",

    [Parameter(Mandatory = $false)]
    [string]$RelayStudioDir = "",

    [Parameter(Mandatory = $false)]
    [switch]$LinkLocalCliAgents
)

$ErrorActionPreference = 'Stop'
$sourceRoot = $PSScriptRoot

Write-Host "=== AgentVault × RelayStudio 软路由配置工具 ===" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($TargetObsidianVault)) {
    $activeVault = $sourceRoot
    Write-Host "[1/3] 使用当前目录作为生效 Obsidian 仓库: $activeVault" -ForegroundColor Green
} else {
    $activeVault = [IO.Path]::GetFullPath($TargetObsidianVault)
    Write-Host "[1/3] 正在将 Agent全局配置/ 与 参考资料/ 迁入现有 Obsidian 仓库: $activeVault" -ForegroundColor Green
    [IO.Directory]::CreateDirectory($activeVault) | Out-Null

    foreach ($subDir in @('Agent全局配置', '参考资料')) {
        $srcPath = Join-Path $sourceRoot $subDir
        $dstPath = Join-Path $activeVault $subDir
        if (Test-Path -LiteralPath $srcPath) {
            [IO.Directory]::CreateDirectory($dstPath) | Out-Null
            Copy-Item -Path (Join-Path $srcPath '*') -Destination $dstPath -Recurse -Force
        }
    }
}

$rulesTarget = Join-Path $activeVault 'Agent全局配置\Global_Agent_Rules.md'
$skillsTarget = Join-Path $activeVault 'Agent全局配置\Skills'

if (-not (Test-Path -LiteralPath $rulesTarget)) {
    throw "未找到全局规则文件: $rulesTarget"
}
if (-not (Test-Path -LiteralPath $skillsTarget)) {
    throw "未找到技能目录: $skillsTarget"
}

if (-not [string]::IsNullOrWhiteSpace($RelayStudioDir)) {
    $relayRoot = [IO.Path]::GetFullPath($RelayStudioDir)
    Write-Host "[2/3] 正在将 RelayStudio ($relayRoot) 软路由指向 Obsidian 仓库..." -ForegroundColor Green

    $dataDir = Join-Path $relayRoot 'data'
    $engineDataDir = Join-Path $relayRoot 'engine-data'
    [IO.Directory]::CreateDirectory($dataDir) | Out-Null
    [IO.Directory]::CreateDirectory($engineDataDir) | Out-Null

    $settingsPath = Join-Path $dataDir 'settings.json'
    $settingsObj = @{}
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $raw = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
            $parsed = $raw | ConvertFrom-Json
            foreach ($prop in $parsed.PSObject.Properties) {
                $settingsObj[$prop.Name] = $prop.Value
            }
        } catch {}
    }
    $settingsObj['agents_md_target'] = $rulesTarget
    $settingsObj['skills_junction_target'] = $skillsTarget
    $jsonOut = $settingsObj | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($settingsPath, $jsonOut, (New-Object System.Text.UTF8Encoding($false)))

    $engineSkillsLink = Join-Path $engineDataDir 'skills'
    if (Test-Path -LiteralPath $engineSkillsLink) {
        $item = Get-Item -LiteralPath $engineSkillsLink -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c rmdir "$engineSkillsLink" | Out-Null
        } else {
            Remove-Item -LiteralPath $engineSkillsLink -Recurse -Force
        }
    }
    New-Item -ItemType Junction -Path $engineSkillsLink -Target $skillsTarget | Out-Null

    $engineAgentsMd = Join-Path $engineDataDir 'AGENTS.md'
    if (Test-Path -LiteralPath $engineAgentsMd) {
        Remove-Item -LiteralPath $engineAgentsMd -Force
    }
    try {
        New-Item -ItemType HardLink -Path $engineAgentsMd -Target $rulesTarget -ErrorAction Stop | Out-Null
    } catch {
        Copy-Item -LiteralPath $rulesTarget -Destination $engineAgentsMd -Force
    }

    Write-Host "  [OK] engine-data\skills -> $skillsTarget" -ForegroundColor Green
    Write-Host "  [OK] engine-data\AGENTS.md -> $rulesTarget" -ForegroundColor Green
} else {
    Write-Host "[2/3] 未指定 -RelayStudioDir，跳过 RelayStudio 软路由绑定。" -ForegroundColor Yellow
}

if ($LinkLocalCliAgents) {
    Write-Host "[3/3] 正在将本机 ~/.codex 与 ~/.claude 软路由指向 Obsidian 仓库..." -ForegroundColor Green
    foreach ($cliHome in @(
        (Join-Path $env:USERPROFILE '.codex'),
        (Join-Path $env:USERPROFILE '.claude')
    )) {
        [IO.Directory]::CreateDirectory($cliHome) | Out-Null
        $cliSkills = Join-Path $cliHome 'skills'
        if (-not (Test-Path -LiteralPath $cliSkills)) {
            try { New-Item -ItemType Junction -Path $cliSkills -Target $skillsTarget | Out-Null } catch {}
        }
    }
} else {
    Write-Host "[3/3] 完成！（如需同时挂载至本机 ~/.codex 与 ~/.claude，可加 -LinkLocalCliAgents 参数）" -ForegroundColor Cyan
}
