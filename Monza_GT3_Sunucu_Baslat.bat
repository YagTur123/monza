@echo off
chcp 65001 >nul
setlocal EnableExtensions
title Monza GT3 Otomatik LAN Sunucu Kurucu
set "SELF=%~f0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[System.IO.File]::ReadAllText($env:SELF,[System.Text.Encoding]::UTF8);$m='<#PS_'+'START#>';$i=$t.IndexOf($m);if($i -lt 0){exit 1};$f=[System.IO.Path]::Combine($env:TEMP,'monza_gt3_setup.ps1');[System.IO.File]::WriteAllText($f,$t.Substring($i+$m.Length),[System.Text.Encoding]::UTF8);& $f;$ec=$LASTEXITCODE;Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue;exit $ec"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo [BILGI] Islem sonlandi ^(Kod: %EXIT_CODE%^).
)
pause
exit /b %EXIT_CODE%

<#PS_START#>
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "SilentlyContinue"

function Write-Header {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "       MONZA GT3 - OTOMATIK LAN SUNUCU KURUCU (SIM KAFE)    " -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
}

function Test-AcDir {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $clean = $Path.Trim().Trim('"')
    return (Test-Path (Join-Path $clean "content\cars")) -and (Test-Path (Join-Path $clean "content\tracks"))
}

function Find-AssettoCorsa {
    # 1. Calisan sureclerden kontrol
    $procNames = @("acs", "acs_x86", "Content Manager", "acServer")
    foreach ($pn in $procNames) {
        $procs = Get-Process -Name $pn -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            try {
                $exePath = $p.MainModule.FileName
                if ($exePath) {
                    $dir = Split-Path $exePath -Parent
                    if (Test-AcDir $dir) { return $dir }
                    $parent = Split-Path $dir -Parent
                    if (Test-AcDir $parent) { return $parent }
                }
            } catch {}
        }
    }

    # 2. Steam Registry ve libraryfolders.vdf kontrolu
    $steamPaths = @()
    $regKeys = @(
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"; Name = "InstallPath" },
        @{ Path = "HKLM:\SOFTWARE\Valve\Steam"; Name = "InstallPath" },
        @{ Path = "HKCU:\Software\Valve\Steam"; Name = "SteamPath" }
    )
    foreach ($rk in $regKeys) {
        $val = (Get-ItemProperty -Path $rk.Path -Name $rk.Name -ErrorAction SilentlyContinue).($rk.Name)
        if ($val) {
            $norm = $val -replace '/', '\'
            if (Test-Path $norm) { $steamPaths += $norm }
        }
    }

    # Content Manager veya AC ozel kayitlari
    $cmAcPath = (Get-ItemProperty -Path "HKCU:\Software\AcTools\Content Manager" -Name "AcRoot" -ErrorAction SilentlyContinue).AcRoot
    if (Test-AcDir $cmAcPath) { return $cmAcPath }

    $acSteamReg = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 244210" -Name "InstallLocation" -ErrorAction SilentlyContinue).InstallLocation
    if (Test-AcDir $acSteamReg) { return $acSteamReg }

    $libraryRoots = New-Object System.Collections.Generic.List[string]
    foreach ($sp in $steamPaths) {
        if (-not $libraryRoots.Contains($sp)) { $libraryRoots.Add($sp) }
        $vdf = Join-Path $sp "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            $vdfLines = Get-Content -Path $vdf -Encoding UTF8 -ErrorAction SilentlyContinue
            foreach ($line in $vdfLines) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $libPath = $matches[1] -replace '\\\\', '\'
                    if (-not $libraryRoots.Contains($libPath)) { $libraryRoots.Add($libPath) }
                }
            }
        }
    }

    foreach ($root in $libraryRoots) {
        $candidate = Join-Path $root "steamapps\common\assettocorsa"
        if (Test-AcDir $candidate) { return $candidate }
    }

    # 3. C:\ - G:\ suruculerinde yaygin yollar
    $drives = @("C:", "D:", "E:", "F:", "G:")
    $relPaths = @(
        "Program Files (x86)\Steam\steamapps\common\assettocorsa",
        "Program Files\Steam\steamapps\common\assettocorsa",
        "Steam\steamapps\common\assettocorsa",
        "SteamLibrary\steamapps\common\assettocorsa",
        "Games\Steam\steamapps\common\assettocorsa",
        "Games\SteamLibrary\steamapps\common\assettocorsa",
        "Games\assettocorsa",
        "Oyunlar\Steam\steamapps\common\assettocorsa",
        "Oyunlar\SteamLibrary\steamapps\common\assettocorsa",
        "assettocorsa"
    )
    foreach ($drv in $drives) {
        if (Test-Path "$drv\") {
            foreach ($rp in $relPaths) {
                $cand = Join-Path "$drv\" $rp
                if (Test-AcDir $cand) { return $cand }
            }
        }
    }

    return $null
}

