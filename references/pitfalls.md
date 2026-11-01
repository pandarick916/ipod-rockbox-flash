# 踩坑记录与实测数据

按主题分组。每条都标了依据来源，避免把推断当结论。

---

## 一、主题字体：最容易判断错的一层

### 1.1 两层字体，只改上面那层没用

Rockbox 主题的字体分两处：

| 位置 | 作用范围 | 例子 |
|---|---|---|
| `.rockbox/themes/<名>.cfg` 里的 `font:` | **菜单、文件浏览器、设置页** | `font: /.rockbox/fonts/22-LeagueSpartan-Regular.fnt` |
| `.rockbox/wps/<名>.wps` 和 `.sbs` 里的 `%Fl()` | **播放屏、状态栏** | `%Fl(2,22-LeagueSpartan-Bold.fnt)` |

只改 cfg 的 `font:`，菜单是中文了，但播放屏的歌名依然是方块。

### 1.2 `%Fl` 是括号逗号语法，不是竖线

实测 Themify 2 里的全部 8 处引用（`grep` 自 `Themify_2.wps` / `.sbs`）：

```
.wps  %Fl(2,22-LeagueSpartan-Bold.fnt)            # 歌名
.wps  %Fl(3,18-LeagueSpartan-Medium.fnt)          # 艺术家/专辑
.wps  %Fl(5,16-LeagueSpartan-SemiBold.fnticons)   # 电池数字（图标字体）
.wps  %Fl(7,Blank_Font.fnticons,5)                # 空白占位
.wps  %Fl(9,Graphics_Font.fnticons)               # 矢量图标
.sbs  %Fl(4,18-LeagueSpartan-Medium.fnt)          # 子文本
.sbs  %Fl(5,16-LeagueSpartan-SemiBold.fnticons)   # 电池图标
.sbs  %Fl(9,Graphics_Font.fnticons)               # 矢量图标
```

搜索正则必须是：

```python
re.finditer(r'%Fl\(\s*\d+\s*,\s*([^,\)]+)\s*[,\)]', text)
```

第一版用了 `%Fl\|([^|]*)\|`（竖线分隔），结果全是空，差点得出「这个主题根本没用字体标签」的错误结论。

### 1.3 三类字体，只有一类该换

| 类型 | 后缀 | 处理 |
|---|---|---|
| 文字字体 | `.fnt` | 换成中文字形 |
| 图标字体 | `.fnticons` | **绝对不能换**，换了图标就废 |
| 未引用的备用字体 | `.fnt` | 不动（比如 `24-LeagueSpartan-Regular.fnt` 没被任何 skin 引用） |

### 1.4 必须保留文件名

`sbs` 里有这样的判断：

```
%?and(%if(%ss(0,2,%St(font)),!=,22),%if(%ss(0,2,%St(font)),!=,24))<...>
```

主题靠**字体名头两位**是不是 `22`/`24` 来决定用哪套排版分支。改名会让整个布局切到另一套。

所以正确顺序是：备份原文件 → 中文字体**覆盖同名文件**。文件名一个字都不动，坐标、图标、进度条、封面位置全部原样。

### 1.5 「体积最大」是致命的启发式

负面测试实录（伪造设备目录 + 真实 `Themify_2.zip`，用「体积最大的 .fnt」当兜底选字体）：

```
找中文字体 → 22-LeagueSpartan-Bold.fnt      ← 把英文字体当成了中文源
替换 22-LeagueSpartan-Regular.fnt
替换 18-LeagueSpartan-Medium.fnt
→ 三个字体全变成英文字体，中文彻底消失
```

原因：`22-LeagueSpartan-Bold.fnt` 有 **2,825,258 字节（2.8 MB）**，比 `16-WenQangYi-Unibit.fnt`（2.4 MB）还大。

改成只认文件名关键词后，同样场景输出：

```
找中文字体 → (没找到)
!! 没找到中文字体 —— 按设计跳过全部替换，一个字体都不动
swapped = 0
```

字体目录零字节改动。

> **一般化的教训**：覆盖类操作里，启发式兜底比没有兜底更危险。宁可停下来报错。

### 1.6 中文字号的真实上限

网上常见的说法是「Rockbox 中文字体最大 16px」。这只对**官方字体包**成立。

官方字体包（`rockbox.org/translate/whichfont.php` 全字体覆盖率表）里的 CJK 字体：

```
16-GNU-Unifont
16-WenQangYi-Unibit
12/11/10/09-WenQangYi-Song(-Bold)
14/13/12/11/10/09/08-Sazanami-Mincho
```

最大 16px。

但**主题自带的字体可以更大**。实测一台装了 `iRB_Classic_With_CJK` 主题的机器，`fonts/` 里有：

