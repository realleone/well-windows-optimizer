# ---------- Language layer: language picker + runtime translation (EN / TR / ZH / AR) ----------
# The application source text is Turkish. Turkish = no translation; other languages are translated at runtime
# (controls, grid cells, list items, message boxes) using the table at the bottom of this file.

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

public static class L10n
{
    // -1 = Turkish (source language, no translation); 0 = English, 1 = Chinese, 2 = Arabic
    public static int Idx = -1;
    public static bool Rtl { get { return Idx == 2; } }

    class Pat { public Regex Re; public string Pre; public string Suf; public string[] Tr; public int Len; }

    static Dictionary<string, string[]> exact = new Dictionary<string, string[]>();
    static List<Pat> pats = new List<Pat>();
    static List<KeyValuePair<string, string[]>> frags = new List<KeyValuePair<string, string[]>>();
    static Dictionary<string, string> cache = new Dictionary<string, string>();
    static HashSet<string> outputs = new HashSet<string>();
    static Regex phRe = new Regex(@"\{(\d+)\}");
    static ConditionalWeakTable<object, object> hooked = new ConditionalWeakTable<object, object>();
    static object marker = new object();
    static Timer timer;
    const string TrChars = "çğıöşüÇĞİÖŞÜ";

    static string Unesc(string s)
    {
        if (s.IndexOf('\\') < 0) return s;
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.Length; i++)
        {
            char c = s[i];
            if (c == '\\' && i + 1 < s.Length)
            {
                char n = s[i + 1];
                if (n == 'n') { sb.Append('\n'); i++; continue; }
                if (n == 't') { sb.Append('\t'); i++; continue; }
                if (n == '\\') { sb.Append('\\'); i++; continue; }
            }
            sb.Append(c);
        }
        return sb.ToString();
    }

    public static void Load(string data)
    {
        exact.Clear(); pats.Clear(); frags.Clear(); cache.Clear(); outputs.Clear();
        string[] lines = data.Split('\n');
        foreach (string line in lines)
        {
            string ln = line.TrimEnd('\r');
            if (ln.Length == 0) continue;
            string[] p = ln.Split('\t');
            if (p.Length < 4) continue;
            string key = Unesc(p[0]).Trim();
            if (key.Length == 0) continue;
            string[] tr = new string[] { Unesc(p[1]).Trim(), Unesc(p[2]).Trim(), Unesc(p[3]).Trim() };
            if (key.IndexOf("{#}", StringComparison.Ordinal) >= 0)
            {
                string[] parts = key.Split(new string[] { "{#}" }, StringSplitOptions.None);
                StringBuilder rx = new StringBuilder("^");
                int lit = 0;
                for (int i = 0; i < parts.Length; i++)
                {
                    if (i > 0) rx.Append("(.*?)");
                    rx.Append(Regex.Escape(parts[i]));
                    lit += parts[i].Length;
                }
                rx.Append("$");
                Pat pt = new Pat();
                pt.Re = new Regex(rx.ToString(), RegexOptions.Singleline);
                pt.Pre = parts[0];
                pt.Suf = parts[parts.Length - 1];
                pt.Tr = tr;
                pt.Len = lit;
                pats.Add(pt);
            }
            else
            {
                exact[key] = tr;
                if (key.Length >= 4) frags.Add(new KeyValuePair<string, string[]>(key, tr));
            }
        }
        pats.Sort(delegate(Pat a, Pat b) { return b.Len.CompareTo(a.Len); });
        frags.Sort(delegate(KeyValuePair<string, string[]> a, KeyValuePair<string, string[]> b) { return b.Key.Length.CompareTo(a.Key.Length); });
    }

    public static string T(string s)
    {
        if (Idx < 0 || string.IsNullOrEmpty(s)) return s;
        string r;
        if (cache.TryGetValue(s, out r)) return r;
        if (outputs.Contains(s)) return s;
        r = Compute(s, 0);
        if (cache.Count > 30000) cache.Clear();
        cache[s] = r;
        if (!string.Equals(r, s)) outputs.Add(r);
        return r;
    }

    static string Compute(string s, int depth)
    {
        int a = 0;
        while (a < s.Length && char.IsWhiteSpace(s[a])) a++;
        int b = s.Length;
        while (b > a && char.IsWhiteSpace(s[b - 1])) b--;
        if (a == b) return s;
        string lead = s.Substring(0, a);
        string core = s.Substring(a, b - a);
        string trail = s.Substring(b);
        string t = Core(core, depth);
        if (string.Equals(t, core)) return s;
        return lead + t + trail;
    }

    static bool HasTr(string s)
    {
        for (int i = 0; i < s.Length; i++) if (TrChars.IndexOf(s[i]) >= 0) return true;
        return false;
    }

    static string Core(string core, int depth)
    {
        string[] tr;
        if (exact.TryGetValue(core, out tr)) return tr[Idx];

        foreach (Pat p in pats)
        {
            if (p.Pre.Length > 0 && !core.StartsWith(p.Pre, StringComparison.Ordinal)) continue;
            if (p.Suf.Length > 0 && !core.EndsWith(p.Suf, StringComparison.Ordinal)) continue;
            Match m = p.Re.Match(core);
            if (!m.Success) continue;
            string tpl = p.Tr[Idx];
            int d = depth;
            return phRe.Replace(tpl, delegate(Match mm)
            {
                int n = int.Parse(mm.Groups[1].Value);
                string v = (n >= 1 && n < m.Groups.Count) ? m.Groups[n].Value : "";
                return d < 3 ? Compute(v, d + 1) : v;
            });
        }

        if (depth < 3 && core.IndexOf('\n') >= 0)
        {
            string[] ls = core.Split('\n');
            bool changed = false;
            for (int i = 0; i < ls.Length; i++)
            {
                string cr = ls[i].EndsWith("\r") ? "\r" : "";
                string body = cr.Length > 0 ? ls[i].Substring(0, ls[i].Length - 1) : ls[i];
                string nb = Compute(body, depth + 1);
                if (!string.Equals(nb, body)) { changed = true; ls[i] = nb + cr; }
            }
            if (changed) return string.Join("\n", ls);
        }

        if (core.IndexOf('\\') < 0 && HasTr(core))
        {
            string work = core;
            List<string> subs = new List<string>();
            foreach (KeyValuePair<string, string[]> kv in frags)
            {
                if (work.IndexOf(kv.Key, StringComparison.Ordinal) < 0) continue;
                string token = "\u0001" + subs.Count + "\u0002";
                string res = ReplaceWord(work, kv.Key, token);
                if (!string.Equals(res, work)) { work = res; subs.Add(kv.Value[Idx]); }
            }
            if (subs.Count > 0)
            {
                for (int i = 0; i < subs.Count; i++) work = work.Replace("\u0001" + i + "\u0002", subs[i]);
                return work;
            }
        }
        return core;
    }

    static string ReplaceWord(string s, string key, string token)
    {
        bool fl = char.IsLetterOrDigit(key[0]);
        bool ll = char.IsLetterOrDigit(key[key.Length - 1]);
        StringBuilder sb = null;
        int pos = 0, last = 0;
        while (true)
        {
            int i = s.IndexOf(key, pos, StringComparison.Ordinal);
            if (i < 0) break;
            int e = i + key.Length;
            bool okL = !fl || i == 0 || !char.IsLetterOrDigit(s[i - 1]);
            bool okR = !ll || e >= s.Length || !char.IsLetterOrDigit(s[e]);
            if (okL && okR)
            {
                if (sb == null) sb = new StringBuilder();
                sb.Append(s, last, i - last).Append(token);
                last = e;
                pos = e;
            }
            else pos = i + 1;
        }
        if (sb == null) return s;
        sb.Append(s, last, s.Length - last);
        return sb.ToString();
    }

    // ---------------- UI hooks ----------------

    public static void Start()
    {
        if (Idx < 0 || timer != null) return;
        timer = new Timer();
        timer.Interval = 60;
        timer.Tick += delegate { Pump(); };
        timer.Start();
    }

    public static void Pump()
    {
        if (Idx < 0) return;
        try
        {
            List<Form> fs = new List<Form>();
            foreach (Form f in Application.OpenForms) fs.Add(f);
            foreach (Form f in fs) Walk(f);
        }
        catch { }
    }

    public static void Walk(Control c)
    {
        if (Idx < 0 || c == null) return;
        object o;
        bool first = !hooked.TryGetValue(c, out o);
        if (first)
        {
            hooked.Add(c, marker);
            c.TextChanged += OnText;
            c.ControlAdded += OnAdded;
            DataGridView g = c as DataGridView;
            if (g != null) g.CellFormatting += OnCellFmt;
            if (!(c is CheckedListBox))
            {
                ListBox lb = c as ListBox;
                ComboBox cb = c as ComboBox;
                if (lb != null)
                {
                    lb.DrawMode = DrawMode.OwnerDrawFixed;
                    lb.ItemHeight = lb.Font.Height + 3;
                    lb.DrawItem += OnDrawItem;
                }
                else if (cb != null)
                {
                    cb.DrawMode = DrawMode.OwnerDrawFixed;
                    cb.ItemHeight = cb.Font.Height + 3;
                    cb.DrawItem += OnDrawItem;
                }
            }
        }
        TrText(c);
        DataGridView grid = c as DataGridView;
        if (grid != null)
        {
            foreach (DataGridViewColumn col in grid.Columns)
            {
                string h = col.HeaderText;
                string th = T(h);
                if (!string.Equals(h, th)) col.HeaderText = th;
            }
            if (first) grid.Invalidate();
        }
        ToolStrip ts = c as ToolStrip;
        if (ts != null) WalkItems(ts.Items);
        if (c.ContextMenuStrip != null) WalkItems(c.ContextMenuStrip.Items);
        foreach (Control ch in c.Controls) Walk(ch);
    }

    static void WalkItems(ToolStripItemCollection items)
    {
        foreach (ToolStripItem it in items)
        {
            object o;
            if (!hooked.TryGetValue(it, out o))
            {
                hooked.Add(it, marker);
                it.TextChanged += OnItemText;
            }
            TrItem(it);
            ToolStripDropDownItem dd = it as ToolStripDropDownItem;
            if (dd != null && dd.DropDownItems.Count > 0) WalkItems(dd.DropDownItems);
        }
    }

    static void TrItem(ToolStripItem it)
    {
        string t = T(it.Text);
        if (!string.Equals(t, it.Text)) it.Text = t;
        string tt = it.ToolTipText;
        if (!string.IsNullOrEmpty(tt))
        {
            string t2 = T(tt);
            if (!string.Equals(t2, tt)) it.ToolTipText = t2;
        }
    }

    static void OnItemText(object s, EventArgs e)
    {
        ToolStripItem it = s as ToolStripItem;
        if (it != null) TrItem(it);
    }

    static void TrText(Control c)
    {
        bool ok = c is Form || c is Label || c is ButtonBase || c is GroupBox || c is TabPage;
        if (!ok)
        {
            TextBoxBase tb = c as TextBoxBase;
            ok = tb != null && tb.ReadOnly;
        }
        if (!ok) return;
        string s = c.Text;
        if (string.IsNullOrEmpty(s)) return;
        string t = T(s);
        if (!string.Equals(s, t)) c.Text = t;
    }

    static void OnText(object s, EventArgs e)
    {
        Control c = s as Control;
        if (c != null) TrText(c);
    }

    static void OnAdded(object s, ControlEventArgs e)
    {
        if (Idx >= 0) Walk(e.Control);
    }

    static void OnCellFmt(object sender, DataGridViewCellFormattingEventArgs e)
    {
        string v = e.Value as string;
        if (string.IsNullOrEmpty(v)) return;
        string t = T(v);
        if (!string.Equals(t, v)) { e.Value = t; e.FormattingApplied = true; }
    }

    static void OnDrawItem(object sender, DrawItemEventArgs e)
    {
        e.DrawBackground();
        if (e.Index >= 0)
        {
            string raw = null;
            ComboBox cb = sender as ComboBox;
            ListBox lb = sender as ListBox;
            if (cb != null && e.Index < cb.Items.Count) raw = Convert.ToString(cb.Items[e.Index]);
            else if (lb != null && e.Index < lb.Items.Count) raw = Convert.ToString(lb.Items[e.Index]);
            if (raw != null)
            {
                TextRenderer.DrawText(e.Graphics, T(raw), e.Font, e.Bounds, e.ForeColor,
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            }
        }
        e.DrawFocusRectangle();
    }
}

public static class L10nMsg
{
    static DialogResult Do(string text, string caption, MessageBoxButtons b, MessageBoxIcon i, MessageBoxDefaultButton d)
    {
        MessageBoxOptions o = L10n.Rtl ? (MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign) : (MessageBoxOptions)0;
        return MessageBox.Show(L10n.T(text), L10n.T(caption), b, i, d, o);
    }
    public static DialogResult Show(string text) { return Do(text, "", MessageBoxButtons.OK, MessageBoxIcon.None, MessageBoxDefaultButton.Button1); }
    public static DialogResult Show(string text, string caption) { return Do(text, caption, MessageBoxButtons.OK, MessageBoxIcon.None, MessageBoxDefaultButton.Button1); }
    public static DialogResult Show(string text, string caption, MessageBoxButtons b) { return Do(text, caption, b, MessageBoxIcon.None, MessageBoxDefaultButton.Button1); }
    public static DialogResult Show(string text, string caption, MessageBoxButtons b, MessageBoxIcon i) { return Do(text, caption, b, i, MessageBoxDefaultButton.Button1); }
    public static DialogResult Show(string text, string caption, MessageBoxButtons b, MessageBoxIcon i, MessageBoxDefaultButton d) { return Do(text, caption, b, i, d); }
}

'@

$LangFile = Join-Path $AppDir 'language.txt'
$script:LangCodes = @('en', 'tr', 'zh', 'ar')
$script:LangCode = 'en'
try {
    if (Test-Path -LiteralPath $LangFile) {
        $c = (Get-Content -LiteralPath $LangFile -Raw).Trim()
        if ($script:LangCodes -contains $c) { $script:LangCode = $c }
    }
} catch {}

function T([string]$s) { [L10n]::T($s) }

function Show-LanguagePicker([string]$current) {
    $f = New-Object Windows.Forms.Form
    $f.Text = 'Language / Dil / 语言 / اللغة'
    $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.ShowInTaskbar = $true
    $f.ClientSize = New-Object Drawing.Size(360, 380)
    $f.BackColor = [Drawing.Color]::FromArgb(30, 32, 40); $f.ForeColor = [Drawing.Color]::White
    $f.Font = New-Object Drawing.Font('Segoe UI', 10)

    $title = New-Object Windows.Forms.Label
    $title.Text = "WinOpt Suite`nSelect your language`nDil seçin`n选择语言`nاختر اللغة"
    $title.TextAlign = 'MiddleCenter'
    $title.Location = New-Object Drawing.Point(10, 10); $title.Size = New-Object Drawing.Size(340, 110)
    $f.Controls.Add($title)

    $langs = @(
        @('en', 'English'),
        @('tr', 'Türkçe'),
        @('zh', '中文（简体）'),
        @('ar', 'العربية')
    )
    $y = 130
    foreach ($l in $langs) {
        $b = New-Object Windows.Forms.Button
        $b.Text = $l[1]; $b.Tag = $l[0]
        $b.Location = New-Object Drawing.Point(40, $y); $b.Size = New-Object Drawing.Size(280, 48)
        $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 1
        $b.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(90, 95, 110)
        $b.Font = New-Object Drawing.Font('Segoe UI', 13)
        $b.BackColor = if ($l[0] -eq $current) { [Drawing.Color]::FromArgb(0, 120, 215) } else { [Drawing.Color]::FromArgb(45, 48, 60) }
        $b.ForeColor = [Drawing.Color]::White
        $b.DialogResult = 'OK'
        $b.Add_Click({ param($s, $e) $script:PickedLang = [string]$s.Tag })
        $f.Controls.Add($b)
        if ($l[0] -eq $current) { $f.ActiveControl = $b }
        $y += 58
    }
    $script:PickedLang = $null
    [void]$f.ShowDialog()
    $f.Dispose()
    return $script:PickedLang
}

if (-not $Maintenance) {
    $picked = Show-LanguagePicker $script:LangCode
    if (-not $picked) { exit }
    $script:LangCode = $picked
    try { Set-Content -LiteralPath $LangFile -Value $script:LangCode -Encoding ASCII } catch {}
}

