Add-Type -AssemblyName System.Drawing

$W = 1600; $H = 1210
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

$fontName = 'Microsoft YaHei'
$fTitle  = New-Object System.Drawing.Font($fontName, 26, [System.Drawing.FontStyle]::Bold)
$fSub    = New-Object System.Drawing.Font($fontName, 13)
$fHead   = New-Object System.Drawing.Font($fontName, 12, [System.Drawing.FontStyle]::Bold)
$fBody   = New-Object System.Drawing.Font($fontName, 12)
$fSmall  = New-Object System.Drawing.Font($fontName, 10)
$fBig    = New-Object System.Drawing.Font($fontName, 15, [System.Drawing.FontStyle]::Bold)

function Brush($hex) { return (New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($hex))) }
$bg      = Brush '#F6F7F9'
$ink     = Brush '#1F2937'
$muted   = Brush '#6B7280'
$line    = Brush '#E1E4E8'
$greenBg = Brush '#E7F5EC'; $greenFg = Brush '#1F7A44'
$amberBg = Brush '#FDF3D8'; $amberFg = Brush '#8A6100'
$redBg   = Brush '#FCE7E7'; $redFg   = Brush '#B02A2A'
$greyBg  = Brush '#EEF0F3'; $greyFg  = Brush '#6B7280'
$blueBg  = Brush '#E8F0FE'; $blueFg  = Brush '#1A4FBA'
$white   = Brush '#FFFFFF'

$g.FillRectangle($bg, 0, 0, $W, $H)

function Text($text, $font, $brush, $x, $y, $w, $h, $align = 'Near') {
  $fmt = New-Object System.Drawing.StringFormat
  switch ($align) {
    'Center' { $fmt.Alignment = [System.Drawing.StringAlignment]::Center; $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center }
    'Far'    { $fmt.Alignment = [System.Drawing.StringAlignment]::Far; $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center }
    default  { $fmt.Alignment = [System.Drawing.StringAlignment]::Near; $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center }
  }
  $fmt.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
  $rect = New-Object System.Drawing.RectangleF($x, $y, $w, $h)
  $g.DrawString($text, $font, $brush, $rect, $fmt)
}

function RoundRect($brush, $x, $y, $w, $h, $r) {
  if ($r -le 0) { $g.FillRectangle($brush, $x, $y, $w, $h); return }
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $path.AddArc($x, $y, $d, $d, 180, 90)
  $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  $g.FillPath($brush, $path)
  $path.Dispose()
}

function Chip($text, $x, $y, $bgBrush, $fgBrush, $w = 150) {
  RoundRect $bgBrush $x $y $w 30 6
  Text $text $fBody $fgBrush $x $y $w 30 'Center'
}

# 标题
Text 'Treehole 1.2.0 改动模块与完成度' $fTitle $ink 60 34 1000 44
Text 'v1.1.2（2026-09-14）→ 现在  ·  48 个提交  ·  21 个测试文件  ·  数据库表结构与授权已核对' $fSub $muted 62 84 1250 26

# 图例（右对齐，避免超出画布）
Chip '已完成' 1000 40 $greenBg $greenFg 96
Chip '待验证/待执行' 1104 40 $amberBg $amberFg 136
Chip '未开始/阻塞' 1248 40 $redBg $redFg 128
Chip '不适用' 1384 40 $greyBg $greyFg 84

# 表格
$colX = @(60, 520, 730, 950, 1170)
$colW = @(450, 200, 210, 210, 370)
$headers = @('模块（v1.1.2 之后新增/改动）', '代码实现', '自动化测试', '真机联调', '发布阻塞')
$rowY = 140
$rowH = 44

RoundRect $white 50 128 1500 ($rowH * 15 + 30) 14
for ($i = 0; $i -lt $headers.Count; $i++) {
  Text $headers[$i] $fHead $muted $colX[$i] $rowY $colW[$i] 34
}

