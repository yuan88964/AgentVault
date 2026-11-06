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

# 1. 确定生效的 Obsidian 仓库根目录（若指定了 -TargetObsidianVault，则先将规则与技能迁入该现有 Obsidian 仓库）
if ([string]::IsNullOrWhiteSpace($TargetObsidianVault)) {
    $activeVault = $sourceRoot
    Write-Host "[1/3] 使用当前目录作为生效 Obsidian 仓库: $activeVault" -ForegroundColor Green
} else {
    $activeVault = [IO.Path]::GetFullPath($TargetObsidianVault)
    if (-not (Test-Path -LiteralPath $activeVault)) {
        [IO.Directory]::CreateDirectory($activeVault) | Out-Null
    }
    Write-Host "[1/3] 正在将全局规则与 16 项深模块技能配置到你的本地 Obsidian 仓库: $activeVault" -ForegroundColor Green
    foreach ($subDir in @('Agent全局配置', 'Skills', '参考资料', '维护')) {
        $srcSub = Join-Path $sourceRoot $subDir
        $dstSub = Join-Path $activeVault $subDir
        if (Test-Path -LiteralPath $srcSub) {
            [IO.Directory]::CreateDirectory($dstSub) | Out-Null
            Copy-Item -Path (Join-Path $srcSub '*') -Destination $dstSub -Recurse -Force
        }
    }
}

$agentsMdTarget = Join-Path $activeVault 'Agent全局配置\Global_Agent_Rules.md'
$skillsTarget = Join-Path $activeVault 'Skills'

if (-not (Test-Path -LiteralPath $agentsMdTarget)) {
    throw "未找到全局规则文件: $agentsMdTarget"
}
if (-not (Test-Path -LiteralPath $skillsTarget)) {
    throw "未找到技能目录: $skillsTarget"
}

# 2. 自动定位或配置 RelayStudio 软路由
if ([string]::IsNullOrWhiteSpace($RelayStudioDir)) {
    foreach ($cand in @(
        (Join-Path (Split-Path $sourceRoot -Parent) 'RelayStudio'),
        'D:\tool\RelayStudio',
        'C:\RelayStudio'
    )) {
        if ($cand -and (Test-Path -LiteralPath (Join-Path $cand 'McpReadOnlyShield.py'))) {
            $RelayStudioDir = $cand
            break
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($RelayStudioDir) -and (Test-Path -LiteralPath $RelayStudioDir)) {
    $RelayStudioDir = [IO.Path]::GetFullPath($RelayStudioDir)
    Write-Host "[2/3] 正在将 RelayStudio ($RelayStudioDir) 软路由指向 Obsidian 仓库..." -ForegroundColor Green

    $dataDir = Join-Path $RelayStudioDir 'data'
    $engineDir = Join-Path $RelayStudioDir 'engine-data'
    [IO.Directory]::CreateDirectory($dataDir) | Out-Null
    [IO.Directory]::CreateDirectory($engineDir) | Out-Null

    # 更新 data/settings.json（非破坏性合并）
    $settingsPath = Join-Path $dataDir 'settings.json'
    $settingsObj = [ordered]@{ schema_version = 1 }
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $rawJson = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $rawJson.PSObject.Properties) {
                $settingsObj[$prop.Name] = $prop.Value
            }
        } catch {}
    }
    $settingsObj['skills_junction_target'] = $skillsTarget
    $settingsObj['agents_md_target'] = $agentsMdTarget
    $jsonOut = $settingsObj | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($settingsPath, $jsonOut, (New-Object Text.UTF8Encoding($false)))

    # 建立 engine-data/skills -> <Vault>/Skills NTFS Junction
    $engineSkills = Join-Path $engineDir 'skills'
    if (Test-Path -LiteralPath $engineSkills) {
        $item = Get-Item -LiteralPath $engineSkills -Force
        if ($item.LinkType -eq 'Junction') {
            cmd.exe /c rmdir "$engineSkills" | Out-Null
        } else {
            Remove-Item -LiteralPath $engineSkills -Recurse -Force
        }
    }
    New-Item -ItemType Junction -Path $engineSkills -Target $skillsTarget | Out-Null

    # 建立 engine-data/AGENTS.md -> <Vault>/Agent全局配置/Global_Agent_Rules.md 硬链接（跨盘自动回退为复制）
    $engineAgents = Join-Path $engineDir 'AGENTS.md'
    if (Test-Path -LiteralPath $engineAgents) {
        Remove-Item -LiteralPath $engineAgents -Force
    }
    try {
        New-Item -ItemType HardLink -Path $engineAgents -Target $agentsMdTarget -ErrorAction Stop | Out-Null
        Write-Host "  + 已建立硬链接: $engineAgents -> $agentsMdTarget" -ForegroundColor Gray
    } catch {
        Copy-Item -LiteralPath $agentsMdTarget -Destination $engineAgents -Force
        Write-Host "  + 跨盘已同步全局规则（且 settings.json 已直连原路径）: $agentsMdTarget" -ForegroundColor Gray
    }
    Write-Host "  + 已建立 NTFS 软链接: $engineSkills -> $skillsTarget" -ForegroundColor Gray
} else {
    Write-Host "[2/3] 未指定或未检测到 RelayStudio 目录；稍后可加 -RelayStudioDir `"D:\path\to\RelayStudio`" 重新运行完成绑定。" -ForegroundColor Yellow
}

# 3. 可选：同步软路由至本机 Codex / Claude CLI
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
