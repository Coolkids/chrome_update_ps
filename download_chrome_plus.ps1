# ���ô�����
$ErrorActionPreference = 'Stop'

# Step 1: ������ʱ�ļ���
$downloadDir = "$PSScriptRoot\Temp"
if (-Not (Test-Path -Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir | Out-Null
} else {
    Remove-Item -Path $downloadDir -Recurse -Force
}

# Step 2: ��ȡ GitHub ���� Release ��Ϣ������ User-Agent
$repoUrl = "https://api.github.com/repos/Bush2021/chrome_plus/releases/latest"
$chromeUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.5993.89 Safari/537.36"

try {
    # ʹ�� WebClient ���� UA ��ȡ Release ��Ϣ
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", $chromeUserAgent)
    $json = $webClient.DownloadString($repoUrl)
    $releaseInfo = ConvertFrom-Json $json
} catch {
    Write-Host "�޷���ȡ���µ� release ��Ϣ��" $_.Exception.Message -ForegroundColor Red
    exit
}

# Step 3: �� assets ������ֱ�ӻ�ȡ��һ���������������
$asset = $releaseInfo.assets[0]
if (-not $asset) {
    Write-Host "δ�ҵ��κο��õ� assets" -ForegroundColor Red
    exit
}

# Step 4: ��� browser_download_url �Ƿ�Ϊ���飬����ǣ���ȡ��һ��Ԫ��
$downloadUrl = if ($asset.browser_download_url -is [Array]) {
    $asset.browser_download_url[0]
} else {
    $asset.browser_download_url
}

# ȷ���������ӽ���
$downloadUrl = [System.Uri]::UnescapeDataString($downloadUrl)
$fileName = [System.Uri]::UnescapeDataString($asset.name)
$downloadPath = Join-Path -Path $downloadDir -ChildPath $fileName

Write-Host "�������� $fileName..."
try {
    # ʹ�� WebClient ���� UA �����ļ�
    $webClient.Headers.Add("User-Agent", $chromeUserAgent)
    $webClient.DownloadFile($downloadUrl, $downloadPath)
} catch {
    Write-Host "����ʧ�ܣ�" $_.Exception.Message -ForegroundColor Red
    exit
}

# Step 5: ��ѹ�� 7z �ļ�
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe" # ��ȷ�� 7z.exe �Ѱ�װ
if (-Not (Test-Path -Path $sevenZipPath)) {
    Write-Host "δ�ҵ� 7z.exe����ȷ�� 7-Zip ����ȷ��װ" -ForegroundColor Red
    exit
}

# Step 6: ��ȡ version.dll �ļ�����ʱ�ļ��У������ļ��нṹ��
Write-Host "��ѹ�� version.dll �ļ�����ʱ�ļ���..."
try {
    Start-Process -FilePath $sevenZipPath -ArgumentList "e `"$downloadPath`" `x64\App\version.dll` -o`"$downloadDir`" -aoa" -NoNewWindow -Wait
} catch {
    Write-Host "��ѹ��ʧ�ܣ�" $_.Exception.Message -ForegroundColor Red
    exit
}

# ����Ƿ�ɹ���ȡ�ļ�
$extractedFile = Join-Path -Path $downloadDir -ChildPath "version.dll"
if (Test-Path -Path $extractedFile) {
    Write-Host "�ļ���ѹ�ɹ�: $extractedFile" -ForegroundColor Green
} else {
    Write-Host "�ļ���ѹʧ��" -ForegroundColor Red
    exit
}

# Step 7: ɾ�����ص� 7z �ļ�
Write-Host "����ɾ�����ص�ѹ���ļ�..."
Remove-Item -Path $downloadPath -Force


# ���� User-Agent �� Content-Type
$chromeUpdateUserAgent = "Google Update/1.3.36.152;winhttp"
$contentType = "application/x-www-form-urlencoded"

# Step 8: ���� POST ������
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

# Step 9: ���� POST �����ȡ��������
$chromeUpdateUrl = "https://tools.google.com/service/update2"
try {
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", $chromeUpdateUserAgent)
    $webClient.Headers.Add("Content-Type", $contentType)
    $response = $webClient.UploadString($chromeUpdateUrl, $requestBody)
} catch {
    Write-Host "��ȡ Chrome ���ص�ַʧ�ܣ�" $_.Exception.Message -ForegroundColor Red
    exit
}

# Step 10: ���� XML ���ؽ��
[xml]$xmlResponse = $response

# ��ȡ���е� codebase URL
$urls = $xmlResponse.response.app.updatecheck.urls.url
$downloadUrls = $urls | ForEach-Object { $_.codebase }

$installerFileName = $xmlResponse.response.app.updatecheck.manifest.actions.action[0].run
$sha256Hash = $xmlResponse.response.app.updatecheck.manifest.packages.package.hash_sha256

# Step 11: ���� Chrome ��װ�������Զ�� URL��
$chromeDownloadPath = Join-Path -Path $downloadDir -ChildPath $installerFileName
$downloadSuccess = $false

foreach ($downloadUrl in $downloadUrls) {
    try {
        Write-Host "���ڴ� $downloadUrl ����..."
        $webClient.DownloadFile($downloadUrl + $installerFileName, $chromeDownloadPath)
        $downloadSuccess = $true
        break
    } catch {
        Write-Host "����ʧ��: $($_.Exception.Message). ������һ�� URL..." -ForegroundColor Yellow
    }
}

if (-Not $downloadSuccess) {
    Write-Host "�����������Ӿ�ʧ�ܡ�" -ForegroundColor Red
    exit
}

# Step 12: ��֤ SHA256 У����
$actualHash = Get-FileHash -Path $chromeDownloadPath -Algorithm SHA256
if ($actualHash.Hash -ne $sha256Hash) {
    Write-Host "�ļ�У��ʧ�ܣ����ص��ļ��������𻵡�" -ForegroundColor Red
    exit
} else {
    Write-Host "�ļ�У��ɹ���" -ForegroundColor Green
}

# Step 13: ��ѹ Chrome ��װ��
Write-Host "��ѹ Chrome ���߰�װ��..."
Start-Process -FilePath $sevenZipPath -ArgumentList "x `"$chromeDownloadPath`" -o`"$downloadDir`" -aoa" -NoNewWindow -Wait

# ����Ƿ��ѹ�� chrome.7z
$chrome7zPath = Join-Path -Path $downloadDir -ChildPath "chrome.7z"
if (Test-Path -Path $chrome7zPath) {
    Write-Host "��⵽ chrome.7z �ļ������ڽ�ѹ..."
    Start-Process -FilePath $sevenZipPath -ArgumentList "x `"$chrome7zPath`" -o`"$downloadDir`" -aoa" -NoNewWindow -Wait
    Remove-Item -Path $chrome7zPath -Force
} else {
    Write-Host "δ�ҵ� chrome.7z �ļ�" -ForegroundColor Red
}

# ����ѹ�������ļ����Ƿ�Ϊ Chrome-bin
$chromeBinDir = Join-Path -Path $downloadDir -ChildPath "Chrome-bin"
if (Test-Path -Path $chromeBinDir) {
    Write-Host "�ɹ���ѹ�� Chrome-bin Ŀ¼: $chromeBinDir" -ForegroundColor Green
} else {
    Write-Host "δ�ҵ� Chrome-bin �ļ���" -ForegroundColor Red
}

# Step 14: ������ʱ�ļ�
Write-Host "������ʱ�ļ�..."
Remove-Item -Path $chromeDownloadPath -Force

# Step 15: ��鲢����Ŀ¼
$appDir = "$PSScriptRoot\App"
$dataDir = "$PSScriptRoot\Data"
$cacheDir = "$PSScriptRoot\Cache"

# ���� Data �� Cache Ŀ¼����������ڣ�
if (-Not (Test-Path -Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir | Out-Null
    Write-Host "���� Data Ŀ¼" -ForegroundColor Green
}

if (-Not (Test-Path -Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir | Out-Null
    Write-Host "���� Cache Ŀ¼" -ForegroundColor Green
}

# ���� App �� App_Bak Ŀ¼
if (Test-Path -Path "$PSScriptRoot\App_Bak") {
    Remove-Item -Path "$PSScriptRoot\App_Bak" -Recurse -Force
    Write-Host "ɾ���� App_Bak Ŀ¼" -ForegroundColor Yellow
}

if (Test-Path -Path $appDir) {
    Rename-Item -Path $appDir -NewName "App_Bak"
    Write-Host "�� App Ŀ¼������Ϊ App_Bak" -ForegroundColor Yellow
}

# �½� App Ŀ¼
New-Item -ItemType Directory -Path $appDir | Out-Null
Write-Host "�½��� App Ŀ¼" -ForegroundColor Green

# Step 16: �ƶ��ļ��� App Ŀ¼
# �ƶ� Temp/Chrome-bin ����
if (Test-Path -Path $chromeBinDir) {
    Move-Item -Path "$chromeBinDir\*" -Destination $appDir -Force
    Write-Host "�� Chrome-bin �е��ļ��ƶ��� App Ŀ¼" -ForegroundColor Green
} else {
    Write-Host "Chrome-bin Ŀ¼�����ڣ��޷��ƶ��ļ�" -ForegroundColor Red
}

# �ƶ� Temp/version.dll
$versionDllPath = Join-Path -Path $downloadDir -ChildPath "version.dll"
if (Test-Path -Path $versionDllPath) {
    Move-Item -Path $versionDllPath -Destination $appDir -Force
    Write-Host "�� version.dll �ƶ��� App Ŀ¼" -ForegroundColor Green
} else {
    Write-Host "version.dll �ļ������ڣ��޷��ƶ�" -ForegroundColor Red
}

# Step 17: ɾ�� Temp Ŀ¼
Remove-Item -Path $downloadDir -Recurse -Force
Write-Host "ɾ���� Temp Ŀ¼" -ForegroundColor Green

# Step 18: ���� chrome++.ini �ļ�������Ϊ chrome++.ini
$iniUrl = "https://raw.githubusercontent.com/Bush2021/chrome_plus/refs/heads/main/src/chrome%2B%2B.ini"
$iniFilePath = Join-Path -Path $PSScriptRoot -ChildPath "App\chrome++.ini"

Write-Host "�������� chrome++.ini..."

try {
    $webClient.DownloadFile($iniUrl, $iniFilePath)
    Write-Host "���� chrome++.ini ���" -ForegroundColor Green
} catch {
    Write-Host "���� chrome++.ini ʧ�ܣ�$($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Step 19: �޸� wheel_tab �� wheel_tab_when_press_rbutton ��ֵ
Write-Host "�����޸������ļ��еĲ���..."

try {
    # ��ȡ�ļ�����
    $iniContent = Get-Content -Path $iniFilePath

    # �滻����ֵ
    $iniContent = $iniContent -replace "wheel_tab=1", "wheel_tab=0"
    $iniContent = $iniContent -replace "wheel_tab_when_press_rbutton=1", "wheel_tab_when_press_rbutton=0"

    # �����޸ĺ���ļ�
    Set-Content -Path $iniFilePath -Value $iniContent -Encoding Unicode

    Write-Host "�����ļ����޸�" -ForegroundColor Green
} catch {
    Write-Host "�޸������ļ�ʧ�ܣ�$($_.Exception.Message)" -ForegroundColor Red
}


Write-Host "������ɣ�"