$rows = @(
  @('私信与消息中心（会话 / 聊天 / 发送重试）', @('已实现', 'g'), @('7 个测试文件', 'g'), @('未做', 'r'), @('—', 'n')),
  @('消息本地加密缓存与增量同步', @('已实现', 'g'), @('4 个用例', 'g'), @('未做', 'r'), @('—', 'n')),
  @('系统消息（回复 / 公告 / 审核）', @('已实现', 'g'), @('system_inbox_test', 'g'), @('未做', 'r'), @('—', 'n')),
  @('举报与隐藏内容', @('已实现', 'g'), @('reports_test', 'g'), @('未做', 'r'), @('—', 'n')),
  @('内容安全与分级处罚', @('已实现', 'g'), @('publication_safety_test', 'g'), @('未做', 'r'), @('—', 'n')),
  @('头像原生裁剪与审核上传', @('已实现', 'g'), @('3 个测试文件', 'g'), @('未做', 'r'), @('—', 'n')),
  @('启动与广场首帧', @('已实现', 'g'), @('startup_posts_test', 'g'), @('未做', 'r'), @('—', 'n')),
  @('视觉与主题（消息页 / 提示）', @('已实现', 'g'), @('布局与头部用例', 'g'), @('未做', 'r'), @('—', 'n')),
  @('Android 正式签名', @('未做', 'r'), @('—', 'n'), @('—', 'n'), @('阻塞发版', 'r')),
  @('versions 写入 1.2.0', @('待执行', 'a'), @('—', 'n'), @('—', 'n'), @('发版时执行', 'a')),
  @('离线推送（App 关闭后）', @('未开始', 'r'), @('—', 'n'), @('—', 'n'), @('范围未定', 'a')),
  @('私信图片 / 附件', @('未开始', 'r'), @('—', 'n'), @('—', 'n'), @('范围未定', 'a')),
  @('会话删除 / 清空', @('未开始', 'r'), @('—', 'n'), @('—', 'n'), @('范围未定', 'a')),
  @('对方已读回执展示', @('未开始', 'r'), @('—', 'n'), @('—', 'n'), @('范围未定', 'a'))
)

$y = $rowY + 40
$idx = 0
foreach ($r in $rows) {
  if ($idx % 2 -eq 0) { RoundRect (Brush '#FAFBFC') 50 ($y - 4) 1500 $rowH 0 }
  Text $r[0] $fBody $ink ($colX[0] + 6) $y ($colW[0] - 10) $rowH
  for ($c = 1; $c -lt 5; $c++) {
    $cell = $r[$c]
    $txt = $cell[0]; $kind = $cell[1]
    switch ($kind) {
      'g' { $bgB = $greenBg; $fgB = $greenFg }
      'a' { $bgB = $amberBg; $fgB = $amberFg }
      'r' { $bgB = $redBg; $fgB = $redFg }
      default { $txt = '—'; $bgB = $greyBg; $fgB = $greyFg }
    }
    if ($txt -ne '—') { Chip $txt ($colX[$c] + 2) ($y + 6) $bgB $fgB ($colW[$c] - 24) }
    else { Text '—' $fBody $greyFg ($colX[$c] + 8) $y ($colW[$c] - 20) $rowH }
  }
  $y += $rowH
  $idx++
}

# 分隔线
$g.DrawLine((New-Object System.Drawing.Pen($line.Color, 1)), 60, 852, 1540, 852)

# 左下：未决产品规则
RoundRect $white 50 880 740 280 14
Text '仍未拍板的产品规则（MESSAGING_PLAN §7）' $fBig $ink 74 898 690 34
$items = @(
  '陌生人能否直接发消息，还是先发会话邀请',
  '注销账号后私信保留多久、是否级联删除',
  '全体公告是否覆盖未来新注册用户',
  '是否需要 App 关闭后的手机推送（成本与合规）',
  '私信是否允许图片/附件，首版是否只做文字'
)
$iy = 946
foreach ($it in $items) {
  $g.FillEllipse((Brush '#93A1B1'), 80, ($iy + 14), 7, 7)
  Text $it $fBody $ink 100 $iy 660 30
  $iy += 38
}

# 右下：发版还差什么
RoundRect $white 830 880 720 280 14
Text '发版还差的动作（按顺序）' $fBig $ink 854 898 670 34
$todo = @(
  @('①', 'Android 正式签名（当前为 debug，阻塞）', 'r'),
  @('②', '真机双账号联调：私信/举报/头像/系统消息', 'r'),
  @('③', '执行 versions apply.sql → 打 tag v1.2.0', 'a'),
  @('④', 'iOS TestFlight 上传与外部测试组确认', 'a'),
  @('⑤', '补 APK 到 v1.2.0/ 目录并核对 4 个 ABI', 'a')
)
$ty = 946
foreach ($t in $todo) {
  Text $t[0] $fHead $muted 860 $ty 24 30
  $bgB = if ($t[2] -eq 'r') { $redBg } else { $amberBg }
  $fgB = if ($t[2] -eq 'r') { $redFg } else { $amberFg }
  Chip $t[1] 892 $ty $bgB $fgB 630
  $ty += 40
}

# 页脚
Text '数据来源：git log v1.1.2..HEAD、test/、lib/ 代码检索、deploy/MIGRATIONS_1.2.0.md、生产库 SHOW GRANTS 输出' $fSmall $muted 60 1176 1480 24

$outDir = Join-Path $PSScriptRoot '..\docs\assets'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$out = Join-Path $outDir '1.2.0-modules.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "saved=$out"