```
18-SFPro-Regular-CJK.fnt       5,977,927 字节  18px
17-SourceHanSans-Medium.fnt    6,980,879 字节  17px
16-SFPro-Bold-CJK.fnt          4,894,215 字节  16px
16-SFPro-Regular-CJK.fnt       4,776,555 字节  16px
15-SourceHanSans-Medium.fnt    5,160,147 字节  15px
```

所以先扫描、再决定，不要预设只有 16px。

注意 `32-SF-Pro-Display-Black.fnt` 这种名字里有 `SF-Pro` 但只有 678 KB 的，是纯拉丁字体，不含 CJK。所以不能靠"字号大"判断，要靠文件名里的 `CJK` 标记。

---

## 二、设备结构与判定

### 2.1 双分区

| 分区 | 容量 | 特征 | Windows 行为 |
|---|---|---|---|
| 苹果固件分区 | ~192 MB | 无 iPod_Control | 认不出 → 弹「需要格式化」 |
| 数据分区 | 剩余全部 | 含 `iPod_Control`、`.rockbox` | 正常读写 |

**格式化弹窗永远点取消。**

### 2.2 数据盘的判定条件

三条同时满足：

1. 容量 > 10 GB
2. 文件系统 FAT32
3. 存在 `iPod_Control` 或 `.rockbox` 目录

192 MB 那条在第一关就被排除，所以不会选错。

### 2.3 哪些目录绝对不能删

```
iPod_Control\
├── Device\            ← SysInfo（序列号）、SysInfoExtended（12 KB 硬件标识）
│                         删了设备认不出自己，必须用 iTunes 恢复
├── Music\             ← 可以清空内容，但保留目录本身
├── iTunes\            ← 可以删 iTunesDB / iTunesControl，保留目录
├── Artwork\           ← 封面缓存，可以清空
├── Tones\ Games_RO\   ← 别管
└── gamedata_RW\ gamestats_WO\
```

---

## 三、原厂歌库清理（实测记录）

### 3.1 用户问「清空 iPod_Control\Music 就行吗」

**答案：不对，会留幽灵条目。**

实测一台机器：

```
iTunesDB（501,122 字节）里 mhit 曲目记录：327 条
iPod_Control\Music 里实际文件：          328 个（3.01 GB，F00–F49 共 50 个文件夹）
```

两者基本对应，说明原厂固件靠索引而不是文件列表。只删文件不删索引，切回原厂会看到 327 首点不开的歌。

### 3.2 但这些文件是收藏，不是缓存

同一次清理，先读 ID3 生成清单才发现内容：

```
李志 17 / 罗大佑 17 / 陈奕迅 14 / 李宗盛 13 / 赵雷 10 / 周华健 9
林忆莲 8 / 野孩子 8 / 王菲 7 / 许巍 7 / 谢天笑 7 / 马飞 7
张玮玮和郭龙 6 / 许美静 6 / 痛仰乐队 5 / 伍佰 4
+ RDR2 原声、Eagles、David Gilmour、Ennio Morricone
```

**关键**：`iPod_Control\Music\F00\WXOO.mp3` 这种 iTunes 自动重命名的文件，用户自己也不知道里面是什么。直接删等于盲删。

所以正确顺序是：

