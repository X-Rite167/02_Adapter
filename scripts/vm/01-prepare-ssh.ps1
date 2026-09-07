# 准备 SSH 免密密钥（一次性）
# 用法：.\scripts\vm\01-prepare-ssh.ps1
# 产出：~/.ssh/id_ed25519_02adapter（公钥打印在最后）
# 手动步骤：把打印出的公钥内容追加到虚拟机的 ~/.ssh/authorized_keys（ssh-copy-id 或手工）

param(
    [string]$KeyFile = "$env:USERPROFILE\.ssh\id_ed25519_02adapter"
)

$ErrorActionPreference = "Continue"
if (Test-Path $KeyFile) {
    Write-Host "密钥已存在，直接输出公钥："
    Get-Content "$KeyFile.pub"
} else {
    & ssh-keygen -t ed25519 -f $KeyFile -N '' -C '02adapter-deploy' | Out-Null
    Write-Host "已生成密钥对。公钥如下（复制到虚拟机 ~/.ssh/authorized_keys）："
    Write-Host "================="
    Get-Content "$KeyFile.pub"
    Write-Host "================="
}
Write-Host ""
# 若 .env 已填虚拟机信息，直接生成可执行命令
$envFile = Join-Path $PSScriptRoot "..\..\.env"
$VmHost = ""; $VmUser = ""; $VmPort = 22
if (Test-Path $envFile) {
    Get-Content $envFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $i = $line.IndexOf("=")
            $k = $line.Substring(0, $i).Trim(); $v = $line.Substring($i + 1).Trim()
            if ($k -eq "VM_HOST") { $VmHost = $v }
            if ($k -eq "VM_USER") { $VmUser = $v }
            if ($k -eq "VM_PORT" -and $v) { $VmPort = $v }
        }
    }
}
if ($VmHost -and $VmUser) {
    Write-Host "检测到 .env 虚拟机信息，直接在 PowerShell 执行以下命令完成公钥安装："
    Write-Host "  type $KeyFile.pub | ssh -p $VmPort $VmUser@$VmHost `"mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys`""
} else {
    Write-Host "若虚拟机上已装 ssh-copy-id（或用 Windows OpenSSH 的手动方式）："
    Write-Host "  type $KeyFile.pub | ssh -p <端口> <用户>@<IP> `"mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys`""
}
Write-Host "（该命令会提示输入虚拟机密码——请你自己在终端输入，不要发给任何人）"
