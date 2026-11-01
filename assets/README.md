# assets 目录说明

这里只放 **GPL 开源组件**，主体是 Rockbox 生态的一部分。

| 文件 | 来源 | 许可 | 大小 |
|---|---|---|---|
| `rockbox-ipod6g.zip` | [rockbox.org](https://www.rockbox.org/download/) 官方构建 | GPL v2 | 9.2 MB |
| `bootloader-ipod6g.ipod` | Rockbox 官方 bootloader | GPL v2 | 102 KB |
| `mks5lboot64.exe` | [freemyipod](https://freemyipod.org/) 项目 | GPL v2 | 1.0 MB |

## 主题不在这里，请自行下载

**Themify 2**（推荐）由 **Dook（Evan Kenny）** 设计制作，是他两年多的作品。虽然是 GPL-3.0，但直接打包进别人的仓库不合适——下载量和反馈应该归作者。

请到以下任一渠道获取：

- 主题库：https://themes.rockbox.org/index.php?themeid=4096 （4.60 MB zip）
- 作者官网：https://d00k.net/design/themify/
- GitHub：https://github.com/Ardakilic/themify （releases 里有 CJK 字体包）

下载后解压到 iPod 数据盘的根目录，它是 `.rockbox/` 结构，直接合并覆盖。

## 想用别的主题

https://themes.rockbox.org/?target=ipod6g 是 iPod Classic 的全部主题。

挑选时注意：

1. **屏幕尺寸必须是 320×240**
2. 标注「Requires Rockbox font pack」的，先装字体包（Rockbox Utility 勾 Fonts）
3. 主题是否自带 CJK 字体。没有的话，本仓库脚本会自动检测并替换字形成中文

## 没有主题也能刷

`ipod-setup.ps1` 找不到主题 zip 时会跳过主题步骤，只装系统 + 中文化。之后你随时可以把主题解压进去，重启生效。
