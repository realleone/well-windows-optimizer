$BrowserBackupRoot = Join-Path $AppDir 'tarayici-yedekleri'
$BrowserHistFile   = Join-Path $AppDir 'tarayici-temizlik-gecmisi.csv'
$script:BrResults  = @()
$script:BrBusy     = $false
$script:BrLoading  = $false
$script:BrWarned   = $false
$script:SqlOk      = $null
$script:BrInfo    = ''

$script:SqliteCs = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class WinOptSqlite
{
    const string Dll = "winsqlite3.dll";
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_busy_timeout(IntPtr db, int ms);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_exec(IntPtr db, byte[] sql, IntPtr cb, IntPtr arg, out IntPtr err);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr sqlite3_errmsg(IntPtr db);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int n, out IntPtr stmt, IntPtr tail);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt, int col);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern void sqlite3_free(IntPtr p);
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr sqlite3_libversion();

    static byte[] U8(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }

    static string PtrU8(IntPtr p)
    {
        if (p == IntPtr.Zero) return null;
        int n = 0;
        while (Marshal.ReadByte(p, n) != 0) n++;
        byte[] b = new byte[n];
        Marshal.Copy(p, b, 0, n);
        return Encoding.UTF8.GetString(b);
    }

    static IntPtr Open(string path, bool write)
    {
        IntPtr db;
        int rc = sqlite3_open_v2(U8(path), out db, write ? 2 : 1, IntPtr.Zero);
        if (rc != 0)
        {
            string m = PtrU8(sqlite3_errmsg(db));
            if (db != IntPtr.Zero) sqlite3_close(db);
            throw new Exception("open: " + m);
        }
        sqlite3_busy_timeout(db, 1500);
        return db;
    }

    public static string Version() { return PtrU8(sqlite3_libversion()); }

    public static string Scalar(string path, string sql)
    {
        IntPtr db = Open(path, false);
        try
        {
            IntPtr st;
            int rc = sqlite3_prepare_v2(db, U8(sql), -1, out st, IntPtr.Zero);
            if (rc != 0) throw new Exception(PtrU8(sqlite3_errmsg(db)));
            try
            {
                if (sqlite3_step(st) == 100) return PtrU8(sqlite3_column_text(st, 0));
                return null;
            }
            finally { sqlite3_finalize(st); }
        }
        finally { sqlite3_close(db); }
    }

    public static string[] Exec(string path, string[] statements)
    {
        List<string> errs = new List<string>();
        IntPtr db = Open(path, true);
        try
        {
            foreach (string s in statements)
            {
                IntPtr err;
                int rc = sqlite3_exec(db, U8(s), IntPtr.Zero, IntPtr.Zero, out err);
                if (err != IntPtr.Zero) sqlite3_free(err);
                if (rc != 0) errs.Add(PtrU8(sqlite3_errmsg(db)) + " [" + s + "]");
            }
        }
        finally { sqlite3_close(db); }
        return errs.ToArray();
    }
}
'@

function Initialize-Sqlite {
    if ($null -ne $script:SqlOk) { return $script:SqlOk }
    try {
        if (-not ('WinOptSqlite' -as [type])) { Add-Type -TypeDefinition $script:SqliteCs -Language CSharp -ErrorAction Stop }
        $v = [WinOptSqlite]::Version()
        if (-not $v) { throw 'sürüm okunamadı' }
        $script:SqlOk = $true
    } catch {
        $script:SqlOk = $false
        Write-Log ('SQLite bileşeni yüklenemedi: ' + $_.Exception.Message)
    }
    return $script:SqlOk
}

$tabBrowser = New-Object Windows.Forms.TabPage
$tabBrowser.Text = 'Tarayıcılar'
[void]$tabs.TabPages.Add($tabBrowser)

$gridBr = New-StdGrid @(@('Seç', 45), @('Tarayıcı', 130), @('Veri türü', 230), @('Profil', 55), @('Öğe', 75), @('Boyut', 90), @('Durum', 230), @('Açıklama', 700))
$gridBr.Columns.RemoveAt(0)
$ccBr = New-Object Windows.Forms.DataGridViewCheckBoxColumn
$ccBr.HeaderText = 'Seç'; $ccBr.Width = 45
$gridBr.Columns.Insert(0, $ccBr)
$gridBr.ReadOnly = $false
$gridBr.MultiSelect = $false
for ($bi = 1; $bi -lt $gridBr.Columns.Count; $bi++) { $gridBr.Columns[$bi].ReadOnly = $true }
$gridBr.Columns[4].DefaultCellStyle.Format = 'N0'
$gridBr.Columns[4].SortMode = 'NotSortable'
$gridBr.Columns[5].SortMode = 'NotSortable'
$tabBrowser.Controls.Add($gridBr)

$lblBrStatus = New-StatusLabel
$lblBrStatus.Text = '  Taramak için "Tara" düğmesine basın.'
$tabBrowser.Controls.Add($lblBrStatus)

