# 设置错误处理
$ErrorActionPreference = 'Stop'

# Step 1: 创建临时文件夹
$downloadDir = "$PSScriptRoot\Temp"
if (-Not (Test-Path -Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir | Out-Null
} else {
    Remove-Item -Path $downloadDir -Recurse -Force
}

# Step 2: 获取 GitHub 最新 Release 信息，设置 User-Agent
$repoUrl = "https://api.github.com/repos/Bush2021/chrome_plus/releases/latest"
$chromeUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.5993.89 Safari/537.36"

try {
    # 使用 WebClient 设置 UA 获取 Release 信息
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", $chromeUserAgent)
    $json = $webClient.DownloadString($repoUrl)
    $releaseInfo = ConvertFrom-Json $json
} catch {
    Write-Host "无法获取最新的 release 信息：" $_.Exception.Message -ForegroundColor Red
    exit
}

# Step 3: 从 assets 对象中直接获取第一个对象的下载链接
$asset = $releaseInfo.assets[0]
if (-not $asset) {
    Write-Host "未找到任何可用的 assets" -ForegroundColor Red
    exit
}

# Step 4: 检查 browser_download_url 是否为数组，如果是，则取第一个元素
$downloadUrl = if ($asset.browser_download_url -is [Array]) {
    $asset.browser_download_url[0]
} else {
    $asset.browser_download_url
}

# 确保下载链接解码
$downloadUrl = [System.Uri]::UnescapeDataString($downloadUrl)
$fileName = [System.Uri]::UnescapeDataString($asset.name)
$downloadPath = Join-Path -Path $downloadDir -ChildPath $fileName

Write-Host "正在下载 $fileName..."
try {
    # 使用 WebClient 设置 UA 下载文件
    $webClient.Headers.Add("User-Agent", $chromeUserAgent)
    $webClient.DownloadFile($downloadUrl, $downloadPath)
} catch {
    Write-Host "下载失败：" $_.Exception.Message -ForegroundColor Red
    exit
}

# Step 5: 解压缩 7z 文件
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe" # 请确保 7z.exe 已安装
if (-Not (Test-Path -Path $sevenZipPath)) {
    Write-Host "未找到 7z.exe，请确保 7-Zip 已正确安装" -ForegroundColor Red
    exit
}

# Step 6: 提取 version.dll 文件到临时文件夹（忽略文件夹结构）
Write-Host "解压缩 version.dll 文件到临时文件夹..."
try {
    Start-Process -FilePath $sevenZipPath -ArgumentList "e `"$downloadPath`" `x64\App\version.dll` -o`"$downloadDir`" -aoa" -NoNewWindow -Wait
} catch {
    Write-Host "解压缩失败：" $_.Exception.Message -ForegroundColor Red
    exit
}

# 检查是否成功提取文件
$extractedFile = Join-Path -Path $downloadDir -ChildPath "version.dll"
if (Test-Path -Path $extractedFile) {
    Write-Host "文件解压成功: $extractedFile" -ForegroundColor Green
} else {
    Write-Host "文件解压失败" -ForegroundColor Red
    exit
}

# Step 7: 删除下载的 7z 文件
Write-Host "正在删除下载的压缩文件..."
Remove-Item -Path $downloadPath -Force


# 设置 User-Agent 和 Content-Type
$chromeUpdateUserAgent = "Google Update/1.3.36.152;winhttp"
$contentType = "application/x-www-form-urlencoded"

# Step 8: 构建 POST 请求体
$requestBody = @"
<?xml version="1.0" encoding="UTF-8"?>
<request protocol="3.0" updater="Omaha" updaterversion="1.3.36.152" shell_version="1.3.36.151" ismachine="0" sessionid="{11111111-1111-1111-1111-111111111111}" installsource="taggedmi" requestid="{11111111-1111-1111-1111-111111111111}" dedup="cr" domainjoined="0">
  <hw physmemory="16" sse="1" sse2="1" sse3="1" ssse3="1" sse41="1" sse42="1" avx="1"/>
  <os platform="win" version="10.0.22621.1028" sp="" arch="x64"/>
  <app appid="{8A69D345-D564-463C-AFF1-A69D9E530F96}" version="" nextversion="" ap="x64-stable-statsdef_1" lang="de" brand="" client="" installage="-1" installdate="-1" iid="{11111111-1111-1111-1111-111111111111}">
    <updatecheck/>
    <data name="install" index="empty"/>
  </app>
</request>
"@

# Step 9: 发送 POST 请求获取下载链接
$chromeUpdateUrl = "https://tools.google.com/service/update2"
try {
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", $chromeUpdateUserAgent)
    $webClient.Headers.Add("Content-Type", $contentType)
    $response = $webClient.UploadString($chromeUpdateUrl, $requestBody)
} catch {
    Write-Host "获取 Chrome 下载地址失败：" $_.Exception.Message -ForegroundColor Red
    exit
}

# Step 10: 解析 XML 返回结果
[xml]$xmlResponse = $response

# 提取所有的 codebase URL
$urls = $xmlResponse.response.app.updatecheck.urls.url
$downloadUrls = $urls | ForEach-Object { $_.codebase }

$installerFileName = $xmlResponse.response.app.updatecheck.manifest.actions.action[0].run
$sha256Hash = $xmlResponse.response.app.updatecheck.manifest.packages.package.hash_sha256

# Step 11: 下载 Chrome 安装包（尝试多个 URL）
$chromeDownloadPath = Join-Path -Path $downloadDir -ChildPath $installerFileName
$downloadSuccess = $false

foreach ($downloadUrl in $downloadUrls) {
    try {
        Write-Host "正在从 $downloadUrl 下载..."
        $webClient.DownloadFile($downloadUrl + $installerFileName, $chromeDownloadPath)
        $downloadSuccess = $true
        break
    } catch {
        Write-Host "下载失败: $($_.Exception.Message). 尝试下一个 URL..." -ForegroundColor Yellow
    }
}

if (-Not $downloadSuccess) {
    Write-Host "所有下载链接均失败。" -ForegroundColor Red
    exit
}

# Step 12: 验证 SHA256 校验码
$actualHash = Get-FileHash -Path $chromeDownloadPath -Algorithm SHA256
if ($actualHash.Hash -ne $sha256Hash) {
    Write-Host "文件校验失败！下载的文件可能已损坏。" -ForegroundColor Red
    exit
} else {
    Write-Host "文件校验成功。" -ForegroundColor Green
}

# Step 13: 解压 Chrome 安装包
Write-Host "解压 Chrome 离线安装包..."
Start-Process -FilePath $sevenZipPath -ArgumentList "x `"$chromeDownloadPath`" -o`"$downloadDir`" -aoa" -NoNewWindow -Wait

# 检查是否解压出 chrome.7z
$chrome7zPath = Join-Path -Path $downloadDir -ChildPath "chrome.7z"
if (Test-Path -Path $chrome7zPath) {
    Write-Host "检测到 chrome.7z 文件，正在解压..."
    Start-Process -FilePath $sevenZipPath -ArgumentList "x `"$chrome7zPath`" -o`"$downloadDir`" -aoa" -NoNewWindow -Wait
    Remove-Item -Path $chrome7zPath -Force
} else {
    Write-Host "未找到 chrome.7z 文件" -ForegroundColor Red
}

# 检查解压出来的文件夹是否为 Chrome-bin
$chromeBinDir = Join-Path -Path $downloadDir -ChildPath "Chrome-bin"
if (Test-Path -Path $chromeBinDir) {
    Write-Host "成功解压到 Chrome-bin 目录: $chromeBinDir" -ForegroundColor Green
} else {
    Write-Host "未找到 Chrome-bin 文件夹" -ForegroundColor Red
}

# Step 14: 清理临时文件
Write-Host "清理临时文件..."
Remove-Item -Path $chromeDownloadPath -Force

# Step 15: 检查并处理目录
$appDir = "$PSScriptRoot\App"
$dataDir = "$PSScriptRoot\Data"
$cacheDir = "$PSScriptRoot\Cache"

# 创建 Data 和 Cache 目录（如果不存在）
if (-Not (Test-Path -Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir | Out-Null
    Write-Host "创建 Data 目录" -ForegroundColor Green
}

if (-Not (Test-Path -Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir | Out-Null
    Write-Host "创建 Cache 目录" -ForegroundColor Green
}

# 处理 App 和 App_Bak 目录
if (Test-Path -Path "$PSScriptRoot\App_Bak") {
    Remove-Item -Path "$PSScriptRoot\App_Bak" -Recurse -Force
    Write-Host "删除了 App_Bak 目录" -ForegroundColor Yellow
}

if (Test-Path -Path $appDir) {
    Rename-Item -Path $appDir -NewName "App_Bak"
    Write-Host "将 App 目录重命名为 App_Bak" -ForegroundColor Yellow
}

# 新建 App 目录
New-Item -ItemType Directory -Path $appDir | Out-Null
Write-Host "新建了 App 目录" -ForegroundColor Green

# Step 16: 移动文件到 App 目录
# 移动 Temp/Chrome-bin 内容
if (Test-Path -Path $chromeBinDir) {
    Move-Item -Path "$chromeBinDir\*" -Destination $appDir -Force
    Write-Host "将 Chrome-bin 中的文件移动到 App 目录" -ForegroundColor Green
} else {
    Write-Host "Chrome-bin 目录不存在，无法移动文件" -ForegroundColor Red
}

# 移动 Temp/version.dll
$versionDllPath = Join-Path -Path $downloadDir -ChildPath "version.dll"
if (Test-Path -Path $versionDllPath) {
    Move-Item -Path $versionDllPath -Destination $appDir -Force
    Write-Host "将 version.dll 移动到 App 目录" -ForegroundColor Green
} else {
    Write-Host "version.dll 文件不存在，无法移动" -ForegroundColor Red
}

# Step 17: 删除 Temp 目录
Remove-Item -Path $downloadDir -Recurse -Force
Write-Host "删除了 Temp 目录" -ForegroundColor Green

# Step 18: 下载 chrome++.ini 文件并保存为 chrome++.ini
$iniUrl = "https://raw.githubusercontent.com/Bush2021/chrome_plus/refs/heads/main/src/chrome%2B%2B.ini"
$iniFilePath = Join-Path -Path $PSScriptRoot -ChildPath "App\chrome++.ini"

Write-Host "正在下载 chrome++.ini..."

try {
    $webClient.DownloadFile($iniUrl, $iniFilePath)
    Write-Host "下载 chrome++.ini 完成" -ForegroundColor Green
} catch {
    Write-Host "下载 chrome++.ini 失败：$($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Step 19: 修改 wheel_tab 和 wheel_tab_when_press_rbutton 的值
Write-Host "正在修改配置文件中的参数..."

try {
    # 读取文件内容
    $iniContent = Get-Content -Path $iniFilePath

    # 替换配置值
    $iniContent = $iniContent -replace "wheel_tab=1", "wheel_tab=0"
    $iniContent = $iniContent -replace "wheel_tab_when_press_rbutton=1", "wheel_tab_when_press_rbutton=0"

    # 保存修改后的文件
    Set-Content -Path $iniFilePath -Value $iniContent -Encoding Unicode

    Write-Host "配置文件已修改" -ForegroundColor Green
} catch {
    Write-Host "修改配置文件失败：$($_.Exception.Message)" -ForegroundColor Red
}


Write-Host "操作完成！"
