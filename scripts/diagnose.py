# -*- coding: utf-8 -*-
"""
iPod Classic / Rockbox 状态诊断（只读，不改任何文件）

用法:
    python diagnose.py            # 自动扫描
    python diagnose.py H:/        # 指定数据盘根目录

输出六块：盘符判定 / Rockbox 安装 / 中文字体 / 主题与字体引用 / 媒体库 / 原厂残留
"""
import os
import re
import sys
import glob
import string
import ctypes

CJK_TIER1 = re.compile(r'CJK')
CJK_TIER2 = re.compile(r'SourceHan')
CJK_TIER3 = re.compile(r'Unifont|WenQangYi|WenQuanYi|Sazanami|Mincho|Song')


def all_drives():
    """列出所有存在的盘符，返回 [(letter, root, type_name, size_gb, fs, label)]"""
    out = []
    try:
        mask = ctypes.windll.kernel32.GetLogicalDrives()
    except Exception:
        mask = 0
    type_names = {0: '未知', 1: '无效', 2: '可移动', 3: '本地磁盘', 4: '网络', 5: '光驱', 6: '内存盘'}
    for i, letter in enumerate(string.ascii_uppercase):
        if not (mask & (1 << i)):
            continue
        root = '%s:\\' % letter
        try:
            dt = ctypes.windll.kernel32.GetDriveTypeW(ctypes.c_wchar_p(root))
        except Exception:
            dt = 0
        if dt not in (2, 3, 6):
            continue
        free = total = 0
        label = ''
        fs = ''
        try:
            free_b, total_b, _ = ctypes.c_ulonglong(0), ctypes.c_ulonglong(0), ctypes.c_ulonglong(0)
            ctypes.windll.kernel32.GetDiskFreeSpaceExW(
                ctypes.c_wchar_p(root), ctypes.byref(free_b), ctypes.byref(total_b), None)
            total = total_b.value
        except Exception:
            pass
        try:
            vol = ctypes.create_unicode_buffer(261)
            fsb = ctypes.create_unicode_buffer(261)
            ctypes.windll.kernel32.GetVolumeInformationW(
                ctypes.c_wchar_p(root), vol, 261, None, None, None, fsb, 261)
            label, fs = vol.value, fsb.value
        except Exception:
            pass
        out.append((letter, root, type_names.get(dt, str(dt)), total / 1073741824.0, fs, label))
    return out


def classify(root):
    """判断这个盘是不是 iPod 数据分区"""
    has_ctl = os.path.isdir(os.path.join(root, 'iPod_Control'))
    has_rb = os.path.isdir(os.path.join(root, '.rockbox'))
    try:
        size = 0
        f = ctypes.c_ulonglong(0)
        ctypes.windll.kernel32.GetDiskFreeSpaceExW(ctypes.c_wchar_p(root), None, ctypes.byref(f), None)
        size = f.value / 1073741824.0
    except Exception:
        pass
    return has_ctl, has_rb, size


def rank_cjk_fonts(font_dir):
    """按 (可靠度, 字号) 排序候选中文字体"""
    cands = []
    if not os.path.isdir(font_dir):
        return cands
    for name in os.listdir(font_dir):
        if not name.lower().endswith('.fnt'):
            continue
        m = re.match(r'^(\d+)', name)
        px = int(m.group(1)) if m else 0
        if CJK_TIER1.search(name):
            tier = 1
        elif CJK_TIER2.search(name):
            tier = 2
        elif CJK_TIER3.search(name):
            tier = 3
        else:
            continue
        try:
            kb = os.path.getsize(os.path.join(font_dir, name)) // 1024
        except OSError:
            kb = 0
        cands.append({'name': name, 'tier': tier, 'px': px, 'kb': kb})
    cands.sort(key=lambda x: (x['tier'], -x['px']))
    return cands