function Find-MonzaTrack {
    param([string]$TracksRoot)
    $allTracks = Get-ChildItem -Path $TracksRoot -Directory -ErrorAction SilentlyContinue
    # Oncelik: tam "monza", sonra "ks_monza", sonra "monza_gp_2017", sonra icinde "monza" gecen herhangi biri
    $selected = $allTracks | Where-Object { $_.Name -eq "monza" } | Select-Object -First 1
    if (-not $selected) {
        $selected = $allTracks | Where-Object { $_.Name -eq "ks_monza" } | Select-Object -First 1
    }
    if (-not $selected) {
        $selected = $allTracks | Where-Object { $_.Name -eq "monza_gp_2017" } | Select-Object -First 1
    }
    if (-not $selected) {
        $selected = $allTracks | Where-Object { $_.Name -imatch "monza" } | Select-Object -First 1
    }
    if (-not $selected) { return $null }

    $trackDir = $selected.FullName
    $trackId = $selected.Name
    $layout = ""

    # Layout kontrolu: root models.ini yoksa veya ui alt klasorlerinde layout varsa ilkini sec
    $hasRootModels = Test-Path (Join-Path $trackDir "models.ini")
    $uiDir = Join-Path $trackDir "ui"
    if (Test-Path $uiDir) {
        $subLayouts = Get-ChildItem -Path $uiDir -Directory -ErrorAction SilentlyContinue
        if (-not $hasRootModels -and $subLayouts.Count -gt 0) {
            $gpLayout = $subLayouts | Where-Object { $_.Name -imatch "^(gp|layout_gp|full)$" } | Select-Object -First 1
            if ($gpLayout) {
                $layout = $gpLayout.Name
            } else {
                $layout = $subLayouts[0].Name
            }
        } elseif ($subLayouts.Count -gt 0 -and -not (Test-Path (Join-Path $uiDir "ui_track.json"))) {
            $gpLayout = $subLayouts | Where-Object { $_.Name -imatch "^(gp|layout_gp|full)$" } | Select-Object -First 1
            if ($gpLayout) {
                $layout = $gpLayout.Name
            } else {
                $layout = $subLayouts[0].Name
            }
        }
    }

    return @{
        TrackId = $trackId
        Layout  = $layout
        Path    = $trackDir
    }
}