$barBr = New-Bar
$tabBrowser.Controls.Add($barBr)

$lblBrWarn = New-Object Windows.Forms.Label
$lblBrWarn.Dock = 'Top'; $lblBrWarn.Height = 44; $lblBrWarn.ForeColor = [Drawing.Color]::Firebrick
$lblBrWarn.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$lblBrWarn.Text = '  DİKKAT: Çerezleri veya oturum verilerini silmek, web sitelerindeki oturumlarınızı KAPATIR (hesaplarınıza yeniden giriş yapmanız gerekebilir). Bu seçenekler varsayılan olarak KAPALIDIR.' + [Environment]::NewLine +
    '  Tarayıcı açıkken o tarayıcıya dokunulmaz; tarayıcılar bu araç tarafından kapatılmaz. Kullanıcı verisi silinmeden önce yedeklenir.'
$tabBrowser.Controls.Add($lblBrWarn)

$script:BrKinds = @(
    @{ K = 'cache';     N = 'Tarayıcı önbelleği';           C = $true;  Note = 'Sitelerin önbelleğe aldığı dosyalar. Siteler ilk açılışta biraz yavaş yüklenebilir.' },
    @{ K = 'temp';      N = 'Geçici internet dosyaları';    C = $true;  Note = 'Medya/uygulama önbelleği, başlangıç önbelleği, küçük resimler, çökme raporları.' },
    @{ K = 'cookies';   N = 'Çerezler';                     C = $false; Note = 'UYARI: Oturumlarınız kapanabilir. "Korunacak siteler" kutusundakiler hariç tutulabilir.' },
    @{ K = 'downloads'; N = 'İndirme geçmişi';              C = $false; Note = 'Yalnızca listeyi siler; indirilen dosyalara dokunulmaz.' },
    @{ K = 'history';   N = 'Tarayıcı geçmişi';             C = $false; Note = 'Ziyaret geçmişi. Chrome/Edge''de indirme geçmişi de aynı dosyada olduğu için birlikte silinir. Yer imleri korunur.' },
    @{ K = 'session';   N = 'Oturum verileri (sekmeler)';   C = $false; Note = 'UYARI: Açık sekmelerin geri yüklenmesi ve oturum verileri silinir; oturumlarınız kapanabilir.' }
)

function Get-BrowserDefs {
    $la = $env:LOCALAPPDATA; $ra = $env:APPDATA
    return @(
        @{ Key = 'chrome';  Name = 'Google Chrome';  Type = 'chromium'; UserData = (Join-Path $la 'Google\Chrome\User Data');    Procs = @('chrome') },
        @{ Key = 'edge';    Name = 'Microsoft Edge'; Type = 'chromium'; UserData = (Join-Path $la 'Microsoft\Edge\User Data');   Procs = @('msedge') },
        @{ Key = 'firefox'; Name = 'Mozilla Firefox'; Type = 'firefox'; Roaming = (Join-Path $ra 'Mozilla\Firefox\Profiles'); Local = (Join-Path $la 'Mozilla\Firefox\Profiles'); Procs = @('firefox') }
    )
}

function Test-BrowserRunning($b) {
    return (@(Get-Process -Name $b.Procs -ErrorAction SilentlyContinue).Count -gt 0)
}

function Get-BrowserProfiles($b) {
    $out = @()
    try {
        if ($b.Type -eq 'chromium') {
            foreach ($d in (Get-ChildItem -LiteralPath $b.UserData -Directory -ErrorAction SilentlyContinue)) {
                if ($d.Name -match '^(Default|Profile \d+)$') { $out += $d.FullName }
            }
        } else {
            foreach ($d in (Get-ChildItem -LiteralPath $b.Roaming -Directory -ErrorAction SilentlyContinue)) {
                $out += @{ R = $d.FullName; L = (Join-Path $b.Local $d.Name) }
            }
        }
    } catch {}
    return $out
}