def theme_font_refs(rbdir, cfg_path):
    """从主题 cfg → wps/sbs → 抓 %Fl(编号, 文件名)"""
    refs = []
    if not os.path.isfile(cfg_path):
        return refs, None, None
    wps = sbs = None
    try:
        lines = open(cfg_path, encoding='utf-8', errors='replace').read().splitlines()
    except Exception:
        return refs, None, None
    for ln in lines:
        m = re.match(r'^\s*font\s*:\s*(.+)$', ln)
        if m:
            refs.append(os.path.basename(m.group(1).strip()))
        m = re.match(r'^\s*wps\s*:\s*(.+)$', ln)
        if m:
            wps = m.group(1).strip()
        m = re.match(r'^\s*sbs\s*:\s*(.+)$', ln)
        if m:
            sbs = m.group(1).strip()
    for skin in (wps, sbs):
        if not skin:
            continue
        rel = skin.replace('/.rockbox/', '').replace('/', os.sep)
        p = os.path.join(rbdir, rel)
        if not os.path.isfile(p):
            continue
        try:
            txt = open(p, encoding='utf-8', errors='replace').read()
        except Exception:
            continue
        for m in re.finditer(r'%Fl\(\s*\d+\s*,\s*([^,\)]+)\s*[,\)]', txt):
            n = m.group(1).strip()
            if n.lower().endswith('.fnt') and n not in refs:
                refs.append(n)
    # 去重保序
    seen, out = set(), []
    for r in refs:
        if r not in seen:
            seen.add(r)
            out.append(r)
    return out, wps, sbs


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else None

    print('=' * 62)
    print(' iPod / Rockbox 诊断')
    print('=' * 62)

    # ---------- 1. 盘符 ----------
    print('\n[1] 磁盘扫描')
    drives = all_drives()
    ipod_root = None
    for letter, r, tname, gb, fs, label in drives:
        has_ctl, has_rb, _ = classify(r)
        mark = ''
        if has_ctl or has_rb:
            mark = '  <== iPod' + (' (已装 Rockbox)' if has_rb else ' (原厂系统)')
        print('    %-3s %-14s %7.1f GB  %-8s %-10s%s' % (letter + ':', label[:14], gb, fs, tname, mark))
        if (has_ctl or has_rb) and gb > 10:
            ipod_root = root or r

    if root:
        ipod_root = root
    if not ipod_root:
        print('\n    !! 没有找到 iPod 数据分区（需要 >10GB 且含 iPod_Control 或 .rockbox）')
        print('       检查：数据线能不能传数据、iPod 是否开机、换机箱后置 USB 口')
        return 1

    rbdir = os.path.join(ipod_root, '.rockbox')
    fontdir = os.path.join(rbdir, 'fonts')
    themedir = os.path.join(rbdir, 'themes')
    print('\n    数据盘: %s' % ipod_root)

    # ---------- 2. Rockbox 安装状态 ----------
    print('\n[2] Rockbox 安装状态')
    fw = os.path.join(rbdir, 'rockbox.ipod')
    cfg = os.path.join(rbdir, 'config.cfg')
    print('    .rockbox 目录      %s' % ('有' if os.path.isdir(rbdir) else '无'))
    print('    rockbox.ipod       %s' % ('有 (%d KB)' % (os.path.getsize(fw) // 1024) if os.path.isfile(fw) else '无  <== 系统文件不完整'))
    if os.path.isfile(cfg):
        txt = open(cfg, encoding='utf-8', errors='replace').read()
        for key in ('lang', 'font', 'wps', 'sbs', 'default codepage'):
            m = re.search(r'^\s*%s\s*:\s*(.+)$' % key, txt, re.M)
            if m:
                print('    %-18s %s' % (key + ':', m.group(1).strip()))
        baks = glob.glob(cfg + '*')
        if baks:
            print('    配置备份           %s' % ', '.join(os.path.basename(b) for b in baks))
    else:
        print('    config.cfg         无')

    # ---------- 3. 中文字体 ----------
    print('\n[3] 中文字体候选（按 可靠度 → 字号 排序）')
    cands = rank_cjk_fonts(fontdir)
    if not cands:
        print('    !! 没有任何中文字体')
        print('       补法：Rockbox Utility 只勾 Fonts 装一次，或把 fonts.zip 解压进 .rockbox\\fonts')
    else:
        for c in cands[:8]:
            star = '  <== 会被选中' if c is cands[0] else ''
            print('    %-34s %2dpx  %5d KB  (tier %d)%s' % (c['name'], c['px'], c['kb'], c['tier'], star))
        if cands[0]['px'] < 16:
            print('    注意：最大的中文只有 %dpx，主题文字会明显变小' % cands[0]['px'])

    # ---------- 4. 主题与字体引用 ----------
    print('\n[4] 主题与字体引用')
    if os.path.isdir(themedir):
        cfgs = [f for f in os.listdir(themedir) if f.endswith('.cfg')
                and f not in ('rockbox_default_icons.cfg', 'rockbox_failsafe.cfg')]
        print('    可用主题           %s' % (', '.join(cfgs) if cfgs else '无'))
    else:
        print('    可用主题           无 themes 目录')

    cur_wps = None
    if os.path.isfile(cfg):
        m = re.search(r'^\s*wps\s*:\s*(.+)$', open(cfg, encoding='utf-8', errors='replace').read(), re.M)
        if m:
            cur_wps = os.path.basename(m.group(1).strip())
    print('    当前皮肤           %s' % (cur_wps or '未知'))

    if cur_wps:
        refs, w, s = theme_font_refs(rbdir, cfg)
        if refs:
            print('    当前主题引用的字体：')
            for r in refs:
                p = os.path.join(fontdir, r)
                if not os.path.isfile(p):
                    print('      %-34s 缺失  <== 会退回内置字体' % r)
                    continue
                kb = os.path.getsize(p) // 1024
                # 判断是不是被换成了中文（体积接近某个 CJK 字体）
                swapped = ''
                if cands:
                    src = cands[0]
                    if abs(kb - src['kb']) < 40 and r != src['name']:
                        swapped = '  <== 已是中文字形（来自 %s）' % src['name']
                print('      %-34s %5d KB%s' % (r, kb, swapped))

    # ---------- 5. 媒体库 ----------
    print('\n[5] Rockbox 媒体库')
    db = glob.glob(os.path.join(rbdir, 'database_*.tcd'))
    idx = os.path.join(rbdir, 'database_idx.tcd')
    music_dir = os.path.join(ipod_root, 'Music')
    n_music = 0
    if os.path.isdir(music_dir):
        for r, _, fs in os.walk(music_dir):
            n_music += sum(1 for f in fs if f.lower().endswith(('.mp3', '.flac', '.m4a', '.ogg', '.opus', '.wav', '.ape', '.aac')))
    print('    数据库文件         %d 个%s' % (len(db), '' if os.path.isfile(idx) else '  <== 没有索引，需要 Initialize'))
    print('    Music 目录音频     %d 个' % n_music)
    if db and n_music and len(db) < 3:
        print('    提示：音频很多但数据库很小，可能没扫全 → 设置 → Database → Initialize Now')

    # ---------- 6. 原厂残留 ----------
    print('\n[6] 原厂系统残留')
    ctl = os.path.join(ipod_root, 'iPod_Control')
    if os.path.isdir(ctl):
        legacy = 0
        mdir = os.path.join(ctl, 'Music')
        if os.path.isdir(mdir):
            for r, _, fs in os.walk(mdir):
                legacy += len(fs)
        idb = os.path.join(ctl, 'iTunes', 'iTunesDB')
        n_rec = 0
        if os.path.isfile(idb):
            data = open(idb, 'rb').read()
            n_rec = data.count(b'mhit')
        art = 0
        for p in glob.glob(os.path.join(ctl, 'Artwork', '*')):
            if os.path.isfile(p):
                art += os.path.getsize(p)
        print('    iPod_Control\\Music 余留文件  %d 个' % legacy)
        print('    iTunesDB 曲目记录            %d 条%s' % (n_rec, '' if n_rec else '（已清空）'))
        print('    Artwork 缓存                 %.1f MB' % (art / 1048576.0))
        if legacy and n_rec:
            print('    !! 有文件也有索引：原厂固件能播，但 Rockbox 媒体库会重复收录')
        elif legacy and not n_rec:
            print('    文件在但索引已清：原厂看不到，Rockbox 靠文件系统仍能访问')
        elif n_rec and not legacy:
            print('    !! 索引还在但文件没了：切回原厂会看到 %d 首幽灵条目' % n_rec)
        dev = os.path.join(ctl, 'Device')
        if os.path.isdir(dev):
            print('    Device\\ 存在              是（%d 个文件，千万别删）' % len(os.listdir(dev)))

    # ---------- 结论 ----------
    print('\n' + '=' * 62)
    todo = []
    if not os.path.isfile(fw):
        todo.append('系统文件不完整 → 解压 rockbox-ipod6g.zip 到数据盘根目录')
    if not cands:
        todo.append('没有中文字体 → 装字体包后重跑')
    if cur_wps and 'CJK' not in (cur_wps or '') and cands:
        pass
    if os.path.isdir(ctl) and os.path.isfile(os.path.join(ctl, 'iTunes', 'iTunesDB')):
        todo.append('原厂索引还在 → 如长期用 Rockbox，可清 iTunesDB/iTunesControl/Artwork')
    if todo:
        print(' 待办：')
        for t in todo:
            print('   - %s' % t)
    else:
        print(' 没发现明显问题')
    print('=' * 62)
    return 0


if __name__ == '__main__':
    sys.exit(main())