function Get-DefaultSurfacesIni {
    return @"
[SURFACE_0]
KEY=ROAD
FRICTION=0.98
DAMPING=0
WAV=
WAV_PITCH=0
FF_EFFECT=0
DIRT_ADDITIVE=0
IS_VALID_TRACK=1
BLACK_FLAG_TIME=0
SIN_HEIGHT=0
SIN_LENGTH=0
IS_PITLANE=0
VIBRATION_GAIN=0
VIBRATION_LENGTH=0

[SURFACE_1]
KEY=TARMAC
FRICTION=0.98
DAMPING=0
WAV=
WAV_PITCH=0
FF_EFFECT=0
DIRT_ADDITIVE=0
IS_VALID_TRACK=1
BLACK_FLAG_TIME=0
SIN_HEIGHT=0
SIN_LENGTH=0
IS_PITLANE=0
VIBRATION_GAIN=0
VIBRATION_LENGTH=0

[SURFACE_2]
KEY=KERB
FRICTION=0.92
DAMPING=0
WAV=kerb.wav
WAV_PITCH=1.3
FF_EFFECT=1
DIRT_ADDITIVE=0
IS_VALID_TRACK=1
BLACK_FLAG_TIME=0
SIN_HEIGHT=0.03
SIN_LENGTH=0.5
IS_PITLANE=0
VIBRATION_GAIN=0.25
VIBRATION_LENGTH=0.5

[SURFACE_3]
KEY=GRASS
FRICTION=0.6
DAMPING=0.05
WAV=grass.wav
WAV_PITCH=0
FF_EFFECT=0
DIRT_ADDITIVE=0.5
IS_VALID_TRACK=0
BLACK_FLAG_TIME=0
SIN_HEIGHT=0.05
SIN_LENGTH=1.2
IS_PITLANE=0
VIBRATION_GAIN=0.15
VIBRATION_LENGTH=0.5

[SURFACE_4]
KEY=SAND
FRICTION=0.45
DAMPING=0.4
WAV=sand.wav
WAV_PITCH=0
FF_EFFECT=0
DIRT_ADDITIVE=1
IS_VALID_TRACK=0
BLACK_FLAG_TIME=0
SIN_HEIGHT=0.08
SIN_LENGTH=0.8
IS_PITLANE=0
VIBRATION_GAIN=0.3
VIBRATION_LENGTH=0.4
"@
}

function Ensure-FileFromSourceOrDefault {
    param(
        [string]$TargetPath,
        [string]$SourcePath,
        [string]$DefaultContent
    )
    $parent = Split-Path $TargetPath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($SourcePath) -and (Test-Path $SourcePath)) {
        Copy-Item -Path $SourcePath -Destination $TargetPath -Force -ErrorAction SilentlyContinue
        return "copied"
    }
    if (-not (Test-Path $TargetPath)) {
        [System.IO.File]::WriteAllText($TargetPath, $DefaultContent, (New-Object System.Text.UTF8Encoding($false)))
        return "generated"
    }
    return "exists"
}

function Ensure-ServerSurfaces {
    param(
        [string]$AcDir,
        [hashtable]$Monza
    )
    $defaultIni = Get-DefaultSurfacesIni
    $serverDir = Join-Path $AcDir "server"
    $trackId = $Monza.TrackId
    $layout = $Monza.Layout

    # 1. server\system\cfg\surfaces.ini
    $mainSysSurfaces = Join-Path $AcDir "system\cfg\surfaces.ini"
    $srvSysSurfaces = Join-Path $serverDir "system\cfg\surfaces.ini"
    $sysSource = if (Test-Path $mainSysSurfaces) { $mainSysSurfaces } else { $null }
    [void](Ensure-FileFromSourceOrDefault -TargetPath $srvSysSurfaces -SourcePath $sysSource -DefaultContent $defaultIni)

    # 2. Ana pist data\surfaces.ini ve server\content\tracks\<TrackId>\data\surfaces.ini
    $mainTrackBaseSurfaces = Join-Path $AcDir "content\tracks\$trackId\data\surfaces.ini"
    $mainTrackLayoutSurfaces = if (-not [string]::IsNullOrWhiteSpace($layout)) {
        Join-Path $AcDir "content\tracks\$trackId\$layout\data\surfaces.ini"
    } else { $null }

    $bestTrackSource = $null
    if ($mainTrackLayoutSurfaces -and (Test-Path $mainTrackLayoutSurfaces)) {
        $bestTrackSource = $mainTrackLayoutSurfaces
    } elseif (Test-Path $mainTrackBaseSurfaces) {
        $bestTrackSource = $mainTrackBaseSurfaces
    }

    if (-not (Test-Path $mainTrackBaseSurfaces)) {
        [void](Ensure-FileFromSourceOrDefault -TargetPath $mainTrackBaseSurfaces -SourcePath $bestTrackSource -DefaultContent $defaultIni)
    }
    if ($mainTrackLayoutSurfaces -and -not (Test-Path $mainTrackLayoutSurfaces)) {
        [void](Ensure-FileFromSourceOrDefault -TargetPath $mainTrackLayoutSurfaces -SourcePath $mainTrackBaseSurfaces -DefaultContent $defaultIni)
    }

    $srvTrackBaseSurfaces = Join-Path $serverDir "content\tracks\$trackId\data\surfaces.ini"
    [void](Ensure-FileFromSourceOrDefault -TargetPath $srvTrackBaseSurfaces -SourcePath $mainTrackBaseSurfaces -DefaultContent $defaultIni)

    if (-not [string]::IsNullOrWhiteSpace($layout)) {
        $srvTrackLayoutSurfaces = Join-Path $serverDir "content\tracks\$trackId\$layout\data\surfaces.ini"
        $layoutSrc = if ($mainTrackLayoutSurfaces -and (Test-Path $mainTrackLayoutSurfaces)) { $mainTrackLayoutSurfaces } else { $mainTrackBaseSurfaces }
        [void](Ensure-FileFromSourceOrDefault -TargetPath $srvTrackLayoutSurfaces -SourcePath $layoutSrc -DefaultContent $defaultIni)
    }
}