function Get-BrowserTargets($b, $profiles, [string]$kind) {
    $roots = @(); $dbs = @()
    if ($b.Type -eq 'chromium') {
        switch ($kind) {
            'cache' {
                foreach ($p in $profiles) { foreach ($s in 'Cache', 'Code Cache', 'GPUCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'Service Worker\CacheStorage', 'Service Worker\ScriptCache') { $roots += (New-CleanRoot (Join-Path $p $s)) } }
                foreach ($s in 'ShaderCache', 'GrShaderCache', 'GraphiteDawnCache') { $roots += (New-CleanRoot (Join-Path $b.UserData $s)) }
            }
            'temp' {
                foreach ($p in $profiles) { foreach ($s in 'Media Cache', 'Application Cache') { $roots += (New-CleanRoot (Join-Path $p $s)) } }
                $roots += (New-CleanRoot (Join-Path $b.UserData 'Crashpad\reports'))
            }
            'cookies' {
                foreach ($p in $profiles) {
                    $roots += (New-CleanRoot (Join-Path $p 'Network') $false @('Cookies', 'Cookies-journal'))
                    $roots += (New-CleanRoot $p $false @('Cookies', 'Cookies-journal'))
                    foreach ($c in (Join-Path $p 'Network\Cookies'), (Join-Path $p 'Cookies')) {
                        if (Test-Path -LiteralPath $c -PathType Leaf) { $dbs += @{ Path = $c; Table = 'cookies'; Col = 'host_key' }; break }
                    }
                }
            }
            'downloads' {
                foreach ($p in $profiles) {
                    $h = Join-Path $p 'History'
                    if (Test-Path -LiteralPath $h -PathType Leaf) {
                        $dbs += @{ Path = $h; Sql = @('DELETE FROM downloads_url_chains', 'DELETE FROM downloads_slices', 'DELETE FROM downloads'); CountSql = 'SELECT COUNT(*) FROM downloads' }
                    }
                }
            }
            'history' {
                foreach ($p in $profiles) {
                    $roots += (New-CleanRoot $p $false @('History', 'History-journal', 'Top Sites', 'Top Sites-journal', 'Visited Links', 'Shortcuts', 'Shortcuts-journal', 'Network Action Predictor', 'Network Action Predictor-journal'))
                }
            }
            'session' {
                foreach ($p in $profiles) {
                    $roots += (New-CleanRoot (Join-Path $p 'Sessions'))
                    $roots += (New-CleanRoot (Join-Path $p 'Session Storage'))
                    $roots += (New-CleanRoot $p $false @('Current Session', 'Current Tabs', 'Last Session', 'Last Tabs'))
                }
            }
        }
    } else {
        foreach ($p in $profiles) {
            switch ($kind) {
                'cache' { $roots += (New-CleanRoot (Join-Path $p.L 'cache2')) }
                'temp' { foreach ($s in 'startupCache', 'thumbnails', 'offlineCache', 'jumpListCache') { $roots += (New-CleanRoot (Join-Path $p.L $s)) } }
                'cookies' {
                    $roots += (New-CleanRoot $p.R $false @('cookies.sqlite', 'cookies.sqlite-wal', 'cookies.sqlite-shm'))
                    $c = Join-Path $p.R 'cookies.sqlite'
                    if (Test-Path -LiteralPath $c -PathType Leaf) { $dbs += @{ Path = $c; Table = 'moz_cookies'; Col = 'host' } }
                }
                'downloads' {
                    $pl = Join-Path $p.R 'places.sqlite'
                    if (Test-Path -LiteralPath $pl -PathType Leaf) {
                        $dbs += @{ Path = $pl
                            Sql = @("DELETE FROM moz_annos WHERE anno_attribute_id IN (SELECT id FROM moz_anno_attributes WHERE name LIKE 'downloads/%')")
                            CountSql = "SELECT COUNT(*) FROM moz_annos WHERE anno_attribute_id IN (SELECT id FROM moz_anno_attributes WHERE name = 'downloads/metaData')" }
                    }
                }
                'history' {
                    $pl = Join-Path $p.R 'places.sqlite'
                    if (Test-Path -LiteralPath $pl -PathType Leaf) {
                        $dbs += @{ Path = $pl
                            Sql = @('PRAGMA foreign_keys=ON', 'DELETE FROM moz_historyvisits', 'DELETE FROM moz_inputhistory',
                                'DELETE FROM moz_places WHERE foreign_count = 0',
                                'UPDATE moz_places SET visit_count = 0, last_visit_date = NULL, frecency = -1 WHERE foreign_count > 0',
                                'DELETE FROM moz_annos WHERE place_id NOT IN (SELECT id FROM moz_places)',
                                'DELETE FROM moz_origins WHERE id NOT IN (SELECT origin_id FROM moz_places)')
                            CountSql = 'SELECT COUNT(*) FROM moz_historyvisits' }
                    }
                }
                'session' {
                    $roots += (New-CleanRoot (Join-Path $p.R 'sessionstore-backups'))
                    $roots += (New-CleanRoot $p.R $false @('sessionstore.jsonlz4', 'sessionstore.js', 'sessionCheckpoints.json'))
                }
            }
        }
    }
    return @{ Roots = $roots; Dbs = $dbs }
}

function Invoke-SqlScalar([string]$db, [string]$sql) {
    try { return [WinOptSqlite]::Scalar($db, $sql) } catch { return $null }
}

function Search-BrowserKind($b, $kdef, $profiles, [bool]$running) {
    $t = Get-BrowserTargets $b $profiles $kdef.K
    $files = New-Object 'System.Collections.Generic.List[object]'
    $dirs  = New-Object 'System.Collections.Generic.List[string]'
    $ctr   = @{ Bytes = [long]0; Denied = 0; Young = 0 }
    $used  = @()
    foreach ($r in $t.Roots) {
        if ($script:ClCancel) { break }
        $rp = Resolve-CleanRoot $r ''
        if (-not $rp) { continue }
        $used += $rp
        Add-CleanFolderScan $rp $r $null $files $dirs $ctr
    }

    $sqlOnly = ($t.Roots.Count -eq 0 -and $t.Dbs.Count -gt 0)
    $rows = $null
    if ($sqlOnly -and $script:SqlOk -and -not $running) {
        $rows = 0
        foreach ($db in $t.Dbs) {
            if ($db.CountSql) { $v = Invoke-SqlScalar $db.Path $db.CountSql; if ($v) { $rows += [int]$v } }
        }
    }
    $count = if ($sqlOnly) { $(if ($null -ne $rows) { $rows } else { 0 }) } else { $files.Count }

    $status = 'Hazır'
    if ($running) { $status = 'Tarayıcı AÇIK: atlanır' }
    elseif ($sqlOnly -and -not $script:SqlOk) { $status = 'SQLite bileşeni yok: atlanır' }
    elseif ($sqlOnly -and $t.Dbs.Count -gt 0 -and $null -eq $rows) { $status = 'Hazır (kayıt sayısı okunamadı)' }
    elseif ($count -eq 0) { $status = 'Temiz / bulunamadı' }

    $canClean = (-not $running) -and (($sqlOnly -and $script:SqlOk -and $t.Dbs.Count -gt 0) -or ((-not $sqlOnly) -and $files.Count -gt 0) -or ($kdef.K -eq 'cookies' -and $t.Dbs.Count -gt 0 -and $script:SqlOk))
    return [pscustomobject]@{
        Browser = $b; Kdef = $kdef; Kind = $kdef.K; Files = $files; Dirs = $dirs; Roots = $used; Dbs = $t.Dbs
        Bytes = [long]$ctr.Bytes; Count = $count; SqlOnly = $sqlOnly; Status = $status; CanClean = $canClean
        Profiles = @($profiles).Count; Running = $running; Checked = [bool]$kdef.C
    }
}

function Invoke-BrowserScan {
    if ($script:BrBusy) { return }
    $script:BrBusy = $true; $script:ClCancel = $false; $script:BrWarned = $false
    $form.Cursor = 'WaitCursor'; $script:Timer.Stop()
    try {
        [void](Initialize-Sqlite)
        $res = @(); $info = @()
        foreach ($b in (Get-BrowserDefs)) {
            $base = if ($b.Type -eq 'chromium') { $b.UserData } else { $b.Roaming }
            if (-not (Test-Path -LiteralPath $base)) { $info += "$($b.Name): kurulu değil"; continue }
            $running = Test-BrowserRunning $b
            $info += ("$($b.Name): " + $(if ($running) { 'AÇIK' } else { 'kapalı' }))
            $profiles = @(Get-BrowserProfiles $b)
            foreach ($kdef in $script:BrKinds) {
                $lblBrStatus.Text = "  Taranıyor: $($b.Name) - $($kdef.N) ..."
                [Windows.Forms.Application]::DoEvents()
                $res += Search-BrowserKind $b $kdef $profiles $running
            }
        }
        $script:BrResults = $res
        $script:BrInfo = ($info -join '  |  ')
        Show-BrowserGrid
    } catch {
        $lblBrStatus.Text = '  Tarama hatası: ' + $_.Exception.Message
        Write-Log ('Tarayıcı tarama hatası: ' + $_.Exception.Message)
    } finally { $form.Cursor = 'Default'; $script:Timer.Start(); $script:BrBusy = $false }
}

function Show-BrowserGrid {
    $script:BrLoading = $true
    try {
        $gridBr.Rows.Clear()
        foreach ($r in $script:BrResults) {
            $size = if ($r.SqlOnly) { '—' } else { Format-Bytes $r.Bytes }
            $on = ($r.Checked -and $r.CanClean)
            $i = $gridBr.Rows.Add([object[]]@($on, $r.Browser.Name, $r.Kdef.N, $r.Profiles, $r.Count, $size, $r.Status, $r.Kdef.Note))
            $row = $gridBr.Rows[$i]; $row.Tag = $r
            if (-not $r.CanClean) { $row.Cells[0].ReadOnly = $true; $row.DefaultCellStyle.ForeColor = [Drawing.Color]::Gray }
            elseif ($r.Kind -eq 'cookies' -or $r.Kind -eq 'session') { $row.DefaultCellStyle.BackColor = [Drawing.Color]::LightYellow }
        }
    } finally { $script:BrLoading = $false }
    Update-BrowserTotals
}

function Update-BrowserTotals {
    if ($script:BrLoading) { return }
    $n = 0; $bytes = [long]0
    foreach ($row in $gridBr.Rows) {
        $r = $row.Tag
        if (-not $r) { continue }
        $on = ($row.Cells[0].Value -eq $true)
        $r.Checked = $on
        if ($on) { $n++; if (-not $r.SqlOnly) { $bytes += $r.Bytes } }
    }
    $lblBrStatus.Text = ('  Seçili: {0} öğe, yaklaşık {1}   |   {2}' -f $n, (Format-Bytes $bytes), $script:BrInfo)
}

function Get-KeepDomains {
    $out = @()
    foreach ($t in ($txtBrKeep.Text -split '[,;\s]+')) {
        if (-not $t) { continue }
        $d = ($t.Trim().ToLower() -replace '^[a-z]+://', '' -replace '/.*$', '' -replace '^\*?\.', '')
        if ($d -match '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$') { $out += $d }
    }
    return @($out | Select-Object -Unique)
}

function Get-CookieKeepSql([string]$table, [string]$col, $domains) {
    $c = @()
    foreach ($d in $domains) { $c += ("{0} = '{1}' OR {0} = '.{1}' OR {0} LIKE '%.{1}'" -f $col, $d) }
    return ('DELETE FROM {0} WHERE NOT ({1})' -f $table, ($c -join ' OR '))
}

$script:BrBkDir = $null
$script:BrManifest = $null

function Start-BrowserBackup {
    New-Item -ItemType Directory -Path $BrowserBackupRoot -Force | Out-Null
    $script:BrBkDir = Join-Path $BrowserBackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $script:BrBkDir -Force | Out-Null
    $script:BrManifest = New-Object 'System.Collections.Generic.List[object]'
}

function Backup-BrowserFile([string]$src, [bool]$isDb) {
    $name = '{0:D4}_{1}' -f ($script:BrManifest.Count + 1), [IO.Path]::GetFileName($src)
    Copy-Item -LiteralPath $src -Destination (Join-Path $script:BrBkDir $name) -ErrorAction Stop
    $script:BrManifest.Add([pscustomobject]@{ Original = $src; Yedek = $name; Db = $isDb })
}

function Save-BrowserManifest {
    if ($script:BrManifest -and $script:BrManifest.Count -gt 0) {
        ConvertTo-Json -InputObject @($script:BrManifest.ToArray()) -Depth 3 | Set-Content -LiteralPath (Join-Path $script:BrBkDir 'manifest.json') -Encoding UTF8

        try { Get-ChildItem -LiteralPath $BrowserBackupRoot -Directory | Sort-Object Name -Descending | Select-Object -Skip 5 | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
    } elseif ($script:BrBkDir -and (Test-Path -LiteralPath $script:BrBkDir)) {
        Remove-Item -LiteralPath $script:BrBkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-DbCleanup([string]$db, $stmts) {
    $side = @($db) + @("$db-wal", "$db-shm", "$db-journal") | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    $first = $true
    $saved = @()
    try {
        foreach ($f in $side) { Backup-BrowserFile $f $first; $first = $false }
    } catch { return @{ Ok = $false; Msg = 'Yedek alınamadı, değiştirilmedi.' } }
    $entries = @($script:BrManifest | Select-Object -Last @($side).Count)
    try {
        $errs = @([WinOptSqlite]::Exec($db, [string[]]$stmts))
        $real = @($errs | Where-Object { $_ -and ($_ -notmatch 'no such (table|column)') })
        $chk = [WinOptSqlite]::Scalar($db, 'PRAGMA quick_check')
        if ($chk -ne 'ok') { throw "bütünlük kontrolü: $chk" }
        if ($real.Count -gt 0) { return @{ Ok = $false; Msg = ('Kısmen uygulandı: ' + $real[0]) } }
        return @{ Ok = $true; Msg = '' }
    } catch {
        $m = $_.Exception.Message
        try {
            foreach ($e in $entries) { Copy-Item -LiteralPath (Join-Path $script:BrBkDir $e.Yedek) -Destination $e.Original -Force -ErrorAction Stop }
            return @{ Ok = $false; Msg = "Hata ($m); yedekten geri alındı." }
        } catch { return @{ Ok = $false; Msg = "Hata ($m); geri alma da başarısız, yedek: $script:BrBkDir" } }
    }
}

function Invoke-BrowserClean {
    if ($script:BrBusy) { return }
    $sel = @($gridBr.Rows | Where-Object { $_.Cells[0].Value -eq $true } | ForEach-Object { $_.Tag } | Where-Object { $_ -and $_.CanClean })
    if ($sel.Count -eq 0) { [L10nMsg]::Show('Önce taratıp temizlenecek öğeleri seçin.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }

    $runNow = @{}
    foreach ($b in (Get-BrowserDefs)) { $runNow[$b.Key] = Test-BrowserRunning $b }
    $blocked = @($sel | Where-Object { $runNow[$_.Browser.Key] })
    $sel = @($sel | Where-Object { -not $runNow[$_.Browser.Key] })
    if ($sel.Count -eq 0) {
        [L10nMsg]::Show("Seçili tarayıcılar şu anda açık. Tarayıcıyı kendiniz kapatıp (arka plan işlemleri dahil) yeniden tarayın.`nAçık tarayıcıdaki dosyalar zorla silinmez.", 'Tarayıcı açık') | Out-Null
        return
    }

    $keep = @(Get-KeepDomains)
    $risk = @($sel | Where-Object { $_.Kind -eq 'cookies' -or $_.Kind -eq 'session' })
    $lines = ($sel | ForEach-Object {
        $sz = if ($_.SqlOnly) { "$($_.Count) kayıt" } else { ('{0:N0} dosya, {1}' -f $_.Count, (Format-Bytes $_.Bytes)) }
        '  • {0} - {1}: {2}' -f $_.Browser.Name, $_.Kdef.N, $sz
    }) -join "`n"
    $msg = "Şu öğeler temizlenecek:`n`n$lines"
    if ($blocked.Count -gt 0) { $msg += "`n`nAÇIK OLDUĞU İÇİN ATLANACAKLAR: " + (($blocked | ForEach-Object { $_.Browser.Name } | Select-Object -Unique) -join ', ') }
    if ($risk.Count -gt 0) {
        $msg += "`n`n!! OTURUMLARINIZ KAPANABİLİR !!`nÇerez/oturum verileri silindiği için web sitelerindeki hesaplarınızdan çıkış yapılabilir; yeniden giriş yapmanız gerekebilir."
        if ($keep.Count -gt 0 -and ($risk | Where-Object { $_.Kind -eq 'cookies' })) { $msg += "`nÇerezlerde şu sitelerin kayıtları KORUNACAK: " + ($keep -join ', ') }
    }
    if (@($sel | Where-Object { $_.Kind -eq 'history' -and $_.Browser.Type -eq 'chromium' }).Count -gt 0) { $msg += "`n`nChrome/Edge geçmişi silinince indirme geçmişi de silinir (aynı dosya)." }
    if (-not $script:SqlOk -and @($sel | Where-Object { $_.Dbs.Count -gt 0 }).Count -gt 0) { $msg += "`n`nSQLite bileşeni yüklenemedi: veritabanı gerektiren işlemler atlanır." }
    $msg += "`n`nÇerez, geçmiş ve oturum verileri silinmeden önce yedeklenir (yedek alınamayan dosya silinmez):`n$BrowserBackupRoot`nKullanımdaki/erişilemeyen dosyalar zorla silinmez, atlanır. Yer imleri, şifreler ve eklentiler hedeflenmez.`n`nDevam edilsin mi?"
    if ([L10nMsg]::Show($msg, 'Tarayıcı temizliğini onayla', 'YesNo', 'Warning') -ne 'Yes') { return }

    $script:BrBusy = $true; $script:ClCancel = $false
    $form.Cursor = 'WaitCursor'; $script:Timer.Stop()
    $free0 = Get-SystemFree; $grand = [long]0; $summary = @()
    try {
        Start-BrowserBackup

        $histBrowsers = @($sel | Where-Object { $_.Kind -eq 'history' -and $_.Browser.Type -eq 'chromium' } | ForEach-Object { $_.Browser.Key })
        foreach ($r in $sel) {
            if ($script:ClCancel) { break }
            $lblBrStatus.Text = "  Temizleniyor: $($r.Browser.Name) - $($r.Kdef.N) ..."; [Windows.Forms.Application]::DoEvents()
            if ($runNow[$r.Browser.Key] -or (Test-BrowserRunning $r.Browser)) { $summary += ("  • {0} - {1}: tarayıcı açıldı, atlandı" -f $r.Browser.Name, $r.Kdef.N); continue }
            $stat = @{ ok = 0; gone = 0; changed = 0; locked = 0; denied = 0; unsafe = 0 }; $freed = [long]0; $note = ''

            if ($r.Kind -eq 'downloads' -and $r.Browser.Type -eq 'chromium' -and ($histBrowsers -contains $r.Browser.Key)) {
                $summary += ("  • {0} - {1}: geçmişle birlikte silindi" -f $r.Browser.Name, $r.Kdef.N); continue
            }

            if ($r.SqlOnly) {
                if (-not $script:SqlOk) { $summary += ("  • {0} - {1}: SQLite yok, atlandı" -f $r.Browser.Name, $r.Kdef.N); continue }
                foreach ($db in $r.Dbs) {
                    $o = Invoke-DbCleanup $db.Path $db.Sql
                    if ($o.Ok) { $stat.ok++ } else { $stat.denied++; $note += ' [' + $o.Msg + ']' }
                }
                $stat.ok = [math]::Max($stat.ok, 0)
            }
            elseif ($r.Kind -eq 'cookies' -and $keep.Count -gt 0) {
                if (-not $script:SqlOk -or $r.Dbs.Count -eq 0) { $summary += ("  • {0} - {1}: korunacak site listesi için SQLite gerekli, atlandı (hiçbir çerez silinmedi)" -f $r.Browser.Name, $r.Kdef.N); continue }
                foreach ($db in $r.Dbs) {
                    $o = Invoke-DbCleanup $db.Path @((Get-CookieKeepSql $db.Table $db.Col $keep))
                    if ($o.Ok) { $stat.ok++ } else { $stat.denied++; $note += ' [' + $o.Msg + ']' }
                }
                $note += ' (korunan: ' + ($keep -join ', ') + ')'
            }
            else {
                $needBackup = ($r.Kind -in 'cookies', 'history', 'session')
                $i = 0
                foreach ($rec in $r.Files) {
                    $i++
                    if (($i % 50) -eq 0) { [Windows.Forms.Application]::DoEvents(); if ($script:ClCancel) { break } }
                    if ($needBackup) {

                        $bk = $true
                        try { Backup-BrowserFile ([string]$rec[0]) $false } catch { $bk = $false }
                        if (-not $bk) { $stat.locked++; continue }
                    }
                    $res = Remove-CleanFile $rec $r.Roots
                    $stat[$res]++
                    if ($res -eq 'ok') { $freed += [long]$rec[1] }
                }
                if (($r.Kind -eq 'cache' -or $r.Kind -eq 'temp') -and -not $script:ClCancel) { [void](Remove-CleanEmptyDirs $r.Dirs $r.Roots $null) }
            }

            $skipped = $stat.locked + $stat.denied + $stat.changed + $stat.unsafe
            $grand += $freed
            Add-CleanHistory $BrowserHistFile ([pscustomobject][ordered]@{
                'Zaman' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); 'Kategori' = ('{0} - {1}' -f $r.Browser.Name, $r.Kdef.N)
                'Silinen' = $stat.ok; 'Atlanan' = $skipped; 'Kazanılan bayt' = $freed; 'Kazanılan alan' = (Format-Bytes $freed) })
            Write-Log ('Tarayıcı temizliği: {0} - {1}: silinen {2}, atlanan {3}, kazanılan {4}{5}' -f $r.Browser.Name, $r.Kdef.N, $stat.ok, $skipped, (Format-Bytes $freed), $note)
            $unit = if ($r.SqlOnly -or ($r.Kind -eq 'cookies' -and $keep.Count -gt 0)) { 'veritabanı işlendi' } else { 'dosya silindi' }
            $summary += ('  • {0} - {1}: {2:N0} {3}, {4:N0} atlandı, {5} kazanıldı{6}' -f $r.Browser.Name, $r.Kdef.N, $stat.ok, $unit, $skipped, (Format-Bytes $freed), $note)
        }
    } catch {
        Write-Log ('Tarayıcı temizliği hatası: ' + $_.Exception.Message)
        $summary += '  ! Hata: ' + $_.Exception.Message
    } finally {
        Save-BrowserManifest
        $form.Cursor = 'Default'; $script:Timer.Start(); $script:BrBusy = $false
    }

    Invoke-BrowserScan
    $m = "Tarayıcı temizliği tamamlandı.`n`n" + ($summary -join "`n") + ("`n`nToplam kazanılan alan: {0}`n{1} sürücüsü boş alan: {2} -> {3}" -f (Format-Bytes $grand), $env:SystemDrive, (Format-Bytes $free0), (Format-Bytes (Get-SystemFree)))
    if ($risk.Count -gt 0) { $m += "`n`nÇerez/oturum verileri silindiyse web sitelerinde yeniden giriş yapmanız gerekebilir." }
    if ($script:BrBkDir -and (Test-Path -LiteralPath $script:BrBkDir)) { $m += "`nYedek: $script:BrBkDir" }
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

function Restore-BrowserBackup {
    if (-not (Test-Path -LiteralPath $BrowserBackupRoot)) { [L10nMsg]::Show('Henüz yedek yok.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $dir = Get-ChildItem -LiteralPath $BrowserBackupRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json') } | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $dir) { [L10nMsg]::Show('Geri yüklenecek yedek bulunamadı.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    $open = @(Get-BrowserDefs | Where-Object { Test-BrowserRunning $_ } | ForEach-Object { $_.Name })
    if ($open.Count -gt 0) { [L10nMsg]::Show("Önce şu tarayıcıları kapatın: " + ($open -join ', '), 'Tarayıcı açık') | Out-Null; return }
    $man = @(Get-Content -LiteralPath (Join-Path $dir.FullName 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
    if ([L10nMsg]::Show("Son yedek geri yüklenecek:`n$($dir.Name)  ($($man.Count) dosya)`n`nYedekten sonra tarayıcıda oluşan yeni çerez/geçmiş verilerinin üzerine yazılır. Devam edilsin mi?", 'Yedeği geri yükle', 'YesNo', 'Question') -ne 'Yes') { return }
    $ok = 0; $fail = @()
    foreach ($e in $man) {
        try {
            if ($e.Db) { foreach ($sfx in '-wal', '-shm', '-journal') { Remove-Item -LiteralPath ($e.Original + $sfx) -Force -ErrorAction SilentlyContinue } }
            $dst = Split-Path -Parent $e.Original
            if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
            Copy-Item -LiteralPath (Join-Path $dir.FullName $e.Yedek) -Destination $e.Original -Force -ErrorAction Stop
            $ok++
        } catch { $fail += [IO.Path]::GetFileName($e.Original) }
    }
    Write-Log "Tarayıcı yedeği geri yüklendi: $($dir.FullName) ($ok/$($man.Count))"
    $m = "$ok/$($man.Count) dosya geri yüklendi."
    if ($fail.Count) { $m += "`n`nBaşarısız: " + ($fail -join ', ') }
    [L10nMsg]::Show($m, 'WinOpt Suite - Developed by Leone') | Out-Null
}

New-Btn $barBr 'Tara' 80 { Invoke-BrowserScan }
New-Btn $barBr 'Seçilileri Temizle' 130 { Invoke-BrowserClean }
New-Btn $barBr 'İptal' 70 { $script:ClCancel = $true }
New-Btn $barBr 'Güvenli Seçim' 110 {
    $script:BrLoading = $true
    foreach ($row in $gridBr.Rows) { $r = $row.Tag; if ($r) { $row.Cells[0].Value = ($r.CanClean -and ($r.Kind -eq 'cache' -or $r.Kind -eq 'temp')) } }
    $script:BrLoading = $false; Update-BrowserTotals
}
New-Btn $barBr 'Seçimi Kaldır' 100 {
    $script:BrLoading = $true
    foreach ($row in $gridBr.Rows) { $row.Cells[0].Value = $false }
    $script:BrLoading = $false; Update-BrowserTotals
}
$lblBrKeep = New-Object Windows.Forms.Label
$lblBrKeep.Text = 'Çerezlerde korunacak siteler:'; $lblBrKeep.AutoSize = $true; $lblBrKeep.Margin = New-Object Windows.Forms.Padding(12, 9, 2, 0)
$barBr.Controls.Add($lblBrKeep)
$txtBrKeep = New-Object Windows.Forms.TextBox
$txtBrKeep.Width = 230; $txtBrKeep.Margin = New-Object Windows.Forms.Padding(2, 6, 8, 0)
$barBr.Controls.Add($txtBrKeep)
New-Btn $barBr 'Son Yedeği Geri Yükle' 150 { Restore-BrowserBackup }
New-Btn $barBr 'Yedek Klasörü' 100 { New-Item -ItemType Directory -Path $BrowserBackupRoot -Force | Out-Null; Start-Process explorer.exe -ArgumentList "`"$BrowserBackupRoot`"" }
New-Btn $barBr 'Yedekleri Sil' 100 {
    if (-not (Test-Path -LiteralPath $BrowserBackupRoot)) { [L10nMsg]::Show('Silinecek yedek yok.', 'WinOpt Suite - Developed by Leone') | Out-Null; return }
    if ([L10nMsg]::Show("Tüm tarayıcı yedekleri (çerez, geçmiş, oturum kopyaları) kalıcı olarak silinecek. Devam edilsin mi?", 'Yedekleri sil', 'YesNo', 'Warning') -eq 'Yes') {
        Remove-Item -LiteralPath $BrowserBackupRoot -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log 'Tarayıcı yedekleri silindi'
    }
}
New-Btn $barBr 'Temizlik Geçmişi' 120 { Show-CsvDialog $BrowserHistFile 'Tarayıcı temizlik geçmişi' }

$gridBr.Add_CurrentCellDirtyStateChanged({ if ($gridBr.IsCurrentCellDirty) { $gridBr.CommitEdit('CurrentCellChange') } })
$gridBr.Add_CellValueChanged({
    param($s, $e)
    if ($e.ColumnIndex -ne 0 -or $script:BrLoading) { return }
    Update-BrowserTotals
    try {
        $row = $gridBr.Rows[$e.RowIndex]
        $r = $row.Tag
        if ($r -and $row.Cells[0].Value -eq $true -and ($r.Kind -eq 'cookies' -or $r.Kind -eq 'session') -and -not $script:BrWarned) {
            $script:BrWarned = $true
            [L10nMsg]::Show("Çerez/oturum verilerini silmek, web sitelerindeki oturumlarınızı KAPATIR.`nHesaplarınıza yeniden giriş yapmanız gerekebilir.`n`nİsterseniz 'Çerezlerde korunacak siteler' kutusuna alan adı yazarak (ör. google.com, github.com) bu sitelerin çerezlerini koruyabilirsiniz.", 'Oturumlar kapanabilir', 'OK', 'Warning') | Out-Null
        }
    } catch {}
})
