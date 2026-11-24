if (-not ('WinOptSpi' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WinOptSpi {
    [StructLayout(LayoutKind.Sequential)]
    public struct ANIMATIONINFO { public uint cbSize; public int iMinAnimate; }
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint a, uint b, ref int c, uint d);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint a, uint b, IntPtr c, uint d);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint a, uint b, ref ANIMATIONINFO c, uint d);
    public static int GetBool(uint code) { int v = 0; if (!SystemParametersInfo(code, 0, ref v, 0)) return -1; return v != 0 ? 1 : 0; }
    public static bool SetBool(uint code, int v) { return SystemParametersInfo(code, 0, (IntPtr)v, 3); }
    public static int GetMinAnimate() {
        ANIMATIONINFO ai = new ANIMATIONINFO();
        ai.cbSize = (uint)Marshal.SizeOf(typeof(ANIMATIONINFO));
        if (!SystemParametersInfo(0x0048, ai.cbSize, ref ai, 0)) return -1;
        return ai.iMinAnimate != 0 ? 1 : 0;
    }
    public static bool SetMinAnimate(int v) {
        ANIMATIONINFO ai = new ANIMATIONINFO();
        ai.cbSize = (uint)Marshal.SizeOf(typeof(ANIMATIONINFO));
        ai.iMinAnimate = v;
        return SystemParametersInfo(0x0049, ai.cbSize, ref ai, 3);
    }
}
'@
}

$TweakBackupFile = Join-Path $AppDir 'ayar-yedegi.json'
$script:VfxPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
$script:TweakLoaded = $false
$script:Plans = @()

$script:SpiMap = @{
    MenuAnim = @(0x1002, 0x1003); ComboAnim = @(0x1004, 0x1005); ListSmooth = @(0x1006, 0x1007)
    SelFade = @(0x1014, 0x1015); TipAnim = @(0x1016, 0x1017); CursorShadow = @(0x101A, 0x101B); ClientAnim = @(0x1042, 0x1043)
}

function Get-TwRegValue([string]$path, [string]$name) {
    try { return (Get-ItemPropertyValue -LiteralPath $path -Name $name -ErrorAction Stop) } catch { return $null }
}

function Set-TwRegValue([string]$path, [string]$name, [string]$type, $value) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    if ($type -eq 'DWord') { $value = [int]$value }
    Set-ItemProperty -LiteralPath $path -Name $name -Value $value -Type $type -ErrorAction Stop
}

function Remove-TwRegValue([string]$path, [string]$name) {
    if (Test-Path -LiteralPath $path) { Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue }
}

function Get-TwRegState([string]$path, [string]$name, [string]$type) {
    $v = Get-TwRegValue $path $name
    return [pscustomobject]@{ Kind = 'Reg'; Path = $path; Name = $name; Type = $type; Existed = ($null -ne $v); Value = $v }
}

function Restore-TwRegState($e) {
    if ($e.Existed) { Set-TwRegValue $e.Path $e.Name $e.Type $e.Value } else { Remove-TwRegValue $e.Path $e.Name }
}

function Get-SpiValue([string]$key) {
    if ($key -eq 'MinAnim') { $v = [WinOptSpi]::GetMinAnimate() } else { $v = [WinOptSpi]::GetBool([uint32]$script:SpiMap[$key][0]) }
    if ($v -lt 0) { return $null }
    return $v
}

function Set-SpiValue([string]$key, [int]$v) {
    if ($key -eq 'MinAnim') { return [WinOptSpi]::SetMinAnimate($v) }
    return [WinOptSpi]::SetBool([uint32]$script:SpiMap[$key][1], $v)
}

function New-Tweak($id, $cat, $name, $kind, $items, $recLabel, $otherLabel, $level, $when, $what, $effect) {
    [pscustomobject]@{
        Id = $id; Cat = $cat; Name = $name; Kind = $kind; Items = @($items); RecLabel = $recLabel; OtherLabel = $otherLabel
        Level = $level; When = $when; What = $what; Effect = $effect
    }
}
function New-TwItem($path, $name, $type, $rec, $dflt, $alt = $null) {
    @{ Path = $path; Name = $name; Type = $type; Rec = $rec; Dflt = $dflt; Alt = $alt }
}
function New-TwSpi($key, $rec, $dflt) {
    @{ Key = $key; Rec = $rec; Dflt = $dflt; Alt = $dflt }
}

$pExp  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$pGb   = 'HKCU:\Software\Microsoft\GameBar'
$pCdm  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$pInp  = 'HKCU:\Software\Microsoft\InputPersonalization'
$noteAnim = 'Arayüz geçişleri daha ani görünür. Güçlü bilgisayarlarda fark çok az olabilir; kazanç sistemden sisteme değişir ve garanti edilmez.'