function Disable-ServerChecksum {
    param([string]$AcDir)
    # Ana content\cars klasorune dokunmadan yalnizca server\content\cars icindeki data.acd dosyalarini temizle
    $serverCarsDir = Join-Path $AcDir "server\content\cars"
    if (Test-Path $serverCarsDir) {
        $acdFiles = Get-ChildItem -Path $serverCarsDir -Filter "data.acd" -Recurse -File -ErrorAction SilentlyContinue
        foreach ($f in $acdFiles) {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Ensure-FirewallRules {
    try {
        $rules = @(
            @{ Name = "AC_Monza_UDP_9600_In";  Dir = "in";  Proto = "UDP"; Port = "9600" },
            @{ Name = "AC_Monza_UDP_9600_Out"; Dir = "out"; Proto = "UDP"; Port = "9600" },
            @{ Name = "AC_Monza_TCP_9600_In";  Dir = "in";  Proto = "TCP"; Port = "9600" },
            @{ Name = "AC_Monza_TCP_8081_In";  Dir = "in";  Proto = "TCP"; Port = "8081" }
        )
        foreach ($r in $rules) {
            & netsh advfirewall firewall delete rule name="$($r.Name)" 2>&1 | Out-Null
            & netsh advfirewall firewall add rule name="$($r.Name)" dir=$($r.Dir) action=allow protocol=$($r.Proto) localport=$($r.Port) 2>&1 | Out-Null
        }
    } catch {}
}

function Get-CarCatalog {
    param([string]$CarsRoot)
    $gt3Cars = New-Object System.Collections.Generic.List[hashtable]
    $allCars = New-Object System.Collections.Generic.List[hashtable]

    $dirs = Get-ChildItem -Path $CarsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($d in $dirs) {
        $carId = $d.Name
        $carName = $carId
        $isGt3 = $false

        if ($carId -imatch "gt3") { $isGt3 = $true }

        $uiCar = Join-Path $d.FullName "ui\ui_car.json"
        if (Test-Path $uiCar) {
            try {
                $raw = Get-Content -Path $uiCar -Raw -Encoding UTF8
                if ($raw -imatch '"name"\s*:\s*"([^"]+)"') {
                    $carName = $matches[1]
                }
                if ($raw -imatch "gt3") {
                    $isGt3 = $true
                }
            } catch {}
        }

        $skinName = ""
        $skinsDir = Join-Path $d.FullName "skins"
        if (Test-Path $skinsDir) {
            $firstSkin = Get-ChildItem -Path $skinsDir -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($firstSkin) { $skinName = $firstSkin.Name }
        }

        $item = @{
            Id   = $carId
            Name = $carName
            Skin = $skinName
        }
        $allCars.Add($item)
        if ($isGt3) { $gt3Cars.Add($item) }
    }

    return @{
        Gt3 = $gt3Cars
        All = $allCars
    }
}

function Get-LocalLanIPs {
    $ips = New-Object System.Collections.Generic.List[string]
    try {
        $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -ne "127.0.0.1" -and
                $_.IPAddress -notlike "169.254.*" -and
                $_.PrefixOrigin -ne "WellKnown"
            } |
            Sort-Object InterfaceMetric
        foreach ($a in $addrs) {
            if (-not $ips.Contains($a.IPAddress)) { $ips.Add($a.IPAddress) }
        }
    } catch {}

    if ($ips.Count -eq 0) {
        try {
            $hostAddrs = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
                Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork }
            foreach ($ha in $hostAddrs) {
                $s = $ha.IPAddressToString
                if ($s -ne "127.0.0.1" -and $s -notlike "169.254.*" -and -not $ips.Contains($s)) {
                    $ips.Add($s)
                }
            }
        } catch {}
    }

    if ($ips.Count -eq 0) { $ips.Add("127.0.0.1") }
    return $ips
}

# --- ANA AKIS ---
Write-Header
Write-Host "[1/5] Assetto Corsa klasoru araniyor..." -ForegroundColor Cyan
$acDir = Find-AssettoCorsa

while (-not (Test-AcDir $acDir)) {
    Write-Host "[UYARI] Assetto Corsa klasoru otomatik bulunamadi." -ForegroundColor Yellow
    Write-Host "Ornek yol: C:\Program Files (x86)\Steam\steamapps\common\assettocorsa" -ForegroundColor Gray
    $manual = Read-Host "Lutfen Assetto Corsa klasor yolunu yapistirin (Cikis icin Q)"
    if ($manual -eq "q" -or $manual -eq "Q") { exit 1 }
    $acDir = $manual.Trim().Trim('"')
    if (-not (Test-AcDir $acDir)) {
        Write-Host "[HATA] Bu klasorde 'content\cars' veya 'content\tracks' bulunamadi!" -ForegroundColor Red
        Write-Host ""
    }
}

Write-Host "[OK] Assetto Corsa bulundu: $acDir" -ForegroundColor Green

# acServer.exe varlik kontrolu
$serverDir = Join-Path $acDir "server"
$serverExe = Join-Path $serverDir "acServer.exe"
while (-not (Test-Path $serverExe)) {
    Write-Host ""
    Write-Host "[UYARI] 'server\acServer.exe' bu bilgisayardan silinmis!" -ForegroundColor Red
    Write-Host "Geri getirmek icin:" -ForegroundColor Yellow
    Write-Host "  1. Tarayiciya veya Win+R penceresine su komutu yapistirip Enter'a basin:" -ForegroundColor White
    Write-Host "     steam://validate/244210" -ForegroundColor Cyan
    Write-Host "  2. Veya Steam -> Assetto Corsa -> Ozellikler -> Yuklu Dosyalar ->" -ForegroundColor White
    Write-Host "     'Oyun dosyalarinin butunlugunu dogrula' secenegine tiklayin." -ForegroundColor White
    Write-Host "  (Alternatif: Arkadasinin bilgisayarindan acServer.exe acmayi deneyebilirsin)" -ForegroundColor Gray
    Write-Host ""
    $srvAns = Read-Host "Dogrulama bittiyse ENTER'a basin (Cikis: Q)"
    if ($srvAns -eq "q" -or $srvAns -eq "Q") { exit 1 }
}
Write-Host "[OK] acServer.exe hazir." -ForegroundColor Green
Write-Host ""

# 2. Monza pisti kontrolu
Write-Host "[2/5] Monza pisti kontrol ediliyor..." -ForegroundColor Cyan
$tracksRoot = Join-Path $acDir "content\tracks"
$monza = Find-MonzaTrack -TracksRoot $tracksRoot

while (-not $monza) {
    Write-Host "[UYARI] Bilgisayarda MONZA pisti yuklu degil!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Yapman gerekenler:" -ForegroundColor White
    Write-Host "  1. Web sayfasindan 'Monza Pisti (acm-monza.zip)' dosyasini indir." -ForegroundColor Gray
    Write-Host "  2. Indirdigin .zip dosyasini Content Manager penceresine surukleyip birak." -ForegroundColor Gray
    Write-Host "  3. Content Manager sag ustteki yesil ikondan 'Install' butonuna bas." -ForegroundColor Gray
    Write-Host ""
    $ans = Read-Host "Kurulumu yaptiktan sonra devam etmek icin ENTER'a bas (Cikis: Q)"
    if ($ans -eq "q" -or $ans -eq "Q") { exit 1 }
    $monza = Find-MonzaTrack -TracksRoot $tracksRoot
}

$layoutDisplay = if ([string]::IsNullOrWhiteSpace($monza.Layout)) { "(Varsayilan)" } else { $monza.Layout }
Write-Host "[OK] Monza pisti hazir: $($monza.TrackId) $layoutDisplay" -ForegroundColor Green
Write-Host ""

# 3. Arac tarama ve secim menusu
Write-Host "[3/5] Yuklu araclar taraniyor..." -ForegroundColor Cyan
$carsRoot = Join-Path $acDir "content\cars"
$catalog = Get-CarCatalog -CarsRoot $carsRoot

if ($catalog.All.Count -eq 0) {
    Write-Host "[HATA] content\cars klasorunde hic arac bulunamadi!" -ForegroundColor Red
    exit 1
}

Write-Host "  - Bulunan GT3 araci sayisi : $($catalog.Gt3.Count)" -ForegroundColor Yellow
Write-Host "  - Toplam yuklu arac sayisi : $($catalog.All.Count)" -ForegroundColor Gray
Write-Host ""

$selectedCars = $null

if ($catalog.Gt3.Count -gt 0) {
    Write-Host "Bulunan GT3 araclari:" -ForegroundColor White
    $previewCount = [Math]::Min($catalog.Gt3.Count, 12)
    for ($k = 0; $k -lt $previewCount; $k++) {
        Write-Host "    * $($catalog.Gt3[$k].Name) [$($catalog.Gt3[$k].Id)]" -ForegroundColor Green
    }
    if ($catalog.Gt3.Count -gt 12) {
        Write-Host "    ... ve $($catalog.Gt3.Count - 12) arac daha." -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "Arac Modunu Secin:" -ForegroundColor Cyan
    Write-Host "  [1] Yuklu GT3 Araclariyla Monza Odasi Ac (Onerilen)" -ForegroundColor White
    Write-Host "  [2] Bilgisayardaki Mevcut Araclarla (Shuto araclari dahil) Monza Odasi Ac" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "Seciminiz [1/2] (Varsayilan 1)"
    if ($choice -eq "2") {
        $selectedCars = $catalog.All
        Write-Host "[SECILDI] Tum mevcut araclarla oda kuruluyor..." -ForegroundColor Yellow
    } else {
        $selectedCars = $catalog.Gt3
        Write-Host "[SECILDI] GT3 araclariyla oda kuruluyor..." -ForegroundColor Green
    }
} else {
    Write-Host "[UYARI] Bilgisayarda henuz GT3 araci bulunamadi!" -ForegroundColor Yellow
    Write-Host "GT3 oynamak istiyorsan web sayfasindaki GT3 araclarini indirip" -ForegroundColor Gray
    Write-Host "Content Manager'a surukle ve Install'a bas." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [1] GT3 Araclarini Kurdum, Tekrar Tara" -ForegroundColor White
    Write-Host "  [2] Bilgisayardaki Mevcut Araclarla (Shuto araclari dahil) Monza Odasi Ac" -ForegroundColor White
    Write-Host ""
    while ($true) {
        $choice = Read-Host "Seciminiz [1/2]"
        if ($choice -eq "2") {
            $selectedCars = $catalog.All
            break
        } else {
            $catalog = Get-CarCatalog -CarsRoot $carsRoot
            if ($catalog.Gt3.Count -gt 0) {
                $selectedCars = $catalog.Gt3
                Write-Host "[OK] $($catalog.Gt3.Count) adet GT3 araci bulundu!" -ForegroundColor Green
                break
            }
            Write-Host "[BILGI] Hala GT3 araci gorunmuyor. Araclari kurup tekrar [1]'e veya Shuto araclari icin [2]'ye basin." -ForegroundColor Yellow
        }
    }
}

# 4. Seans / Oyun Modu Secimi
Write-Host ""
Write-Host "[4/5] Seans / Oyun Modunu Secin:" -ForegroundColor Cyan
Write-Host "  [1] Hemen Yaris Modu (3 dk Kisa Siralama + 10 Tur Yaris - Tekrarli) [Onerilen]" -ForegroundColor White
Write-Host "  [2] Serbest Gazlama / Trackday Modu (120 dk Acik Antrenman)" -ForegroundColor White
Write-Host ""
$modeChoice = Read-Host "Seciminiz [1/2] (Varsayilan 1)"

if ($modeChoice -eq "2") {
    $sessionBlock = @"
[PRACTICE]
NAME=Trackday Serbest Surus
TIME=120
IS_OPEN=1
"@
    $modeLabel = "Serbest Gazlama / Trackday (120 dk)"
} else {
    $sessionBlock = @"
[QUALIFY]
NAME=Kisa Siralama
TIME=3
IS_OPEN=1

[RACE]
NAME=Monza GT3 Yaris
LAPS=10
WAIT_TIME=20
IS_OPEN=2
"@
    $modeLabel = "Hemen Yaris Modu (3 dk Siralama + 10 Tur Yaris)"
}

# 5. surfaces.ini korumasi, checksum temizligi, firewall ve config yazimi
Write-Host ""
Write-Host "[5/5] Sunucu guvenlik, surfaces.ini ve yapilandirma ayarlari yapiliyor..." -ForegroundColor Cyan

Ensure-ServerSurfaces -AcDir $acDir -Monza $monza
Write-Host "[OK] surfaces.ini cokme korumasi uygulandi." -ForegroundColor Green

Disable-ServerChecksum -AcDir $acDir
Write-Host "[OK] Checksum (MD5) kontrolu temizlendi." -ForegroundColor Green

Ensure-FirewallRules
Write-Host "[OK] Windows Firewall port izinleri (9600, 8081) islendi." -ForegroundColor Green

$cfgDir = Join-Path $serverDir "cfg"
if (-not (Test-Path $cfgDir)) {
    New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null
}

# Her aractan 4 kopya, toplam maksimum 24 slot
$maxSlots = 24
$entrySb = New-Object System.Text.StringBuilder
$addedModels = New-Object System.Collections.Generic.List[string]
$slot = 0

foreach ($car in $selectedCars) {
    if ($slot -ge $maxSlots) { break }
    $copies = 0
    while ($copies -lt 4 -and $slot -lt $maxSlots) {
        [void]$entrySb.AppendLine("[CAR_$slot]")
        [void]$entrySb.AppendLine("MODEL=$($car.Id)")
        [void]$entrySb.AppendLine("SKIN=$($car.Skin)")
        [void]$entrySb.AppendLine("SPECTATOR_MODE=0")
        [void]$entrySb.AppendLine("DRIVERNAME=")
        [void]$entrySb.AppendLine("TEAM=")
        [void]$entrySb.AppendLine("GUID=")
        [void]$entrySb.AppendLine("BALLAST=0")
        [void]$entrySb.AppendLine("RESTRICTOR=0")
        [void]$entrySb.AppendLine("")
        if (-not $addedModels.Contains($car.Id)) {
            $addedModels.Add($car.Id)
        }
        $slot++
        $copies++
    }
}

$carsLine = [string]::Join(";", $addedModels.ToArray())
$entryPath = Join-Path $cfgDir "entry_list.ini"
[System.IO.File]::WriteAllText($entryPath, $entrySb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$serverCfg = @"
[SERVER]
NAME=SIM KAFE MONZA GT3 LAN
CARS=$carsLine
CONFIG_TRACK=$($monza.Layout)
TRACK=$($monza.TrackId)
SUN_ANGLE=16
PASSWORD=
ADMIN_PASSWORD=monza123
UDP_PORT=9600
TCP_PORT=9600
HTTP_PORT=8081
MAX_BALLAST_KG=0
QUALIFY_MAX_WAIT_PERC=120
RACE_PIT_WINDOW_START=0
RACE_PIT_WINDOW_END=0
REVERSED_GRID_RACE_PERCENTAGES=0
LOCKED_ENTRY_LIST=0
PICKUP_MODE_ENABLED=1
LOOP_MODE=1
SLEEP_TIME=1
CLIENT_SEND_INTERVAL_HZ=18
SEND_BUFFER_SIZE=0
RECV_BUFFER_SIZE=0
RACE_OVER_TIME=60
KICK_QUORUM=85
VOTING_QUORUM=80
VOTE_DURATION=20
BLACKLIST_MODE=1
FUEL_RATE=0
DAMAGE_MULTIPLIER=0
TYRE_WEAR_RATE=0
ALLOWED_TYRES_OUT=4
ABS_ALLOWED=1
TC_ALLOWED=1
STABILITY_ALLOWED=1
AUTOCLUTCH_ALLOWED=1
TYRE_BLANKETS_ALLOWED=1
FORCE_VIRTUAL_MIRROR=0
REGISTER_TO_LOBBY=0
LAN_DISCOVERY=1
MAX_CLIENTS=$slot
START_RULE=0
RACE_GAS_PENALTY_DISABLED=1
RESULT_SCREEN_TIME=45
TIME_OF_DAY_MULT=1
THREADS=2

$sessionBlock

[DYNAMIC_TRACK]
SESSION_START=98
RANDOMNESS=0
SESSION_TRANSFER=90
LAP_GAIN=10

[WEATHER_0]
GRAPHICS=3_clear
BASE_TEMPERATURE_AMBIENT=24
BASE_TEMPERATURE_ROAD=30
VARIATION_AMBIENT=1
VARIATION_ROAD=2
WIND_BASE_SPEED_MIN=0
WIND_BASE_SPEED_MAX=2
WIND_BASE_DIRECTION=0
WIND_VARIATION_DIRECTION=0
"@

$cfgPath = Join-Path $cfgDir "server_cfg.ini"
[System.IO.File]::WriteAllText($cfgPath, $serverCfg, (New-Object System.Text.UTF8Encoding($false)))

# Onceki acServer calisiyorsa kapat
Get-Process -Name "acServer" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400

$ips = Get-LocalLanIPs
$primaryIp = $ips[0]

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "SUNUCU AKTIF! Arkadasinla Content Manager -> Online -> LAN" -ForegroundColor Green
Write-Host "sekmesine tiklayip direkt girebilirsiniz." -ForegroundColor Green
Write-Host ""
Write-Host "  Yerel IP Adresi : $primaryIp" -ForegroundColor Yellow
Write-Host "  Add IP Adresi   : ${primaryIp}:8081" -ForegroundColor Yellow
Write-Host "  Direkt Link     : acmanager://race/online/join?ip=${primaryIp}&httpPort=8081" -ForegroundColor Cyan
if ($ips.Count -gt 1) {
    Write-Host "  Diger IP'ler    : $([string]::Join(', ', $ips.ToArray()))" -ForegroundColor Gray
}
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Oda Adi   : SIM KAFE MONZA GT3 LAN" -ForegroundColor White
Write-Host "Pist      : $($monza.TrackId) $layoutDisplay" -ForegroundColor White
Write-Host "Oyun Modu : $modeLabel" -ForegroundColor White
Write-Host "Arac Say. : $($addedModels.Count) model ($slot slot)" -ForegroundColor White
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Oyun Ici Chat Admin Komutlari (Beklemeden Yaris Gecisi):" -ForegroundColor Yellow
Write-Host "  /admin monza123     -> Yonetici yetkisi al" -ForegroundColor White
Write-Host "  /next_session       -> Siralama beklemeden hemen yarisa gec" -ForegroundColor White
Write-Host "  /restart_session    -> Yarisi bastan baslat" -ForegroundColor White
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "NOT: Windows Guvenlik Duvari sorarsa 'Erisime Izin Ver' deyin." -ForegroundColor Gray
Write-Host "     Oyun bitene kadar bu siyah pencereyi KAPATMAYIN." -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

$proc = Start-Process -FilePath $serverExe -ArgumentList "-c cfg/server_cfg.ini -e cfg/entry_list.ini" -WorkingDirectory $serverDir -NoNewWindow -PassThru -Wait
exit $proc.ExitCode