1. **先生成可读清单**（CSV：路径 / 歌名 / 歌手 / 专辑 / 时长 / 字节）
2. 给用户看内容，确认是要「清空壳」还是「删歌」
3. 推荐**搬家**：按 `<歌手>\<歌名>.<ext>` 移到 `Music\`
4. 迁移核数通过后，再删索引

### 3.3 迁移实测数据

```
源 328 个文件 / 3.01 GB
→ 目标 328 个 mp3 + 134 个歌手目录，0 失败
→ 冲突 1 个（歌名与专辑同名，用「歌名 (专辑)」消解）
→ 非法字符清洗 3 个（Windows 不允许 \ / : * ? " < > |）
→ 超长路径 0 个
→ 释放 130 MB（iTunesDB 0.48 MB + iTunesControl 75 MB + Artwork 54.8 MB）
```

歌没删，所以 3.01 GB 仍在，只是换了位置。这一点要对用户讲清楚，否则他会以为空间该腾出来 3 GB。

迁移后 `iPod_Control\Music` 只剩 50 个空文件夹（保留，让原厂固件重建时结构完整）。

`Device\` 做了前后快照比对，8 个文件完全一致。

### 3.4 迁移后必须重建 Rockbox 媒体库

音频路径全变了，数据库条目还指向旧路径。必须在设备上：

> 设置 → General Settings → Database → Initialize Now

---

## 四、PowerShell / 脚本环境的坑

### 4.1 无 BOM 的 UTF-8 ps1 会报语法错

PowerShell 5.1 默认按 ANSI 读文件。没有 BOM 的 UTF-8 脚本里，中文会被解析成乱码，进而吞掉引号，报：

```
方法调用中缺少")"。
```

解决：脚本文件开头加 UTF-8 BOM（`EF BB BF`）。

### 4.2 `Out-File -Encoding ASCII` 会把中文变成问号

```
# 老 MP3 的标签如果显示乱码...
```
被写成
```
# ? MP3 ??????????????????
```

写进 `config.cfg` 的注释一律用英文。这个文件本身也应当是纯 ASCII。

### 4.3 `Add-Type` 被安全策略拦

```
Command blocked for security: Add-Type compiles and loads .NET code at runtime
```

所以不能用 `Add-Type -AssemblyName System.IO.Compression.FileSystem` 解压。改用：

- `[System.IO.File]::ReadAllBytes()` 做文件头校验
- Python `zipfile` 做 zip 内容检查

### 4.4 Bash 调 PowerShell 被拦

```
Command blocked for security: Invoking PowerShell from Bash bypasses PowerShell security checks
```

`.bat` 文件用文件工具写，PowerShell 用专用工具跑。

### 4.5 `Write-Progress` 在管道下会输出海量重复行

捕获脚本输出做日志时，进度条会把每一帧都打出来，看起来像「流程跑了两遍」。判断以最后的关键行为准（字体替换、配置写入各只出现一次）。

### 4.6 `Sort-Object` 混合排序写法

```powershell
$ranked | Sort-Object Tier, @{Expression={$_.Px}; Descending=$true}
```

`Expression` 必须给 scriptblock，不能写成 `@{Expression='Px'}`。

---

## 五、下载源

### 5.1 `download.rockbox.org` 全站反爬

请求 `fonts.zip`、字体文件、`bootloader/ipod/` 目录，全部返回 **4,418 字节的 HTML 验证页**（标题 "Making sure you're not a bot!"），HTTP 状态却是 200。

Web Archive 备份返回 429。GitHub API 返回 403。

**结论**：官方字体包无法程序化获取。只能：

- 让用户用 Rockbox Utility 的 Fonts 组件（它内部有下载逻辑）
- 或者从已有设备上取

### 5.2 下载到的文件要做头校验

曾经拿到一个 4,518 字节的 `bootloader-ipod6g.ipod`，开头是 `<!doctype`，其实是反爬页面。正确的文件是 102,344 字节。

校验方式：读第 5–8 字节，应为 `ip6g`。

---

## 六、mks5lboot 源码结论

针对「工具太旧、不支持新版 Rockbox」这个疑虑，读 `mkdfu.c` 得到的结论：

| 检查项 | 是否检查 |
|---|---|
| 文件第 5–8 字节的型号标识（ipod6g = `ip6g`） | ✅ 检查，不符则 `_ERR()` 退出 |
| ROM 载荷尺寸上限 `128 KiB - 0x50 - 700 = 130,292` 字节 | ✅ 检查 |
| bootloader 版本 | ❌ 不检查 |
| Rockbox 版本 | ❌ 不检查 |
| 固件版本 | ❌ 不检查 |

所以只要型号对、尺寸不超，新版 Rockbox 一样能刷。官方 `bootloader-ipod6g.ipod` 自 2017-03-22 起未更新，`bin/` 里那份就是最新。

CLI 用法：

```
mks5lboot64.exe --dfuscan               # 扫描，无设备退出码 1
mks5lboot64.exe --bl-inst <文件>        # = mkdfu-inst + dfusend
mks5lboot64.exe --bl-uninst <platform>
```

`--dfuscan` 同时走 winapi 和 libusb 两条路径扫描。

---

## 七、诊断输出示例（健康状态）

```
[1] 磁盘扫描
    G:                 0.0 GB  FAT      可移动
    H:  PANDA'S IPO   74.3 GB  FAT32    可移动       <== iPod (已装 Rockbox)

[3] 中文字体候选（按 可靠度 → 字号 排序）
    18-SFPro-Regular-CJK.fnt           18px   5838 KB  (tier 1)  <== 会被选中
    16-SFPro-Bold-CJK.fnt              16px   4780 KB  (tier 1)
    17-SourceHanSans-Medium.fnt        17px   6817 KB  (tier 2)
    16-GNU-Unifont.fnt                 16px   6518 KB  (tier 3)

[4] 主题与字体引用
    当前皮肤           Themify_2.wps
     22-LeagueSpartan-Regular.fnt     5838 KB  <== 已是中文字形（来自 18-SFPro-Regular-CJK.fnt）
     22-LeagueSpartan-Bold.fnt        5838 KB  <== 已是中文字形
     18-LeagueSpartan-Medium.fnt      5838 KB  <== 已是中文字形
```