$script:LangData = @'
!! OTURUMLARINIZ KAPANABİLİR !!\nÇerez/oturum verileri silindiği için web sitelerindeki hesaplarınızdan çıkış yapılabilir; yeniden giriş yapmanız gerekebilir.	!! YOUR SESSIONS MAY END !!\nBecause cookie/session data was deleted, you may be signed out of your accounts on websites and may need to sign in again.	!! 您的会话可能会结束 !!\n由于 Cookie/会话数据已被删除，您可能会从网站账户中退出，需要重新登录。	!! قد تنتهي جلساتك !!\nلأنه تم حذف بيانات ملفات تعريف الارتباط/الجلسات، فقد يتم تسجيل خروجك من حساباتك على مواقع الويب وقد تحتاج إلى تسجيل الدخول مرة أخرى.
'Atlanan' dosyalar kullanımda, erişim engelli veya taramadan sonra değişmiş olanlardır; zorla silinmez.	'Skipped' files are in use, access-denied, or changed after the scan; they are not force-deleted.	“已跳过”的文件正在使用中、无法访问，或在扫描后已被更改；不会被强制删除。	الملفات "المتخطاة" هي ملفات قيد الاستخدام أو ممنوعة الوصول أو تغيرت بعد الفحص؛ ولا تُحذف بالقوة.
'Yalnızca öneri' satırları otomatik uygulanmaz; işlem kapatma İşlemler sekmesinde onayınızla yapılır.	'Suggestion only' rows are not applied automatically; closing a process is done with your confirmation on the Processes tab.	"仅建议"的行不会自动应用；关闭进程需在“进程”选项卡中经您确认后进行。	لا تُطبَّق صفوف "اقتراح فقط" تلقائياً؛ ويتم إنهاء العملية بعد موافقتك في علامة تبويب العمليات.
({#} 'yalnızca öneri' satırı atlanacak.)	({1} 'suggestion only' row(s) will be skipped.)	（将跳过 {1} 个“仅建议”行。）	(سيتم تخطي {1} من صفوف "اقتراح فقط".)
AÇIK OLDUĞU İÇİN ATLANACAKLAR:	SKIPPED BECAUSE ENABLED:	因已开启而跳过：	تم تخطيها لأنها مفعّلة:
Başarısız (bağımlı servisler veya yetki):	Failed (dependent services or permissions):	失败（依赖的服务或权限）：	فشل (خدمات تابعة أو صلاحيات):
Başarısız (değişiklik geri alındı):	Failed (change reverted):	失败（更改已还原）：	فشل (تم التراجع عن التغيير):
Başarısız (yetki yetersiz olabilir):	Failed (insufficient permissions may be the cause):	失败（可能是权限不足）：	فشل (ربما بسبب عدم كفاية الصلاحيات):
Başarısız:	Failed:	失败：	فشل:
Bunların zamanlanmış bakımda sizin adınıza otomatik temizlenmesini onaylıyor musunuz?	Do you confirm that these will be cleaned automatically on your behalf during scheduled maintenance?	您是否确认在计划维护中自动为您清理这些内容？	هل تؤكد تنظيف هذه العناصر تلقائياً نيابةً عنك أثناء الصيانة المجدولة؟
Chrome/Edge geçmişi silinince indirme geçmişi de silinir (aynı dosya).	When Chrome/Edge history is deleted, download history is also deleted (same file).	删除 Chrome/Edge 历史记录时，下载记录也会一并删除（为同一文件）。	عند حذف سجل Chrome/Edge يُحذف سجل التنزيلات أيضاً (الملف نفسه).
Devam edilsin mi?	Continue?	是否继续？	هل تريد المتابعة؟
Dikkat gerektirenler:	Requires attention:	需要注意：	عناصر تتطلب الانتباه:
DİKKAT: {#} kayıt ORTA risklidir (paylaşılan DLL kaydı).	WARNING: {1} entries are MEDIUM risk (shared DLL registration).	注意：{1} 项为中等风险（共享 DLL 注册）。	تنبيه: {1} من السجلات ذات مخاطر متوسطة (تسجيل DLL مشترك).
Her değişiklikten önce önceki durum kaydedilir. Devam edilsin mi?	The previous state is saved before each change. Continue?	每次更改前都会保存先前的状态。是否继续？	يتم حفظ الحالة السابقة قبل كل تغيير. هل تريد المتابعة؟
Kullanımda olan veya erişim engelli dosyalar zorla silinmez, atlanır. Windows Update bileşenlerine ve kritik sistem dosyalarına dokunulmaz.\n\nDevam edilsin mi?	Files in use or access-denied are not force-deleted; they are skipped. Windows Update components and critical system files are not touched.\n\nContinue?	正在使用或无法访问的文件不会被强制删除，而是被跳过。不会触及 Windows 更新组件和关键系统文件。\n\n是否继续？	لا تُحذف الملفات قيد الاستخدام أو الممنوعة الوصول بالقوة، بل يتم تخطيها. لا يتم المساس بمكونات Windows Update أو ملفات النظام الحرجة.\n\nهل تريد المتابعة؟
SQLite bileşeni yüklenemedi: veritabanı gerektiren işlemler atlanır.	The SQLite component could not be loaded: operations that require a database are skipped.	无法加载 SQLite 组件：需要数据库的操作将被跳过。	تعذّر تحميل مكوّن SQLite: يتم تخطي العمليات التي تتطلب قاعدة بيانات.
Silmeden önce ilgili anahtarların .reg yedeği alınır; yedek alınamayan kayıt silinmez. Yedeği 'Yedeği Geri Yükle' ile geri getirebilirsiniz.	Before deleting, a .reg backup of the related keys is made; a registry entry that cannot be backed up is not deleted. You can restore the backup with 'Restore Backup'.	删除前会备份相关键的 .reg 文件；无法备份的注册表项不会被删除。您可以使用“还原备份”恢复。	قبل الحذف يتم أخذ نسخة احتياطية بصيغة .reg للمفاتيح المعنية؛ ولا يُحذف أي سجل لا يمكن نسخه احتياطياً. يمكنك استعادة النسخة الاحتياطية باستخدام "Restore Backup".
Toplam kazanılan alan: {#}\n{#} sürücüsü boş alan: {#} -> {#}	Total space gained: {1}\n{2} drive free space: {3} -> {4}	释放的总空间：{1}\n{2} 驱动器可用空间：{3} -> {4}	إجمالي المساحة المستعادة: {1}\nالمساحة الفارغة لمحرك {2}: {3} -> {4}
Çerez, geçmiş ve oturum verileri silinmeden önce yedeklenir (yedek alınamayan dosya silinmez):\n{#}\nKullanımdaki/erişilemeyen dosyalar zorla silinmez, atlanır. Yer imleri, şifreler ve eklentiler hedeflenmez.\n\nDevam edilsin mi?	Cookies, history and session data are backed up before deletion (files that cannot be backed up are not deleted):\n{1}\nFiles in use or inaccessible are not force-deleted; they are skipped. Bookmarks, passwords and extensions are not targeted.\n\nContinue?	Cookie、历史记录和会话数据在删除前会先备份（无法备份的文件不会被删除）：\n{1}\n正在使用或无法访问的文件不会被强制删除，而是被跳过。书签、密码和扩展程序不在处理范围内。\n\n是否继续？	يتم نسخ ملفات تعريف الارتباط والسجل وبيانات الجلسات احتياطياً قبل حذفها (لا تُحذف الملفات التي يتعذر نسخها احتياطياً):\n{1}\nلا تُحذف الملفات قيد الاستخدام أو غير القابلة للوصول بالقوة، بل يتم تخطيها. لا تشمل العملية الإشارات المرجعية وكلمات المرور والإضافات.\n\nهل تريد المتابعة؟
Çerez/oturum verileri silindiyse web sitelerinde yeniden giriş yapmanız gerekebilir.	If cookie/session data was deleted, you may need to sign in again on websites.	如果已删除 Cookie/会话数据，您可能需要在网站上重新登录。	إذا تم حذف بيانات ملفات تعريف الارتباط/الجلسات، فقد تحتاج إلى تسجيل الدخول مرة أخرى إلى مواقع الويب.
ÖN KONTROL UYARILARI:	PRE-CHECK WARNINGS:	预检查警告：	تحذيرات الفحص المسبق:
Önceki ayar kaydedilir ve geri yüklenebilir. Devam edilsin mi?	The previous setting is saved and can be restored. Continue?	先前的设置已保存，可以还原。是否继续？	يتم حفظ الإعداد السابق ويمكن استعادته. هل تريد المتابعة؟
Önceki değerler yedeklenir ve geri alınabilir. Öneriler performans artışı garantisi vermez. Devam edilsin mi?	Previous values are backed up and can be reverted. Recommendations do not guarantee a performance improvement. Continue?	先前的值已备份，可以撤销。建议不保证性能提升。是否继续？	يتم نسخ القيم السابقة احتياطياً ويمكن التراجع عنها. التوصيات لا تضمن تحسناً في الأداء. هل تريد المتابعة؟
Önceki plan yedeklenir. Devam edilsin mi?	The previous plan is backed up. Continue?	先前的计划已备份。是否继续？	يتم نسخ الخطة السابقة احتياطياً. هل تريد المتابعة؟
Şu ayarlar daha sonra etkili olur:	These settings take effect later:	以下设置稍后生效：	تصبح هذه الإعدادات فعّالة لاحقاً:
Tüm zamanlarda kazanılan:	Total gained across all time:	所有时间累计释放：	المساحة المستعادة على مدار كل الأوقات:
Çerezlerde şu sitelerin kayıtları KORUNACAK:	Cookie records for these sites will be KEPT:	以下网站的 Cookie 记录将被保留：	سيتم الاحتفاظ بسجلات ملفات تعريف الارتباط لهذه المواقع:
Uygulanınca önceki plan yedeklenir; Önceki Plana Dön ile geri alınır.	When applied, the previous plan is backed up; it can be reverted with 'Revert to Previous Plan'.	应用后会备份先前的计划；可通过“恢复到上一计划”撤销。	عند التطبيق يتم نسخ الخطة السابقة احتياطياً؛ ويمكن التراجع عنها باستخدام "العودة إلى الخطة السابقة".
Açıklama: {#}	Description: {1}	说明：{1}	الوصف: {1}
Beklenen etki: {#}	Expected effect: {1}	预期效果：{1}	التأثير المتوقع: {1}
Geri alma: {#}	Revert: {1}	撤销：{1}	التراجع: {1}
Temizlik: {#} silindi, {#} atlandı, {#} kazanıldı	Cleanup: {1} deleted, {2} skipped, {3} gained	清理：已删除 {1}，已跳过 {2}，已释放 {3}	التنظيف: تم حذف {1}، وتخطي {2}، واستعادة {3}
(ayar uygulanmadı)	(setting not applied)	（未应用设置）	(لم يتم تطبيق الإعداد)
(geri alınamaz)	(cannot be reverted)	（无法撤销）	(لا يمكن التراجع عنه)
(geri yüklenecek ayar yoktu)	(there was no setting to restore)	（没有可还原的设置）	(لم يكن هناك إعداد لاستعادته)
(varsayılan kapalı; kişisel/uygulama verisi içerebilir)	(off by default; may contain personal/app data)	（默认关闭；可能包含个人或应用数据）	(مُعطّل افتراضياً؛ قد يحتوي على بيانات شخصية أو بيانات تطبيقات)
- Bu rapor FPS ölçmez; yalnızca kaynak kullanımını gösterir. FPS için oyun içi sayaç veya PresentMon/CapFrameX gibi araçlar kullanın.	- This report does not measure FPS; it only shows resource usage. For FPS, use an in-game counter or a tool such as PresentMon/CapFrameX.	- 此报告不测量 FPS，仅显示资源占用情况。如需 FPS，请使用游戏内计数器或 PresentMon/CapFrameX 等工具。	- هذا التقرير لا يقيس عدد الإطارات في الثانية (FPS)، بل يعرض استخدام الموارد فقط. لقياس FPS استخدم عداداً داخل اللعبة أو أداة مثل PresentMon/CapFrameX.
- Oyun CPU yüzdesi tüm çekirdeklere göre hesaplanır; tek çekirdek darboğazı bu değerde görünmeyebilir.	- Game CPU percentage is calculated across all cores; a single-core bottleneck may not appear in this value.	- 游戏 CPU 百分比按所有核心计算；单核瓶颈可能不会体现在该数值中。	- تُحسب نسبة CPU للعبة عبر جميع الأنوية؛ وقد لا يظهر اختناق نواة واحدة في هذه القيمة.
- Profil ayarlarının FPS artıracağı garanti edilmez; etki oyuna ve donanıma göre değişir. Karşılaştırma için aynı sahnede profilli ve profilsiz ölçüm yapın.	- Profile settings are not guaranteed to increase FPS; the effect varies by game and hardware. For comparison, measure with and without the profile in the same scene.	- 不保证配置文件设置能提升 FPS；效果因游戏和硬件而异。为便于比较，请在同一场景中分别使用和不使用该配置文件进行测量。	- لا يُضمن أن تزيد إعدادات الملف الشخصي من عدد الإطارات؛ ويختلف التأثير حسب اللعبة والعتاد. للمقارنة، قم بالقياس في المشهد نفسه مع الملف الشخصي ومن دونه.
1/5 Donanım ve Windows sürümü tanınıyor...	1/5 Recognizing hardware and Windows version...	1/5 正在识别硬件和 Windows 版本...	1/5 جارٍ التعرف على العتاد وإصدار Windows...
2/5 Windows ayarları inceleniyor...	2/5 Examining Windows settings...	2/5 正在检查 Windows 设置...	2/5 جارٍ فحص إعدادات Windows...
3/5 Başlangıç uygulamaları inceleniyor...	3/5 Examining startup apps...	3/5 正在检查启动应用...	3/5 جارٍ فحص تطبيقات بدء التشغيل...
4/5 Servisler ve arka plan işlemleri inceleniyor...	4/5 Examining services and background processes...	4/5 正在检查服务和后台进程...	4/5 جارٍ فحص الخدمات والعمليات الخلفية...
5/5 Temizlenebilir dosyalar ve güç planı inceleniyor...	5/5 Examining cleanable files and power plan...	5/5 正在检查可清理文件和电源计划...	5/5 جارٍ فحص الملفات القابلة للتنظيف وخطة الطاقة...
Ayarlar okunuyor...	Reading settings...	正在读取设置...	جارٍ قراءة الإعدادات...
Ayrıntılar rapor penceresinde ve Raporlar sekmesinde.	Details are in the report window and on the Reports tab.	详细信息请见报告窗口和“报告”选项卡。	التفاصيل موجودة في نافذة التقرير وفي علامة تبويب التقارير.
Bakım bitti.	Maintenance finished.	维护已完成。	انتهت الصيانة.
Bakım çalışıyor...	Maintenance running...	正在执行维护...	الصيانة قيد التشغيل...
Başlamak için "Analiz Et" düğmesine basın. Hiçbir değişiklik sizin onayınız olmadan yapılmaz.	Click "Analyze" to start. No changes are made without your confirmation.	点击“分析”按钮开始。未经您的确认，不会进行任何更改。	انقر على "تحليل" للبدء. لا تُجرى أي تغييرات دون موافقتك.
Bir kategori seçin: en büyük dosyaları burada listelenir.	Select a category: its largest files are listed here.	选择一个类别：此处将列出其中最大的文件。	اختر فئة: ستُعرض هنا أكبر الملفات فيها.
Bu pencere yalnızca incelemek içindir; hiçbir özellik değiştirilmez.	This window is for review only; no features are changed.	此窗口仅供查看；不会更改任何功能。	هذه النافذة للمراجعة فقط؛ لا يتم تغيير أي ميزة.
Bulgu: {#} (gösterilen {#})  |  Düşük: {#}  |  Orta: {#}  |  Yüksek (yalnızca inceleme): {#}	Findings: {1} (shown {2})  |  Low: {3}  |  Medium: {4}  |  High (review only): {5}	发现：{1}（显示 {2}）  |  低：{3}  |  中：{4}  |  高（仅供查看）：{5}	النتائج: {1} (المعروضة {2})  |  منخفضة: {3}  |  متوسطة: {4}  |  عالية (للمراجعة فقط): {5}
Donanım ve sistem bilgisi okunuyor...	Reading hardware and system information...	正在读取硬件和系统信息...	جارٍ قراءة معلومات العتاد والنظام...
DİKKAT: Çerezleri veya oturum verilerini silmek, web sitelerindeki oturumlarınızı KAPATIR (hesaplarınıza yeniden giriş yapmanız gerekebilir). Bu seçenekler varsayılan olarak KAPALIDIR.	WARNING: Deleting cookies or session data will CLOSE your sessions on websites (you may need to sign in to your accounts again). These options are OFF by default.	注意：删除 Cookie 或会话数据会关闭您在网站上的会话（您可能需要重新登录账户）。这些选项默认关闭。	تنبيه: حذف ملفات تعريف الارتباط أو بيانات الجلسات سيُغلق جلساتك على مواقع الويب (قد تحتاج إلى تسجيل الدخول إلى حساباتك مرة أخرى). هذه الخيارات مُعطّلة افتراضياً.
Genel durum: {#}.  Okunamayan/sensörsüz veri: {#} (uydurulmaz).  RAM canlı güncellenir; diğer değerler için Yenile.	Overall status: {1}.  Unreadable/no-sensor data: {2} (not fabricated).  RAM updates live; for other values, click Refresh.	总体状况：{1}。无法读取或无传感器的数据：{2}（不作虚构）。RAM 实时更新；其他数值请点击“刷新”。	الحالة العامة: {1}.  بيانات غير قابلة للقراءة أو بدون مستشعر: {2} (لا يتم اختلاقها).  تتحدث الذاكرة (RAM) مباشرةً؛ وللقيم الأخرى انقر على "تحديث".
Geri alma bitti: {#} başarılı, {#} hatalı. Güncel durum için Analiz Et'e basın.	Revert finished: {1} successful, {2} failed. For the current status, click Analyze.	撤销完成：{1} 成功，{2} 失败。如需查看当前状态，请点击“分析”。	انتهى التراجع: {1} ناجحة، {2} فاشلة. للحالة الحالية، انقر على "تحليل".
Kapanmayan (arka planda çalışıyor olabilir):	Not closed (may be running in the background):	未关闭（可能在后台运行）：	لم تُغلق (قد تعمل في الخلفية):
Kapatılan uygulamalar:	Closed apps:	已关闭的应用：	التطبيقات المُغلقة:
Kurulu program: {#}  |  Gösterilen: {#}  |  'Kaldır' programın kendi kaldırıcısını açar; WinOpt dosya silmez. Boyut, programın bildirdiği tahmini değerdir.	Installed programs: {1}  |  Shown: {2}  |  'Uninstall' opens the program's own uninstaller; WinOpt does not delete files. Size is an estimate reported by the program.	已安装程序：{1}  |  显示：{2}  |  “卸载”会打开程序自带的卸载程序；WinOpt 不会删除文件。大小为程序报告的估计值。	البرامج المثبتة: {1}  |  المعروضة: {2}  |  يفتح "إلغاء التثبيت" أداة الإلغاء الخاصة بالبرنامج؛ ولا يحذف WinOpt أي ملفات. الحجم قيمة تقديرية يبلغ عنها البرنامج.
Not: Registry temizliği CPU/RAM performansını doğrudan artırmaz. Gerçek iyileştirme için Başlangıç, İşlemler ve Servisler sekmelerini kullanın.	Note: Registry cleanup does not directly improve CPU/RAM performance. For real improvement, use the Startup, Processes and Services tabs.	注意：注册表清理不会直接提升 CPU/RAM 性能。如需真正的改善，请使用“启动”、“进程”和“服务”选项卡。	ملاحظة: تنظيف السجل (Registry) لا يحسّن أداء CPU/RAM بشكل مباشر. لتحقيق تحسن فعلي، استخدم علامات تبويب بدء التشغيل والعمليات والخدمات.
Profil: {#}  |  Etkin profil: {#}  |  Windows Oyun Modu: {#}  |  Ayarların FPS artışı garanti edilmez; FPS ölçülmez, yalnızca kaynak kullanımı izlenir.	Profile: {1}  |  Active profile: {2}  |  Windows Game Mode: {3}  |  FPS gains are not guaranteed by the settings; FPS is not measured, only resource usage is monitored.	配置文件：{1}  |  当前配置文件：{2}  |  Windows 游戏模式：{3}  |  设置不保证提升 FPS；不测量 FPS，仅监控资源占用。	الملف الشخصي: {1}  |  الملف النشط: {2}  |  وضع اللعب في Windows: {3}  |  لا يُضمن تحسن عدد الإطارات في الثانية من الإعدادات؛ لا يتم قياس FPS، بل تُراقَب موارد النظام فقط.
Profil: {#}  |  Öneri: {#}	Profile: {1}  |  Suggestion: {2}	配置文件：{1}  |  建议：{2}	الملف الشخصي: {1}  |  اقتراح: {2}
Servisler okunuyor...	Reading services...	正在读取服务...	جارٍ قراءة الخدمات...
Seçili: {#} öğe, yaklaşık {#}   |   {#}	Selected: {1} item(s), approx. {2}   |   {3}	已选择：{1} 项，约 {2}   |   {3}	المحدد: {1} عنصر، بحجم تقريبي {2}   |   {3}
Tarama hatası:	Scan error:	扫描错误：	خطأ في الفحص:
Tarama iptal edildi (kısmi sonuç).	Scan cancelled (partial result).	扫描已取消（部分结果）。	تم إلغاء الفحص (نتيجة جزئية).
Taramak için "Tara" düğmesine basın.	Click "Scan" to start scanning.	点击“扫描”按钮开始扫描。	انقر على "فحص" لبدء الفحص.
Taramak için "Tara" düğmesine basın. Hiçbir şey seçmeden/onaylamadan silinmez.	Click "Scan" to start scanning. Nothing is deleted without selection and confirmation.	点击“扫描”按钮开始扫描。未经选择和确认，不会删除任何内容。	انقر على "فحص" لبدء الفحص. لا يُحذف شيء دون تحديده وتأكيده.
Taranıyor: {#} - {#} ...	Scanning: {1} - {2} ...	正在扫描：{1} - {2} ...	جارٍ الفحص: {1} - {2} ...
Taranıyor: {#} ...	Scanning: {1} ...	正在扫描：{1} ...	جارٍ الفحص: {1} ...
Tarayıcı açıkken o tarayıcıya dokunulmaz; tarayıcılar bu araç tarafından kapatılmaz. Kullanıcı verisi silinmeden önce yedeklenir.	A browser that is open is not touched; browsers are not closed by this tool. User data is backed up before deletion.	浏览器打开时不会处理该浏览器；本工具不会关闭浏览器。用户数据在删除前会先备份。	لا يتم المساس بالمتصفح أثناء فتحه؛ ولا تقوم هذه الأداة بإغلاق المتصفحات. يتم نسخ بيانات المستخدم احتياطياً قبل حذفها.
Temizlenebilir toplam: {#} ({#} dosya)   |   Seçili: {#} ({#} dosya)   |   {#} boş alan: {#}	Total cleanable: {1} ({2} files)   |   Selected: {3} ({4} files)   |   {5} free space: {6}	可清理总计：{1}（{2} 个文件）   |   已选择：{3}（{4} 个文件）   |   {5} 可用空间：{6}	الإجمالي القابل للتنظيف: {1} ({2} ملف)   |   المحدد: {3} ({4} ملف)   |   المساحة الفارغة {5}: {6}
Toplam: {#}  |  Çalışan: {#}  |  Yönetilebilir: {#}  |  Gösterilen: {#}  |  CPU/RAM değerleri servisin çalıştığı işleme aittir; svchost paylaşımlı olabilir.	Total: {1}  |  Running: {2}  |  Manageable: {3}  |  Shown: {4}  |  CPU/RAM values belong to the process the service runs in; svchost may be shared.	总计：{1}  |  运行中：{2}  |  可管理：{3}  |  显示：{4}  |  CPU/RAM 值属于服务所在的进程；svchost 可能是共享的。	الإجمالي: {1}  |  قيد التشغيل: {2}  |  قابل للإدارة: {3}  |  المعروض: {4}  |  قيم CPU/RAM تعود إلى العملية التي تعمل فيها الخدمة؛ وقد تكون svchost مشتركة.
Toplam: {#}  |  Önerilen değerde: {#}  |  Farklı: {#}  |  Etkin güç planı: {#}  |  Öneriler genel eğilimdir; hız veya FPS artışı garanti edilmez.	Total: {1}  |  At recommended value: {2}  |  Different: {3}  |  Active power plan: {4}  |  Recommendations are general trends; a speed or FPS gain is not guaranteed.	总计：{1}  |  已为推荐值：{2}  |  不同：{3}  |  当前电源计划：{4}  |  建议仅为一般趋势；不保证速度或 FPS 提升。	الإجمالي: {1}  |  على القيمة الموصى بها: {2}  |  مختلف: {3}  |  خطة الطاقة النشطة: {4}  |  التوصيات اتجاهات عامة؛ ولا يُضمن تحسن السرعة أو عدد الإطارات.
Uygulama bitti: {#} başarılı, {#} hatalı.	Apply finished: {1} successful, {2} failed.	应用完成：{1} 成功，{2} 失败。	انتهى التطبيق: {1} ناجحة، {2} فاشلة.
Uygulanıyor: {#}	Applying: {1}	正在应用：{1}	جارٍ التطبيق: {1}
Zamanlanmış görev kaldırıldı.	Scheduled task removed.	计划任务已删除。	تمت إزالة المهمة المجدولة.
Zamanlanmış görev:	Scheduled task:	计划任务：	المهمة المجدولة:
{#}: en büyük {#} dosya (kategori toplamı {#}, {#} dosya)	{1}: largest {2} files (category total {3}, {4} files)	{1}：最大的 {2} 个文件（类别总计 {3}，{4} 个文件）	{1}: أكبر {2} ملفات (إجمالي الفئة {3}، {4} ملف)
İmza doğrulanıyor ({#}/{#})...	Verifying signature ({1}/{2})...	正在验证签名（{1}/{2}）...	جارٍ التحقق من التوقيع ({1}/{2})...
İşlem sonrası CPU/RAM ölçülüyor (~5 sn)...	Measuring CPU/RAM after the operation (~5 s)...	正在测量操作后的 CPU/RAM（约 5 秒）...	جارٍ قياس CPU/RAM بعد العملية (~5 ثوانٍ)...
İşlem öncesi CPU/RAM ölçülüyor (~5 sn)...	Measuring CPU/RAM before the operation (~5 s)...	正在测量操作前的 CPU/RAM（约 5 秒）...	جارٍ قياس CPU/RAM قبل العملية (~5 ثوانٍ)...
İşlem: {#} (gösterilen {#})  |  Toplam CPU: %{#}  |  Yüksek tüketen: {#}  |  Kapatma önerisi: {#}  |  İmzasız/bilinmeyen işlemler zararlı sayılmaz, yalnızca bilgi verilir.	Processes: {1} (shown {2})  |  Total CPU: %{3}  |  High consumers: {4}  |  Close suggestion: {5}  |  Unsigned/unknown processes are not considered harmful; they are only reported for information.	进程：{1}（显示 {2}）  |  CPU 总计：%{3}  |  高占用：{4}  |  关闭建议：{5}  |  未签名或未知的进程不视为有害，仅供参考。	العمليات: {1} (المعروضة {2})  |  إجمالي CPU: %{3}  |  استهلاك مرتفع: {4}  |  اقتراح الإغلاق: {5}  |  لا تُعتبر العمليات غير الموقّعة أو المجهولة ضارة، بل يتم الإبلاغ عنها للعلم فقط.
• [{#}] {#}  (Risk: {#})\n      Geri alma: {#}	• [{1}] {2}  (Risk: {3})\n      Revert: {4}	• [{1}] {2}（风险：{3}）\n      撤销：{4}	• [{1}] {2}  (المخاطر: {3})\n      التراجع: {4}
• {#} - {#}: SQLite yok, atlandı	• {1} - {2}: no SQLite, skipped	• {1} - {2}：没有 SQLite，已跳过	• {1} - {2}: لا يوجد SQLite، تم التخطي
• {#} - {#}: geçmişle birlikte silindi	• {1} - {2}: deleted along with history	• {1} - {2}：已连同历史记录一并删除	• {1} - {2}: تم الحذف مع السجل
• {#} - {#}: korunacak site listesi için SQLite gerekli, atlandı (hiçbir çerez silinmedi)	• {1} - {2}: SQLite is required for the list of sites to keep; skipped (no cookies were deleted)	• {1} - {2}：保留站点列表需要 SQLite，已跳过（未删除任何 Cookie）	• {1} - {2}: يلزم SQLite لقائمة المواقع المراد الاحتفاظ بها؛ تم التخطي (لم يتم حذف أي ملفات تعريف ارتباط)
• {#} - {#}: tarayıcı açıldı, atlandı	• {1} - {2}: browser is open, skipped	• {1} - {2}：浏览器已打开，已跳过	• {1} - {2}: المتصفح مفتوح، تم التخطي
• {#} - {#}: {#} {#}, {#} atlandı, {#} kazanıldı{#}	• {1} - {2}: {3} {4}, {5} skipped, {6} gained{7}	• {1} - {2}：{3} {4}，已跳过 {5}，已释放 {6}{7}	• {1} - {2}: {3} {4}، تم تخطي {5}، تمت استعادة {6}{7}
• {#}: {#} silindi, {#} atlandı, {#} kazanıldı{#}	• {1}: {2} deleted, {3} skipped, {4} gained{5}	• {1}：已删除 {2}，已跳过 {3}，已释放 {4}{5}	• {1}: تم حذف {2}، وتخطي {3}، واستعادة {4}{5}
✓ Geri alındı: {#}	✓ Reverted: {1}	✓ 已撤销：{1}	✓ تم التراجع: {1}
✗ Geri alınamadı: {#} -> {#}	✗ Could not revert: {1} -> {2}	✗ 无法撤销：{1} -> {2}	✗ تعذّر التراجع: {1} -> {2}
(Otomatik Bakım)	(Auto Maintenance)	（自动维护）	(الصيانة التلقائية)
(silinen geçici dosyalar geri alınamaz)	(deleted temporary files cannot be reverted)	（已删除的临时文件无法撤销）	(لا يمكن التراجع عن الملفات المؤقتة المحذوفة)
(sürücü {#})	(drive {1})	（驱动器 {1}）	(المحرك {1})
({#} klasöre erişim yok, atlandı.)	({1} folder(s) inaccessible, skipped.)	（{1} 个文件夹无法访问，已跳过。）	(تعذّر الوصول إلى {1} مجلد، تم تخطيها.)
({#} modül	({1} modules	（{1} 个模块	({1} وحدة
({#} yeni dosya yaş filtresi nedeniyle dışarıda bırakıldı.)	({1} new file(s) excluded by the age filter.)	（{1} 个新文件因年龄筛选而被排除。）	(تم استبعاد {1} ملف جديد بسبب مرشح العمر.)
(şu an etkin)	(currently active)	（当前已启用）	(مفعّل حالياً)
Boş {#} GB	Free {1} GB	可用 {1} GB	فارغ {1} GB
Donanım seviyeniz görsel efekt yükünden daha çok etkilenir.	Your hardware is more affected by the visual effects load.	您的硬件受视觉效果负载的影响更大。	يتأثر عتادك بحمل التأثيرات البصرية بدرجة أكبر.
Donanım seviyeniz için başlangıç yükünü azaltmak daha belirgin fayda sağlar.	For your hardware level, reducing the startup load gives a more noticeable benefit.	对于您的硬件水平，减少启动负载会带来更明显的好处。	بالنسبة لمستوى عتادك، يحقق تقليل حمل بدء التشغيل فائدة أوضح.
Güçlü donanımda kazanç küçüktür, bu yüzden isteğe bağlıdır.	On powerful hardware the gain is small, so it is optional.	在高性能硬件上收益较小，因此为可选项。	على العتاد القوي يكون المكسب صغيراً، لذا فهو اختياري.
Kullanılan {#} GB	Used {1} GB	已用 {1} GB	مستخدم {1} GB
SSD ve güçlü işlemcide yük artışı genelde sorun olmaz.	On an SSD and a powerful processor, the load increase is usually not a problem.	在 SSD 和高性能处理器上，负载增加通常不会造成问题。	مع قرص SSD ومعالج قوي، لا تشكّل زيادة الحمل عادةً مشكلة.
Sistem RAM kullanımı %{#} ile yüksek.	System RAM usage is high at %{1}.	系统 RAM 占用率较高，为 %{1}。	استخدام ذاكرة النظام (RAM) مرتفع عند %{1}.
Sistem sürücüsünde boş alan az.	Free space on the system drive is low.	系统驱动器上的可用空间不足。	المساحة الفارغة على محرك النظام قليلة.
Windows tanılama kaydı bu uygulamanın başlatmayı {#} sn geciktirdiğini gösteriyor.	The Windows diagnostic log shows this app delays startup by {1} s.	Windows 诊断日志显示该应用使启动延迟了 {1} 秒。	يُظهر سجل تشخيص Windows أن هذا التطبيق يؤخر بدء التشغيل بمقدار {1} ث.
Xbox/Game Pass/oyun kaydı kullanıyorsanız bu öneriyi atlayın.	If you use Xbox/Game Pass/game recording, skip this suggestion.	如果您使用 Xbox/Game Pass/游戏录制，请跳过此建议。	إذا كنت تستخدم Xbox/Game Pass/تسجيل الألعاب، فتجاهل هذا الاقتراح.
Zayıf donanımda masaüstü açılışında takılma olabilir.	On weak hardware, the desktop may stutter when opening.	在性能较弱的硬件上，桌面打开时可能会卡顿。	قد يحدث تقطّع عند فتح سطح المكتب على العتاد الضعيف.
[yalnızca izleme]	[monitoring only]	[仅监控]	[للمراقبة فقط]
uygulanamadı:	could not be applied:	无法应用：	تعذّر التطبيق:
%{#} kullanıldı	{1} used	已使用 {1}	مستخدم {1}
'Birlikte aç' listesinde kalmış uygulama kaydı; çalıştırılacak dosya artık yok.	An app entry left in the 'Open with' list; the file to run no longer exists.	“打开方式”列表中残留的应用记录；要运行的文件已不存在。	سجل تطبيق متبقٍ في قائمة "فتح بواسطة"؛ ولم يعد الملف المراد تشغيله موجوداً.
'{#}' için kayıtlı uygulama yolu geçersiz; Çalıştır penceresi veya kısayollar bu kaydı kullanmaya çalışırsa hata verir.	The saved app path for '{1}' is invalid; the Run window or shortcuts will show an error if they try to use this entry.	“{1}”的已保存应用路径无效；如果“运行”窗口或快捷方式尝试使用该记录，将会报错。	مسار التطبيق المحفوظ لـ '{1}' غير صالح؛ وستظهر أخطاء إذا حاولت نافذة "تشغيل" أو الاختصارات استخدام هذا السجل.
'{#}' için programlar listesinde kayıt duruyor, ancak kaldırıcı dosyası bulunamadı. Uygulama büyük olasılıkla elle silinmiş.	An entry for '{1}' remains in the programs list, but its uninstaller file was not found. The app was most likely deleted manually.	“{1}”在程序列表中仍有记录，但找不到其卸载程序文件。该应用很可能已被手动删除。	لا يزال سجل '{1}' موجوداً في قائمة البرامج، لكن لم يتم العثور على ملف أداة الإلغاء الخاصة به. ومن المرجح أن التطبيق قد حُذف يدوياً.
'{#}' için programın kendi kaldırıcısı açılacak. Kaldırma işlemi o programın penceresinden onaylanır.\n\nDevam edilsin mi?	The program's own uninstaller will open for '{1}'. Removal is confirmed in that program's window.\n\nContinue?	将为“{1}”打开该程序自带的卸载程序。卸载需在该程序的窗口中确认。\n\n是否继续？	سيتم فتح أداة الإلغاء الخاصة بالبرنامج لـ '{1}'. تتم الموافقة على الإزالة من نافذة ذلك البرنامج.\n\nهل تريد المتابعة؟
'{#}' profili silinecek. Devam edilsin mi?	The profile '{1}' will be deleted. Continue?	将删除配置文件“{1}”。是否继续？	سيتم حذف الملف الشخصي '{1}'. هل تريد المتابعة؟
(Değiştirme)	(Replace)	（替换）	(استبدال)
(değiştirme)	(replace)	（替换）	(استبدال)
, HDD var	, HDD present	，存在 HDD	، يوجد HDD
, paylaşımlı	, shared	，共享	، مشترك
.  Bakım yalnızca seçtiğiniz temizlik kategorilerini çalıştırır; ayar/servis/başlangıç değişikliği yapmaz.	.  Maintenance only runs the cleanup categories you select; it does not change settings, services or startup.	。维护仅运行您所选的清理类别；不会更改设置、服务或启动项。	.  تُشغّل الصيانة فئات التنظيف التي تختارها فقط؛ ولا تغيّر الإعدادات أو الخدمات أو بدء التشغيل.
1 gün ve daha eski	1 day and older	1 天及更早	يوم واحد وأقدم
30 günden eski CBS/DISM günlükleri. Güncel günlük dosyaları ve Windows Update günlükleri korunur.	CBS/DISM logs older than 30 days. Current log files and Windows Update logs are kept.	超过 30 天的 CBS/DISM 日志。当前日志文件和 Windows 更新日志将被保留。	سجلات CBS/DISM الأقدم من 30 يوماً. تُحتفظ بملفات السجل الحالية وسجلات Windows Update.
7 gün ve daha eski	7 days and older	7 天及更早	7 أيام وأقدم
AKILLI OPTİMİZASYON GERİ ALINDI:	SMART OPTIMIZATION REVERTED:	智能优化已撤销：	تم التراجع عن التحسين الذكي:
AKILLI OPTİMİZASYON GERİ ALMA HATA: {#}: {#}	SMART OPTIMIZATION REVERT ERROR: {1}: {2}	智能优化撤销错误：{1}：{2}	خطأ في التراجع عن التحسين الذكي: {1}: {2}
AKILLI OPTİMİZASYON HATA: {#}: {#}	SMART OPTIMIZATION ERROR: {1}: {2}	智能优化错误：{1}：{2}	خطأ في التحسين الذكي: {1}: {2}
AKILLI OPTİMİZASYON: {#} [{#}]	SMART OPTIMIZATION: {1} [{2}]	智能优化：{1} [{2}]	التحسين الذكي: {1} [{2}]
Akıllı Optimizasyon	Smart Optimization	智能优化	التحسين الذكي
Akıllı Optimizasyon - analiz özeti	Smart Optimization - analysis summary	智能优化 - 分析摘要	التحسين الذكي - ملخص التحليل
Akıllı Optimizasyon raporu	Smart Optimization report	智能优化报告	تقرير التحسين الذكي
Akıllı motor temizlik taraması hatası:	Smart engine cleanup scan error:	智能引擎清理扫描错误：	خطأ في فحص التنظيف لمحرك التحسين الذكي:
Akıllı optimizasyon analiz hatası:	Smart Optimization analysis error:	智能优化分析错误：	خطأ في تحليل التحسين الذكي:
Ana betik yolu bulunamadı; planlama yapılamadı (EXE sürümünde desteklenmez).	Main script path not found; scheduling could not be done (not supported in the EXE version).	未找到主脚本路径；无法进行计划（EXE 版本不支持）。	لم يتم العثور على مسار النص البرمجي الرئيسي؛ تعذّر الجدولة (غير مدعومة في إصدار EXE).
Anahtar açılamadı (zaten silinmiş olabilir).	The key could not be opened (it may already be deleted).	无法打开该键（可能已被删除）。	تعذّر فتح المفتاح (ربما تم حذفه بالفعل).
Anakart	Motherboard	主板	اللوحة الأم
Anakart bilgisi	Motherboard info	主板信息	معلومات اللوحة الأم
Analiz Et	Analyze	分析	تحليل
Animasyonlar	Animations	动画	الرسوم المتحركة
Anlık ölçümlerdir; çalışan diğer uygulamalar sonucu etkileyebilir. Bu rapor "performans artışı yüzdesi" hesaplamaz ve hız kazancı iddia etmez.	These are instantaneous measurements; other running apps may affect the result. This report does not calculate a "performance gain percentage" and does not claim any speed gain.	这些是即时测量值；其他正在运行的应用可能会影响结果。本报告不计算“性能提升百分比”，也不声称有任何速度提升。	هذه قياسات لحظية؛ وقد تؤثر التطبيقات الأخرى قيد التشغيل في النتيجة. لا يحسب هذا التقرير "نسبة تحسن الأداء" ولا يدّعي أي زيادة في السرعة.
Arayüz düz renkli görünür. Ekran kartı yükü hafifler; etkisi özellikle entegre grafikli ve düşük donanımlı sistemlerde fark edilebilir ama garanti edilmez.	The interface appears in flat colors. The graphics card load is reduced; the effect may be noticeable especially on systems with integrated graphics and low-end hardware, but it is not guaranteed.	界面将显示为纯色。显卡负载会减轻；其影响在集成显卡和低配硬件系统上尤为明显，但不作保证。	تظهر الواجهة بألوان مسطحة. يخفّ حمل بطاقة الرسومات؛ وقد يكون التأثير ملحوظاً خاصة في الأنظمة ذات الرسومات المدمجة والعتاد المنخفض، لكنه غير مضمون.
Arayüz geçişleri daha ani görünür. Güçlü bilgisayarlarda fark çok az olabilir; kazanç sistemden sisteme değişir ve garanti edilmez.	Interface transitions appear more abrupt. On powerful computers the difference may be very small; the gain varies from system to system and is not guaranteed.	界面过渡效果会显得更突然。在性能强劲的电脑上差异可能很小；收益因系统而异，不作保证。	تبدو انتقالات الواجهة أكثر فجائية. على الحواسيب القوية قد يكون الفرق ضئيلاً؛ ويختلف المكسب من نظام لآخر ولا يُضمن.
Araç başlatılamadı:	Tool could not be started:	无法启动工具：	تعذّر بدء الأداة:
Araç başlatıldı:	Tool started:	工具已启动：	تم بدء الأداة:
Araç ipucu animasyonu	Tooltip animation	工具提示动画	رسوم متحركة لتلميح الأداة
Araçlar	Tools	工具	الأدوات
Araçlar listeleme hatası:	Tools listing error:	工具列表错误：	خطأ في عرض قائمة الأدوات:
Arka plan	Background	后台	الخلفية
Arka plan (kullanıcı)	Background (user)	后台（用户）	الخلفية (المستخدم)
Arka plan oyun kaydı (Game DVR)	Background game recording (Game DVR)	后台游戏录制（Game DVR）	تسجيل الألعاب في الخلفية (Game DVR)
Arka plan oyun kaydı kapatıldı	Background game recording turned off	后台游戏录制已关闭	تم إيقاف تسجيل الألعاب في الخلفية
Arka plan*	Background*	后台*	الخلفية*
Arıza öngörülmüyor	No failure predicted	未预测到故障	لا يُتوقع أي عطل
Atlanan	Skipped	已跳过	متخطاة
Atlandı	Skipped	已跳过	تم التخطي
Ayar	Setting	设置	إعداد
Ayar geri yüklenemedi ({#}): {#}	Setting could not be restored ({1}): {2}	无法还原设置（{1}）：{2}	تعذّرت استعادة الإعداد ({1}): {2}
Ayar listesi hatası:	Settings list error:	设置列表错误：	خطأ في قائمة الإعدادات:
Ayar: {#}   [Düzey: {#}]	Setting: {1}   [Level: {2}]	设置：{1}   [级别：{2}]	الإعداد: {1}   [المستوى: {2}]
Ayarlar kaydedildi ve bakım planlandı.	Settings saved and maintenance scheduled.	设置已保存，维护已计划。	تم حفظ الإعدادات وجدولة الصيانة.
Ayarlar kaydedildi; otomatik bakım kapalı (zamanlanmış görev kaldırıldı).	Settings saved; auto maintenance is off (scheduled task removed).	设置已保存；自动维护已关闭（计划任务已删除）。	تم حفظ الإعدادات؛ الصيانة التلقائية مُعطّلة (تمت إزالة المهمة المجدولة).
Ayarları uygula	Apply settings	应用设置	تطبيق الإعدادات
Aylık	Monthly	每月	شهرياً
Ayrıntı için Microsoft belgelerine bakın; ne işe yaradığını bilmiyorsanız değiştirmeyin.	For details, see Microsoft documentation; if you don't know what it does, don't change it.	详细信息请参阅 Microsoft 文档；如果您不了解其用途，请勿更改。	للتفاصيل راجع وثائق Microsoft؛ وإذا كنت لا تعرف وظيفته فلا تغيّره.
Ayrıntılı Liste (Akıllı Optimizasyon)	Detailed List (Smart Optimization)	详细列表（智能优化）	قائمة مفصلة (التحسين الذكي)
Az önce	Just now	刚刚	الآن
AÇIK	ON	开	مُفعّل
Aç	Open	打开	فتح
Açık	On	开启	مُفعّل
Açık renkli duvar kâğıtlarında simge yazıları daha zor okunabilir.	On light-colored wallpapers, icon labels are harder to read.	在浅色壁纸上，图标文字更难辨认。	على خلفيات سطح المكتب الفاتحة، يصعب قراءة نصوص الرموز.
Açıklama	Description	说明	الوصف
Açıklama / uyarı	Description / warning	说明 / 警告	الوصف / التحذير
Açılamadı: {#}	Could not open: {1}	无法打开：{1}	تعذّر الفتح: {1}
Açılır kutu animasyonu	Dropdown box animation	下拉框动画	رسوم متحركة لصندوق القائمة المنسدلة
Açılır listelerin (combo box) kayarak açılma animasyonunu kapatır.	Turns off the sliding animation when dropdown lists (combo boxes) open.	关闭下拉列表（组合框）展开时的滑动动画。	يُوقف الرسوم المتحركة للانزلاق عند فتح القوائم المنسدلة (combo box).
Açılış süresi	Startup time	启动时间	وقت بدء التشغيل
Açılış süresi: ölçüm yok	Startup time: no measurement	启动时间：无测量数据	وقت بدء التشغيل: لا يوجد قياس
Ağ/ses/sürücü servisi	Network/audio/driver service	网络/音频/驱动程序服务	خدمة الشبكة/الصوت/برامج التشغيل
Aşınma: %{#}	Wear: %{1}	磨损：%{1}	التآكل: %{1}
BAŞARISIZ İŞLEMLER	FAILED OPERATIONS	失败的操作	العمليات الفاشلة
Bakım ayarları yüklenemedi:	Maintenance settings could not be loaded:	无法加载维护设置：	تعذّر تحميل إعدادات الصيانة:
Bakım geçmişi yazılamadı:	Could not write maintenance history:	无法写入维护历史记录：	تعذّرت كتابة سجل الصيانة:
Bakım hatası:	Maintenance error:	维护错误：	خطأ في الصيانة:
Bakım planlama hatası:	Maintenance scheduling error:	维护计划错误：	خطأ في جدولة الصيانة:
Bakım raporu	Maintenance report	维护报告	تقرير الصيانة
Bakım yalnızca sizin seçtiğiniz temizlik kategorilerini çalıştırır; başlangıç, servis veya Windows ayarı değiştirmez.	Maintenance only runs the cleanup categories you select; it does not change startup, services or Windows settings.	维护仅运行您选择的清理类别；不会更改启动项、服务或 Windows 设置。	تُشغّل الصيانة فئات التنظيف التي تختارها فقط؛ ولا تغيّر بدء التشغيل أو الخدمات أو إعدادات Windows.
Bakımda temizlenecek kategoriler (siz seçersiniz):	Categories to clean during maintenance (you choose):	维护时要清理的类别（由您选择）：	فئات التنظيف أثناء الصيانة (تختارها أنت):
Bakımı onayla	Confirm maintenance	确认维护	تأكيد الصيانة
Basit dosya aktarım protokolü istemcisi.	Simple file transfer protocol client.	简单文件传输协议客户端。	عميل بروتوكول نقل الملفات البسيط.
Bazı Windows ayarları (ör. Explorer gerektirenler) oturumu yeniden açınca etkili olur; bu yüzden sonrası ölçümde görünmeyebilir.	Some Windows settings (e.g. those requiring Explorer) take effect when you sign in again, so they may not appear in the after-measurement.	部分 Windows 设置（例如需要资源管理器的设置）在重新登录后才生效，因此可能不会出现在操作后的测量中。	تسري بعض إعدادات Windows (مثل تلك التي تتطلب Explorer) عند إعادة تسجيل الدخول، لذا قد لا تظهر في القياس اللاحق.
Bazı siteler içeriği yerel dilinizde otomatik sunamayabilir.	Some sites may not automatically serve content in your local language.	部分网站可能无法自动以您的本地语言提供内容。	قد لا تقدّم بعض المواقع المحتوى بلغتك المحلية تلقائياً.
Başarılı	Successful	成功	ناجح
Başarısız	Failed	失败	فشل
Başarısız (kutu zaten boş olabilir): {#}	Failed (the bin may already be empty): {1}	失败（回收站可能已经为空）：{1}	فشل (ربما تكون سلة المحذوفات فارغة بالفعل): {1}
Başarısız: {#}	Failed: {1}	失败：{1}	فشل: {1}
Başka bir bakım zaten çalışıyor	Another maintenance is already running	另一项维护已在运行	هناك صيانة أخرى قيد التشغيل بالفعل
Başlangıç	Startup	启动	بدء التشغيل
Başlangıç   : {#}	Startup   : {1}	启动   ：{1}	بدء التشغيل   : {1}
Başlangıç Türünü Uygula	Apply Startup Type	应用启动类型	تطبيق نوع بدء التشغيل
Başlangıç klasörü (Genel)	Startup folder (All users)	启动文件夹（所有用户）	مجلد بدء التشغيل (عام)
Başlangıç klasörü (Kullanıcı)	Startup folder (User)	启动文件夹（用户）	مجلد بدء التشغيل (المستخدم)
Başlangıç türü	Startup type	启动类型	نوع بدء التشغيل
Başlangıç türü değiştirildi	Startup type changed	启动类型已更改	تم تغيير نوع بدء التشغيل
Başlangıç türü hatası {#}: {#}	Startup type error {1}: {2}	启动类型错误 {1}：{2}	خطأ في نوع بدء التشغيل {1}: {2}
Başlangıç türünü değiştir	Change startup type	更改启动类型	تغيير نوع بدء التشغيل
Başlangıç uygulamaları gecikmesi	Startup apps delay	启动应用延迟	تأخير تطبيقات بدء التشغيل
Başlangıç uygulamaları yaklaşık 10 sn erken başlar; masaüstü açılırken yük artabilir	Startup apps start about 10 s earlier; load may increase while the desktop opens	启动应用会提前约 10 秒开始；打开桌面时负载可能会增加	تبدأ تطبيقات بدء التشغيل قبل نحو 10 ثوانٍ؛ وقد يزيد الحمل أثناء فتح سطح المكتب
Başlangıç: {#}   Bitiş: {#}   Süre: {#} sn	Start: {1}   End: {2}   Duration: {3} s	开始：{1}   结束：{2}   时长：{3} 秒	البداية: {1}   النهاية: {2}   المدة: {3} ث
Başlangıçtan kaldır: {#}	Remove from startup: {1}	从启动中移除：{1}	إزالة من بدء التشغيل: {1}
Başlat menüsündeki önerilen uygulamalar, Ayarlar içindeki öneriler ve Windows ipuçlarını kapatır.	Turns off suggested apps in the Start menu, suggestions in Settings, and Windows tips.	关闭“开始”菜单中的推荐应用、“设置”中的建议以及 Windows 提示。	يُوقف التطبيقات المقترحة في قائمة ابدأ، والاقتراحات داخل الإعدادات، ونصائح Windows.
Başlat ve Ayarlar önerileri, ipuçları	Start and Settings suggestions, tips	“开始”和“设置”建议、提示	اقتراحات ابدأ والإعدادات والنصائح
Başlatma etkisi	Startup impact	启动影响	تأثير بدء التشغيل
Başlatılamadı: {#}	Could not start: {1}	无法启动：{1}	تعذّر البدء: {1}
Beklemede	Pending	等待中	قيد الانتظار
Beklenen etki	Expected effect	预期效果	التأثير المتوقع
Bekliyor	Waiting	等待中	في الانتظار
Bellek	Memory	内存	الذاكرة
Bellek Geçmişini Göster	Show Memory History	显示内存历史	عرض سجل الذاكرة
Bellek kullanım geçmişi	Memory usage history	内存使用历史	سجل استخدام الذاكرة
Bellek sızıntısı şüphesi	Suspected memory leak	疑似内存泄漏	الاشتباه في تسريب الذاكرة
Bilgi	Information	信息	معلومات
Bilgisayar 30 dk içinde boşta olmadı (kullanıcı çalışıyor veya CPU yüksek)	Computer was not idle for 30 min (user is working or CPU is high)	电脑 30 分钟内未处于空闲状态（用户正在使用或 CPU 占用较高）	لم يكن الكمبيوتر خاملاً خلال 30 دقيقة (المستخدم يعمل أو وحدة CPU مرتفعة)
Bilinen güvenlik açıkları vardır; eski cihaz gerekmiyorsa kapalı olması önerilir.	Known security vulnerabilities exist; if no legacy device is needed, it is recommended to keep it off.	存在已知安全漏洞；如果不需要旧设备，建议保持关闭。	توجد ثغرات أمنية معروفة؛ ويُنصح بإيقافه إذا لم تكن بحاجة إلى أجهزة قديمة.
Bilinmiyor	Unknown	未知	غير معروف
Bilinmiyor (dosya bulunamadı)	Unknown (file not found)	未知（未找到文件）	غير معروف (لم يتم العثور على الملف)
Bilinmiyor (yol okunamadı)	Unknown (path could not be read)	未知（无法读取路径）	غير معروف (تعذّرت قراءة المسار)
Bir mod seçin; WinOpt bilgisayarınızı tarar, uygun ayarları listeler ve onayınızla uygular. Her değişiklik öncesinde yedeklenir ve geri alınabilir.	Select a mode; WinOpt scans your computer, lists suitable settings and applies them with your confirmation. Each change is backed up before it is made and can be reverted.	选择一种模式；WinOpt 会扫描您的电脑，列出合适的设置，并在您确认后应用。每项更改前都会先备份，并可撤销。	اختر وضعاً؛ يفحص WinOpt جهازك ويعرض الإعدادات المناسبة ويطبقها بعد موافقتك. يتم نسخ كل تغيير احتياطياً قبل إجرائه، ويمكن التراجع عنه.
Bir mod seçip "Uygula" düğmesine basın. Değişiklikler uygulanmadan önce size gösterilir ve onayınız istenir.	Select a mode and click "Apply". Changes are shown to you and your confirmation is requested before they are applied.	选择一种模式，然后点击“应用”按钮。更改在应用前会向您展示，并需要您确认。	اختر وضعاً ثم انقر على "تطبيق". تُعرض التغييرات عليك ويُطلب تأكيدك قبل تطبيقها.
Bir sistem geri yükleme noktası oluşturulacak. Birkaç saniye sürebilir.\n\nNot: Windows varsayılan olarak 24 saatte en fazla bir nokta oluşturur ve Sistem Korumasının açık olması gerekir.\n\nDevam edilsin mi?	A system restore point will be created. This may take a few seconds.\n\nNote: Windows creates at most one point every 24 hours by default, and System Protection must be turned on.\n\nContinue?	将创建一个系统还原点。可能需要几秒钟。\n\n注意：Windows 默认每 24 小时最多创建一个还原点，并且需要开启系统保护。\n\n是否继续？	سيتم إنشاء نقطة استعادة للنظام. قد يستغرق ذلك بضع ثوانٍ.\n\nملاحظة: يُنشئ Windows نقطة واحدة على الأكثر كل 24 ساعة افتراضياً، ويجب أن تكون حماية النظام مفعّلة.\n\nهل تريد المتابعة؟
Bitiş       : {#}   ({#})	End       : {1}   ({2})	结束       ：{1}   （{2}）	النهاية       : {1}   ({2})
Boyut	Size	大小	الحجم
Bozuk uygulama yolları taranıyor...	Scanning for broken app paths...	正在扫描损坏的应用路径...	جارٍ فحص مسارات التطبيقات المعطلة...
Bozuk uygulama yolu	Broken app path	损坏的应用路径	مسار تطبيق معطل
Boşta kalma süresi (dk):	Idle time (min):	空闲时间（分钟）：	مدة الخمول (دقيقة):
Bu mod için uygulanacak yeni bir ayar bulunamadı; sisteminiz bu mod için zaten uygun görünüyor.	No new setting to apply was found for this mode; your system already appears suitable for it.	未找到适用于此模式的新设置；您的系统似乎已符合此模式的要求。	لم يُعثر على إعداد جديد لتطبيقه في هذا الوضع؛ يبدو نظامك مناسباً له بالفعل.
Bu oyun işlemi için profil zaten var.	A profile already exists for this game process.	该游戏进程已有配置文件。	يوجد ملف شخصي بالفعل لعملية اللعبة هذه.
Bu plan zaten etkin.	This plan is already active.	该计划已处于启用状态。	هذه الخطة مفعّلة بالفعل.
Bu program kaldırma komutu bildirmemiş. Windows Ayarları > Uygulamalar bölümünü kullanın.	This program has not reported an uninstall command. Use Windows Settings > Apps.	该程序未报告卸载命令。请使用 Windows 设置 > 应用。	لم يُبلغ هذا البرنامج عن أمر إلغاء التثبيت. استخدم Windows Settings > Apps.
Bu sekme belleği zorla boşaltmaz ve uygulama kapatmaz. Geçmiş, uygulama açıkken dakikada bir kaydedilir.	This tab does not forcibly free memory or close apps. History is recorded every minute while the app is open.	此选项卡不会强制释放内存，也不会关闭应用。应用运行时，历史记录每分钟保存一次。	لا تُحرّر علامة التبويب هذه الذاكرة قسراً ولا تُغلق التطبيقات. يُسجَّل السجل كل دقيقة أثناء فتح التطبيق.
Bu çalıştırmada tamamlanmış oturum yok. Önceki oturumlar için Rapor Geçmişi düğmesini kullanın.	There is no completed session in this run. For previous sessions, use the Report History button.	本次运行中没有已完成的会话。如需查看之前的会话，请使用“报告历史”按钮。	لا توجد جلسة مكتملة في هذا التشغيل. للجلسات السابقة، استخدم زر "سجل التقارير".
Bulunamadı	Not found	未找到	غير موجود
Bulunamadı / bu sistemde yok	Not found / not present on this system	未找到 / 此系统中不存在	غير موجود / غير متوفر على هذا النظام
CPU kullanımı : ölçülemedi (Windows performans sayacı okunamadı)	CPU usage: could not be measured (Windows performance counter could not be read)	CPU 占用：无法测量（无法读取 Windows 性能计数器）	استخدام CPU: تعذّر القياس (تعذّرت قراءة عداد أداء Windows)
CPU kullanımı : önce %{#} (aralık %{#}-%{#})  ->  sonra %{#} (aralık %{#}-%{#})   fark {#} puan: {#}	CPU usage: before %{1} (range %{2}-%{3})  ->  after %{4} (range %{5}-%{6})   difference {7} points: {8}	CPU 占用：操作前 %{1}（范围 %{2}-%{3}）  ->  操作后 %{4}（范围 %{5}-%{6}）   差值 {7} 个百分点：{8}	استخدام CPU: قبل %{1} (النطاق %{2}-%{3})  ->  بعد %{4} (النطاق %{5}-%{6})   الفرق {7} نقطة: {8}
CPU sonra %	CPU after %	操作后 CPU %	CPU بعد %
CPU sıcaklığı	CPU temperature	CPU 温度	درجة حرارة CPU
CPU önce %	CPU before %	操作前 CPU %	CPU قبل %
CSV Raporu	CSV Report	CSV 报告	تقرير CSV
Canlı takip	Live tracking	实时跟踪	التتبع المباشر
Cuma	Friday	星期五	الجمعة
Cumartesi	Saturday	星期六	السبت
DEVRE DIŞI	DISABLED	已禁用	معطّل
DEVRE DIŞI BIRAKILAN BAŞLANGIÇ UYGULAMALARI	DISABLED STARTUP APPS	已禁用的启动应用	تطبيقات بدء التشغيل المعطلة
DEĞİŞTİRİLEN SERVİSLER	CHANGED SERVICES	已更改的服务	الخدمات المُغيّرة
DISM Onarım	DISM Repair	DISM 修复	إصلاح DISM
DNS Önbelleğini Temizle	Flush DNS Cache	清除 DNS 缓存	مسح ذاكرة DNS المؤقتة
DNS önbelleği temizlendi	DNS cache cleared	DNS 缓存已清除	تم مسح ذاكرة DNS المؤقتة
Delivery Optimization önbelleği (7 günden eski). Windows Update bileşenlerine dokunulmaz.	Delivery Optimization cache (older than 7 days). Windows Update components are not touched.	传递优化缓存（超过 7 天）。不会触及 Windows 更新组件。	ذاكرة Delivery Optimization المؤقتة (الأقدم من 7 أيام). لا يتم المساس بمكونات Windows Update.
Dengeli	Balanced	平衡	متوازن
Dengeli mod ve ek olarak düşük riskli gelişmiş ayarlar: başlangıç uygulamaları, gereksiz servisler, görsel efektler.	Balanced mode plus additional low-risk advanced settings: startup apps, unnecessary services, visual effects.	平衡模式，并额外包括低风险的高级设置：启动应用、不必要的服务、视觉效果。	الوضع المتوازن مع إعدادات متقدمة إضافية منخفضة المخاطر: تطبيقات بدء التشغيل والخدمات غير الضرورية والتأثيرات البصرية.
Dengeli: güç tüketimi ile performansı otomatik dengeler. Çoğu kullanıcı için varsayılandır.	Balanced: automatically balances power consumption and performance. It is the default for most users.	平衡：自动平衡功耗与性能。对大多数用户而言是默认设置。	متوازن: يوازن تلقائياً بين استهلاك الطاقة والأداء. وهو الافتراضي لمعظم المستخدمين.
Derin Temizlik	Deep Clean	深度清理	التنظيف العميق
Derin Temizlik taraması	Deep Clean scan	深度清理扫描	فحص التنظيف العميق
Derin temizlik hatası:	Deep Clean error:	深度清理错误：	خطأ في التنظيف العميق:
Derin temizlik tarama hatası:	Deep Clean scan error:	深度清理扫描错误：	خطأ في فحص التنظيف العميق:
Derin temizlik: {#} - silinen {#}, atlanan {#} (kullanımda {#}, erişim engeli {#}, değişen {#}), kazanılan {#}	Deep Clean: {1} - deleted {2}, skipped {3} (in use {4}, access denied {5}, changed {6}), gained {7}	深度清理：{1} - 已删除 {2}，已跳过 {3}（使用中 {4}，访问受限 {5}，已更改 {6}），已释放 {7}	التنظيف العميق: {1} - تم حذف {2}، وتخطي {3} (قيد الاستخدام {4}، ممنوع الوصول {5}، متغير {6})، واستعادة {7}
Desteklenmeyen başlangıç türü: {#}	Unsupported startup type: {1}	不支持的启动类型：{1}	نوع بدء التشغيل غير مدعوم: {1}
Devre Dışı Bırak	Disable	禁用	تعطيل
Devre dışı	Disabled	已禁用	معطّل
Değer	Value	值	القيمة
Değerlendirme	Assessment	评估	التقييم
Değişiklik Geçmişi	Change History	更改历史	سجل التغييرات
Değişiklikleri onayla	Confirm changes	确认更改	تأكيد التغييرات
Değiştirme	Replace	替换	استبدال
Değiştirme (Normal)	Replace (Normal)	替换（普通）	استبدال (عادي)
Dijital imza	Digital signature	数字签名	التوقيع الرقمي
Dikkat	Caution	注意	تنبيه
DirectX shader önbelleği silinince oyunlar/uygulamalar ilk açılışta shader'ları yeniden derler (kısa süreli takılma).	When the DirectX shader cache is deleted, games/apps recompile shaders on first launch (brief stutter).	删除 DirectX 着色器缓存后，游戏和应用会在首次启动时重新编译着色器（短暂卡顿）。	عند حذف ذاكرة DirectX المؤقتة للمظللات، تعيد الألعاب والتطبيقات تجميع المظللات عند أول تشغيل (تقطّع قصير).
Disk Denetimi (salt okunur)	Disk Check (read-only)	磁盘检查（只读）	فحص القرص (للقراءة فقط)
Disk modeli	Disk model	磁盘型号	طراز القرص
Disk sağlık verisi	Disk health data	磁盘健康数据	بيانات صحة القرص
Disk sağlığı:	Disk health:	磁盘健康状况：	صحة القرص:
Diğer	Other	其他	أخرى
Dosya	File	文件	ملف
Dosya Konumunu Aç	Open File Location	打开文件位置	فتح موقع الملف
Dosya Temizliği	File Cleanup	文件清理	تنظيف الملفات
Dosya bulunamadı.	File not found.	未找到文件。	لم يتم العثور على الملف.
Dosya dizinleme ve arama hizmeti.	File indexing and search service.	文件索引和搜索服务。	خدمة فهرسة الملفات والبحث.
Dosya yaşı	File age	文件年龄	عمر الملف
Dosya yaşı (TEMP/uygulama):	File age (TEMP/app):	文件年龄（TEMP/应用）：	عمر الملف (TEMP/التطبيق):
Dosya yolu	File path	文件路径	مسار الملف
Dosya yolu bulunamadı.	File path not found.	未找到文件路径。	لم يتم العثور على مسار الملف.
Dosya yolu okunamadı (yetki)	File path could not be read (permission)	无法读取文件路径（权限不足）	تعذرت قراءة مسار الملف (صلاحيات)
Doğrulanamadı	Could not be verified	无法验证	تعذر التحقق
Doğrulanmadı	Not verified	未验证	لم يتم التحقق
Durdu	Stopped	已停止	توقف
Durduruldu	Stopped	已停止	تم الإيقاف
Durum	Status	状态	الحالة
Düzeltilemeyen okuma hatası: {#}	Unrecoverable read error: {1}	无法修复的读取错误：{1}	خطأ قراءة غير قابل للإصلاح: {1}
Düzey	Level	级别	المستوى
Düşük	Low	低	منخفض
Düşük-orta; güç tüketimi ve ısı artar, FPS artışı garanti edilmez	Low-medium; increases power use and heat, FPS gain is not guaranteed	中低：会增加功耗和发热，不保证FPS提升	منخفض-متوسط؛ يزيد استهلاك الطاقة والحرارة، ولا يُضمن ارتفاع معدل الإطارات
Düşük; arka plan işlemi ve az miktarda RAM/CPU azalır	Low; reduces background processes and a small amount of RAM/CPU usage	低：减少后台进程及少量内存/CPU占用	منخفض؛ يقلل عمليات الخلفية وكمية قليلة من ذاكرة الوصول العشوائي/المعالج
ETKİNLEŞTİRİLDİ	ENABLED	已启用	تم التفعيل
Ekran kartı	Graphics card	显卡	بطاقة الرسوميات
Eksik hedef	Missing target	缺少目标	هدف مفقود
Elle	Manual	手动	يدوي
Elle bitirildi	Finished manually	已手动完成	اكتمل يدويًا
Elle İzle (Çalışan)	Manual Monitor (Running)	手动监控（运行中）	مراقبة يدوية (قيد التشغيل)
En Hızlı	Fastest	最快	الأسرع
En güvenli	Safest	最安全	الأكثر أمانًا
Eski Bileşenler	Legacy Components	旧版组件	المكونات القديمة
Eski PowerShell motoru.	Legacy PowerShell engine.	旧版 PowerShell 引擎。	محرك PowerShell القديم.
Eski PowerShell sürümü.	Legacy PowerShell version.	旧版 PowerShell 版本。	إصدار PowerShell القديم.
Eski grafik önbellekleri (NVIDIA/AMD/Intel)	Old graphics caches (NVIDIA/AMD/Intel)	旧显卡缓存（NVIDIA/AMD/Intel）	ذاكرات الرسوميات القديمة (NVIDIA/AMD/Intel)
Eski hata raporları	Old error reports	旧错误报告	تقارير الأخطاء القديمة
Eski medya oynatıcı.	Legacy media player.	旧版媒体播放器。	مشغل الوسائط القديم.
Eski oyun oynuyorsanız gerekebilir.	May be needed if you play older games.	如果您玩旧游戏，可能需要。	قد تكون مطلوبة إذا كنت تلعب ألعابًا قديمة.
Eski oyun ve programlar için uyumluluk bileşenleri.	Compatibility components for older games and programs.	旧游戏和程序的兼容性组件。	مكونات التوافق للألعاب والبرامج القديمة.
Eski program kullanıyorsanız kapatmayın.	Do not disable if you use older programs.	如果您使用旧程序，请勿关闭。	لا تُعطّلها إذا كنت تستخدم برامج قديمة.
Eski teslim iyileştirme dosyaları	Old Delivery Optimization files	旧的传递优化文件	ملفات تحسين التسليم القديمة
Eski uygulama ve oyunların çalışması için gerekebilir.	May be needed for older apps and games to run.	旧应用和游戏运行可能需要。	قد تكون مطلوبة لتشغيل التطبيقات والألعاب القديمة.
Eski ve denetimi zayıf bir ortamdır; gerekmiyorsa kapalı olması önerilir.	Old, weakly controlled environment; if not needed, it is recommended to keep it off.	这是一个旧的、管控较弱的环境；如不需要，建议保持关闭。	بيئة قديمة وضعيفة الرقابة؛ يُنصح بإيقافها إن لم تكن مطلوبة.
Eski web tarayıcısı.	Legacy web browser.	旧版网页浏览器。	متصفح الويب القديم.
Eski yazılım kullanıyorsanız gerekebilir.	May be needed if you use older software.	如果您使用旧软件，可能需要。	قد تكون مطلوبة إذا كنت تستخدم برامج قديمة.
Etkili olma	Take effect	生效	السريان
Etkili olma zamanı: {#}	Takes effect at: {1}	生效时间：{1}	وقت السريان: {1}
Etkin	Active	活动	نشط
Etkin / Pasif Yap	Enable / Disable	启用 / 禁用	تفعيل / تعطيل
Etkin olduğunda hipervizör katmanı çalışır; küçük bir ek yük oluşturabilir.	When enabled, the hypervisor layer runs and may add a small overhead.	启用后，虚拟机监控程序层将运行，可能带来少量额外开销。	عند التفعيل، تعمل طبقة المشرف الافتراضي وقد تضيف حملًا بسيطًا.
Etkin oturumdaki profil düzenlenemez; oyun kapandıktan sonra deneyin.	The profile in the active session cannot be edited; try after the game closes.	无法编辑当前会话中的配置文件；请在游戏关闭后重试。	لا يمكن تعديل الملف الشخصي في الجلسة النشطة؛ جرّب بعد إغلاق اللعبة.
Etkin oturumdaki profil silinemez.	The profile in the active session cannot be deleted.	无法删除当前会话中的配置文件。	لا يمكن حذف الملف الشخصي في الجلسة النشطة.
Etkin oyun oturumu yok.	No active game session.	没有正在进行的游戏会话。	لا توجد جلسة لعب نشطة.
Etkinse sanallaştırma tabanlı güvenlik ile birlikte bazı oyunlarda küçük performans kaybı oluşabilir. Sanal makine kullanmıyorsanız gerekmeyebilir.	If enabled, some games may see a small performance loss with virtualization-based security. Not needed if you don't use virtual machines.	启用后，基于虚拟化的安全功能可能导致部分游戏出现轻微性能损失。如果不使用虚拟机，则可能不需要。	إذا فُعّلت، قد تشهد بعض الألعاب انخفاضًا طفيفًا في الأداء مع الأمان المعتمد على الافتراضية. قد لا تكون مطلوبة إن لم تكن تستخدم أجهزة افتراضية.
Etkisi oyuna ve donanıma göre değişir; bazı oyunlarda fark yok, nadiren takılma bildirilmiştir. FPS artışı garanti edilmez. Sorun yaşarsanız kapatın.	The effect varies by game and hardware; in some games there is no difference, and stuttering has rarely been reported. FPS gain is not guaranteed. Turn it off if you have problems.	效果因游戏和硬件而异；部分游戏没有差异，偶有卡顿的报告。不保证FPS提升。如遇问题请关闭。	يختلف التأثير حسب اللعبة والعتاد؛ في بعض الألعاب لا يوجد فرق، وقد أُفيد نادرًا بحدوث تقطّع. لا يُضمن ارتفاع معدل الإطارات. أوقفها إذا واجهت مشكلات.
Evet	Yes	是	نعم
Explorer kullandığı dosyaları kilitler; kilitli dosyalar atlanır, Explorer kapatılmaz.	Locks files used by Explorer; locked files are skipped, Explorer is not closed.	锁定 Explorer 正在使用的文件；被锁定的文件将被跳过，Explorer 不会关闭。	يقفل الملفات التي يستخدمها Explorer؛ تُتخطى الملفات المقفلة، ولا يُغلق Explorer.
Explorer yeniden başlayınca	When Explorer restarts	Explorer 重新启动时	عند إعادة تشغيل Explorer
FPS odaklı	FPS-focused	以FPS为重点	موجّه نحو معدل الإطارات
Faks	Fax	传真	فاكس
Fare imleci gölgesi	Mouse cursor shadow	鼠标指针阴影	ظل مؤشر الماوس
Fare imlecinin altındaki gölgeyi kapatır.	Turns off the shadow under the mouse cursor.	关闭鼠标指针下方的阴影。	يُوقف الظل الموجود أسفل مؤشر الماوس.
Fare üzerine gelince çıkan ipucu kutularının solarak belirmesini kapatır.	Turns off the fade-in of tooltips shown on hover.	关闭鼠标悬停时工具提示的淡入效果。	يُوقف ظهور مربعات التلميحات عند تمرير الماوس بتأثير التلاشي.
GERİ ALINABİLİR DEĞİŞİKLİKLER	REVERSIBLE CHANGES	可撤销的更改	التغييرات القابلة للتراجع
GERİ ALINAMAYAN İŞLEMLER	IRREVERSIBLE ACTIONS	不可撤销的操作	الإجراءات غير القابلة للتراجع
GERİ DÖNÜŞÜM KUTUSU KALICI OLARAK BOŞALTILIR; içindeki dosyalar geri getirilemez.	THE RECYCLE BIN WILL BE PERMANENTLY EMPTIED; files in it cannot be recovered.	回收站将被永久清空；其中的文件无法恢复。	سيتم إفراغ سلة المحذوفات نهائيًا؛ لا يمكن استعادة الملفات الموجودة فيها.
GERİ YÜKLEME	RESTORE	还原	استعادة
GPU kullanımı sürekli yüksek göründü; grafik ayarlarını düşürmek daha etkili olabilir.	GPU usage appeared consistently high; lowering graphics settings may be more effective.	GPU 使用率持续偏高；降低图形设置可能更有效。	بدا استخدام وحدة المعالجة الرسومية مرتفعًا باستمرار؛ قد يكون خفض إعدادات الرسوميات أكثر فعالية.
GPU modeli	GPU model	GPU 型号	طراز وحدة معالجة الرسوميات
GPU sıcaklığı	GPU temperature	GPU 温度	درجة حرارة وحدة معالجة الرسوميات
Game Bar kısayolları ve kontrolcü düğmesiyle açma çalışmaz. Win+G ile elle açma Windows sürümüne göre değişebilir.	Opening Game Bar with shortcuts and the controller button will not work. Manually opening with Win+G may vary by Windows version.	使用快捷键和手柄按钮打开 Game Bar 将无法工作。通过 Win+G 手动打开的方式因 Windows 版本而异。	لن يعمل فتح Game Bar باختصارات لوحة المفاتيح وزر وحدة التحكم. قد يختلف الفتح اليدوي عبر Win+G حسب إصدار Windows.
Gecikme yok (0 ms)	No delay (0 ms)	无延迟（0 毫秒）	بدون تأخير (0 مللي ثانية)
Gelişmiş	Advanced	高级	متقدم
Gerekmiyorsa kapalı kalabilir.	Can stay off if not needed.	如果不需要，可以保持关闭。	يمكن أن تبقى معطلة إن لم تكن مطلوبة.
Gerekmiyorsa kapalı kalması önerilir.	It is recommended to keep it off if not needed.	如果不需要，建议保持关闭。	يُنصح بإبقائها معطلة إن لم تكن مطلوبة.
Gerekmiyorsa kapalı olması önerilir.	It is recommended to keep it off if not needed.	如果不需要，建议保持关闭。	يُنصح بإبقائها معطلة إن لم تكن مطلوبة.
Gereksiz Dosyaları Tara	Scan for Unnecessary Files	扫描不必要的文件	فحص الملفات غير الضرورية
Gereksiz uygulama önbellekleri	Unnecessary app caches	不必要的应用缓存	ذاكرات التطبيقات غير الضرورية
Geri Dönüşüm Kutusu boşaltıldı	Recycle Bin emptied	回收站已清空	تم إفراغ سلة المحذوفات
Geri Dönüşüm Kutusu boşaltıldı.	Recycle Bin emptied.	回收站已清空。	تم إفراغ سلة المحذوفات.
Geri Dönüşüm Kutusunu Boşalt	Empty Recycle Bin	清空回收站	إفراغ سلة المحذوفات
Geri Dönüşüm|Çöp	Recycle Bin|Trash	回收站|垃圾	سلة المحذوفات|المهملات
Geri Yükle	Restore	还原	استعادة
Geri Yükleme Noktaları	Restore Points	还原点	نقاط الاستعادة
Geri Yükleme Noktaları (son 20)	Restore Points (last 20)	还原点（最近 20 个）	نقاط الاستعادة (آخر 20)
Geri Yükleme Noktası Oluştur	Create Restore Point	创建还原点	إنشاء نقطة استعادة
Geri alma	Undo	撤销	التراجع
Geri alma hatası:	Undo error:	撤销错误：	خطأ في التراجع:
Geri alma imkânı: {#}	Undo available: {1}	可撤销：{1}	إمكانية التراجع: {1}
Geri alma tamamlandı: {#} başarılı, {#} hatalı.	Undo completed: {1} succeeded, {2} failed.	撤销完成：{1} 成功，{2} 失败。	اكتمل التراجع: {1} ناجح، {2} فاشل.
Geri alma: Akıllı Optimizasyon sekmesinde "Son Uygulamayı Geri Al" düğmesi.	Undo: "Undo Last Action" button on the Smart Optimization tab.	撤销：智能优化选项卡中的“撤销上次操作”按钮。	التراجع: زر "التراجع عن آخر إجراء" في تبويب التحسين الذكي.
Geri alma: Uygulamadan önce önceki değer yedeklenir; Önceki Ayara Dön düğmesiyle geri yüklenir.	Undo: the previous value is backed up before applying; it is restored with the "Revert to Previous Setting" button.	撤销：应用前会备份之前的值；可通过“恢复到之前的设置”按钮还原。	التراجع: يُحفظ احتياطيًا بالقيمة السابقة قبل التطبيق، وتُستعاد بزر "العودة إلى الإعداد السابق".
Geri almayı onayla	Confirm undo	确认撤销	تأكيد التراجع
Geri alınacak bir Akıllı Optimizasyon işlemi yok (geçici dosya temizliği geri alınamaz).	There is no Smart Optimization action to undo (temporary file cleanup cannot be undone).	没有可撤销的智能优化操作（临时文件清理无法撤销）。	لا توجد إجراءات تحسين ذكي للتراجع عنها (لا يمكن التراجع عن تنظيف الملفات المؤقتة).
Geri alınamaz	Cannot be undone	无法撤销	لا يمكن التراجع
Geri alınamaz (geçici dosyalar silinir); uygulamalar gerekirse yeniden oluşturur.	Cannot be undone (temporary files are deleted); apps recreate them if needed.	无法撤销（临时文件将被删除）；应用会在需要时重新生成。	لا يمكن التراجع (تُحذف الملفات المؤقتة)؛ تعيد التطبيقات إنشاءها عند الحاجة.
Geri bildirim isteme sıklığı	Feedback request frequency	反馈请求频率	تكرار طلب الملاحظات
Geri dönüşüm kutusu	Recycle Bin	回收站	سلة المحذوفات
Geri yükle	Restore	还原	استعادة
Geri yükleme noktası hatası:	Restore point error:	还原点错误：	خطأ في نقطة الاستعادة:
Geri yükleme noktası oluşturulamadı:\n\n{#}\n\nSistem Koruması kapalı olabilir (Sistem Özellikleri > Sistem Koruması).	Could not create restore point:\n\n{1}\n\nSystem Protection may be turned off (System Properties > System Protection).	无法创建还原点：\n\n{1}\n\n系统保护可能已关闭（系统属性 > 系统保护）。	تعذّر إنشاء نقطة الاستعادة:\n\n{1}\n\nقد تكون حماية النظام معطلة (خصائص النظام > حماية النظام).
Geri yükleme noktası oluşturuldu	Restore point created	已创建还原点	تم إنشاء نقطة الاستعادة
Geri yükleme noktası uyarısı:	Restore point warning:	还原点警告：	تحذير نقطة الاستعادة:
Geri yüklenecek kayıt yok.	No records to restore.	没有可还原的记录。	لا توجد سجلات لاستعادتها.
Geri yüklenecek yedek bulunamadı.	No backup found to restore.	未找到可还原的备份。	لم يتم العثور على نسخة احتياطية للاستعادة.
Geri yüklenecek yedeği seçin	Select the backup to restore	选择要还原的备份	اختر النسخة الاحتياطية للاستعادة
Geçerli kullanıcı	Current user	当前用户	المستخدم الحالي
Geçerli: {#}	Valid: {1}	有效：{1}	صالح: {1}
Geçersiz ({#})	Invalid ({1})	无效（{1}）	غير صالح ({1})
Geçersiz başlangıç girdileri taranıyor...	Scanning for invalid startup entries...	正在扫描无效的启动项...	جارٍ فحص إدخالات بدء التشغيل غير الصالحة...
Geçersiz başlangıç girdisi	Invalid startup entry	无效的启动项	إدخال بدء تشغيل غير صالح
Geçersiz*	Invalid*	无效*	غير صالح*
Geçici dosyaları temizle (Kullanıcı TEMP)	Clean temporary files (User TEMP)	清理临时文件（用户 TEMP）	تنظيف الملفات المؤقتة (TEMP للمستخدم)
Geçici internet dosyaları	Temporary Internet files	Internet 临时文件	ملفات الإنترنت المؤقتة
Geçici kapatılacak uygulamalar	Apps to temporarily close	需要临时关闭的应用	التطبيقات التي ستُغلق مؤقتًا
Geçmiş	History	历史记录	السجل
Geçmişi Yenile	Refresh History	刷新历史记录	تحديث السجل
Gizlilik	Privacy	隐私	الخصوصية
Grafik sürücüsü shader önbellekleri; sürücü kendiliğinden yeniden üretir.	Graphics driver shader caches; the driver regenerates them automatically.	图形驱动程序着色器缓存；驱动程序会自动重新生成。	ذاكرات المظللات (Shader) لبرنامج تشغيل الرسوميات؛ يعيد البرنامج إنشاءها تلقائيًا.
Grafik sürücüsü önbellekleri (7 günden eski) silinince oyunlar ilk açılışta shader'ları yeniden oluşturabilir.	When graphics driver caches (older than 7 days) are deleted, games may rebuild shaders on first launch.	删除图形驱动程序缓存（7 天以上）后，游戏首次启动时可能会重新生成着色器。	عند حذف ذاكرات برنامج تشغيل الرسوميات (الأقدم من 7 أيام)، قد تعيد الألعاب بناء المظللات عند أول تشغيل.
Görev	Task	任务	مهمة
Görev Zamanlayıcı	Task Scheduler	任务计划程序	جدولة المهام
Görev çubuğu animasyonları	Taskbar animations	任务栏动画	رسوم متحركة شريط المهام
Görev çubuğu, Başlat menüsü ve pencerelerdeki saydam/bulanık (akrilik, mika) arka planı kapatır.	Turns off the transparent/blurred (acrylic, mica) background in the taskbar, Start menu and windows.	关闭任务栏、开始菜单和窗口中的透明/模糊（亚克力、云母）背景。	يُوقف الخلفية الشفافة/الضبابية (أكريليك، ميكا) في شريط المهام وقائمة ابدأ والنوافذ.
Görev çubuğundaki düğme ve önizleme animasyonlarını kapatır.	Turns off button and preview animations on the taskbar.	关闭任务栏上的按钮和预览动画。	يُوقف رسوم الأزرار ومعاينة الصور المتحركة في شريط المهام.
Görsel efektler	Visual effects	视觉效果	المؤثرات البصرية
Görünen ad	Display name	显示名称	اسم العرض
Gözat...	Browse...	浏览...	استعراض...
Gün:	Day:	日：	اليوم:
Günlük	Daily	每日	يومي
Günlüğü Aç	Open Log	打开日志	فتح السجل
Güvenli	Safe	安全	آمن
Güvenli Olanları Seç	Select Safe Ones	选择安全项	تحديد الآمنة
Güvenli Seçim	Safe Selection	安全选择	تحديد آمن
Güvenlik bileşeni	Security component	安全组件	مكوّن أمني
Güvenlik güncellemesi almaz; gerekmiyorsa kapalı olması önerilir.	Does not receive security updates; it is recommended to keep it off if not needed.	不接收安全更新；如不需要，建议保持关闭。	لا يتلقى تحديثات أمنية؛ يُنصح بإيقافها إن لم تكن مطلوبة.
Güvenlik için tek seferde en fazla 5 servis değiştirilebilir.	For safety, at most 5 services can be changed at once.	为安全起见，一次最多只能更改 5 项服务。	لأسباب أمنية، يمكن تغيير 5 خدمات كحد أقصى في المرة الواحدة.
Güvenlik için tek seferde en fazla 5 servis durdurulabilir.	For safety, at most 5 services can be stopped at once.	为安全起见，一次最多只能停止 5 项服务。	لأسباب أمنية، يمكن إيقاف 5 خدمات كحد أقصى في المرة الواحدة.
Güç Planını Uygula	Apply Power Plan	应用电源计划	تطبيق خطة الطاقة
Güç planı	Power plan	电源计划	خطة الطاقة
Güç planı '{#}' olarak değiştirilecek.	Power plan will be changed to '{1}'.	电源计划将更改为“{1}”。	ستُغيَّر خطة الطاقة إلى '{1}'.
Güç planı değiştirildi: {#}	Power plan changed: {1}	电源计划已更改：{1}	تم تغيير خطة الطاقة: {1}
Güç planı değiştirilemedi:	Could not change power plan:	无法更改电源计划：	تعذّر تغيير خطة الطاقة:
Güç planı ekle	Add power plan	添加电源计划	إضافة خطة طاقة
Güç planı geri yüklendi:	Power plan restored:	电源计划已还原：	تمت استعادة خطة الطاقة:
Güç planı geri yüklenemedi:	Could not restore power plan:	无法还原电源计划：	تعذّرت استعادة خطة الطاقة:
Güç planı:	Power plan:	电源计划：	خطة الطاقة:
Güç planı: {#} -> {#}	Power plan: {1} -> {2}	电源计划：{1} -> {2}	خطة الطاقة: {1} -> {2}
Güç planı: {#}{#}	Power plan: {1}{2}	电源计划：{1}{2}	خطة الطاقة: {1}{2}
Güç tasarrufu: performansı sınırlar, pil ömrünü uzatır. Oyun ve ağır işlerde yavaşlık hissedilebilir.	Power saver: limits performance, extends battery life. Slowdowns may be noticeable in games and heavy tasks.	节能模式：限制性能，延长电池续航。游戏和高负载任务中可能会感觉变慢。	توفير الطاقة: يحدّ من الأداء ويطيل عمر البطارية. قد يُلاحظ بطء في الألعاب والمهام الثقيلة.
Haftalık	Weekly	每周	أسبوعي
Haritalar	Maps	地图	الخرائط
Haritalar, hava durumu, Cihazımı Bul ve konum isteyen uygulamalar çalışmaz veya yanlış bölge gösterebilir.	Maps, weather, Find My Device and apps that request location may not work or may show the wrong region.	地图、天气、“查找我的设备”以及需要位置信息的应用可能无法工作，或显示错误的区域。	قد لا تعمل الخرائط والطقس و"البحث عن جهازي" والتطبيقات التي تطلب الموقع، أو قد تعرض منطقة خاطئة.
Hata	Error	错误	خطأ
Hata ({#}); geri alma da başarısız, yedek: {#}	Error ({1}); undo also failed, backup: {2}	错误（{1}）；撤销也失败，备份：{2}	خطأ ({1}); فشل التراجع أيضًا، النسخة الاحتياطية: {2}
Hata ({#}); yedekten geri alındı.	Error ({1}); restored from backup.	错误（{1}）；已从备份还原。	خطأ ({1}); تمت الاستعادة من النسخة الاحتياطية.
Hayır	No	否	لا
Hazır	Ready	就绪	جاهز
Hazır (kayıt sayısı okunamadı)	Ready (record count could not be read)	就绪（无法读取记录数）	جاهز (تعذّرت قراءة عدد السجلات)
Hemen	Immediately	立即	فورًا
Henüz bakım raporu yok.	No maintenance report yet.	暂无维护报告。	لا يوجد تقرير صيانة بعد.
Henüz işlem günlüğü yok.	No action log yet.	暂无操作日志。	لا يوجد سجل إجراءات بعد.
Henüz kayıt yok.	No records yet.	暂无记录。	لا توجد سجلات بعد.
Henüz oturum yok.	No sessions yet.	暂无会话。	لا توجد جلسات بعد.
Henüz rapor yok.	No reports yet.	暂无报告。	لا توجد تقارير بعد.
Henüz yedek yok.	No backups yet.	暂无备份。	لا توجد نسخ احتياطية بعد.
Henüz yok	Not yet	暂无	لا يوجد بعد
Hyper-V altyapısı kullanır; kaynak tüketimi artabilir.	Uses Hyper-V infrastructure; resource usage may increase.	使用 Hyper-V 基础结构；资源占用可能增加。	يستخدم بنية Hyper-V؛ قد يزداد استهلاك الموارد.
Hyper-V altyapısına dayanır; kullanmıyorsanız gerekmez.	Relies on Hyper-V infrastructure; not needed if you don't use it.	依赖 Hyper-V 基础结构；如果不使用则不需要。	يعتمد على بنية Hyper-V؛ غير مطلوب إن لم تكن تستخدمه.
Hızlı	Fast	快速	سريع
Hızlı Mod	Quick Mode	快速模式	الوضع السريع
Hızlı mod hatası:	Quick mode error:	快速模式错误：	خطأ الوضع السريع:
Hızlı İşlemler	Quick Actions	快速操作	إجراءات سريعة
KAYNAK KULLANIMI	RESOURCE USAGE	资源占用	استخدام الموارد
Kaldır	Remove	卸载	إزالة
Kaldırıcı açılamadı:	Could not open uninstaller:	无法打开卸载程序：	تعذّر فتح أداة الإزالة:
Kaldırıcı açıldı:	Uninstaller opened:	卸载程序已打开：	تم فتح أداة الإزالة:
Kaldırılmış uygulama kalıntıları taranıyor...	Scanning for leftovers from uninstalled apps...	正在扫描已卸载应用的残留项...	جارٍ فحص بقايا التطبيقات المحذوفة...
Kaldırılmış uygulama kalıntısı	Leftover from uninstalled app	已卸载应用的残留项	بقايا تطبيق تمت إزالته
Kalıcı silme olduğu için varsayılan olarak seçili değildir.	Not selected by default because deletion is permanent.	由于是永久删除，默认不选中。	غير محدد افتراضيًا لأن الحذف دائم.
Kapalı	Off	关闭	متوقف
Kapat	Close	关闭	إغلاق
Kapatma önerisi	Close suggestion	关闭建议	اقتراح الإغلاق
Kapatmayı düşünün: {#} (PID {#})	Consider closing: {1} (PID {2})	建议关闭：{1}（PID {2}）	فكّر في إغلاق: {1} (PID {2})
Kapatılacak uygulamaları seçin	Select apps to close	选择要关闭的应用	اختر التطبيقات المراد إغلاقها
Kapatılırsa arama yavaşlar veya çalışmaz.	If turned off, search will be slow or stop working.	如果关闭，搜索会变慢或无法工作。	إذا أُوقف، سيصبح البحث بطيئًا أو لن يعمل.
Kapatırsanız PDF olarak yazdırma kaybolur.	If you turn it off, Print to PDF will disappear.	如果关闭，“打印为 PDF”将消失。	إذا أوقفتها، ستختفي خاصية الطباعة إلى PDF.
Kapsam	Scope	范围	النطاق
Kategori	Category	类别	الفئة
Kaydet	Save	保存	حفظ
Kaydet ve Planla	Save and Schedule	保存并计划	حفظ وجدولة
Kaydırma daha sert hissedilebilir. Performansa etkisi genellikle çok küçüktür.	Scrolling may feel firmer. Performance impact is usually very small.	滚动可能会感觉更生硬。对性能的影响通常很小。	قد يبدو التمرير أكثر صلابة. عادةً يكون تأثيره على الأداء ضئيلًا جدًا.
Kaynak	Source	来源	المصدر
Kayıt Defteri	Registry	注册表	سجل النظام
Kayıt defteri temizliğini onayla	Confirm registry cleanup	确认注册表清理	تأكيد تنظيف سجل النظام
Kayıt yolu	Registry path	注册表路径	مسار السجل
Kayıtlı geri yükleme noktası bulunamadı (Sistem Koruması kapalı olabilir).	No saved restore point found (System Protection may be off).	未找到已保存的还原点（系统保护可能已关闭）。	لم يتم العثور على نقطة استعادة محفوظة (قد تكون حماية النظام معطلة).
Kazanılan	Gained	已释放	المكتسب
Kazanılan alan	Space gained	释放的空间	المساحة المحررة
Kazanılan bayt	Bytes gained	释放的字节	البايتات المحررة
Kişiselleştirilmiş deneyimler	Personalized experiences	个性化体验	تجارب مخصصة
Klasör	Folder	文件夹	المجلد
Klasörü Aç	Open Folder	打开文件夹	فتح المجلد
Komut	Command	命令	الأمر
Komut hatasız tamamlandı. Noktayı 'Geri Yükleme Noktaları' düğmesiyle listede görebilirsiniz.	Command completed without errors. You can see the point in the list with the "Restore Points" button.	命令已成功完成。您可以使用“还原点”按钮在列表中查看该还原点。	اكتمل الأمر بدون أخطاء. يمكنك رؤية النقطة في القائمة بزر "نقاط الاستعادة".
Konum erişimi (kullanıcı için)	Location access (for user)	位置访问（针对用户）	الوصول إلى الموقع (للمستخدم)
Koruma / kategori	Protection / category	保护 / 类别	الحماية / الفئة
Korumalı	Protected	受保护	محمي
Korumalı işlemler	Protected processes	受保护的进程	العمليات المحمية
Korumalı kayıtlar	Protected registry entries	受保护的注册表项	إدخالات السجل المحمية
Korumalı servisler	Protected services	受保护的服务	الخدمات المحمية
Korumalı: {#}	Protected: {1}	受保护：{1}	محمي: {1}
Kritik Windows işlemi	Critical Windows process	关键 Windows 进程	عملية Windows حرجة
Kritik Windows servisi	Critical Windows service	关键 Windows 服务	خدمة Windows حرجة
Kullanmıyorsanız durdurulabilir	Can be stopped if you don't use it	如果不使用可以停止	يمكن إيقافها إن لم تكن تستخدمها
Kullanmıyorsanız kapalı kalabilir.	Can stay off if you don't use it.	如果不使用，可以保持关闭。	يمكن أن تبقى معطلة إن لم تكن تستخدمها.
Kullanmıyorsanız kapalı kalabilir; doğrudan performans etkisi küçüktür.	Can stay off if you don't use it; direct performance impact is small.	如果不使用，可以保持关闭；对性能的直接影响较小。	يمكن أن تبقى معطلة إن لم تكن تستخدمها؛ التأثير المباشر على الأداء صغير.
Kullanıcı TEMP klasörü	User TEMP folder	用户 TEMP 文件夹	مجلد TEMP للمستخدم
Kullanıcı TEMP klasörü (Akıllı Optimizasyon)	User TEMP folder (Smart Optimization)	用户 TEMP 文件夹（智能优化）	مجلد TEMP للمستخدم (التحسين الذكي)
Kullanıcı TEMP klasöründe eski (kullanılmayan) geçici dosyalar birikmiş.	Old (unused) temporary files have accumulated in the user TEMP folder.	用户 TEMP 文件夹中积累了旧的（未使用的）临时文件。	تراكمت ملفات مؤقتة قديمة (غير مستخدمة) في مجلد TEMP للمستخدم.
Kullanılmayan günlük dosyaları	Unused log files	未使用的日志文件	ملفات السجل غير المستخدمة
Kullanılmayan uygulama yapılandırmaları taranıyor...	Scanning for unused app configurations...	正在扫描未使用的应用配置...	جارٍ فحص إعدادات التطبيقات غير المستخدمة...
Kullanılmayan uygulama yapılandırması	Unused app configuration	未使用的应用配置	إعداد تطبيق غير مستخدم
Kurulum tarihi	Install date	安装日期	تاريخ التثبيت
Kurumsal klasör eşitleme.	Enterprise folder sync.	企业文件夹同步。	مزامنة المجلدات المؤسسية.
Kurumsal kullanım dışında gerekmez.	Not needed outside enterprise use.	企业使用以外无需此功能。	غير مطلوب خارج الاستخدام المؤسسي.
Küçük resim önbelleği Explorer tarafından yeniden oluşturulur (klasörler ilk açılışta biraz yavaş olabilir).	The thumbnail cache is rebuilt by Explorer (folders may be slightly slow to open at first).	缩略图缓存会由 Explorer 重新生成（文件夹首次打开可能会稍慢）。	يعيد Explorer بناء ذاكرة الصور المصغرة (قد تكون المجلدات أبطأ قليلًا عند فتحها أول مرة).
Kısmen başarılı	Partially successful	部分成功	نجح جزئيًا
Kısmen uygulandı:	Partially applied:	部分已应用：	طُبّق جزئيًا:
Linux için Windows Alt Sistemi	Windows Subsystem for Linux	适用于 Linux 的 Windows 子系统	نظام Windows الفرعي لـ Linux
Liste kutularında yumuşak kaydırmayı kapatır; kaydırma satır satır ilerler.	Turns off smooth scrolling in list boxes; scrolling moves line by line.	关闭列表框中的平滑滚动；滚动将逐行进行。	يُوقف التمرير السلس في مربعات القوائم؛ يتحرك التمرير سطرًا سطرًا.
Liste kutusu yumuşak kaydırma	List box smooth scrolling	列表框平滑滚动	التمرير السلس لمربعات القوائم
Liste okunamadı: {#}	List could not be read: {1}	无法读取列表：{1}	تعذّرت قراءة القائمة: {1}
Listelenecek uygulama yok (ilk ölçüm bekleniyor olabilir).	No apps to list (initial measurement may still be pending).	没有可列出的应用（可能仍在等待首次测量）。	لا توجد تطبيقات لعرضها (قد تكون القياسات الأولى قيد الانتظار).
Lütfen bekleyin	Please wait	请稍候	يُرجى الانتظار
Maksimum performans	Maximum performance	最高性能	أقصى أداء
Masaüstü bilgisayar algılandı (pil yok); yüksek performans planı işlemci hızını daha yüksek tutar.	Desktop PC detected (no battery); the High Performance plan keeps CPU speed higher.	检测到台式机（无电池）；高性能计划可使处理器保持更高速度。	تم اكتشاف كمبيوتر مكتبي (بدون بطارية)؛ تُبقي خطة الأداء العالي سرعة المعالج أعلى.
Masaüstü simge adlarının arkasındaki gölgeyi kapatır.	Turns off the shadow behind desktop icon names.	关闭桌面图标名称背后的阴影。	يُوقف الظل خلف أسماء أيقونات سطح المكتب.
Masaüstü simge etiketi gölgesi	Desktop icon label shadow	桌面图标标签阴影	ظل تسميات أيقونات سطح المكتب
Mavi: oyun CPU %   Turuncu: oyun GPU %   Yeşil: sistem RAM %   (son ~6 dk)	Blue: game CPU %   Orange: game GPU %   Green: system RAM %   (last ~6 min)	蓝色：游戏 CPU %   橙色：游戏 GPU %   绿色：系统内存 %   （最近约 6 分钟）	أزرق: معالج اللعبة %   برتقالي: معالج الرسوميات للعبة %   أخضر: ذاكرة النظام %   (آخر ~6 دقائق)
Mağaza (UWP) uygulamalarının kullanılmadığı sırada arka planda çalışmasını genel olarak engeller.	Generally prevents Store (UWP) apps from running in the background when not in use.	通常会阻止 Store (UWP) 应用在未使用时在后台运行。	يمنع عمومًا تطبيقات المتجر (UWP) من العمل في الخلفية عندما لا تكون قيد الاستخدام.
Medya oynatma uygulamaları bu bileşenlere bağlı olabilir.	Media playback apps may depend on these components.	媒体播放应用可能依赖这些组件。	قد تعتمد تطبيقات تشغيل الوسائط على هذه المكونات.
Medya paylaşımı	Media sharing	媒体共享	مشاركة الوسائط
Medya Özellikleri	Media Features	媒体功能	ميزات الوسائط
Medya/uygulama önbelleği, başlangıç önbelleği, küçük resimler, çökme raporları.	Media/app cache, startup cache, thumbnails, crash reports.	媒体/应用缓存、启动缓存、缩略图、崩溃报告。	ذاكرة الوسائط/التطبيقات، وذاكرة بدء التشغيل، والصور المصغرة، وتقارير الأعطال.
Menü açılış animasyonu	Menu opening animation	菜单打开动画	رسوم متحركة لفتح القوائم
Menülerin kayarak veya solarak açılmasını kapatır; menüler anında görünür.	Turns off menus sliding or fading open; menus appear instantly.	关闭菜单的滑动或淡入打开效果；菜单将立即显示。	يُوقف انزلاق القوائم أو تلاشيها عند فتحها؛ تظهر القوائم فورًا.
Mevcut Durum	Current Status	当前状态	الحالة الحالية
Nazik kapatma	Graceful close	正常关闭	إغلاق لطيف
Nazikçe kapanmazsa zorla sonlandır (kaydedilmemiş veri kaybolabilir)	If it doesn't close gracefully, force terminate (unsaved data may be lost)	如果无法正常关闭，则强制结束（未保存的数据可能会丢失）	إن لم يُغلق بلطف، فأنهِه بالقوة (قد تفقد البيانات غير المحفوظة)
Neden önerildi	Why suggested	推荐原因	سبب الاقتراح
Neden önerildi: {#}	Why suggested: {1}	推荐原因：{1}	سبب الاقتراح: {1}
Nihai Performans Planı Ekle	Add Ultimate Performance Plan	添加卓越性能计划	إضافة خطة الأداء الفائق
Nihai Performans güç planı Windows'a eklenecek (otomatik etkinleştirilmez). Bu cihazda desteklenmeyebilir ve dizüstünde önerilmez.\n\nDevam edilsin mi?	The Ultimate Performance power plan will be added to Windows (it is not enabled automatically). It may not be supported on this device and is not recommended on laptops.\n\nContinue?	卓越性能电源计划将添加到 Windows（不会自动启用）。此设备可能不支持，笔记本电脑不建议使用。\n\n是否继续？	ستُضاف خطة الطاقة "الأداء الفائق" إلى Windows (لا تُفعَّل تلقائيًا). قد لا تكون مدعومة على هذا الجهاز، ولا يُنصح بها على الحواسيب المحمولة.\n\nهل تريد المتابعة؟
Nihai Performans güç planı eklendi	Ultimate Performance power plan added	已添加卓越性能电源计划	تمت إضافة خطة الأداء الفائق
Nihai Performans: küçük güç yönetimi gecikmelerini kaldırmayı amaçlar. Güç tüketimi ve ısı yüksektir, dizüstü için önerilmez. Kazanç çoğu kullanımda sınırlıdır ve garanti edilmez.	Ultimate Performance: aims to remove small power management delays. Power use and heat are high; not recommended for laptops. Gains are limited in most uses and not guaranteed.	卓越性能：旨在消除细微的电源管理延迟。功耗和发热较高，不建议用于笔记本电脑。在大多数场景下提升有限，且不保证效果。	الأداء الفائق: يهدف إلى إزالة تأخيرات إدارة الطاقة الطفيفة. استهلاك الطاقة والحرارة مرتفعان، ولا يُنصح به للحواسيب المحمولة. المكاسب محدودة في معظم الاستخدامات ولا تُضمن.
Normal	Normal	正常	عادي
Normalin üstü	Above normal	高于正常	أعلى من الطبيعي
Not	Note	注意	ملاحظة
OLASI GÖZLEMLER (bilgi amaçlı, kesin değildir)	POSSIBLE OBSERVATIONS (for information only, not definitive)	可能的观察结果（仅供参考，不一定准确）	ملاحظات محتملة (للاطلاع فقط، وليست قاطعة)
OYUN PERFORMANS RAPORU  |  Developed by Leone	GAME PERFORMANCE REPORT  |  Developed by Leone	游戏性能报告  |  Developed by Leone	تقرير أداء الألعاب  |  Developed by Leone
Olası etkiler	Possible effects	可能的影响	التأثيرات المحتملة
Olası etkiler / öneri	Possible effects / recommendation	可能的影响 / 建议	التأثيرات المحتملة / التوصية
Olası etkiler: {#}	Possible effects: {1}	可能的影响：{1}	التأثيرات المحتملة: {1}
Orta	Medium	中	متوسط
Orta (düşük/orta donanımda arayüz akıcılığı artabilir; garanti edilmez)	Medium (interface smoothness may improve on low/mid hardware; not guaranteed)	中（在中低端硬件上界面流畅度可能提升；不保证）	متوسط (قد تتحسن سلاسة الواجهة على العتاد المنخفض/المتوسط؛ غير مضمون)
Otomatik	Automatic	自动	تلقائي
Otomatik Bakım	Auto Maintenance	自动维护	الصيانة التلقائية
Otomatik Bakım ({#})	Auto Maintenance ({1})	自动维护（{1}）	الصيانة التلقائية ({1})
Otomatik bakım ({#}): {#}, kazanılan {#}	Auto maintenance ({1}): {2}, gained {3}	自动维护（{1}）：{2}，释放 {3}	الصيانة التلقائية ({1}): {2}، المكتسب {3}
Otomatik bakım atlandı: bilgisayar boşta değil	Auto maintenance skipped: computer is not idle	已跳过自动维护：计算机未处于空闲状态	تم تخطي الصيانة التلقائية: الكمبيوتر ليس في وضع الخمول
Otomatik bakım planlandı: {#} {#} {#}	Auto maintenance scheduled: {1} {2} {3}	已计划自动维护：{1} {2} {3}	تمت جدولة الصيانة التلقائية: {1} {2} {3}
Otomatik bakım planı kapatıldı	Auto maintenance schedule turned off	自动维护计划已关闭	تم إيقاف جدول الصيانة التلقائية
Otomatik bakımı etkinleştir (Windows Görev Zamanlayıcı ile planlanır)	Enable auto maintenance (scheduled with Windows Task Scheduler)	启用自动维护（通过 Windows 任务计划程序计划）	تفعيل الصيانة التلقائية (مجدولة عبر جدولة المهام في Windows)
Otomatik başlıyor: kullanıyor musunuz?	Starting automatically: are you using it?	即将自动开始：您正在使用吗？	ستبدأ تلقائيًا: هل تستخدمه؟
Otomatik düzeltme ve tahmin önerileri zamanla daha az kişiye özel olabilir.	Autocorrect and prediction suggestions may become less personalized over time.	自动更正和预测建议随时间推移可能变得不够个性化。	قد تصبح اقتراحات التصحيح التلقائي والتنبؤ أقل تخصيصًا مع الوقت.
Oturum dosyası yazılamadı:	Could not write session file:	无法写入会话文件：	تعذّرت كتابة ملف الجلسة:
Oturum kurtarma hatası:	Session recovery error:	会话恢复错误：	خطأ في استعادة الجلسة:
Oturum sürüyor; rapor oyun kapanınca oluşur.	Session in progress; the report is generated when the game closes.	会话进行中；游戏关闭后将生成报告。	الجلسة جارية؛ يُنشأ التقرير عند إغلاق اللعبة.
Oturum verileri (sekmeler)	Session data (tabs)	会话数据（标签页）	بيانات الجلسة (علامات التبويب)
Oturum yeniden açılınca	When session reopens	会话重新打开时	عند إعادة فتح الجلسة
Oturumlar kapanabilir	Sessions may close	会话可能会关闭	قد تُغلق الجلسات
Oturumu Bitir	End Session	结束会话	إنهاء الجلسة
Oyun	Game	游戏	اللعبة
Oyun     CPU: %{#}    RAM: {#} MB    GPU: {#}    VRAM: {#}\nSistem   CPU: %{#}    RAM: %{#}	Game     CPU: %{1}    RAM: {2} MB    GPU: {3}    VRAM: {4}\nSystem   CPU: %{5}    RAM: %{6}	游戏     CPU: %{1}    RAM: {2} MB    GPU: {3}    VRAM: {4}\n系统     CPU: %{5}    RAM: %{6}	اللعبة     المعالج: %{1}    RAM: {2} MB    الرسوميات: {3}    VRAM: {4}\nالنظام   المعالج: %{5}    RAM: %{6}
Oyun CPU %        :	Game CPU %        :	游戏 CPU %        :	معالج اللعبة %        :
Oyun GPU %        :	Game GPU %        :	游戏 GPU %        :	رسوميات اللعبة %        :
Oyun Modu	Game Mode	游戏模式	وضع اللعب
Oyun Modu / kayıt ayarları geri yüklendi	Game Mode / registry settings restored	游戏模式 / 注册表设置已还原	تمت استعادة وضع اللعب / إعدادات السجل
Oyun Modu ayarı değiştirilemedi:	Could not change Game Mode setting:	无法更改游戏模式设置：	تعذّر تغيير إعداد وضع اللعب:
Oyun Modu açıldı	Game Mode turned on	游戏模式已开启	تم تشغيل وضع اللعب
Oyun Modu kapatıldı	Game Mode turned off	游戏模式已关闭	تم إيقاف وضع اللعب
Oyun Modunu Aç	Turn On Game Mode	开启游戏模式	تشغيل وضع اللعب
Oyun Modunu Kapat	Turn Off Game Mode	关闭游戏模式	إيقاف وضع اللعب
Oyun Optimizasyonu	Game Optimization	游戏优化	تحسين الألعاب
Oyun RAM (MB)     :	Game RAM (MB)     :	游戏内存 (MB)     :	ذاكرة اللعبة (MB)     :
Oyun VRAM (MB)    :	Game VRAM (MB)    :	游戏显存 (MB)    :	ذاكرة الفيديو للعبة (MB)    :
Oyun algılandığında Windows arka plan etkinliğini (ör. güncelleme yüklemeleri, sürücü bildirimleri) sınırlayarak oyuna öncelik vermeye çalışır.	When a game is detected, it tries to prioritize the game by limiting Windows background activity (e.g. update installs, driver notifications).	检测到游戏时，会通过限制 Windows 后台活动（例如更新安装、驱动程序通知）来优先保障游戏。	عند اكتشاف لعبة، يحاول إعطاء الأولوية لها بتقييد نشاط Windows في الخلفية (مثل تثبيت التحديثات وإشعارات برامج التشغيل).
Oyun algılanmadı.	No game detected.	未检测到游戏。	لم يتم اكتشاف لعبة.
Oyun algılanmadı. Etkin bir profildeki oyun açıldığında profil otomatik etkinleşir.	No game detected. When a game in an active profile opens, the profile is enabled automatically.	未检测到游戏。当启用的配置文件中的游戏打开时，该配置文件将自动启用。	لم يتم اكتشاف لعبة. عند فتح لعبة في ملف شخصي نشط، يُفعَّل الملف الشخصي تلقائيًا.
Oyun ayarları, yüksek performanslı güç planı ve güvenli geçici dosya temizliği. Başlangıç ve servislere dokunmaz.	Game settings, high-performance power plan and safe temporary file cleanup. Does not touch startup or services.	游戏设置、高性能电源计划和安全的临时文件清理。不会修改启动项和服务。	إعدادات الألعاب، وخطة طاقة عالية الأداء، وتنظيف آمن للملفات المؤقتة. لا يمس عناصر بدء التشغيل والخدمات.
Oyun izleme hatası:	Game monitoring error:	游戏监控错误：	خطأ في مراقبة اللعبة:
Oyun izleniyor: {#}   |   Profil: {#} ({#})   |   Süre: {#}	Monitoring game: {1}   |   Profile: {2} ({3})   |   Duration: {4}	正在监控游戏：{1}   |   配置文件：{2}（{3}）   |   时长：{4}	جارٍ مراقبة اللعبة: {1}   |   الملف الشخصي: {2} ({3})   |   المدة: {4}
Oyun işlem adı (.exe)	Game process name (.exe)	游戏进程名称 (.exe)	اسم عملية اللعبة (.exe)
Oyun işlemi	Game process	游戏进程	عملية اللعبة
Oyun işlemi : {#}	Game process : {1}	游戏进程 : {1}	عملية اللعبة : {1}
Oyun işlemini seçin	Select a game process	请选择游戏进程	اختر عملية اللعبة
Oyun kapandı	Game closed	游戏已关闭	أُغلقت اللعبة
Oyun kapanınca kapattığım uygulamaları yeniden başlat	Reopen apps I closed when the game exits	游戏关闭后重新启动我关闭的应用	أعد تشغيل التطبيقات التي أغلقتها عند إغلاق اللعبة
Oyun kaydı	Game recording	游戏录制	تسجيل اللعب
Oyun kolundaki düğmeyle Game Bar açılmasını ve başlangıç ipucu panelini kapatır.	Turns off opening Game Bar with the game controller button and hides the startup tip panel.	关闭使用游戏手柄按钮打开 Game Bar 的功能，并隐藏启动提示面板。	يعطّل فتح Game Bar بزر وحدة التحكم في الألعاب ويخفي لوحة نصائح البدء.
Oyun oturumu başladı: {#} (profil: {#}){#}	Game session started: {1} (profile: {2}){3}	游戏会话已开始：{1}（配置文件：{2}）{3}	بدأت جلسة اللعب: {1} (الملف الشخصي: {2}){3}
Oyun oturumu bitti: {#} ({#}) - ayarlar geri yüklendi	Game session ended: {1} ({2}) - settings restored	游戏会话已结束：{1}（{2}）- 设置已还原	انتهت جلسة اللعب: {1} ({2}) - تمت استعادة الإعدادات
Oyun oturumu sürerken Oyun Modu elle değiştirilemez; oturum bitince önceki değer geri yüklenir.	Game Mode cannot be changed manually while a game session is running; the previous value is restored when the session ends.	游戏会话进行时无法手动更改游戏模式；会话结束后将恢复之前的值。	لا يمكن تغيير وضع الألعاب يدويًا أثناء جلسة اللعب؛ تُستعاد القيمة السابقة عند انتهاء الجلسة.
Oyun profili	Game profile	游戏配置文件	ملف تعريف اللعبة
Oyun rapor geçmişi	Game report history	游戏报告历史记录	سجل تقارير اللعب
Oyun raporu yazılamadı:	Failed to write game report:	无法写入游戏报告：	تعذّرت كتابة تقرير اللعبة:
Oyun sırasında Windows Oyun Modu açık olsun	Keep Windows Game Mode on during games	游戏期间保持 Windows 游戏模式开启	أبقِ وضع الألعاب في Windows مفعّلًا أثناء اللعب
Oyun sırasında arka plan oyun kaydını (Game DVR) kapat	Turn off background game recording (Game DVR) during games	游戏期间关闭后台游戏录制（Game DVR）	أوقف تسجيل الألعاب في الخلفية (Game DVR) أثناء اللعب
Oyun sırasında geçici kapatılacak uygulamalar (yalnızca sizin seçtikleriniz):	Apps to temporarily close during games (only those you select):	游戏期间需临时关闭的应用（仅限您选择的应用）：	التطبيقات التي ستُغلق مؤقتًا أثناء اللعب (التي تختارها أنت فقط):
Oyun yeniden başlayınca	When the game starts again	游戏再次启动时	عند إعادة تشغيل اللعبة
Oyuna ve donanıma göre değişir; FPS artışı garanti edilmez	Varies by game and hardware; an FPS increase is not guaranteed	因游戏和硬件而异，不保证提升 FPS	يختلف حسب اللعبة والعتاد؛ لا يُضمن ارتفاع معدل الإطارات
Oyunun son anlarını sürekli kaydeden arka plan yakalamayı kapatır.	Turns off background capture that continuously records the last moments of your game.	关闭持续记录游戏最后时刻的后台捕获功能。	يوقف التقاط الخلفية الذي يسجّل باستمرار آخر لحظات اللعبة.
PDF olarak yazdır	Print as PDF	打印为 PDF	طباعة كملف PDF
Panoya Kopyala	Copy to clipboard	复制到剪贴板	نسخ إلى الحافظة
Pasif	Inactive	未激活	غير نشط
Paylaşılan DLL kaydı (kullanılmayan yapılandırma)	Shared DLL entry (unused configuration)	共享 DLL 项（未使用的配置）	إدخال DLL مشترك (إعداد غير مستخدم)
Paylaşılan DLL kayıtları taranıyor...	Scanning shared DLL entries...	正在扫描共享 DLL 项...	جارٍ فحص إدخالات DLL المشتركة...
Paylaşılan DLL sayaç kaydı, ancak dosya diskte yok. Orta risk: kaldırıcıların sayaç mantığıyla ilgilidir, yalnızca emin olduğunuzda kaldırın.	Shared DLL count entry exists, but the file is not on disk. Medium risk: it relates to uninstaller counter logic; remove it only if you are sure.	共享 DLL 计数项存在，但磁盘上没有该文件。中等风险：与卸载程序的计数逻辑有关，仅在确定时删除。	إدخال عداد DLL مشترك، لكن الملف غير موجود على القرص. خطورة متوسطة: يتعلق بمنطق العداد في برامج الإزالة، فلا تحذفه إلا إذا كنت متأكدًا.
Paylaşım açık	Sharing on	共享已开启	المشاركة مفعّلة
Paylaşım kapalı	Sharing off	共享已关闭	المشاركة معطّلة
Pazar	Sunday	星期日	الأحد
Pazartesi	Monday	星期一	الاثنين
Pencere	Window	窗口	النافذة
Pencere açılış/kapanış, kaydırma ve geçiş animasyonlarını kapatır (Ayarlar > Erişilebilirlik > Görsel efektler > Animasyon efektleri).	Turns off window open/close, scrolling and transition animations (Settings > Accessibility > Visual effects > Animation effects).	关闭窗口打开/关闭、滚动和过渡动画（设置 > 辅助功能 > 视觉效果 > 动画效果）。	يوقف رسوم فتح النوافذ وإغلاقها والتمرير والانتقال (الإعدادات > سهولة الوصول > التأثيرات المرئية > تأثيرات الحركة).
Pencere küçültme/büyütme animasyonu	Window minimize/maximize animation	窗口最小化/最大化动画	رسوم تصغير النافذة وتكبيرها
Pencereler simge durumuna küçülürken ve büyürken oynayan animasyonu kapatır.	Turns off the animation that plays when windows are minimized and maximized.	关闭窗口最小化和最大化时播放的动画。	يوقف الرسوم المتحركة التي تُعرض عند تصغير النوافذ وتكبيرها.
Pencereli uygulama	Windowed app	窗口化应用	تطبيق بنوافذ
Perakende demo	Retail demo	零售演示	عرض توضيحي للبيع بالتجزئة
Performans etkisi yok; gizlilik ve öneri gürültüsü azalır	No performance impact; privacy and suggestion noise are reduced.	对性能无影响；隐私和推荐干扰会减少。	لا تأثير على الأداء؛ تقلّ مشاركة البيانات والاقتراحات المزعجة.
Performans raporu	Performance report	性能报告	تقرير الأداء
Perşembe	Thursday	星期四	الخميس
Plan	Plan	计划	الخطة
Plan değiştirildi:	Plan changed:	计划已更改：	تم تغيير الخطة:
Plan eklendi. Listeden seçip uygulayabilirsiniz.	Plan added. You can select it from the list and apply it.	已添加计划。可从列表中选择并应用。	تمت إضافة الخطة. يمكنك اختيارها من القائمة وتطبيقها.
Plan eklenemedi (bu cihaz desteklemiyor olabilir):	Couldn't add plan (this device may not support it):	无法添加计划（此设备可能不支持）：	تعذّرت إضافة الخطة (قد لا يدعم هذا الجهاز ذلك):
Planlama başarısız:	Scheduling failed:	计划任务失败：	فشلت الجدولة:
Planlamadan önce en az bir temizlik kategorisi seçin.	Select at least one cleanup category before scheduling.	安排计划前请至少选择一个清理类别。	اختر فئة تنظيف واحدة على الأقل قبل الجدولة.
Planı Kaldır	Remove Plan	删除计划	إزالة الخطة
Posta, takvim, hava durumu gibi uygulamalar bildirim ve eşitleme yapmayabilir. Windows 11 bazı sürümlerinde bu genel anahtar yerine uygulama bazlı ayar geçerlidir; bunun için Uygulama Bazlı Arka Plan Ayarı düğmesini kullanın.	Mail, calendar, weather and similar apps may not show notifications or sync. On some Windows 11 versions, the per-app setting applies instead of this master switch; use the Per-App Background Setting button for that.	邮件、日历、天气等应用可能无法显示通知或同步。在某些 Windows 11 版本中，应使用“应用级后台设置”按钮，而非此总开关。	قد لا تعرض تطبيقات مثل البريد والتقويم والطقس الإشعارات أو تتزامن. في بعض إصدارات Windows 11 يُطبَّق الإعداد الخاص بكل تطبيق بدلًا من هذا المفتاح العام؛ استخدم زر «إعداد الخلفية لكل تطبيق» لذلك.
Profil	Profile	配置文件	الملف الشخصي
Profil Ekle (Dosya)	Add Profile (File)	添加配置文件（文件）	إضافة ملف شخصي (ملف)
Profil Ekle (Çalışan)	Add Profile (Running)	添加配置文件（正在运行）	إضافة ملف شخصي (قيد التشغيل)
Profil adı	Profile name	配置文件名称	اسم الملف الشخصي
Profil adı ve oyun işlem adı boş olamaz.	Profile name and game process name cannot be empty.	配置文件名称和游戏进程名称不能为空。	لا يمكن أن يكون اسم الملف الشخصي واسم عملية اللعبة فارغًا.
Profil etkinleşince yalnızca burada seçtiğiniz ayarlar uygulanır; oyun kapanınca önceki değerler geri yüklenir. Kapatma önce nazik (pencere kapatma) denenir. Sistem ve güvenlik işlemleri listelenmez. Bu ayarların FPS değerini artıracağı garanti edilmez.	When a profile is activated, only the settings you select here are applied; previous values are restored when the game closes. Closing is first attempted gracefully (closing the window). System and security processes are not listed. These settings are not guaranteed to increase FPS.	启用配置文件后，仅应用您在此选择的设置；游戏关闭后恢复之前的值。将先尝试正常关闭（关闭窗口）。不会列出系统和安全进程。这些设置不保证提升 FPS。	عند تفعيل الملف الشخصي تُطبَّق فقط الإعدادات التي تختارها هنا؛ وعند إغلاق اللعبة تُستعاد القيم السابقة. تُجرَّب أولًا إغلاقة لطيفة (بإغلاق النافذة). لا تُدرج عمليات النظام والأمان. لا يُضمن أن ترفع هذه الإعدادات معدل الإطارات.
Profili Düzenle	Edit Profile	编辑配置文件	تحرير الملف الشخصي
Profili Sil	Delete Profile	删除配置文件	حذف الملف الشخصي
Profili sil	Delete profile	删除配置文件	حذف الملف الشخصي
Program	Program	程序	برنامج
Program listesi dışa aktarıldı: {#}	Program list exported: {1}	程序列表已导出：{1}	تم تصدير قائمة البرامج: {1}
Programları Yenile	Refresh Programs	刷新程序	تحديث البرامج
RAM kullanımı	RAM usage	内存使用情况	استخدام الذاكرة (RAM)
RAM kullanımı : ölçülemedi	RAM usage: could not be measured	内存使用情况：无法测量	استخدام RAM: تعذّر القياس
RAM kullanımı : önce {#} MB (%{#})  ->  sonra {#} MB (%{#})   fark {#} MB: {#}	RAM usage: before {1} MB ({2}%)  ->  after {3} MB ({4}%)   difference {5} MB: {6}	内存使用：之前 {1} MB（{2}%） -> 之后 {3} MB（{4}%）  差值 {5} MB：{6}	استخدام RAM: قبل {1} ميغابايت ({2}%)  ->  بعد {3} ميغابايت ({4}%)   الفرق {5} ميغابايت: {6}
RAM miktarı	RAM amount	内存容量	مقدار الذاكرة (RAM)
RAM sonra %	RAM after %	之后内存 %	نسبة RAM بعد
RAM önce %	RAM before %	之前内存 %	نسبة RAM قبل
Rapor	Report	报告	تقرير
Rapor Geçmişi	Report History	报告历史记录	سجل التقارير
Rapor dosyası	Report file	报告文件	ملف التقرير
Rapor dışa aktarıldı: {#}	Report exported: {1}	报告已导出：{1}	تم تصدير التقرير: {1}
Rapor yazılamadı:	Failed to write report:	无法写入报告：	تعذّرت كتابة التقرير:
Rapor özeti	Report summary	报告摘要	ملخص التقرير
Raporlar	Reports	报告	التقارير
Raporu Aç	Open Report	打开报告	فتح التقرير
Raporu Kaydet (TXT)	Save Report (TXT)	保存报告（TXT）	حفظ التقرير (TXT)
Registry Run (Kullanıcı)	Registry Run (User)	Registry Run（用户）	Registry Run (المستخدم)
Registry Run (Sistem)	Registry Run (System)	Registry Run（系统）	Registry Run (النظام)
Registry Run (Sistem, 32-bit)	Registry Run (System, 32-bit)	Registry Run（系统，32 位）	Registry Run (النظام، 32 بت)
Registry RunOnce (Kullanıcı)	Registry RunOnce (User)	Registry RunOnce（用户）	Registry RunOnce (المستخدم)
Registry RunOnce (Sistem)	Registry RunOnce (System)	Registry RunOnce（系统）	Registry RunOnce (النظام)
Registry kaldırma hatası {#}: {#}	Registry removal error {1}: {2}	删除注册表项时出错 {1}：{2}	خطأ في إزالة إدخال Registry {1}: {2}
Registry kaydı kaldırıldı: {#} {#}	Registry entry removed: {1} {2}	已删除注册表项：{1} {2}	تمت إزالة إدخال Registry: {1} {2}
Registry tarama hatası:	Registry scan error:	注册表扫描错误：	خطأ في فحص Registry:
Registry yedeği geri yüklendi: {#} ({#}/{#})	Registry backup restored: {1} ({2}/{3})	已还原注册表备份：{1}（{2}/{3}）	تمت استعادة نسخة Registry الاحتياطية: {1} ({2}/{3})
Reklam kimliği	Advertising ID	广告 ID	معرّف الإعلانات
Reklam sayısı azalmaz, yalnızca daha az kişiselleştirilir. Uygulama işlevlerini etkilemez.	The number of ads does not decrease; they are just less personalized. App functions are not affected.	广告数量不会减少，只是个性化程度降低。不影响应用功能。	لا يقل عدد الإعلانات، بل تقلّ مخصّصيتها فقط. لا يؤثر ذلك في وظائف التطبيقات.
Risk	Risk	风险	الخطورة
Risk seviyesi: {#}	Risk level: {1}	风险等级：{1}	مستوى الخطورة: {1}
SFC Taraması	SFC Scan	SFC 扫描	فحص SFC
SMART arıza tahmini	SMART failure prediction	SMART 故障预测	التنبؤ بأعطال SMART
SQLite bileşeni yok: atlanır	SQLite component not found: skipped	未找到 SQLite 组件：已跳过	مكوّن SQLite غير موجود: تم التخطي
SQLite bileşeni yüklenemedi:	SQLite component could not be loaded:	无法加载 SQLite 组件：	تعذّر تحميل مكوّن SQLite:
Salı	Tuesday	星期二	الثلاثاء
Sanal Makine Platformu	Virtual Machine Platform	虚拟机平台	منصة الآلة الافتراضية
Sanal makineler çalıştırır.	Runs virtual machines.	运行虚拟机。	يشغّل الأجهزة الافتراضية.
Saydamlık	Transparency	透明度	الشفافية
Saydamlık efektleri	Transparency effects	透明效果	تأثيرات الشفافية
Sağlık: {#}	Health: {1}	健康状况：{1}	الحالة الصحية: {1}
Sensör verisi yok (Windows bu bilgiyi sunmuyor; LibreHardwareMonitor çalışıyorsa okunur)	No sensor data (Windows does not provide this information; it is read if LibreHardwareMonitor is running)	没有传感器数据（Windows 不提供此信息；若 LibreHardwareMonitor 正在运行则会读取）	لا توجد بيانات من المستشعرات (لا يوفر Windows هذه المعلومة؛ تُقرأ إذا كان LibreHardwareMonitor يعمل)
Sensör verisi yok (nvidia-smi veya LibreHardwareMonitor bulunamadı)	No sensor data (nvidia-smi or LibreHardwareMonitor not found)	没有传感器数据（未找到 nvidia-smi 或 LibreHardwareMonitor）	لا توجد بيانات من المستشعرات (لم يُعثر على nvidia-smi أو LibreHardwareMonitor)
Servis	Service	服务	الخدمة
Servis ({#}) Otomatik yerine Elle başlar; gerektiğinde Windows kendisi başlatır. Servis silinmez, çalışan servis durdurulmaz.	Service ({1}) starts as Manual instead of Automatic; Windows starts it itself when needed. The service is not deleted, and a running service is not stopped.	服务（{1}）将改为手动启动（而非自动）；需要时 Windows 会自行启动。服务不会被删除，正在运行的服务也不会被停止。	ستبدأ الخدمة ({1}) يدويًا بدلًا من تلقائيًا؛ وسيشغّلها Windows بنفسه عند الحاجة. لن تُحذف الخدمة، ولن تُوقف الخدمة الجارية.
Servis adı	Service name	服务名称	اسم الخدمة
Servis başlangıcını 'Elle' yap: {#}	Set service startup to “Manual”: {1}	将服务启动类型设为“手动”：{1}	اجعل بدء الخدمة «يدويًا»: {1}
Servis başlangıç türü: {#} {#} -> {#}	Service startup type: {1} {2} -> {3}	服务启动类型：{1} {2} -> {3}	نوع بدء الخدمة: {1} {2} -> {3}
Servis değişiklik geçmişi	Service change history	服务更改历史记录	سجل تغييرات الخدمة
Servis durdurma hatası {#}: {#}	Service stop error {1}: {2}	停止服务时出错 {1}：{2}	خطأ في إيقاف الخدمة {1}: {2}
Servis durduruldu: {#}	Service stopped: {1}	服务已停止：{1}	تم إيقاف الخدمة: {1}
Servis geri yüklendi: {#}	Service restored: {1}	服务已还原：{1}	تمت استعادة الخدمة: {1}
Servis listesi hatası:	Service list error:	服务列表错误：	خطأ في قائمة الخدمات:
Servis otomatik başlıyor ve kategorisi '{#}'. {#}.{#}	Service starts automatically and its category is “{1}”. {2}.{3}	服务会自动启动，类别为“{1}”。{2}.{3}	تبدأ الخدمة تلقائيًا وفئتها «{1}». {2}.{3}
Servis oturumu (Servisler sekmesini kullanın)	Service session (use the Services tab)	服务会话（请使用“服务”选项卡）	جلسة الخدمة (استخدم علامة تبويب الخدمات)
Servisler	Services	服务	الخدمات
Servisleri durdur	Stop services	停止服务	إيقاف الخدمات
Seç	Select	选择	تحديد
Seçilenleri Temizle	Clear Selected	清除所选项	مسح المحدد
Seçili Kayıtları Yedekle ve Kaldır	Back Up and Remove Selected Entries	备份并删除所选项	نسخ احتياطي للإدخالات المحددة وإزالتها
Seçili Programı Kaldır	Remove Selected Program	卸载所选程序	إزالة البرنامج المحدد
Seçili Servisi Durdur	Stop Selected Service	停止所选服务	إيقاف الخدمة المحددة
Seçili ayarlar zaten önerilen değerde.	Selected settings already have the recommended value.	所选设置已为推荐值。	الإعدادات المحددة بالفعل على القيمة الموصى بها.
Seçili tarayıcılar şu anda açık. Tarayıcıyı kendiniz kapatıp (arka plan işlemleri dahil) yeniden tarayın.\nAçık tarayıcıdaki dosyalar zorla silinmez.	The selected browsers are open right now. Close the browser yourself (including background processes) and scan again.\nFiles in an open browser are not forcibly deleted.	所选浏览器当前处于打开状态。请自行关闭浏览器（包括后台进程）后重新扫描。\n打开的浏览器中的文件不会被强制删除。	المتصفحات المحددة مفتوحة حاليًا. أغلق المتصفح بنفسك (بما في ذلك العمليات الخلفية) ثم أعد الفحص.\nلن تُحذف الملفات الموجودة في متصفح مفتوح بالقوة.
Seçili temizlik kategorisi yok	No cleanup category selected	未选择清理类别	لم يتم تحديد فئة تنظيف
Seçili İşlemi Sonlandır	End Selected Process	结束所选进程	إنهاء العملية المحددة
Seçilileri Temizle	Clear Selected	清除所选项	مسح المحدد
Seçilileri Uygula	Apply Selected	应用所选项	تطبيق المحدد
Seçiliyi Geri Yükle	Restore Selected	还原所选项	استعادة المحدد
Seçiliyi Kaldır	Remove Selected	删除所选项	إزالة المحدد
Seçim dikdörtgeni solma efekti	Selection rectangle fade effect	选择框淡出效果	تأثير تلاشي مستطيل التحديد
Seçimi Kaldır	Deselect	取消选择	إلغاء التحديد
Seçimi Temizle	Clear Selection	清除选择	مسح التحديد
Silinecek yedek yok.	No backups to delete.	没有可删除的备份。	لا توجد نسخ احتياطية للحذف.
Silinen	Deleted	已删除	المحذوف
Silinen geçici dosyalar geri alınamaz.	Deleted temporary files cannot be recovered.	已删除的临时文件无法恢复。	لا يمكن استرداد الملفات المؤقتة المحذوفة.
Sistem / bu uygulama	System / this app	系统 / 本应用	النظام / هذا التطبيق
Sistem / korumalı	System / protected	系统 / 受保护	النظام / محمي
Sistem CPU %      :	System CPU %      :	系统 CPU %      :	نسبة CPU للنظام %      :
Sistem RAM %      :	System RAM %      :	系统内存 %      :	نسبة RAM للنظام %      :
Sistem RAM kullanımı % (son ~6 dk)	System RAM usage % (last ~6 min)	系统内存使用率 %（最近约 6 分钟）	استخدام RAM للنظام % (آخر ~6 دقائق)
Sistem RAM kullanımı %90 üzerine çıktı; bellek yetersizliği takılmalara yol açabilir.	System RAM usage rose above 90%; low memory can cause stuttering.	系统内存使用率超过 90%；内存不足可能导致卡顿。	ارتفع استخدام RAM للنظام فوق 90%؛ قد يؤدي نقص الذاكرة إلى التقطّع.
Sistem Sağlığı	System Health	系统健康	صحة النظام
Sistem analiz ediliyor, lütfen bekleyin...	Analyzing system, please wait...	正在分析系统，请稍候...	جارٍ تحليل النظام، يُرجى الانتظار...
Sistem ayarı uygulanamadı: {#}	System setting could not be applied: {1}	无法应用系统设置：{1}	تعذّر تطبيق إعداد النظام: {1}
Sistem bileşeni	System component	系统组件	مكوّن النظام
Sistem geçici dosyaları. Kullanımdaki dosyalar atlanır.	System temporary files. Files in use are skipped.	系统临时文件。正在使用的文件将被跳过。	ملفات النظام المؤقتة. تُتخطى الملفات قيد الاستخدام.
Sistem mimarisi	System architecture	系统架构	بنية النظام
Sistem sağlığı hatası:	System health error:	系统健康错误：	خطأ في صحة النظام:
Sistem sağlığı raporu kaydedildi: {#}	System health report saved: {1}	系统健康报告已保存：{1}	تم حفظ تقرير صحة النظام: {1}
Sistem sürücüsü yalnızca okuma modunda denetlenecek (hiçbir şey onarılmaz). Sonuç konsol penceresinde görünür.\n\nBaşlatılsın mı?	The system drive will be checked in read-only mode (nothing will be repaired). The result is shown in the console window.\n\nStart it?	系统驱动器将以只读模式检查（不修复任何内容）。结果将显示在控制台窗口中。\n\n是否开始？	سيُفحص قرص النظام في وضع القراءة فقط (لن يُصلح أي شيء). تظهر النتيجة في نافذة وحدة التحكم.\n\nهل تريد البدء؟
Sistem/Önyükleme	System/Boot	系统/启动	النظام/الإقلاع
Sitelerin önbelleğe aldığı dosyalar. Siteler ilk açılışta biraz yavaş yüklenebilir.	Files cached by websites. Sites may load slightly slower on first visit.	网站缓存的文件。网站首次加载时可能稍慢。	ملفات تخزنها المواقع مؤقتًا. قد تُحمَّل المواقع ببطء أكبر عند أول زيارة.
Son Bakım Raporu	Last Maintenance Report	上次维护报告	تقرير الصيانة الأخير
Son Oturum Raporu	Last Session Report	上次会话报告	تقرير الجلسة الأخيرة
Son Tarama	Last Scan	上次扫描	آخر فحص
Son Uygulamayı Geri Al	Undo Last Apply	撤销上次应用	التراجع عن آخر تطبيق
Son Yedeği Geri Yükle	Restore Last Backup	还原上次备份	استعادة آخر نسخة احتياطية
Son açılış süresi: {#} sn	Last startup time: {1} s	上次启动时间：{1} 秒	آخر مدة بدء: {1} ث
Son başlatma / çalışma süresi	Last start / uptime	上次启动 / 运行时长	آخر بدء / مدة التشغيل
Son değişiklik	Last change	最近更改	آخر تغيير
Son oturum raporu hazır: Son Oturum Raporu düğmesine tıklayın.\nOyun kapandığında önceki ayarlar otomatik geri yüklenir.	Last session report is ready: click the Last Session Report button.\nWhen the game closes, previous settings are restored automatically.	上次会话报告已就绪：请点击“上次会话报告”按钮。\n游戏关闭时，之前的设置将自动还原。	تقرير الجلسة الأخيرة جاهز: انقر على زر «تقرير الجلسة الأخيرة».\nعند إغلاق اللعبة تُستعاد الإعدادات السابقة تلقائيًا.
Son oyun oturumu raporu	Last game session report	上次游戏会话报告	تقرير آخر جلسة لعب
Son uygulamadaki {#} değişiklik geri alınacak:	{1} changes from the last apply will be undone:	上次应用中的 {1} 项更改将被撤销：	سيتم التراجع عن {1} من التغييرات في آخر تطبيق:
Son yedek geri yüklenecek:\n{#}  ({#} dosya)\n\nYedekten sonra tarayıcıda oluşan yeni çerez/geçmiş verilerinin üzerine yazılır. Devam edilsin mi?	The last backup will be restored:\n{1}  ({2} files)\n\nNew cookie/history data created in the browser after the backup will be overwritten. Continue?	将还原上次备份：\n{1}（{2} 个文件）\n\n备份之后在浏览器中产生的新 Cookie/历史数据将被覆盖。是否继续？	ستُستعاد آخر نسخة احتياطية:\n{1}  ({2} ملف)\n\nستُستبدل بيانات ملفات تعريف الارتباط والسجل الجديدة التي نشأت في المتصفح بعد النسخ الاحتياطي. هل تريد المتابعة؟
Sonlandırma Geçmişi	Termination History	结束进程历史记录	سجل الإنهاء
Sonlandırmayı onayla	Confirm termination	确认结束	تأكيد الإنهاء
Sonraki oturum açılışı	Next session start	下次会话启动	بدء الجلسة التالية
Süre        : {#} dk   |   Ölçüm sayısı: {#}	Duration: {1} min   |   Measurements: {2}	时长：{1} 分钟   |   测量次数：{2}	المدة: {1} دقيقة   |   عدد القياسات: {2}
Süre (sn)	Duration (s)	时长（秒）	المدة (ث)
Süre sn	Duration (s)	时长（秒）	المدة (ث)
Sürücü Kullanımı	Drive Usage	驱动器使用情况	استخدام القرص
Sürücü bilgisi okunamadı.	Could not read drive information.	无法读取驱动器信息。	تعذّرت قراءة معلومات القرص.
Sürüm	Version	版本	الإصدار
Sıcaklık	Temperature	温度	درجة الحرارة
Sıcaklık: {#} °C	Temperature: {1} °C	温度：{1} °C	درجة الحرارة: {1} °C
TEMİZLENEN DİSK ALANI	CLEANED DISK SPACE	已清理的磁盘空间	مساحة القرص المُنظَّفة
TFTP İstemcisi	TFTP Client	TFTP 客户端	عميل TFTP
Tahmini boyut	Estimated size	预计大小	الحجم التقديري
Tanılama verilerinin kişiselleştirilmiş ipucu ve öneriler için kullanılmasını engeller.	Prevents diagnostic data from being used for personalized tips and suggestions.	阻止诊断数据用于个性化提示和建议。	يمنع استخدام بيانات التشخيص لتقديم نصائح واقتراحات مخصصة.
Tara	Scan	扫描	فحص
Tarama {#} dk önce yapıldı; her dosya silinmeden önce yeniden doğrulanır, değişenler atlanır.	The scan was done {1} min ago; each file is re-verified before deletion, and changed files are skipped.	扫描于 {1} 分钟前完成；每个文件在删除前都会重新验证，已更改的文件将被跳过。	أُجري الفحص قبل {1} دقيقة؛ يُعاد التحقق من كل ملف قبل حذفه، وتُتخطى الملفات التي تغيّرت.
Taramak için tıklayın	Click to scan	点击进行扫描	انقر للفحص
Taranabilir Toplam	Total scannable	可扫描总量	الإجمالي القابل للفحص
Taranan konum	Scanned location	已扫描位置	الموقع المفحوص
Taranıyor	Scanning	扫描中	جارٍ الفحص
Taranıyor...	Scanning...	扫描中...	جارٍ الفحص...
Tarayıcı	Browser	浏览器	المتصفح
Tarayıcı AÇIK: atlanır	Browser OPEN: skipped	浏览器已打开：已跳过	المتصفح مفتوح: تم التخطي
Tarayıcı Temizleyici	Browser Cleaner	浏览器清理工具	منظّف المتصفح
Tarayıcı açık	Browser open	浏览器已打开	المتصفح مفتوح
Tarayıcı geçmişi	Browser history	浏览器历史记录	سجل المتصفح
Tarayıcı tarama hatası:	Browser scan error:	浏览器扫描错误：	خطأ في فحص المتصفح:
Tarayıcı temizlik geçmişi	Browser cleanup history	浏览器清理历史记录	سجل تنظيف المتصفح
Tarayıcı temizliği hatası:	Browser cleanup error:	浏览器清理错误：	خطأ في تنظيف المتصفح:
Tarayıcı temizliği tamamlandı.	Browser cleanup completed.	浏览器清理已完成。	اكتمل تنظيف المتصفح.
Tarayıcı temizliği: {#} - {#}: silinen {#}, atlanan {#}, kazanılan {#}{#}	Browser cleanup: {1} - {2}: deleted {3}, skipped {4}, freed {5}{6}	浏览器清理：{1} - {2}：已删除 {3}，已跳过 {4}，已释放 {5}{6}	تنظيف المتصفح: {1} - {2}: تم حذف {3}، وتخطي {4}، وتحرير {5}{6}
Tarayıcı temizliğini onayla	Confirm browser cleanup	确认浏览器清理	تأكيد تنظيف المتصفح
Tarayıcı yedekleri silindi	Browser backups deleted	浏览器备份已删除	تم حذف نسخ المتصفح الاحتياطية
Tarayıcı yedeği geri yüklendi: {#} ({#}/{#})	Browser backup restored: {1} ({2}/{3})	已还原浏览器备份：{1}（{2}/{3}）	تمت استعادة نسخة المتصفح الاحتياطية: {1} ({2}/{3})
Tarayıcı önbelleği	Browser cache	浏览器缓存	ذاكرة التخزين المؤقت للمتصفح
Tarayıcı önbelleği, çerez ve geçmişini ayrı modülde temizleyin.	Clean browser cache, cookies and history in the separate module.	请在单独的模块中清理浏览器缓存、Cookie 和历史记录。	نظّف ذاكرة التخزين المؤقت وملفات تعريف الارتباط وسجل المتصفح من الوحدة المنفصلة.
Tarayıcılar	Browsers	浏览器	المتصفحات
Tarayıcılara Git   >	Go to Browsers >	前往浏览器 >	الانتقال إلى المتصفحات >
Tarayıcıyı yalıtılmış sanal ortamda çalıştırır.	Runs the browser in an isolated virtual environment.	在隔离的虚拟环境中运行浏览器。	يشغّل المتصفح في بيئة افتراضية معزولة.
Tek kullanımlık yalıtılmış masaüstü ortamı sunar.	Provides an isolated one-time-use desktop environment.	提供一次性隔离的桌面环境。	يوفّر بيئة سطح مكتب معزولة للاستخدام لمرة واحدة.
Telemetri	Telemetry	遥测	القياس عن بُعد
Telnet İstemcisi	Telnet Client	Telnet 客户端	عميل Telnet
Temiz / bulunamadı	Clean / not found	干净 / 未找到	نظيف / غير موجود
Temizleme Geçmişi	Cleanup History	清理历史记录	سجل التنظيف
Temizleme geçmişi	Cleanup history	清理历史记录	سجل التنظيف
Temizlemeye hazır	Ready to clean	准备清理	جاهز للتنظيف
Temizlik Geçmişi	Cleanup History	清理历史记录	سجل التنظيف
Temizlik Kategorileri	Cleanup Categories	清理类别	فئات التنظيف
Temizlik geçmişi yazılamadı:	Failed to write cleanup history:	无法写入清理历史记录：	تعذّرت كتابة سجل التنظيف:
Temizlik tamamlandı.	Cleanup completed.	清理已完成。	اكتمل التنظيف.
Temizliği onayla	Confirm cleanup	确认清理	تأكيد التنظيف
Tetikleyici	Trigger	触发器	المُشغِّل
Thumbnail (küçük resim) önbelleği	Thumbnail cache	缩略图缓存	ذاكرة التخزين المؤقت للصور المصغّرة
Toplam RAM %	Total RAM %	总内存 %	إجمالي RAM %
Toplam Temizlenen	Total Cleaned	总清理量	إجمالي ما تم تنظيفه
Toplam {#} GB	Total {1} GB	总计 {1} GB	الإجمالي {1} GB
Toplam: {#}  |  Etkin: {#}  |  Devre dışı: {#}  |  Yeni: {#}  |  {#}	Total: {1}  |  Enabled: {2}  |  Disabled: {3}  |  New: {4}  |  {5}	总计：{1}  |  已启用：{2}  |  已禁用：{3}  |  新增：{4}  |  {5}	الإجمالي: {1}  |  مُفعّل: {2}  |  معطّل: {3}  |  جديد: {4}  |  {5}
Toplam: {#} GB      Kullanılan: {#} GB (%{#})      Kullanılabilir: {#} GB	Total: {1} GB      Used: {2} GB ({3}%)      Available: {4} GB	总计：{1} GB      已使用：{2} GB（{3}%）      可用：{4} GB	الإجمالي: {1} GB      المستخدم: {2} GB ({3}%)      المتاح: {4} GB
Toplama açık	Collection on	收集已开启	الجمع مفعّل
Toplama kapalı	Collection off	收集已关闭	الجمع معطّل
Tüm kullanıcılar	All users	所有用户	جميع المستخدمين
Tüm kullanıcılar (32 bit)	All users (32-bit)	所有用户（32 位）	جميع المستخدمين (32 بت)
Tüm sürücülerdeki Geri Dönüşüm Kutusu kalıcı olarak boşaltılacak. Bu işlem geri alınamaz.	The Recycle Bin on all drives will be permanently emptied. This action cannot be undone.	将永久清空所有驱动器上的回收站。此操作无法撤销。	سيُفرَّغ سلة المحذوفات على جميع الأقراص بشكل دائم. لا يمكن التراجع عن هذا الإجراء.
Tüm tarayıcı yedekleri (çerez, geçmiş, oturum kopyaları) kalıcı olarak silinecek. Devam edilsin mi?	All browser backups (cookies, history, session copies) will be permanently deleted. Continue?	所有浏览器备份（Cookie、历史记录、会话副本）将被永久删除。是否继续？	ستُحذف جميع نسخ المتصفح الاحتياطية (ملفات تعريف الارتباط والسجل ونسخ الجلسات) بشكل دائم. هل تريد المتابعة؟
Tüm uygulanabilir önerileri kapsar (orta riskliler dahil). Onay penceresinde her değişikliği tek tek görürsünüz.	Covers all applicable suggestions (including medium-risk ones). You will see each change one by one in the confirmation window.	涵盖所有适用的建议（包括中等风险项）。您可在确认窗口中逐一查看每项更改。	يشمل جميع الاقتراحات القابلة للتطبيق (بما فيها متوسطة الخطورة). ستشاهد كل تغيير على حدة في نافذة التأكيد.
Tüm zamanlar	All time	全部时间	كل الأوقات
Tüm İmzaları Doğrula	Verify All Signatures	验证所有签名	التحقق من جميع التواقيع
Tümü	All	全部	الكل
Tümü (kullanımda olmayanlar)	All (not in use)	全部（未在使用中）	الكل (غير المستخدم)
Tümünü Geri Al	Undo All	全部撤销	التراجع عن الكل
Tümünü Geri Yükle	Restore All	全部还原	استعادة الكل
Tümünü Seç	Select All	全选	تحديد الكل
Tür	Type	类型	النوع
Tür: {#}	Type: {1}	类型：{1}	النوع: {1}
UYARI: Açık sekmelerin geri yüklenmesi ve oturum verileri silinir; oturumlarınız kapanabilir.	WARNING: Open tabs will be restored and session data will be deleted; your sessions may close.	警告：将还原打开的标签页并删除会话数据；您的会话可能会关闭。	تحذير: ستُستعاد علامات التبويب المفتوحة وستُحذف بيانات الجلسة؛ وقد تُغلق جلساتك.
UYARI: Oturumlarınız kapanabilir. "Korunacak siteler" kutusundakiler hariç tutulabilir.	WARNING: Your sessions may close. Sites in the “Sites to keep” box can be excluded.	警告：您的会话可能会关闭。“要保留的网站”框中的网站可被排除在外。	تحذير: قد تُغلق جلساتك. يمكن استثناء المواقع الموجودة في مربع «المواقع المراد الاحتفاظ بها».
UYGULANAN PROFİL AYARLARI	APPLIED PROFILE SETTINGS	已应用的配置文件设置	إعدادات الملف الشخصي المطبّقة
UYGULANAN WINDOWS AYARLARI	APPLIED WINDOWS SETTINGS	已应用的 Windows 设置	إعدادات Windows المطبّقة
Uyarı	Warning	警告	تحذير
Uygula	Apply	应用	تطبيق
Uygulama Bazlı Arka Plan Ayarı	Per-App Background Setting	应用级后台设置	إعداد الخلفية لكل تطبيق
Uygulama kapatıldı	App closed	应用已关闭	أُغلق التطبيق
Uygulama silinmez; yalnızca Windows ile otomatik başlaması durdurulur. Yayıncı: {#}.	The app is not deleted; only its automatic start with Windows is stopped. Publisher: {1}.	应用不会被删除；仅停止其随 Windows 自动启动。发布者：{1}。	لن يُحذف التطبيق؛ يُوقف فقط بدؤه التلقائي مع Windows. الناشر: {1}.
Uygulama önbellekleri (Discord, Slack, VS Code, Teams, Steam web, INetCache) silinir; uygulamalar ilk açılışta biraz yavaş olabilir. Oturum/ayar verilerine dokunulmaz.	App caches (Discord, Slack, VS Code, Teams, Steam web, INetCache) are deleted; apps may load slightly slower on first launch. Session and settings data are not touched.	应用缓存（Discord、Slack、VS Code、Teams、Steam web、INetCache）将被删除；应用首次启动可能稍慢。会话和设置数据不受影响。	تُحذف ذاكرات التطبيقات المؤقتة (Discord وSlack وVS Code وTeams وSteam web وINetCache)؛ وقد تبدأ التطبيقات ببطء أكبر عند أول تشغيل. لا تُمسّ بيانات الجلسة والإعدادات.
Uygulamadan önce önceki değer yedeklenir; "Son Uygulamayı Geri Al" ile eski değere döner.	The previous value is backed up before applying; it returns to the old value with “Undo Last Apply”.	应用前会备份之前的值；使用“撤销上次应用”可恢复为旧值。	يُنسخ احتياطيًا للقيمة السابقة قبل التطبيق؛ ويعود إلى القيمة القديمة عبر «التراجع عن آخر تطبيق».
Uygulamaların arka planda çalışması (genel)	Apps running in the background (general)	应用在后台运行（通用）	تشغيل التطبيقات في الخلفية (عام)
Uygulamaların bıraktığı geçici dosyalar. Kullanımdaki dosyalar atlanır.	Temporary files left by apps. Files in use are skipped.	应用遗留的临时文件。正在使用的文件将被跳过。	ملفات مؤقتة تتركها التطبيقات. تُتخطى الملفات قيد الاستخدام.
Uygulamaların kişiselleştirilmiş reklam için kullandığı kimliği devre dışı bırakır.	Disables the ID apps use for personalized ads.	禁用应用用于个性化广告的 ID。	يعطّل المعرّف الذي تستخدمه التطبيقات للإعلانات المخصصة.
Uygulamaların konumunuza erişmesini kullanıcı düzeyinde engeller.	Blocks apps from accessing your location at the user level.	在用户级别阻止应用访问您的位置。	يمنع التطبيقات من الوصول إلى موقعك على مستوى المستخدم.
Uygulamayı yeniden açabilirsiniz (kaydedilmemiş veri kaybolabilir).	You can reopen the app (unsaved data may be lost).	您可以重新打开应用（未保存的数据可能丢失）。	يمكنك إعادة فتح التطبيق (قد تضيع البيانات غير المحفوظة).
Uygulandı	Applied	已应用	تم التطبيق
Uygulandı ({#})	Applied ({1})	已应用（{1}）	تم التطبيق ({1})
Uygulandı*	Applied*	已应用*	تم التطبيق*
Uzun süredir CPU kullanmayan arka plan işlemi.	Background process that has not used CPU for a long time.	长时间未使用 CPU 的后台进程。	عملية خلفية لم تستخدم المعالج منذ فترة طويلة.
Veri türü	Data type	数据类型	نوع البيانات
Veri yok	No data	无数据	لا توجد بيانات
Veri yok (Windows tanılama olayı bulunamadı)	No data (no Windows diagnostic event found)	无数据（未找到 Windows 诊断事件）	لا توجد بيانات (لم يُعثر على حدث تشخيصي في Windows)
Veri yok (disk/sürücü bu verileri sunmuyor)	No data (disk/drive does not provide this data)	无数据（磁盘/驱动器不提供此数据）	لا توجد بيانات (القرص/المحرك لا يوفر هذه البيانات)
Veri yok (okunamadı)	No data (could not be read)	无数据（无法读取）	لا توجد بيانات (تعذّرت القراءة)
Veri yok (üretici bilgi vermiyor)	No data (manufacturer does not provide information)	无数据（制造商未提供信息）	لا توجد بيانات (لا يوفر المصنّع معلومات)
WSL 2 ve bazı Android alt sistemleri için gerekir.	Required for WSL 2 and some Android subsystems.	WSL 2 和部分 Android 子系统需要此功能。	مطلوب لـ WSL 2 وبعض الأنظمة الفرعية لأندرويد.
WSL 2 veya emülatör kullanmıyorsanız gerekmez; etkinken hipervizör katmanı çalışabilir.	Not needed if you don't use WSL 2 or an emulator; when enabled, the hypervisor layer may run.	如果不使用 WSL 2 或模拟器则无需启用；启用后，虚拟机监控程序层可能会运行。	لا حاجة إليه إن لم تستخدم WSL 2 أو محاكيًا؛ عند تفعيله قد تعمل طبقة المشرف (Hypervisor).
Web sitelerine dil listesi paylaşımı	Sharing language list with websites	与网站共享语言列表	مشاركة قائمة اللغات مع مواقع الويب
Web sitelerinin Windows dil listenize erişmesini engeller.	Prevents websites from accessing your Windows language list.	阻止网站访问您的 Windows 语言列表。	يمنع مواقع الويب من الوصول إلى قائمة لغات Windows الخاصة بك.
Web sunucusu geliştirmiyorsanız gerekmez; açık hizmet güvenlik yüzeyini artırır.	Not needed unless you develop web servers; an open service increases the security attack surface.	除非开发 Web 服务器，否则无需此功能；开放的服务会增加安全攻击面。	لا حاجة إليه إلا إذا كنت تطوّر خوادم ويب؛ فالخدمة المفتوحة توسّع سطح الهجوم الأمني.
Win+Alt+G ile son saniyeleri klip yapma ve Game Bar ile kayıt çalışmaz. Kayıt yükü ortadan kalkar; FPS farkı sistemden sisteme değişir ve garanti edilmez.	Win+Alt+G clip-the-last-seconds and Game Bar recording will not work. Recording overhead is removed; the FPS difference varies from system to system and is not guaranteed.	Win+Alt+G 截取最近片段和 Game Bar 录制将无法使用。录制开销将被消除；FPS 差异因系统而异，且不作保证。	لن يعمل قص آخر الثواني بـ Win+Alt+G ولا التسجيل عبر Game Bar. يزول عبء التسجيل؛ ويختلف فرق معدل الإطارات من نظام إلى آخر ولا يُضمن.
WinOpt Suite - Başlangıç Uygulamaları Yöneticisi | Developed by Leone	WinOpt Suite - Startup App Manager | Developed by Leone	WinOpt Suite - 启动应用管理器 | Developed by Leone	WinOpt Suite - مدير تطبيقات بدء التشغيل | Developed by Leone
WinOpt Suite - Performans Raporu  |  Developed by Leone	WinOpt Suite - Performance Report  |  Developed by Leone	WinOpt Suite - 性能报告  |  Developed by Leone	WinOpt Suite - تقرير الأداء  |  Developed by Leone
WinOpt Suite - Sistem Sağlığı Raporu  |  Developed by Leone  ({#})	WinOpt Suite - System Health Report  |  Developed by Leone  ({1})	WinOpt Suite - 系统健康报告  |  Developed by Leone  ({1})	WinOpt Suite - تقرير صحة النظام  |  Developed by Leone  ({1})
WinOpt Suite - Windows Sistem Optimize Edici   |   Developed by Leone	WinOpt Suite - Windows System Optimizer   |   Developed by Leone	WinOpt Suite - Windows 系统优化器   |   Developed by Leone	WinOpt Suite - أداة تحسين نظام Windows   |   Developed by Leone
WinOpt Suite - Windows Sistem Optimize Edici | Developed by Leone	WinOpt Suite - Windows System Optimizer | Developed by Leone	WinOpt Suite - Windows 系统优化器 | Developed by Leone	WinOpt Suite - أداة تحسين نظام Windows | Developed by Leone
WinOptSuite Otomatik Bakim	WinOptSuite Auto Maintenance	WinOptSuite 自动维护	WinOptSuite للصيانة التلقائية
Windows Arama	Windows Search	Windows 搜索	بحث Windows
Windows Ayarları	Windows Settings	Windows 设置	إعدادات Windows
Windows Hipervizör Platformu	Windows Hypervisor Platform	Windows 虚拟机监控程序平台	منصة Hypervisor في Windows
Windows Media Player ve ilgili medya bileşenlerini içerir.	Includes Windows Media Player and related media components.	包含 Windows Media Player 及相关媒体组件。	يتضمن Windows Media Player ومكوّنات الوسائط ذات الصلة.
Windows Oyun Modu	Windows Game Mode	Windows 游戏模式	وضع الألعاب في Windows
Windows Oyun Modu açıldı	Windows Game Mode turned on	已开启 Windows 游戏模式	تم تفعيل وضع الألعاب في Windows
Windows TEMP klasörü	Windows TEMP folder	Windows TEMP 文件夹	مجلد TEMP في Windows
Windows animasyonları (genel)	Windows animations (general)	Windows 动画（通用）	رسوم Windows المتحركة (عام)
Windows ayar değişiklik geçmişi	Windows setting change history	Windows 设置更改历史记录	سجل تغييرات إعدادات Windows
Windows ayarı geri yüklendi: {#}	Windows setting restored: {1}	已还原 Windows 设置：{1}	تمت استعادة إعداد Windows: {1}
Windows ayarı hatası {#}: {#}	Windows setting error {1}: {2}	Windows 设置错误 {1}：{2}	خطأ في إعداد Windows {1}: {2}
Windows ayarı uygulandı: {#}	Windows setting applied: {1}	已应用 Windows 设置：{1}	تم تطبيق إعداد Windows: {1}
Windows açılışında çalıştırılmak istenen dosya bulunamadı; girdi her açılışta boşuna denenir. Çalışan başlangıç girdilerini Başlangıç sekmesinden yönetin.	The file to run at Windows startup was not found; the entry is pointlessly tried at every startup. Manage running startup entries from the Startup tab.	未找到需在 Windows 启动时运行的文件；每次启动都会徒劳地尝试该条目。请在“启动”选项卡中管理正在运行的启动项。	لم يُعثر على الملف المراد تشغيله عند بدء Windows؛ تُجرَّب الإدخال عبثًا عند كل بدء. أدر إدخالات بدء التشغيل النشطة من علامة تبويب «بدء التشغيل».
Windows bileşen deposu onarılacak (DISM RestoreHealth). Internet bağlantısı gerekebilir, 10-30 dakika sürebilir.\n\nBaşlatılsın mı?	The Windows component store will be repaired (DISM RestoreHealth). An internet connection may be required; it may take 10-30 minutes.\n\nStart it?	将修复 Windows 组件存储（DISM RestoreHealth）。可能需要联网，耗时约 10–30 分钟。\n\n是否开始？	سيُصلَح مخزن مكوّنات Windows (DISM RestoreHealth). قد يلزم اتصال بالإنترنت، وقد تستغرق العملية من 10 إلى 30 دقيقة.\n\nهل تريد البدء؟
Windows bileşeni	Windows component	Windows 组件	مكوّن Windows
Windows bir uyarı verdi, nokta oluşmamış olabilir:\n\n{#}	Windows reported a warning; a restore point may not have been created:\n\n{1}	Windows 发出了警告，可能未创建还原点：\n\n{1}	أبلغ Windows عن تحذير، وربما لم تُنشأ نقطة الاستعادة:\n\n{1}
Windows gecikmesi (varsayılan)	Windows delay (default)	Windows 延迟（默认）	تأخير Windows (الافتراضي)
Windows geri bildirim hub bildirimlerinin sıklığını sıfıra ayarlar.	Sets the frequency of Windows Feedback Hub notifications to zero.	将 Windows 反馈中心通知的频率设为零。	يضبط تكرار إشعارات مركز ملاحظات Windows على صفر.
Windows hata raporları ve çökme dökümleri (7 günden eski).	Windows error reports and crash dumps (older than 7 days).	Windows 错误报告和崩溃转储（超过 7 天）。	تقارير أخطاء Windows وملفات تفريغ الأعطال (أقدم من 7 أيام).
Windows ipuçları ve öneriler daha genel olur. Sistem işlevi etkilenmez.	Windows tips and suggestions become more generic. System functionality is not affected.	Windows 提示和建议将变得更通用。系统功能不受影响。	ستصبح نصائح Windows واقتراحاته أكثر عمومية. لا تتأثر وظائف النظام.
Windows isteğe bağlı bileşeni.	Windows optional component.	Windows 可选组件。	مكوّن Windows اختياري.
Windows içinde Linux araçları çalıştırır.	Runs Linux tools inside Windows.	在 Windows 中运行 Linux 工具。	يشغّل أدوات Linux داخل Windows.
Windows karar verir	Windows decides	由 Windows 决定	يقرر Windows
Windows oturum açılışında '{#}' uygulamasını otomatik başlatıyor ({#}).	Automatically starts '{1}' at Windows sign-in ({2}).	Windows 登录时自动启动“{1}”（{2}）。	يبدأ تلقائياً '{1}' عند تسجيل الدخول إلى Windows ({2}).
Windows servisi	Windows service	Windows 服务	خدمة Windows
Windows sistem dosyaları denetlenecek (sfc /scannow). Yaklaşık 5-20 dakika sürebilir; sonuç açılan konsol penceresinde görünür.\n\nBaşlatılsın mı?	Windows system files will be checked (sfc /scannow). This may take about 5-20 minutes; the result is shown in the console window that opens.\n\nStart it?	将检查 Windows 系统文件（sfc /scannow）。可能需要约 5-20 分钟；结果显示在打开的控制台窗口中。\n\n是否开始？	سيتم فحص ملفات نظام Windows (sfc /scannow). قد يستغرق ذلك نحو 5-20 دقيقة؛ تظهر النتيجة في نافذة وحدة التحكم التي ستُفتح.\n\nهل تريد البدء؟
Windows sürümü	Windows version	Windows 版本	إصدار Windows
Windows tarafından otomatik yeniden oluşturulur.	Automatically recreated by Windows.	由 Windows 自动重新创建。	يعيد Windows إنشاءه تلقائياً.
Windows'ta Aç/Kapat Penceresi	Windows Features window	Windows 功能窗口	نافذة ميزات Windows
Windows, masaüstü açıldıktan sonra başlangıç uygulamalarını yaklaşık 10 saniye bekletir. Değer 0 yapılırsa uygulamalar hemen başlar.	Windows delays startup apps by about 10 seconds after the desktop opens. Setting the value to 0 starts apps immediately.	桌面打开后，Windows 会将启动应用延迟约 10 秒。将值设为 0 则应用立即启动。	يؤخر Windows تطبيقات بدء التشغيل نحو 10 ثوانٍ بعد فتح سطح المكتب. ضبط القيمة على 0 يشغّل التطبيقات فوراً.
XPS Hizmetleri	XPS Services	XPS 服务	خدمات XPS
XPS belge yazıcısı ve görüntüleyicisi.	XPS document printer and viewer.	XPS 文档打印机和查看器。	طابعة مستندات XPS وعارضها.
XPS kullanmıyorsanız gerekmez.	Not needed if you don't use XPS.	如果不使用 XPS，则无需启用。	غير مطلوب إذا كنت لا تستخدم XPS.
Xbox Game Bar kısayol ve ipuçları	Xbox Game Bar shortcuts and tips	Xbox Game Bar 快捷方式和提示	اختصارات ونصائح Xbox Game Bar
YENİ	NEW	新	جديد
Yaklaşık {#} boş alan	About {1} free space	约 {1} 可用空间	حوالي {1} مساحة فارغة
Yalnızca arka plan kullanıcı uygulamaları	Background user apps only	仅后台用户应用	تطبيقات المستخدم في الخلفية فقط
Yalnızca açıklaması bilinenler	Only those with a known description	仅显示已知说明的项目	العناصر ذات الوصف المعروف فقط
Yalnızca bilgisayar boşta iken çalıştır (kullanıcı girişi yok ve CPU %25 altı); en fazla 30 dk beklenir, boşta olmazsa atlanır	Run only when the computer is idle (no user input and CPU below 25%); waits up to 30 min, skipped if it does not become idle.	仅在计算机空闲时运行（无用户输入且 CPU 低于 25%）；最多等待 30 分钟，若未进入空闲状态则跳过。	التشغيل فقط عندما يكون الكمبيوتر خاملاً (لا يوجد إدخال من المستخدم ومعالج أقل من 25%)؛ ينتظر حتى 30 دقيقة، ويُتخطى إذا لم يصبح خاملاً.
Yalnızca düşük riskli "Güvenli" öneriler: eski geçici dosyalar, gizlilik ayarları, ölçülen yavaş başlangıç uygulamaları.	Only low-risk “Safe” suggestions: old temporary files, privacy settings, and measured slow startup apps.	仅显示低风险的“安全”建议：旧临时文件、隐私设置和经测量较慢的启动应用。	اقتراحات “آمنة” منخفضة الخطورة فقط: ملفات مؤقتة قديمة، وإعدادات الخصوصية، وتطبيقات بدء التشغيل البطيئة المقاسة.
Yalnızca etkin olanlar	Active only	仅已启用	المفعّلة فقط
Yalnızca geri bildirim isteme bildirimleri durur.	Only feedback request notifications stop.	仅停止反馈请求通知。	تتوقف إشعارات طلب الملاحظات فقط.
Yalnızca görünüm değişir; performansa etkisi önemsizdir.	Only the appearance changes; performance impact is negligible.	仅外观会改变；对性能的影响可以忽略不计。	يتغير المظهر فقط؛ الأثر على الأداء ضئيل جداً.
Yalnızca görünüm değişir; ölçülebilir performans kazancı beklenmemelidir.	Only the appearance changes; no measurable performance gain should be expected.	仅外观会改变；不应期望有可测量的性能提升。	يتغير المظهر فقط؛ لا ينبغي توقع أي تحسن ملموس في الأداء.
Yalnızca izleme	Monitoring only	仅监控	المراقبة فقط
Yalnızca listeyi siler; indirilen dosyalara dokunulmaz.	Only clears the list; downloaded files are not touched.	仅清空列表；不会处理已下载的文件。	يمسح القائمة فقط؛ لا تُمس الملفات المنزّلة.
Yalnızca yönetilebilir olanlar	Manageable only	仅可管理项	القابلة للإدارة فقط
Yalnızca yüksek tüketenler	High consumers only	仅高占用项	المستهلكة بكثافة فقط
Yalnızca çalışanlar	Running only	仅运行中	قيد التشغيل فقط
Yalnızca önbellek klasörleri; oturum, ayar ve yerel depolama verileri hedeflenmez. Varsayılan: seçili değil.	Cache folders only; session, settings and local storage data are not targeted. Default: not selected.	仅缓存文件夹；不针对会话、设置和本地存储数据。默认：未选中。	مجلدات التخزين المؤقت فقط؛ لا تُستهدف بيانات الجلسة والإعدادات والتخزين المحلي. الافتراضي: غير محدد.
Yalnızca öneri	Suggestion only	仅建议	الاقتراح فقط
Yalnızca öneri ve reklam benzeri içerikler kaybolur; Windows işlevleri etkilenmez.	Only suggestions and ad-like content disappear; Windows functions are not affected.	仅建议和类似广告的内容会消失；Windows 功能不受影响。	تختفي الاقتراحات والمحتوى الشبيه بالإعلانات فقط؛ لا تتأثر وظائف Windows.
Yalnızca önerilenden farklı olanlar	Only those that differ from recommended	仅与推荐值不同的项	المختلفة عن الموصى به فقط
Yarım kalan oyun oturumu devralındı: {#}	Unfinished game session taken over: {1}	已接管未完成的游戏会话：{1}	تم استئناف جلسة لعب غير مكتملة: {1}
Yarım kalan oyun oturumu geri yüklendi:	Unfinished game session restored:	已还原未完成的游戏会话：	تمت استعادة جلسة لعب غير مكتملة:
Yayıncı	Publisher	发布者	الناشر
Yazdırma	Printing	打印	الطباعة
Yazdırma menüsünde PDF çıktı yazıcısı sağlar.	Provides a PDF output printer in the print menu.	在打印菜单中提供 PDF 输出打印机。	يوفر طابعة إخراج PDF في قائمة الطباعة.
Yazma ve mürekkep verisi toplama	Typing and inking data collection	键入和墨迹数据收集	جمع بيانات الكتابة والحبر
Yazı ve el yazısı örneklerinin kişiselleştirme için toplanmasını kısıtlar.	Restricts collection of typing and handwriting samples for personalization.	限制为个性化而收集键入和手写样本。	يقيّد جمع عينات الكتابة والخط اليدوي لأغراض التخصيص.
Yazıcı bulundu*	Printer found*	发现打印机*	تم العثور على طابعة*
Yazıcı bulundu, durdurmanız önerilmez	Printer found, stopping it is not recommended	发现打印机，不建议停止	تم العثور على طابعة، ولا يُنصح بإيقافها
Yazıcı yok: durdurulabilir	No printer: can be stopped	无打印机：可以停止	لا توجد طابعة: يمكن إيقافها
Yaş filtresi	Age filter	年龄筛选	فلتر العمر
Yedek Klasörü	Backup Folder	备份文件夹	مجلد النسخ الاحتياطي
Yedek Klasörünü Aç	Open Backup Folder	打开备份文件夹	فتح مجلد النسخ الاحتياطي
Yedek alınamadı, değiştirilmedi.	Backup could not be created; nothing was changed.	无法创建备份；未做任何更改。	تعذّر إنشاء النسخة الاحتياطية؛ لم يُجرَ أي تغيير.
Yedek alınamadı, kayıt silinmedi.	Backup could not be created; entry was not deleted.	无法创建备份；未删除该条目。	تعذّر إنشاء النسخة الاحتياطية؛ لم يُحذف السجل.
Yedek seçilmedi veya henüz yedek yok.	No backup selected or no backup exists yet.	未选择备份或尚无备份。	لم يتم اختيار نسخة احتياطية أو لا توجد نسخ بعد.
Yedek var	Backup available	有备份	توجد نسخة احتياطية
Yedekleri Sil	Delete Backups	删除备份	حذف النسخ الاحتياطية
Yedekleri sil	Delete backups	删除备份	حذف النسخ الاحتياطية
Yedeği Geri Yükle	Restore Backup	还原备份	استعادة النسخة الاحتياطية
Yedeği geri yükle	Restore backup	还原备份	استعادة النسخة الاحتياطية
Yeni Girdileri Onayla	Approve New Entries	确认新条目	الموافقة على الإدخالات الجديدة
Yeni girdiler bilinen olarak işaretlendi	New entries marked as known	新条目已标记为已知	تم وضع علامة معروفة على الإدخالات الجديدة
Yeniden Etkinleştir	Re-enable	重新启用	إعادة التفعيل
Yeniden başlatılamadı:	Could not restart:	无法重新启动：	تعذّر إعادة التشغيل:
Yeniden başlatıldı:	Restarted:	已重新启动：	أُعيد التشغيل:
Yeniden etkinleştirilebilir ("Son Uygulamayı Geri Al" veya Başlangıç sekmesi); uygulama silinmez.	Can be re-enabled (via “Undo Last App” or the Startup tab); the app is not deleted.	可以重新启用（通过“撤销上次应用”或“启动”选项卡）；应用不会被删除。	يمكن إعادة تفعيلها (عبر “التراجع عن آخر تطبيق” أو تبويب بدء التشغيل)؛ لا يُحذف التطبيق.
Yenile	Refresh	刷新	تحديث
Yerel web sunucusu.	Local web server.	本地 Web 服务器。	خادم ويب محلي.
Yok	None	无	لا يوجد
Yok (bu işlemde dosya silinmedi)	None (no files were deleted in this operation)	无（本次操作未删除任何文件）	لا شيء (لم يُحذف أي ملف في هذه العملية)
Yönetici izni verilmedi. Uygulama yönetici olarak çalıştırılmalıdır.	Administrator permission not granted. The app must be run as administrator.	未授予管理员权限。必须以管理员身份运行本应用。	لم يتم منح صلاحية المسؤول. يجب تشغيل التطبيق كمسؤول.
Yüksek	High	高	مرتفع
Yüksek CPU	High CPU	CPU 占用高	استهلاك CPU مرتفع
Yüksek RAM	High RAM	内存占用高	استهلاك RAM مرتفع
Yüksek performans: işlemci daha yüksek hızda tutulur. Güç tüketimi ve ısı artar, dizüstünde pil hızla azalır. Oyunlarda fark her zaman oluşmaz ve garanti edilmez.	High performance: the processor is kept at a higher speed. Power consumption and heat increase, and laptop batteries drain quickly. The difference is not always noticeable in games and is not guaranteed.	高性能：处理器将保持在更高速度。功耗和发热增加，笔记本电池耗电加快。游戏中的差异不一定明显，也不保证。	أداء عالٍ: يُحافظ على سرعة المعالج عند مستوى أعلى. يزداد استهلاك الطاقة والحرارة، وتنفد بطارية الحاسوب المحمول بسرعة. قد لا يكون الفرق واضحاً دائماً في الألعاب، ولا يُضمن.
Yüksek riskli (Windows/güvenlik ile ilgili) kayıtlar yalnızca incelenir, kaldırılamaz:	High-risk (Windows/security-related) entries are for review only and cannot be removed:	高风险（与 Windows/安全相关）的条目仅供查看，无法删除：	الإدخالات عالية الخطورة (المتعلقة بـ Windows/الأمان) للمراجعة فقط ولا يمكن إزالتها:
Yüksek riskli (yalnızca inceleme) kayıtları gizle	Hide high-risk (review-only) entries	隐藏高风险（仅供查看）条目	إخفاء الإدخالات عالية الخطورة (للمراجعة فقط)
Yüksek öncelik diğer işlemleri aç bırakabilir.	High priority may starve other processes.	高优先级可能导致其他进程无响应。	قد تؤدي الأولوية العالية إلى تجويع العمليات الأخرى.
Zaman	Time	时间	الوقت
Zamanlanmış	Scheduled	已计划	مجدول
Zamanlanmış bakım hatası:	Scheduled maintenance error:	计划维护错误：	خطأ في الصيانة المجدولة:
Zaten bir oyun oturumu sürüyor.	A game session is already in progress.	游戏会话已在进行中。	توجد جلسة لعب قيد التشغيل بالفعل.
Ziyaret geçmişi. Chrome/Edge'de indirme geçmişi de aynı dosyada olduğu için birlikte silinir. Yer imleri korunur.	Browsing history. Since download history in Chrome/Edge is stored in the same file, it is deleted too. Bookmarks are kept.	浏览历史记录。由于 Chrome/Edge 的下载历史也存储在同一文件中，因此会一并删除。书签将保留。	سجل التصفح. بما أن سجل التنزيلات في Chrome/Edge موجود في الملف نفسه، فسيُحذف أيضاً. تبقى الإشارات المرجعية محفوظة.
Zorla sonlandırma	Force termination	强制终止	إنهاء قسري
[{#}] {#}  (Risk: {#}, Durum: {#})	[{1}] {2}  (Risk: {3}, Status: {4})	[{1}] {2}  （风险：{3}，状态：{4}）	[{1}] {2}  (الخطورة: {3}، الحالة: {4})
dosya silindi	file deleted	文件已删除	تم حذف الملف
düşük ölçüldü	measured low	测得较低	تم قياسه منخفضاً
düşük/orta donanım	low/medium hardware	低/中等配置	أجهزة منخفضة/متوسطة
fark ölçüm dalgalanması içinde; anlamlı değişiklik sayılmaz	difference is within measurement fluctuation; not considered a meaningful change	差异在测量波动范围内；不视为有意义的变化	الفرق ضمن تذبذب القياس؛ ولا يُعد تغييراً ذا معنى
güçlü donanım	strong hardware	高性能硬件	أجهزة قوية
kapalı	off	关闭	متوقف
kayıtlı	saved	已保存	محفوظ
kayıtlı değil	not saved	未保存	غير محفوظ
masaüstü	Desktop	桌面	سطح المكتب
orta düzey donanım	mid-range hardware	中等配置硬件	أجهزة متوسطة المستوى
profil etkin	profile active	配置已启用	الملف الشخصي مفعّل
sürüm okunamadı	version could not be read	无法读取版本	تعذّرت قراءة الإصدار
veritabanı işlendi	database processed	数据库已处理	تمت معالجة قاعدة البيانات
yalnızca izleme	Monitoring only	仅监控	المراقبة فقط
yüksek ölçüldü	measured high	测得较高	تم قياسه مرتفعاً
{#}   -   {#} kayıt	{1}   -   {2} entries	{1}   -   {2} 条记录	{1}   -   {2} سجل
{#}  toplam {#}  |  kullanılan {#} (%{#})  |  boş {#}	{1}  total {2}  |  used {3} (%{4})  |  free {5}	{1}  总计 {2}  |  已用 {3}（%{4}）  |  可用 {5}	{1}  الإجمالي {2}  |  المستخدم {3} (%{4})  |  الفارغ {5}
{#} (RunOnce: yalnızca izlenir)	{1} (RunOnce: monitoring only)	{1}（RunOnce：仅监控）	{1} (RunOnce: المراقبة فقط)
{#} (derleme {#}) | {#} | {#} çekirdek | {#} GB RAM | {#}	{1} (build {2}) | {3} | {4} cores | {5} GB RAM | {6}	{1}（版本 {2}）| {3} | {4} 核心 | {5} GB 内存 | {6}	{1} (الإصدار {2}) | {3} | {4} نواة | {5} GB RAM | {6}
{#} (derleme {#}) | {#} | {#} çekirdek | {#} GB RAM | {#} | {#}{#} -> {#}	{1} (build {2}) | {3} | {4} cores | {5} GB RAM | {6} | {7}{8} -> {9}	{1}（版本 {2}）| {3} | {4} 核心 | {5} GB 内存 | {6} | {7}{8} -> {9}	{1} (الإصدار {2}) | {3} | {4} نواة | {5} GB RAM | {6} | {7}{8} -> {9}
{#} (işlem: {#})	{1} (process: {2})	{1}（进程：{2}）	{1} (العملية: {2})
{#} (korumalı Windows/güvenlik bileşeni)	{1} (protected Windows/security component)	{1}（受保护的 Windows/安全组件）	{1} (مكوّن Windows/أمان محمي)
{#} (sürüm {#}, derleme {#})	{1} (version {2}, build {3})	{1}（版本 {2}，版本号 {3}）	{1} (الإصدار {2}، البناء {3})
{#} ({#} kayıt)	{1} ({2} entries)	{1}（{2} 条记录）	{1} ({2} سجل)
{#} ({#} çekirdek / {#} mantıksal işlemci)	{1} ({2} cores / {3} logical processors)	{1}（{2} 核心 / {3} 个逻辑处理器）	{1} ({2} نواة / {3} معالج منطقي)
{#} (önceki başlangıç türü: {#} -> Elle)	{1} (previous startup type: {2} -> Manual)	{1}（先前启动类型：{2} -> 手动）	{1} (نوع بدء التشغيل السابق: {2} -> يدوي)
{#} (şu an: {#})	{1} (currently: {2})	{1}（当前：{2}）	{1} (حالياً: {2})
{#} GB dolu / {#} GB (%{#}), boş {#} GB	{1} GB used / {2} GB (%{3}), {4} GB free	已用 {1} GB / {2} GB（%{3}），可用 {4} GB	مستخدم {1} GB / {2} GB (%{3})، فارغ {4} GB
{#} GB kullanılıyor / {#} GB (%{#}), boş {#} GB	{1} GB in use / {2} GB (%{3}), {4} GB free	使用中 {1} GB / {2} GB（%{3}），可用 {4} GB	قيد الاستخدام {1} GB / {2} GB (%{3})، فارغ {4} GB
{#} MB RAM serbest kalabilir	{1} MB of RAM may be freed	可释放 {1} MB 内存	قد يتم تحرير {1} MB من الذاكرة
{#} MB RAM tutuyor ve yaklaşık {#} dk boşta.	Holding {1} MB of RAM and idle for about {2} min.	占用 {1} MB 内存，已空闲约 {2} 分钟。	يحتفظ بـ {1} MB من الذاكرة وخامل منذ حوالي {2} دقيقة.
{#} Olası yan etki: {#}	{1} Possible side effect: {2}	{1} 可能的副作用：{2}	{1} أثر جانبي محتمل: {2}
{#} ayar uygulandı.	{1} setting(s) applied.	已应用 {1} 项设置。	تم تطبيق {1} إعداد.
{#} değişiklik geri yüklendi.	{1} change(s) restored.	已还原 {1} 项更改。	تمت استعادة {1} تغيير.
{#} değişiklik geri yüklenecek (en yeniden eskiye):	{1} change(s) will be restored (newest to oldest):	将还原 {1} 项更改（从新到旧）：	سيتم استعادة {1} تغيير (من الأحدث إلى الأقدم):
{#} diskte arıza öngörülüyor - verilerinizi yedekleyin	Disk {1} failure predicted - back up your data	预测磁盘 {1} 将出现故障 - 请备份您的数据	يُتوقع فشل القرص {1} - قم بنسخ بياناتك احتياطياً
{#} dk önce	{1} min ago	{1} 分钟前	منذ {1} دقيقة
{#} dosya, toplam {#}. Kullanımdaki/erişim engelli dosyalar atlanır; Windows ve sistem klasörlerine dokunulmaz.	{1} files, total {2}. Files in use or with blocked access are skipped; Windows and system folders are not touched.	{1} 个文件，共 {2}。正在使用或访问受阻的文件将被跳过；不会触及 Windows 和系统文件夹。	{1} ملف، الإجمالي {2}. تُتخطى الملفات قيد الاستخدام أو المحظورة الوصول؛ ولا تُمس مجلدات Windows والنظام.
{#} gün+	{1}+ days	{1} 天以上	{1}+ يوم
{#} işlem sonlandırıldı.	{1} process(es) terminated.	已终止 {1} 个进程。	تم إنهاء {1} عملية.
{#} kategori, {#} dosya, toplam {#} temizlenecek:\n\n{#}	{1} categories, {2} files, total {3} will be cleaned:\n\n{4}	将清理 {1} 个类别、{2} 个文件，共 {3}：\n\n{4}	سيتم تنظيف {1} فئة و{2} ملف، الإجمالي {3}:\n\n{4}
{#} kayıt	{1} entries	{1} 条记录	{1} سجل
{#} kayıt kaldırılacak.	{1} entries will be removed.	将删除 {1} 条记录。	سيتم إزالة {1} سجل.
{#} kayıt kaldırıldı.	{1} entries removed.	已删除 {1} 条记录。	تمت إزالة {1} سجل.
{#} servis durduruldu.	{1} service(s) stopped.	已停止 {1} 个服务。	تم إيقاف {1} خدمة.
{#} servis güncellendi.	{1} service(s) updated.	已更新 {1} 个服务。	تم تحديث {1} خدمة.
{#} sn (Windows tanılama kaydı, son ölçüm)	{1} s (Windows diagnostic log, last measurement)	{1} 秒（Windows 诊断日志，最近一次测量）	{1} ث (سجل تشخيص Windows، آخر قياس)
{#} uyarı var (sarı satırlar)	{1} warning(s) (yellow rows)	{1} 个警告（黄色行）	{1} تحذير (صفوف صفراء)
{#} yedek dosyası içe aktarılacak. Silinen kayıtlar yeniden oluşturulur.\n\n{#}\n\nDevam edilsin mi?	{1} backup file(s) will be imported. Deleted entries will be recreated.\n\n{2}\n\nContinue?	将导入 {1} 个备份文件。已删除的条目将被重新创建。\n\n{2}\n\n是否继续？	سيتم استيراد {1} ملف نسخ احتياطي. ستُعاد إنشاء السجلات المحذوفة.\n\n{2}\n\nهل تريد المتابعة؟
{#} °C (ACPI termal bölge; doğrudan CPU çekirdek sıcaklığı olmayabilir)	{1} °C (ACPI thermal zone; may not be the direct CPU core temperature)	{1} °C（ACPI 热区；可能不是 CPU 核心的直接温度）	{1} °C (منطقة حرارية ACPI؛ قد لا تمثل حرارة نواة المعالج مباشرةً)
{#} °C (nvidia-smi)	{1} °C (nvidia-smi)	{1} °C（nvidia-smi）	{1} °C (nvidia-smi)
{#} öğe güncellendi.	{1} item(s) updated.	已更新 {1} 项。	تم تحديث {1} عنصر.
{#}/{#} dosya geri yüklendi.	{1}/{2} file(s) restored.	已还原 {1}/{2} 个文件。	تمت استعادة {1}/{2} ملف.
{#}/{#} yedek dosyası geri yüklendi.	{1}/{2} backup file(s) restored.	已还原 {1}/{2} 个备份文件。	تمت استعادة {1}/{2} ملف نسخ احتياطي.
{#}: güvenli kök klasör bulunamadı.	{1}: safe root folder not found.	{1}：未找到安全的根文件夹。	{1}: لم يُعثر على مجلد الجذر الآمن.
{#}: kurulu değil	{1}: not installed	{1}：未安装	{1}: غير مثبت
{#}: {#} -> önceki: {#}, {#}	{1}: {2} -> previous: {3}, {4}	{1}：{2} -> 先前：{3}，{4}	{1}: {2} -> السابق: {3}، {4}
{#}: {#} silindi, {#} atlandı (kullanımda/erişim engelli), {#} kazanıldı	{1}: {2} deleted, {3} skipped (in use/access blocked), {4} gained	{1}：已删除 {2}，跳过 {3}（使用中/访问受阻），释放 {4}	{1}: تم حذف {2}، وتخطي {3} (قيد الاستخدام/الوصول محظور)، وتحرير {4}
Çalışan uygulama: {#}. Kilitli dosyalar atlanır; tam temizlik için önce uygulamayı kendiniz kapatın.	Running app: {1}. Locked files are skipped; for a full cleanup, close the app yourself first.	正在运行的应用：{1}。被锁定的文件将被跳过；如需完整清理，请先自行关闭该应用。	التطبيق قيد التشغيل: {1}. تُتخطى الملفات المقفلة؛ للتنظيف الكامل، أغلق التطبيق بنفسك أولاً.
Çalışanlardan Ekle...	Add from running...	从正在运行的项中添加...	إضافة من العمليات الجارية...
Çalışma Klasörleri İstemcisi	Work Folders Client	工作文件夹客户端	عميل Work Folders
Çalışma: {#} saat	Runtime: {1} h	运行时间：{1} 小时	وقت التشغيل: {1} ساعة
Çalıştığı işlem	Running process	正在运行的进程	العملية قيد التشغيل
Çalışıyor	Running	运行中	قيد التشغيل
Çarşamba	Wednesday	星期三	الأربعاء
Çerez/oturum verilerini silmek, web sitelerindeki oturumlarınızı KAPATIR.\nHesaplarınıza yeniden giriş yapmanız gerekebilir.\n\nİsterseniz 'Çerezlerde korunacak siteler' kutusuna alan adı yazarak (ör. google.com, github.com) bu sitelerin çerezlerini koruyabilirsiniz.	Deleting cookie/session data will SIGN YOU OUT of websites.\nYou may need to sign in to your accounts again.\n\nIf you want, you can protect the cookies of specific sites by entering domains in the 'Sites to keep in cookies' box (e.g. google.com, github.com).	删除 Cookie/会话数据将使您退出网站登录。\n您可能需要重新登录您的账户。\n\n如需要，可以在“Cookie 中保留的网站”框中输入域名（例如 google.com、github.com）来保护这些网站的 Cookie。	سيؤدي حذف بيانات ملفات تعريف الارتباط/الجلسة إلى تسجيل خروجك من مواقع الويب.\nقد تحتاج إلى تسجيل الدخول إلى حساباتك مرة أخرى.\n\nإن أردت، يمكنك حماية ملفات تعريف الارتباط لمواقع معينة بإدخال النطاقات في المربع “مواقع يجب الاحتفاظ بملفات تعريفها” (مثل google.com، github.com).
Çerezler	Cookies	Cookie	ملفات تعريف الارتباط
Çerezlerde korunacak siteler:	Sites to keep in cookies:	Cookie 中保留的网站：	مواقع يجب الاحتفاظ بملفات تعريفها:
Çok düşük (donanımınız güçlü, fark neredeyse hissedilmez)	Very low (your hardware is strong, the difference is barely noticeable)	极低（您的硬件性能强，差异几乎不明显）	منخفض جداً (أجهزتك قوية، والفرق بالكاد ملحوظ)
Çok eski ağ paylaşım protokolü.	Very old network sharing protocol.	非常旧的网络共享协议。	بروتوكول مشاركة شبكة قديم جداً.
Çok eski oyunların ağ bileşeni.	Network component for very old games.	用于非常旧的游戏的网络组件。	مكوّن شبكة للألعاب القديمة جداً.
Çok sayıda başlangıç uygulaması varsa masaüstü açılırken yavaşlama ve takılma olabilir. Genellikle yalnızca az uygulaması olan sistemlerde mantıklıdır.	If there are many startup apps, the desktop may slow down and stutter when opening. This is usually only useful on systems with few apps.	如果启动应用过多，桌面打开时可能变慢并卡顿。通常仅在应用较少的系统上才有意义。	إذا كان هناك عدد كبير من تطبيقات بدء التشغيل، فقد يتباطأ سطح المكتب ويتقطع عند فتحه. عادةً ما يكون هذا مفيداً فقط في الأنظمة ذات التطبيقات القليلة.
ÖLÇÜMLER (işlem öncesi / sonrası)	MEASUREMENTS (before / after action)	测量数据（操作前 / 操作后）	القياسات (قبل / بعد الإجراء)
ÖNEMLİ NOTLAR	IMPORTANT NOTES	重要说明	ملاحظات مهمة
Ölçülen başlatma gecikmesi: {#} sn (açılışı kısaltma garantisi yok)	Measured startup delay: {1} s (no guarantee of shorter boot)	测得的启动延迟：{1} 秒（不保证缩短开机时间）	تأخير بدء التشغيل المقاس: {1} ث (لا يوجد ضمان لتقصير وقت الإقلاع)
Ölçülmedi	Not measured	未测量	لم يُقَس
Ölçülmedi; açılışta bir işlem ve bir miktar RAM azalır (süre kazancı garanti edilmez)	Not measured; one process and some RAM are reduced at startup (no guaranteed time gain)	未测量；启动时减少一个进程和部分内存（不保证节省时间）	لم يُقَس؛ يتم تقليل عملية واحدة وبعض الذاكرة عند بدء التشغيل (لا يوجد ضمان لتوفير الوقت)
Ölçülüyor...	Measuring...	正在测量...	جارٍ القياس...
Ölçüm koşulları: her değer, aynı yöntemle (5 ardışık örnek, 1 sn aralık, ortalama) işlemden hemen önce ve hemen sonra alınmıştır.	Measurement conditions: each value was taken immediately before and after the action, using the same method (5 consecutive samples, 1 s interval, average).	测量条件：每个数值均使用相同方法（5 次连续采样，间隔 1 秒，取平均值），在操作前后立即获取。	شروط القياس: أُخذت كل قيمة مباشرةً قبل الإجراء وبعده، بالطريقة نفسها (5 عينات متتالية، بفاصل ثانية واحدة، والمتوسط).
Önce Analiz Et düğmesine basın.	Press the Analyze button first.	请先点击“分析”按钮。	اضغط زر التحليل أولاً.
Önce bir güç planı seçin.	Select a power plan first.	请先选择电源计划。	اختر خطة طاقة أولاً.
Önce en az bir temizlik kategorisi seçin.	Select at least one cleanup category first.	请先选择至少一个清理类别。	اختر فئة تنظيف واحدة على الأقل أولاً.
Önce listeden ayar seçin veya Tümünü Geri Al düğmesini kullanın.	First select a setting from the list, or use the Undo All button.	请先从列表中选择一项设置，或使用“全部撤销”按钮。	اختر إعداداً من القائمة أولاً، أو استخدم زر “التراجع عن الكل”.
Önce listeden bir profil seçin.	Select a profile from the list first.	请先从列表中选择一个配置文件。	اختر ملفاً شخصياً من القائمة أولاً.
Önce listeden bir program seçin.	Select a program from the list first.	请先从列表中选择一个程序。	اختر برنامجاً من القائمة أولاً.
Önce listeden bir veya daha fazla ayar seçin.	Select one or more settings from the list first.	请先从列表中选择一项或多项设置。	اختر إعداداً واحداً أو أكثر من القائمة أولاً.
Önce listeden bir veya daha fazla öğe seçin.	Select one or more items from the list first.	请先从列表中选择一个或多个项目。	اختر عنصراً واحداً أو أكثر من القائمة أولاً.
Önce listeden işlem seçin.	Select a process from the list first.	请先从列表中选择一个进程。	اختر عملية من القائمة أولاً.
Önce listeden kayıt seçin.	Select an entry from the list first.	请先从列表中选择一个条目。	اختر إدخالاً من القائمة أولاً.
Önce listeden servis seçin.	Select a service from the list first.	请先从列表中选择一个服务。	اختر خدمة من القائمة أولاً.
Önce listeden uygulanabilir bir veya daha fazla öneri seçin.	Select one or more applicable suggestions from the list first.	请先从列表中选择一条或多条适用的建议。	اختر اقتراحاً واحداً أو أكثر قابلاً للتطبيق من القائمة أولاً.
Önce tarama yapın.	Run a scan first.	请先进行扫描。	قم بإجراء فحص أولاً.
Önce taratıp temizlenecek kategorileri seçin (dosya içeren kategoriler).	Scan first, then select the categories to clean (categories containing files).	请先扫描，然后选择要清理的类别（包含文件的类别）。	افحص أولاً، ثم اختر الفئات المراد تنظيفها (الفئات التي تحتوي على ملفات).
Önce taratıp temizlenecek öğeleri seçin.	Scan first, then select the items to clean.	请先扫描，然后选择要清理的项目。	افحص أولاً، ثم اختر العناصر المراد تنظيفها.
Önce yeni başlangıç türünü seçin.	Select the new startup type first.	请先选择新的启动类型。	اختر نوع بدء التشغيل الجديد أولاً.
Önce şu tarayıcıları kapatın:	Close these browsers first:	请先关闭以下浏览器：	أغلق هذه المتصفحات أولاً:
Önceki Ayara Dön	Revert to Previous Setting	恢复到之前的设置	العودة إلى الإعداد السابق
Önceki Plana Dön	Revert to Previous Plan	恢复到之前的计划	العودة إلى الخطة السابقة
Önceki başlangıç türü kaydedilir; "Son Uygulamayı Geri Al" ile geri yüklenir.	The previous startup type is saved and restored with “Undo Last App”.	先前的启动类型会被保存，并可通过“撤销上次应用”还原。	يتم حفظ نوع بدء التشغيل السابق واستعادته عبر “التراجع عن آخر تطبيق”.
Önceki başlangıç türü tanınmıyor	Previous startup type not recognized	无法识别先前的启动类型	نوع بدء التشغيل السابق غير معروف
Önceki oturum devralındı	Previous session taken over	已接管之前的会话	تم استئناف الجلسة السابقة
Önceki plan ({#}) geri yüklenir.	Previous plan ({1}) will be restored.	将还原之前的计划（{1}）。	سيتم استعادة الخطة السابقة ({1}).
Öncelik	Priority	优先级	الأولوية
Öncelik ayarlanamadı (PID {#}):	Could not set priority (PID {1}):	无法设置优先级（PID {1}）：	تعذّر تعيين الأولوية (PID {1}):
Öneri: yaklaşık {#} dk boşta, kapatılabilir	Suggestion: idle for about {1} min, can be closed	建议：已空闲约 {1} 分钟，可以关闭	اقتراح: خامل منذ حوالي {1} دقيقة، ويمكن إغلاقه
Önerilen	Recommended	推荐	موصى به
Önerilen Ayarı Uygula	Apply Recommended Setting	应用推荐设置	تطبيق الإعداد الموصى به
Önerilen değer uygulandı	Recommended value applied	已应用推荐值	تم تطبيق القيمة الموصى بها
Önerilir	Recommended	推荐	موصى به
Örnek	Example	示例	مثال
Örnekleme hatası:	Sampling error:	采样错误：	خطأ في أخذ العينات:
Özel veya üretici planı ({#}). Ayrıntıları için Windows Güç Seçenekleri sayfasına bakın.	Custom or manufacturer plan ({1}). For details, see the Windows Power Options page.	自定义或厂商电源计划（{1}）。详情请参阅 Windows 电源选项页面。	خطة طاقة مخصصة أو من الشركة المصنعة ({1}). للتفاصيل، راجع صفحة خيارات الطاقة في Windows.
Özellik	Feature	功能	الميزة
Özet CSV	Summary CSV	摘要 CSV	ملخص CSV
Öğe	Item	项目	العنصر
Öğe seçildiğinde veya menü kapandığında oluşan solma efektini kapatır.	Turns off the fade effect that appears when an item is selected or a menu closes.	关闭选中项目或菜单关闭时出现的淡出效果。	يُوقف تأثير التلاشي الذي يظهر عند تحديد عنصر أو إغلاق قائمة.
Üst anahtar açılamadı (zaten silinmiş olabilir).	Parent key could not be opened (it may already be deleted).	无法打开父项键（可能已被删除）。	تعذّر فتح المفتاح الأصلي (ربما تم حذفه بالفعل).
Üçüncü taraf	Third party	第三方	طرف ثالث
Üçüncü taraf sanallaştırma ve emülatörlerin Hyper-V katmanını kullanmasını sağlar.	Allows third-party virtualization and emulators to use the Hyper-V layer.	允许第三方虚拟化和模拟器使用 Hyper-V 层。	يتيح لبرامج المحاكاة الافتراضية والمحاكيات التابعة لجهات خارجية استخدام طبقة Hyper-V.
Üçüncü taraf: yardımcı/güncelleyici	Third party: helper/updater	第三方：辅助程序/更新程序	طرف ثالث: مساعد/أداة تحديث
ölçülebilen verilerde dikkat gerektiren bir durum yok	no condition requiring attention in measurable data	可测量数据中没有需要注意的情况	لا توجد حالة تستدعي الانتباه في البيانات القابلة للقياس
ölçülemedi	could not be measured	无法测量	تعذّر القياس
İmza sorunu (bilgi amaçlı)	Signature issue (for information)	签名问题（仅供参考）	مشكلة في التوقيع (للعلم)
İmzasız	Unsigned	未签名	غير موقّع
İmzasız*	Unsigned*	未签名*	غير موقّع*
İmzayı Doğrula (Seçili)	Verify Signature (Selected)	验证签名（已选中）	التحقق من التوقيع (المحدد)
İndirme geçmişi	Download history	下载历史	سجل التنزيلات
İptal	Cancel	取消	إلغاء
İsteğe Bağlı Özellikleri İncele	Review Optional Features	查看可选功能	مراجعة الميزات الاختيارية
İsteğe bağlı	Optional	可选	اختياري
İsteğe bağlı Windows özellikleri ({#})	Optional Windows features ({1})	可选 Windows 功能（{1}）	ميزات Windows الاختيارية ({1})
İsteğe bağlı başlıyor	Optional starting	可选项正在启动	بدء الاختياري
İsteğe bağlı özellikler okunamadı:	Could not read optional features:	无法读取可选功能：	تعذّرت قراءة الميزات الاختيارية:
İsteğe bağlı:	Optional:	可选：	اختياري:
İsteğe bağlı:*	Optional:*	可选：*	اختياري:*
İzlenecek uygulamayı seçin	Select the app to monitor	选择要监控的应用	اختر التطبيق المراد مراقبته
İşlem	Process	进程	العملية
İşlem adı	Process name	进程名称	اسم العملية
İşlem adı: {#}   [Kategori: {#}]	Process name: {1}   [Category: {2}]	进程名称：{1}   [类别：{2}]	اسم العملية: {1}   [الفئة: {2}]
İşlem artık mevcut değil (PID yeniden kullanılmış).	Process no longer exists (PID was reused).	进程已不存在（PID 已被重用）。	العملية لم تعد موجودة (تمت إعادة استخدام PID).
İşlem onaylanmadı, hiçbir değişiklik yapılmadı.	Operation not confirmed; no changes were made.	操作未确认；未做任何更改。	لم تُؤكَّد العملية؛ لم يُجرَ أي تغيير.
İşlem sonlandırma geçmişi	Process termination history	进程终止历史	سجل إنهاء العمليات
İşlem sonlandırma: {#} (PID {#}) -> {#}	Process termination: {1} (PID {2}) -> {3}	进程终止：{1}（PID {2}）-> {3}	إنهاء العملية: {1} (PID {2}) -> {3}
İşlem önceliği	Process priority	进程优先级	أولوية العملية
İşlem önceliği:	Process priority:	进程优先级：	أولوية العملية:
İşlemci	Processor	处理器	المعالج
İşlemci modeli	Processor model	处理器型号	طراز المعالج
İşlemler	Processes	进程	العمليات
ŞU AN ETKİN	CURRENTLY ACTIVE	当前已启用	نشط حالياً
Şifresiz uzak bağlantı aracı.	Passwordless remote connection tool.	免密码远程连接工具。	أداة اتصال عن بُعد بدون كلمة مرور.
Şimdi Yenile	Refresh Now	立即刷新	تحديث الآن
Şimdi Çalıştır	Run Now	立即运行	تشغيل الآن
Şimdi şu kategoriler temizlenecek (silinenler geri alınamaz):\n\n{#}\n\nDevam edilsin mi?	The following categories will be cleaned now (deleted items cannot be recovered):\n\n{1}\n\nContinue?	以下类别将立即清理（已删除的项目无法恢复）：\n\n{1}\n\n是否继续？	سيتم تنظيف الفئات التالية الآن (لا يمكن استرداد العناصر المحذوفة):\n\n{1}\n\nهل تريد المتابعة؟
Şu an öneri yok. Gözlem süresi: {#} dk (sızıntı tespiti için en az 3 dk, boşta tespiti için 5 dk gerekir).	No suggestions right now. Observation time: {1} min (at least 3 min is needed for leak detection, 5 min for idle detection).	目前没有建议。观察时间：{1} 分钟（泄漏检测至少需要 3 分钟，空闲检测需要 5 分钟）。	لا توجد اقتراحات حالياً. وقت المراقبة: {1} دقيقة (يلزم 3 دقائق على الأقل لاكتشاف التسريب، و5 دقائق لاكتشاف الخمول).
Şu an önerilecek bir optimizasyon bulunamadı. Not: boşta işlem önerileri için uygulamanın en az 5 dk açık kalması gerekir.	No optimization to suggest right now. Note: the app must stay open for at least 5 min for idle process suggestions.	目前没有可建议的优化项。注意：要获得空闲进程建议，应用必须保持打开至少 5 分钟。	لا توجد تحسينات لاقتراحها حالياً. ملاحظة: يجب أن يبقى التطبيق مفتوحاً لمدة 5 دقائق على الأقل للحصول على اقتراحات العمليات الخاملة.
Şu an: {#}. Önerilen: {#}.	Current: {1}. Recommended: {2}.	当前：{1}。推荐：{2}。	الحالي: {1}. الموصى به: {2}.
Şu anki durum	Current status	当前状态	الحالة الحالية
Şu anki durum: {#}   |   Önerilen: {#}	Current status: {1}   |   Recommended: {2}	当前状态：{1}   |   推荐：{2}	الحالة الحالية: {1}   |   الموصى به: {2}
Şu ayarlar değiştirilecek:	The following settings will be changed:	以下设置将被更改：	سيتم تغيير الإعدادات التالية:
Şu işlemler korumalıdır ve sonlandırılamaz:	The following processes are protected and cannot be terminated:	以下进程受保护，无法终止：	العمليات التالية محمية ولا يمكن إنهاؤها:
Şu işlemler sonlandırılacak. Kaydedilmemiş veriler kaybolabilir:	The following processes will be terminated. Unsaved data may be lost:	以下进程将被终止。未保存的数据可能会丢失：	سيتم إنهاء العمليات التالية. قد تفقد البيانات غير المحفوظة:
Şu kategoriler varsayılan olarak kapalıdır ve kişisel/uygulama verisi içerebilir veya geri alınamaz:	The following categories are off by default and may contain personal/app data or cannot be undone:	以下类别默认关闭，可能包含个人/应用数据，或无法撤销：	الفئات التالية متوقفة افتراضياً وقد تحتوي على بيانات شخصية/تطبيقات أو لا يمكن التراجع عنها:
Şu servisler durdurulacak (başlangıç türleri değişmez, yeniden başlatmada tekrar açılabilir):	The following services will be stopped (startup types stay the same; they may start again after restart):	以下服务将被停止（启动类型保持不变；重启后可能会再次启动）：	سيتم إيقاف الخدمات التالية (تبقى أنواع بدء التشغيل كما هي؛ وقد تعود للعمل بعد إعادة التشغيل):
Şu servisler korumalıdır, değiştirilemez:	The following services are protected and cannot be changed:	以下服务受保护，无法更改：	الخدمات التالية محمية ولا يمكن تغييرها:
Şu servislerin başlangıç türü '{#}' yapılacak:	The startup type of the following services will be set to '{1}':	以下服务的启动类型将设置为“{1}”：	سيتم تعيين نوع بدء التشغيل للخدمات التالية إلى '{1}':
Şu {#} değişiklik yapılacak:	The following {1} change(s) will be made:	将进行以下 {1} 项更改：	سيتم إجراء {1} التغييرات التالية:
Şu öğeler temizlenecek:\n\n{#}	The following items will be cleaned:\n\n{1}	以下项目将被清理：\n\n{1}	سيتم تنظيف العناصر التالية:\n\n{1}
• {#} (PID {#}): {#} MB tutuyor, yaklaşık {#} dk boşta. Kullanmıyorsanız İşlemler sekmesinden onayınızla kapatabilirsiniz.	• {1} (PID {2}): holding {3} MB, idle for about {4} min. If you are not using it, you can close it from the Processes tab with your confirmation.	• {1}（PID {2}）：占用 {3} MB，已空闲约 {4} 分钟。如果您没有在使用，可以在“进程”选项卡中确认后关闭它。	• {1} (PID {2}): يحتفظ بـ {3} MB، وخامل منذ حوالي {4} دقيقة. إذا كنت لا تستخدمه، يمكنك إغلاقه من تبويب العمليات بعد تأكيدك.
• {#} (PID {#}): özel bellek gözlem boyunca {#} MB -> {#} MB arttı (sızıntı şüphesi, kesin değildir). Uygulamayı yeniden başlatmak sorunu çözebilir.	• {1} (PID {2}): private memory increased from {3} MB -> {4} MB during observation (suspected leak, not certain). Restarting the app may fix the issue.	• {1}（PID {2}）：观察期间专用内存从 {3} MB 增至 {4} MB（疑似泄漏，未经确认）。重新启动应用可能会解决该问题。	• {1} (PID {2}): زادت الذاكرة الخاصة من {3} MB إلى {4} MB أثناء المراقبة (تسريب مشتبه به، غير مؤكد). قد تحل إعادة تشغيل التطبيق المشكلة.
Ad	Name	名称	الاسم
Boyut (MB)	Size (MB)	大小 (MB)	الحجم (ميغابايت)
Ne yapar	What it does	作用	وظيفته
Ara:	Search:	搜索：	بحث:
Hata:	Error:	错误：	خطأ:
'@

switch ($script:LangCode) {
    'tr'    { [L10n]::Idx = -1 }
    'zh'    { [L10n]::Idx = 1 }
    'ar'    { [L10n]::Idx = 2 }
    default { [L10n]::Idx = 0 }
}
if ([L10n]::Idx -ge 0) { [L10n]::Load($script:LangData) }

# Buttons that get the "primary" theme colour, in the active language
$script:PrimaryBtn = @('Seçilileri Uygula', 'Analiz Et', 'Taramayı Başlat', 'Geri Yükleme Noktası Oluştur') | ForEach-Object { [L10n]::T($_) }
