# chrome_update_ps
chrome便携版制作和更新powershell脚本

chrome和chrome++版本均使用当前已发布的最新版本, chrome使用windows x64版本

使用方法：
1. git clone 或者 下载download_chrome_plus.ps1脚本
2. 将download_chrome_plus.ps1放置在需要制作便携版chrome的目录内
3. 在此目录内打开powershell，执行下面的命令即可
```{powershell}
powershell -ExecutionPolicy Bypass -File .\download_chrome_plus.ps1
```