$script:Tweaks = @(
    New-Tweak 'anim_client' 'Animasyonlar' 'Windows animasyonları (genel)' 'Spi' @((New-TwSpi 'ClientAnim' 0 1)) 'Kapalı' 'Açık' 'Önerilir' 'Hemen' `
        'Pencere açılış/kapanış, kaydırma ve geçiş animasyonlarını kapatır (Ayarlar > Erişilebilirlik > Görsel efektler > Animasyon efektleri).' $noteAnim
    New-Tweak 'anim_min' 'Animasyonlar' 'Pencere küçültme/büyütme animasyonu' 'Spi' @((New-TwSpi 'MinAnim' 0 1)) 'Kapalı' 'Açık' 'Önerilir' 'Hemen' `
        'Pencereler simge durumuna küçülürken ve büyürken oynayan animasyonu kapatır.' $noteAnim
    New-Tweak 'anim_menu' 'Animasyonlar' 'Menü açılış animasyonu' 'Spi' @((New-TwSpi 'MenuAnim' 0 1)) 'Kapalı' 'Açık' 'Önerilir' 'Hemen' `
        'Menülerin kayarak veya solarak açılmasını kapatır; menüler anında görünür.' $noteAnim
    New-Tweak 'anim_combo' 'Animasyonlar' 'Açılır kutu animasyonu' 'Spi' @((New-TwSpi 'ComboAnim' 0 1)) 'Kapalı' 'Açık' 'Önerilir' 'Hemen' `
        'Açılır listelerin (combo box) kayarak açılma animasyonunu kapatır.' $noteAnim
    New-Tweak 'anim_tip' 'Animasyonlar' 'Araç ipucu animasyonu' 'Spi' @((New-TwSpi 'TipAnim' 0 1)) 'Kapalı' 'Açık' 'Önerilir' 'Hemen' `
        'Fare üzerine gelince çıkan ipucu kutularının solarak belirmesini kapatır.' $noteAnim
    New-Tweak 'anim_list' 'Animasyonlar' 'Liste kutusu yumuşak kaydırma' 'Spi' @((New-TwSpi 'ListSmooth' 0 1)) 'Kapalı' 'Açık' 'İsteğe bağlı' 'Hemen' `
        'Liste kutularında yumuşak kaydırmayı kapatır; kaydırma satır satır ilerler.' 'Kaydırma daha sert hissedilebilir. Performansa etkisi genellikle çok küçüktür.'
    New-Tweak 'anim_task' 'Animasyonlar' 'Görev çubuğu animasyonları' 'Reg' @((New-TwItem $pExp 'TaskbarAnimations' 'DWord' 0 1)) 'Kapalı' 'Açık' 'İsteğe bağlı' 'Explorer yeniden başlayınca' `
        'Görev çubuğundaki düğme ve önizleme animasyonlarını kapatır.' $noteAnim
    New-Tweak 'vfx_fade' 'Görsel efektler' 'Seçim dikdörtgeni solma efekti' 'Spi' @((New-TwSpi 'SelFade' 0 1)) 'Kapalı' 'Açık' 'İsteğe bağlı' 'Hemen' `
        'Öğe seçildiğinde veya menü kapandığında oluşan solma efektini kapatır.' 'Yalnızca görünüm değişir; ölçülebilir performans kazancı beklenmemelidir.'
    New-Tweak 'vfx_shadow' 'Görsel efektler' 'Fare imleci gölgesi' 'Spi' @((New-TwSpi 'CursorShadow' 0 1)) 'Kapalı' 'Açık' 'İsteğe bağlı' 'Hemen' `
        'Fare imlecinin altındaki gölgeyi kapatır.' 'Yalnızca görünüm değişir; performansa etkisi önemsizdir.'
    New-Tweak 'vfx_iconshadow' 'Görsel efektler' 'Masaüstü simge etiketi gölgesi' 'Reg' @((New-TwItem $pExp 'ListviewShadow' 'DWord' 0 1)) 'Kapalı' 'Açık' 'İsteğe bağlı' 'Explorer yeniden başlayınca' `
        'Masaüstü simge adlarının arkasındaki gölgeyi kapatır.' 'Açık renkli duvar kâğıtlarında simge yazıları daha zor okunabilir.'
    New-Tweak 'transparency' 'Saydamlık' 'Saydamlık efektleri' 'Reg' @((New-TwItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 'DWord' 0 1)) 'Kapalı' 'Açık' 'Önerilir' 'Hemen' `
        'Görev çubuğu, Başlat menüsü ve pencerelerdeki saydam/bulanık (akrilik, mika) arka planı kapatır.' 'Arayüz düz renkli görünür. Ekran kartı yükü hafifler; etkisi özellikle entegre grafikli ve düşük donanımlı sistemlerde fark edilebilir ama garanti edilmez.'
    New-Tweak 'gamemode' 'Oyun' 'Windows Oyun Modu' 'Reg' @((New-TwItem $pGb 'AutoGameModeEnabled' 'DWord' 1 1 0), (New-TwItem $pGb 'AllowAutoGameMode' 'DWord' 1 1 0)) 'Açık' 'Kapalı' 'Önerilir' 'Hemen' `
        'Oyun algılandığında Windows arka plan etkinliğini (ör. güncelleme yüklemeleri, sürücü bildirimleri) sınırlayarak oyuna öncelik vermeye çalışır.' 'Etkisi oyuna ve donanıma göre değişir; bazı oyunlarda fark yok, nadiren takılma bildirilmiştir. FPS artışı garanti edilmez. Sorun yaşarsanız kapatın.'
    New-Tweak 'gamebar' 'Oyun' 'Xbox Game Bar kısayol ve ipuçları' 'Reg' @((New-TwItem $pGb 'UseNexusForGameBarEnabled' 'DWord' 0 1), (New-TwItem $pGb 'ShowStartupPanel' 'DWord' 0 1)) 'Kapalı' 'Açık' 'İsteğe bağlı' 'Hemen' `
        'Oyun kolundaki düğmeyle Game Bar açılmasını ve başlangıç ipucu panelini kapatır.' 'Game Bar kısayolları ve kontrolcü düğmesiyle açma çalışmaz. Win+G ile elle açma Windows sürümüne göre değişebilir.'
    New-Tweak 'gamedvr' 'Oyun' 'Arka plan oyun kaydı (Game DVR)' 'Reg' @((New-TwItem 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 'DWord' 0 1), (New-TwItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 'DWord' 0 1)) 'Kapalı' 'Açık' 'İsteğe bağlı' 'Oyun yeniden başlayınca' `
        'Oyunun son anlarını sürekli kaydeden arka plan yakalamayı kapatır.' 'Win+Alt+G ile son saniyeleri klip yapma ve Game Bar ile kayıt çalışmaz. Kayıt yükü ortadan kalkar; FPS farkı sistemden sisteme değişir ve garanti edilmez.'
    New-Tweak 'startdelay' 'Başlangıç' 'Başlangıç uygulamaları gecikmesi' 'Reg' @((New-TwItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 'DWord' 0 10000)) 'Gecikme yok (0 ms)' 'Windows gecikmesi (varsayılan)' 'Dikkat' 'Sonraki oturum açılışı' `
        'Windows, masaüstü açıldıktan sonra başlangıç uygulamalarını yaklaşık 10 saniye bekletir. Değer 0 yapılırsa uygulamalar hemen başlar.' 'Çok sayıda başlangıç uygulaması varsa masaüstü açılırken yavaşlama ve takılma olabilir. Genellikle yalnızca az uygulaması olan sistemlerde mantıklıdır.'
    New-Tweak 'bgapps' 'Arka plan' 'Uygulamaların arka planda çalışması (genel)' 'Reg' @((New-TwItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 'DWord' 1 0)) 'Kapalı' 'Açık' 'İsteğe bağlı' 'Oturum yeniden açılınca' `
        'Mağaza (UWP) uygulamalarının kullanılmadığı sırada arka planda çalışmasını genel olarak engeller.' 'Posta, takvim, hava durumu gibi uygulamalar bildirim ve eşitleme yapmayabilir. Windows 11 bazı sürümlerinde bu genel anahtar yerine uygulama bazlı ayar geçerlidir; bunun için Uygulama Bazlı Arka Plan Ayarı düğmesini kullanın.'
    New-Tweak 'priv_adid' 'Gizlilik' 'Reklam kimliği' 'Reg' @((New-TwItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'DWord' 0 1)) 'Kapalı' 'Açık' 'Önerilir' 'Hemen' `
        'Uygulamaların kişiselleştirilmiş reklam için kullandığı kimliği devre dışı bırakır.' 'Reklam sayısı azalmaz, yalnızca daha az kişiselleştirilir. Uygulama işlevlerini etkilemez.'
    New-Tweak 'priv_tailored' 'Gizlilik' 'Kişiselleştirilmiş deneyimler' 'Reg' @((New-TwItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'DWord' 0 1)) 'Kapalı' 'Açık' 'Önerilir' 'Hemen' `
        'Tanılama verilerinin kişiselleştirilmiş ipucu ve öneriler için kullanılmasını engeller.' 'Windows ipuçları ve öneriler daha genel olur. Sistem işlevi etkilenmez.'
    New-Tweak 'priv_suggest' 'Gizlilik' 'Başlat ve Ayarlar önerileri, ipuçları' 'Reg' @(
        (New-TwItem $pCdm 'SubscribedContent-338388Enabled' 'DWord' 0 1), (New-TwItem $pCdm 'SubscribedContent-338389Enabled' 'DWord' 0 1),
        (New-TwItem $pCdm 'SubscribedContent-353694Enabled' 'DWord' 0 1), (New-TwItem $pCdm 'SubscribedContent-353696Enabled' 'DWord' 0 1),
        (New-TwItem $pCdm 'SystemPaneSuggestionsEnabled' 'DWord' 0 1), (New-TwItem $pCdm 'SoftLandingEnabled' 'DWord' 0 1)) 'Kapalı' 'Açık' 'Önerilir' 'Hemen' `
        'Başlat menüsündeki önerilen uygulamalar, Ayarlar içindeki öneriler ve Windows ipuçlarını kapatır.' 'Yalnızca öneri ve reklam benzeri içerikler kaybolur; Windows işlevleri etkilenmez.'
    New-Tweak 'priv_ink' 'Gizlilik' 'Yazma ve mürekkep verisi toplama' 'Reg' @((New-TwItem $pInp 'RestrictImplicitInkCollection' 'DWord' 1 0), (New-TwItem $pInp 'RestrictImplicitTextCollection' 'DWord' 1 0)) 'Toplama kapalı' 'Toplama açık' 'İsteğe bağlı' 'Hemen' `
        'Yazı ve el yazısı örneklerinin kişiselleştirme için toplanmasını kısıtlar.' 'Otomatik düzeltme ve tahmin önerileri zamanla daha az kişiye özel olabilir.'
    New-Tweak 'priv_lang' 'Gizlilik' 'Web sitelerine dil listesi paylaşımı' 'Reg' @((New-TwItem 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 'DWord' 1 0)) 'Paylaşım kapalı' 'Paylaşım açık' 'İsteğe bağlı' 'Hemen' `
        'Web sitelerinin Windows dil listenize erişmesini engeller.' 'Bazı siteler içeriği yerel dilinizde otomatik sunamayabilir.'
    New-Tweak 'priv_feedback' 'Gizlilik' 'Geri bildirim isteme sıklığı' 'Reg' @((New-TwItem 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 'DWord' 0 $null)) 'Hiç sorma' 'Windows karar verir' 'İsteğe bağlı' 'Hemen' `
        'Windows geri bildirim hub bildirimlerinin sıklığını sıfıra ayarlar.' 'Yalnızca geri bildirim isteme bildirimleri durur.'
    New-Tweak 'priv_location' 'Gizlilik' 'Konum erişimi (kullanıcı için)' 'Reg' @((New-TwItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'String' 'Deny' 'Allow')) 'Kapalı' 'Açık' 'Dikkat' 'Hemen' `
        'Uygulamaların konumunuza erişmesini kullanıcı düzeyinde engeller.' 'Haritalar, hava durumu, Cihazımı Bul ve konum isteyen uygulamalar çalışmaz veya yanlış bölge gösterebilir.'
)

function Get-TweakById([string]$id) { $script:Tweaks | Where-Object { $_.Id -eq $id } | Select-Object -First 1 }

function Get-TweakState($tw) {
    $match = $true
    foreach ($it in $tw.Items) {
        if ($tw.Kind -eq 'Spi') { $v = Get-SpiValue $it.Key } else { $v = Get-TwRegValue $it.Path $it.Name }
        if ($null -eq $v) { $v = $it.Dflt }
        if (($null -eq $v) -or ("$v" -ne "$($it.Rec)")) { $match = $false }
    }
    $txt = if ($match) { $tw.RecLabel } else { $tw.OtherLabel }
    return [pscustomobject]@{ IsRec = $match; Text = $txt }
}

function Get-TweakPrev($tw) {
    $prev = @()
    foreach ($it in $tw.Items) {
        if ($tw.Kind -eq 'Spi') { $prev += [pscustomobject]@{ Kind = 'Spi'; Key = $it.Key; Value = (Get-SpiValue $it.Key) } }
        else { $prev += (Get-TwRegState $it.Path $it.Name $it.Type) }
    }
    if ($tw.Kind -eq 'Spi') { $prev += (Get-TwRegState $script:VfxPath 'VisualFXSetting' 'DWord') }
    return $prev
}

function Set-TweakItems($tw, [string]$mode) {
    foreach ($it in $tw.Items) {
        $val = if ($mode -eq 'Alt') { $it.Alt } else { $it.Rec }
        if ($tw.Kind -eq 'Spi') {
            if (-not (Set-SpiValue $it.Key ([int]$val))) { throw "Sistem ayarı uygulanamadı: $($tw.Name)" }
        } else { Set-TwRegValue $it.Path $it.Name $it.Type $val }
    }
    if ($tw.Kind -eq 'Spi') { Set-TwRegValue $script:VfxPath 'VisualFXSetting' 'DWord' 3 }
}

function Get-PowerPlans {
    $out = & powercfg.exe /list 2>&1 | Out-String
    $plans = @()
    foreach ($line in ($out -split "`r?`n")) {
        if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\((.+?)\)(\s*\*)?') {
            $plans += [pscustomobject]@{ Guid = $Matches[1].ToLower(); Name = $Matches[2]; Active = [bool]$Matches[3] }
        }
    }
    return $plans
}

function Get-ActivePowerGuid {
    $a = @(Get-PowerPlans | Where-Object { $_.Active })
    if ($a.Count -gt 0) { return $a[0].Guid }
    return ''
}

function Set-PowerPlanByGuid([string]$guid) {
    $o = & powercfg.exe /setactive $guid 2>&1
    if ($LASTEXITCODE -ne 0) { throw (($o | Out-String).Trim()) }
}

function Get-PlanText([string]$guid, [string]$name) {
    switch ($guid) {
        '381b4222-f694-41f0-9685-ff5bb260df2e' { return 'Dengeli: güç tüketimi ile performansı otomatik dengeler. Çoğu kullanıcı için varsayılandır.' }
        '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' { return 'Yüksek performans: işlemci daha yüksek hızda tutulur. Güç tüketimi ve ısı artar, dizüstünde pil hızla azalır. Oyunlarda fark her zaman oluşmaz ve garanti edilmez.' }
        'a1841308-3541-4fab-bc81-f71556f20b4a' { return 'Güç tasarrufu: performansı sınırlar, pil ömrünü uzatır. Oyun ve ağır işlerde yavaşlık hissedilebilir.' }
        'e9a42b02-d5df-448d-aa00-03f14749eb61' { return 'Nihai Performans: küçük güç yönetimi gecikmelerini kaldırmayı amaçlar. Güç tüketimi ve ısı yüksektir, dizüstü için önerilmez. Kazanç çoğu kullanımda sınırlıdır ve garanti edilmez.' }
        default { return "Özel veya üretici planı ($name). Ayrıntıları için Windows Güç Seçenekleri sayfasına bakın." }
    }
}

function Add-TweakBackup([string]$id, [string]$name, [string]$op, $prev) {
    $rec = [pscustomobject]@{
        Id = [guid]::NewGuid().ToString(); Zaman = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Ayar = $id; Adi = $name
        Islem = $op; Prev = @($prev); GeriYuklendi = $false
    }
    Save-TweakBackup (@(Read-TweakBackup) + $rec)
}

function Read-TweakBackup {
    if (Test-Path -LiteralPath $TweakBackupFile) {
        try {
            $x = Get-Content -LiteralPath $TweakBackupFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $x) { return @() }
            return @($x | ForEach-Object { $_ })
        } catch {}
    }
    return @()
}

function Save-TweakBackup($recs) { ConvertTo-Json -InputObject @($recs) -Depth 6 | Set-Content -LiteralPath $TweakBackupFile -Encoding UTF8 }

function Restore-TweakPrev($prev) {
    $list = @($prev | Where-Object { $_ })
    for ($i = $list.Count - 1; $i -ge 0; $i--) {
        $e = $list[$i]
        switch ($e.Kind) {
            'Reg'   { Restore-TwRegState $e }
            'Spi'   { if ($null -ne $e.Value) { [void](Set-SpiValue $e.Key ([int]$e.Value)) } }
            'Power' { if ($e.Guid) { Set-PowerPlanByGuid $e.Guid } }
        }
    }
}

function Get-SelectedTweaks { @($gridTw.SelectedRows | ForEach-Object { $_.Tag } | Where-Object { $_ }) }

function Show-TweakDetail {
    $sel = @(Get-SelectedTweaks)
    if ($sel.Count -eq 0) { return }
    $t = $sel[0].Tw
    $lines = @(
        "Ayar: $($t.Name)   [Düzey: $($t.Level)]",
        "Şu anki durum: $($sel[0].State.Text)   |   Önerilen: $($t.RecLabel)",
        "Ne yapar: $($t.What)",
        "Olası etkiler: $($t.Effect)",
        "Etkili olma zamanı: $($t.When)",
        'Geri alma: Uygulamadan önce önceki değer yedeklenir; Önceki Ayara Dön düğmesiyle geri yüklenir.'
    )
    $txtTwInfo.Text = ($lines -join "`r`n")
}

function Show-PowerInfo {
    $i = $cmbPower.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:Plans.Count) { return }
    $p = $script:Plans[$i]
    $act = if ($p.Active) { ' (şu an etkin)' } else { '' }
    $txtTwInfo.Text = "Güç planı: $($p.Name)$act`r`n" + (Get-PlanText $p.Guid $p.Name) + "`r`nUygulanınca önceki plan yedeklenir; Önceki Plana Dön ile geri alınır."
}

function Update-PowerList {
    $script:Plans = @(Get-PowerPlans)
    $cmbPower.Items.Clear()
    foreach ($p in $script:Plans) {
        $label = $p.Name
        if ($p.Active) { $label += ' (etkin)' }
        [void]$cmbPower.Items.Add($label)
    }
    for ($i = 0; $i -lt $script:Plans.Count; $i++) { if ($script:Plans[$i].Active) { $cmbPower.SelectedIndex = $i } }
}

function Update-TweakList {
    $form.Cursor = 'WaitCursor'; $lblTw.Text = '  Ayarlar okunuyor...'; $form.Refresh()
    try {
        $backups = @(Read-TweakBackup | Where-Object { $_.GeriYuklendi -ne $true })
        $gridTw.Rows.Clear()
        $recCount = 0; $total = 0
        foreach ($tw in $script:Tweaks) {
            $st = Get-TweakState $tw
            $total++
            if ($st.IsRec) { $recCount++ }
            if ($chkTwDiff.Checked -and $st.IsRec) { continue }
            $note = ''
            if (@($backups | Where-Object { $_.Ayar -eq $tw.Id }).Count -gt 0) { $note = 'Yedek var' }
            $i = $gridTw.Rows.Add([object[]]@($tw.Name, $tw.Cat, $st.Text, $tw.RecLabel, $tw.Level, $tw.When, $tw.What, $tw.Effect, $note))
            $row = $gridTw.Rows[$i]
            $row.Tag = [pscustomobject]@{ Tw = $tw; State = $st }
            if ($st.IsRec) { $row.DefaultCellStyle.BackColor = [Drawing.Color]::Honeydew }
            elseif ($tw.Level -eq 'Dikkat') { $row.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
        }
        Update-PowerList
        $act = @($script:Plans | Where-Object { $_.Active } | Select-Object -First 1)
        $planName = if ($act.Count -gt 0) { $act[0].Name } else { 'bilinmiyor' }
        $lblTw.Text = "  Toplam: $total  |  Önerilen değerde: $recCount  |  Farklı: $($total - $recCount)  |  Etkin güç planı: $planName  |  Öneriler genel eğilimdir; hız veya FPS artışı garanti edilmez."
        $script:TweakLoaded = $true
    } catch {
        $lblTw.Text = '  Hata: ' + $_.Exception.Message
        Write-Log ('Ayar listesi hatası: ' + $_.Exception.Message)
    } finally { $form.Cursor = 'Default' }
}

function Show-Tweaks { if (-not $script:TweakLoaded) { Update-TweakList } }

function Invoke-ApplySelectedTweaks {
    $sel = @(Get-SelectedTweaks)
    if ($sel.Count -eq 0) { [L10nMsg]::Show('Önce listeden bir veya daha fazla ayar seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $todo = @($sel | Where-Object { -not $_.State.IsRec })
    if ($todo.Count -eq 0) { [L10nMsg]::Show('Seçili ayarlar zaten önerilen değerde.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $lines = @($todo | ForEach-Object { "- $($_.Tw.Name): $($_.State.Text) -> $($_.Tw.RecLabel)" })
    $warn = @($todo | Where-Object { $_.Tw.Level -eq 'Dikkat' })
    $msg = "Şu ayarlar değiştirilecek:`n`n" + ($lines -join "`n")
    if ($warn.Count -gt 0) { $msg += "`n`nDikkat gerektirenler:`n" + (($warn | ForEach-Object { "- $($_.Tw.Name): $($_.Tw.Effect)" }) -join "`n") }
    $msg += "`n`nÖnceki değerler yedeklenir ve geri alınabilir. Öneriler performans artışı garantisi vermez. Devam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Ayarları uygula', 'YesNo', 'Warning') -ne 'Yes') { return }
    $ok = 0; $fail = @(); $later = @()
    foreach ($r in $todo) {
        $tw = $r.Tw
        $prev = @()
        try {
            $prev = @(Get-TweakPrev $tw)
            Set-TweakItems $tw 'Rec'
            Add-TweakBackup $tw.Id $tw.Name 'Önerilen değer uygulandı' $prev
            Write-Log "Windows ayarı uygulandı: $($tw.Name)"
            if ($tw.When -ne 'Hemen') { $later += "$($tw.Name): $($tw.When)" }
            $ok++
        } catch {
            $fail += "$($tw.Name): $($_.Exception.Message)"
            try { Restore-TweakPrev $prev } catch {}
            Write-Log "Windows ayarı hatası $($tw.Name): $($_.Exception.Message)"
        }
    }
    Update-TweakList
    $m = "$ok ayar uygulandı."
    if ($later.Count) { $m += "`n`nŞu ayarlar daha sonra etkili olur:`n" + ($later -join "`n") }
    if ($fail.Count) { $m += "`n`nBaşarısız (değişiklik geri alındı):`n" + ($fail -join "`n") }
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

function Restore-Tweaks([string[]]$ids) {
    $recs = @(Read-TweakBackup)
    $pending = @(for ($i = $recs.Count - 1; $i -ge 0; $i--) { if ($recs[$i].GeriYuklendi -ne $true) { $recs[$i] } })
    if ($ids) { $pending = @($pending | Where-Object { $ids -contains $_.Ayar }) }
    if ($pending.Count -eq 0) { [L10nMsg]::Show('Geri yüklenecek kayıt yok.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $doneIds = @{}; $toRestore = @()
    foreach ($r in $pending) {
        if ($ids) { if ($doneIds.ContainsKey($r.Ayar)) { continue }; $doneIds[$r.Ayar] = $true }
        $toRestore += $r
    }
    $msg = "$($toRestore.Count) değişiklik geri yüklenecek (en yeniden eskiye):`n`n" + (($toRestore | ForEach-Object { "$($_.Adi): $($_.Islem)" }) -join "`n") + "`n`nDevam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Geri yükle', 'YesNo', 'Question') -ne 'Yes') { return }
    $done = 0; $fail = @()
    foreach ($r in $toRestore) {
        try {
            Restore-TweakPrev $r.Prev
            $r.GeriYuklendi = $true; $done++
            Write-Log "Windows ayarı geri yüklendi: $($r.Adi)"
        } catch { $fail += "$($r.Adi): $($_.Exception.Message)" }
    }
    Save-TweakBackup $recs
    Update-TweakList
    $m = "$done değişiklik geri yüklendi."
    if ($fail.Count) { $m += "`n`nBaşarısız:`n" + ($fail -join "`n") }
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

function Invoke-ApplyPowerPlan {
    $i = $cmbPower.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:Plans.Count) { [L10nMsg]::Show('Önce bir güç planı seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $p = $script:Plans[$i]
    if ($p.Active) { [L10nMsg]::Show('Bu plan zaten etkin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $msg = "Güç planı '$($p.Name)' olarak değiştirilecek.`n`n" + (Get-PlanText $p.Guid $p.Name) + "`n`nÖnceki plan yedeklenir. Devam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Güç planı', 'YesNo', 'Question') -ne 'Yes') { return }
    try {
        $cur = Get-ActivePowerGuid
        Set-PowerPlanByGuid $p.Guid
        Add-TweakBackup 'power' 'Güç planı' ("Plan değiştirildi: " + $p.Name) @([pscustomobject]@{ Kind = 'Power'; Guid = $cur })
        Write-Log "Güç planı değiştirildi: $($p.Name)"
    } catch {
        [L10nMsg]::Show('Güç planı değiştirilemedi: ' + $_.Exception.Message, 'WinOpt Suite - Developed by Leone') | Out-Null
    }
    Update-TweakList
}

function Add-UltimatePlan {
    $msg = "Nihai Performans güç planı Windows'a eklenecek (otomatik etkinleştirilmez). Bu cihazda desteklenmeyebilir ve dizüstünde önerilmez.`n`nDevam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Güç planı ekle', 'YesNo', 'Question') -ne 'Yes') { return }
    $o = & powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { [L10nMsg]::Show('Plan eklenemedi (bu cihaz desteklemiyor olabilir):' + "`n" + $o.Trim(), 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    Write-Log 'Nihai Performans güç planı eklendi'
    Update-PowerList
    [L10nMsg]::Show('Plan eklendi. Listeden seçip uygulayabilirsiniz.', 'WinOpt Suite - Developed by Leone') | Out-Null
}

$script:FeatureInfo = @{
    'Microsoft-Hyper-V-All' = @('Hyper-V', 'Sanal makineler çalıştırır.', 'Etkinse sanallaştırma tabanlı güvenlik ile birlikte bazı oyunlarda küçük performans kaybı oluşabilir. Sanal makine kullanmıyorsanız gerekmeyebilir.')
    'HypervisorPlatform' = @('Windows Hipervizör Platformu', 'Üçüncü taraf sanallaştırma ve emülatörlerin Hyper-V katmanını kullanmasını sağlar.', 'Etkin olduğunda hipervizör katmanı çalışır; küçük bir ek yük oluşturabilir.')
    'VirtualMachinePlatform' = @('Sanal Makine Platformu', 'WSL 2 ve bazı Android alt sistemleri için gerekir.', 'WSL 2 veya emülatör kullanmıyorsanız gerekmez; etkinken hipervizör katmanı çalışabilir.')
    'Microsoft-Windows-Subsystem-Linux' = @('Linux için Windows Alt Sistemi', 'Windows içinde Linux araçları çalıştırır.', 'Kullanmıyorsanız kapalı kalabilir; doğrudan performans etkisi küçüktür.')
    'Containers-DisposableClientVM' = @('Windows Sandbox', 'Tek kullanımlık yalıtılmış masaüstü ortamı sunar.', 'Hyper-V altyapısına dayanır; kullanmıyorsanız gerekmez.')
    'SMB1Protocol' = @('SMB 1.0/CIFS', 'Çok eski ağ paylaşım protokolü.', 'Bilinen güvenlik açıkları vardır; eski cihaz gerekmiyorsa kapalı olması önerilir.')
    'TelnetClient' = @('Telnet İstemcisi', 'Şifresiz uzak bağlantı aracı.', 'Gerekmiyorsa kapalı kalması önerilir.')
    'TFTP' = @('TFTP İstemcisi', 'Basit dosya aktarım protokolü istemcisi.', 'Gerekmiyorsa kapalı kalabilir.')
    'Internet-Explorer-Optional-amd64' = @('Internet Explorer 11', 'Eski web tarayıcısı.', 'Güvenlik güncellemesi almaz; gerekmiyorsa kapalı olması önerilir.')
    'MicrosoftWindowsPowerShellV2Root' = @('PowerShell 2.0', 'Eski PowerShell sürümü.', 'Eski ve denetimi zayıf bir ortamdır; gerekmiyorsa kapalı olması önerilir.')
    'MicrosoftWindowsPowerShellV2' = @('PowerShell 2.0 motoru', 'Eski PowerShell motoru.', 'Gerekmiyorsa kapalı olması önerilir.')
    'NetFx3' = @('.NET Framework 3.5', 'Eski uygulama ve oyunların çalışması için gerekebilir.', 'Eski program kullanıyorsanız kapatmayın.')
    'MediaPlayback' = @('Medya Özellikleri', 'Windows Media Player ve ilgili medya bileşenlerini içerir.', 'Medya oynatma uygulamaları bu bileşenlere bağlı olabilir.')
    'WindowsMediaPlayer' = @('Windows Media Player', 'Eski medya oynatıcı.', 'Kullanmıyorsanız kapalı kalabilir.')
    'Printing-PrintToPDFServices-Features' = @('PDF olarak yazdır', 'Yazdırma menüsünde PDF çıktı yazıcısı sağlar.', 'Kapatırsanız PDF olarak yazdırma kaybolur.')
    'Printing-XPSServices-Features' = @('XPS Hizmetleri', 'XPS belge yazıcısı ve görüntüleyicisi.', 'XPS kullanmıyorsanız gerekmez.')
    'WorkFolders-Client' = @('Çalışma Klasörleri İstemcisi', 'Kurumsal klasör eşitleme.', 'Kurumsal kullanım dışında gerekmez.')
    'DirectPlay' = @('DirectPlay', 'Çok eski oyunların ağ bileşeni.', 'Eski oyun oynuyorsanız gerekebilir.')
    'LegacyComponents' = @('Eski Bileşenler', 'Eski oyun ve programlar için uyumluluk bileşenleri.', 'Eski yazılım kullanıyorsanız gerekebilir.')
    'Windows-Defender-ApplicationGuard' = @('Microsoft Defender Application Guard', 'Tarayıcıyı yalıtılmış sanal ortamda çalıştırır.', 'Hyper-V altyapısı kullanır; kaynak tüketimi artabilir.')
    'IIS-WebServerRole' = @('Internet Information Services', 'Yerel web sunucusu.', 'Web sunucusu geliştirmiyorsanız gerekmez; açık hizmet güvenlik yüzeyini artırır.')
    'SearchEngine-Client-Package' = @('Windows Arama', 'Dosya dizinleme ve arama hizmeti.', 'Kapatılırsa arama yavaşlar veya çalışmaz.')
}

function Show-OptionalFeatures {
    $form.Cursor = 'WaitCursor'
    $feats = @()
    try { $feats = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop) }
    catch {
        $form.Cursor = 'Default'
        [L10nMsg]::Show('İsteğe bağlı özellikler okunamadı: ' + $_.Exception.Message, 'WinOpt Suite - Developed by Leone') | Out-Null
        return
    }
    $form.Cursor = 'Default'
    $rows = foreach ($f in $feats) {
        $name = [string]$f.FeatureName
        $info = $script:FeatureInfo[$name]
        $state = switch ([string]$f.State) { 'Enabled' { 'Etkin' } 'Disabled' { 'Devre dışı' } default { [string]$f.State } }
        [pscustomobject]@{
            Name = $name; State = $state; Known = [bool]$info
            Title = $(if ($info) { $info[0] } else { $name })
            What = $(if ($info) { $info[1] } else { 'Windows isteğe bağlı bileşeni.' })
            Effect = $(if ($info) { $info[2] } else { 'Ayrıntı için Microsoft belgelerine bakın; ne işe yaradığını bilmiyorsanız değiştirmeyin.' })
        }
    }
    $script:FeatRows = @($rows | Sort-Object @{ e = { $_.State -eq 'Etkin' }; Descending = $true }, Title)
    $d = New-Object Windows.Forms.Form
    $d.Text = "İsteğe bağlı Windows özellikleri ($($script:FeatRows.Count))"; $d.Size = New-Object Drawing.Size(1150, 560); $d.StartPosition = 'CenterParent'
    $script:FeatGrid = New-StdGrid @(@('Özellik', 230), @('Durum', 90), @('Ne yapar', 360), @('Olası etkiler / öneri', 430))
    $d.Controls.Add($script:FeatGrid)
    $pnl = New-Object Windows.Forms.FlowLayoutPanel
    $pnl.Dock = 'Top'; $pnl.Height = 40; $pnl.Padding = New-Object Windows.Forms.Padding(6)
    $d.Controls.Add($pnl)
    $lbl = New-StatusLabel
    $lbl.Text = '  Bu pencere yalnızca incelemek içindir; hiçbir özellik değiştirilmez.'
    $d.Controls.Add($lbl)
    $script:FeatFill = {
        $script:FeatGrid.Rows.Clear()
        foreach ($r in $script:FeatRows) {
            if ($script:FeatChkOn.Checked -and $r.State -ne 'Etkin') { continue }
            if ($script:FeatChkKnown.Checked -and -not $r.Known) { continue }
            $i = $script:FeatGrid.Rows.Add([object[]]@($r.Title, $r.State, $r.What, $r.Effect))
            if ($r.State -ne 'Etkin') { $script:FeatGrid.Rows[$i].DefaultCellStyle.ForeColor = [Drawing.Color]::Gray }
        }
    }
    $script:FeatChkOn = New-Chk $pnl 'Yalnızca etkin olanlar' $true { & $script:FeatFill }
    $script:FeatChkKnown = New-Chk $pnl 'Yalnızca açıklaması bilinenler' $false { & $script:FeatFill }
    New-Btn $pnl "Windows'ta Aç/Kapat Penceresi" 210 { Start-Process optionalfeatures.exe }
    & $script:FeatFill
    [void]$d.ShowDialog($form)
}

$gridTw = New-StdGrid @(
    @('Ayar', 250), @('Kategori', 110), @('Şu anki durum', 150), @('Önerilen', 150), @('Düzey', 80), @('Etkili olma', 150),
    @('Ne yapar', 420), @('Olası etkiler', 460), @('Not', 90))
$tabTweak = New-Object Windows.Forms.TabPage
$tabTweak.Text = 'Windows Ayarları'
[void]$tabs.TabPages.Add($tabTweak)
$tabTweak.Controls.Add($gridTw)

$txtTwInfo = New-Object Windows.Forms.TextBox
$txtTwInfo.Multiline = $true; $txtTwInfo.ReadOnly = $true; $txtTwInfo.ScrollBars = 'Vertical'
$txtTwInfo.Dock = 'Bottom'; $txtTwInfo.Height = 120; $txtTwInfo.BackColor = [Drawing.Color]::White
$tabTweak.Controls.Add($txtTwInfo)

$barTw = New-Bar
$barTw.Height = 116
$tabTweak.Controls.Add($barTw)
$lblTw = New-StatusLabel
$tabTweak.Controls.Add($lblTw)

$gridTw.Add_SelectionChanged({ try { Show-TweakDetail } catch {} })

New-Btn $barTw 'Yenile' 70 { Update-TweakList }
New-Btn $barTw 'Önerilen Ayarı Uygula' 160 { Invoke-ApplySelectedTweaks }
New-Btn $barTw 'Önceki Ayara Dön' 130 {
    $ids = @(Get-SelectedTweaks | ForEach-Object { $_.Tw.Id })
    if ($ids.Count -eq 0) { [L10nMsg]::Show('Önce listeden ayar seçin veya Tümünü Geri Al düğmesini kullanın.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    Restore-Tweaks $ids
}
New-Btn $barTw 'Tümünü Geri Al' 110 { Restore-Tweaks $null }
New-Btn $barTw 'Değişiklik Geçmişi' 130 {
    $recs = @(Read-TweakBackup)
    $tmp = Join-Path $AppDir 'ayar-degisiklikleri.csv'
    if ($recs.Count -gt 0) { $recs | Select-Object Zaman, Adi, Islem, GeriYuklendi | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding UTF8 }
    Show-CsvDialog $tmp 'Windows ayar değişiklik geçmişi'
}
New-Btn $barTw 'İsteğe Bağlı Özellikleri İncele' 200 { Show-OptionalFeatures }
New-Btn $barTw 'Uygulama Bazlı Arka Plan Ayarı' 200 {
    $uri = if ([Environment]::OSVersion.Version.Build -ge 22000) { 'ms-settings:appsfeatures' } else { 'ms-settings:privacy-backgroundapps' }
    Start-Process $uri
}
$cmbPower = New-Object Windows.Forms.ComboBox
$cmbPower.DropDownStyle = 'DropDownList'; $cmbPower.Width = 230; $cmbPower.Margin = New-Object Windows.Forms.Padding(8, 5, 0, 0)
$barTw.Controls.Add($cmbPower)
$cmbPower.Add_SelectedIndexChanged({ try { Show-PowerInfo } catch {} })
New-Btn $barTw 'Güç Planını Uygula' 130 { Invoke-ApplyPowerPlan }
New-Btn $barTw 'Önceki Plana Dön' 120 { Restore-Tweaks @('power') }
New-Btn $barTw 'Nihai Performans Planı Ekle' 190 { Add-UltimatePlan }
$chkTwDiff = New-Chk $barTw 'Yalnızca önerilenden farklı olanlar' $false { if ($script:TweakLoaded) { Update-TweakList } }
