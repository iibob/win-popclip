#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
CoordMode "Mouse", "Screen"
SetWorkingDir A_ScriptDir

; ============================================================
;  WinPopClip —— Windows 版 PopClip
;  配置文件: 同目录 WinPopClip_config.ini (首次运行自动生成)
; ============================================================


; 版本号常量
APP_VERSION := "1.2.0"

; ---------- 全局状态 ----------
CFG := A_ScriptDir "\WinPopClip_config.ini"
IniData := Map()           ; 自解析的 ini 数据
Conf := Map()              ; 配置缓存
ProcSet := Map()           ; 进程过滤集合(小写进程名)
InsertSet := Map()         ; 需用 Ctrl+Insert 复制的进程(终端类)
CtrlDownTick := 0          ; Ctrl 按下的时刻(0=未按下)
CtrlExSet := Map()         ; 单击 Ctrl 不生效的进程集合(小写进程名)
SearchLabel := Map("Baidu", "百度搜索", "Google", "谷歌搜索", "Bing", "必应搜索", "Translate", "谷歌翻译", "BaiduTranslate", "百度翻译")
IsWin11 := VerCompare(A_OSVersion, "10.0.22000") >= 0   ;  Win11 支持系统原生圆角

Enabled := true
Busy := false              ; 正在取词
MenuGui := ""              ; 当前菜单窗口
MenuBtns := []             ; 菜单按钮控件
MenuActions := []          ; 对应动作
HoverIdx := 0              ; 当前悬停的菜单按钮索引（0=未悬停）
LastActive := 0            ; 最近一次"操作菜单"的时间
OriginHwnd := 0            ; 菜单弹出时的活动窗口
KbHook := ""               ; 键盘监听(按键即关闭菜单)
SelText := ""              ; 选中文本
SelClip := ""              ; 选区剪贴板内容(含格式)

DownX := 0, DownY := 0, DownOnMenu := false, DownSerial := 0
ClickCount := 0, LastUpTick := 0, LastUpX := 0, LastUpY := 0
PendX := 0, PendY := 0     ; 自动模式下菜单弹出位置

; ---------- 初始化 ----------
LoadConfig()
SetupTray()
if (Conf["ManualHotkey"] != "") {
    try Hotkey(Conf["ManualHotkey"], (*) => ManualTrigger(false))   ; 包一层, 避免热键名被当成参数
    catch
        MsgBox("手动快捷键无效: " Conf["ManualHotkey"] "`n请检查 WinPopClip_config.ini 中的 ManualHotkey", "WinPopClip", "Icon!")
}


; ============================================================
;  配置
; ============================================================

; 读取配置文件并加载到运行时缓存
LoadConfig() {
    if !FileExist(CFG)
        FileAppend(DefaultConfig(), CFG, "UTF-8-RAW")   ; UTF-8 无 BOM，避免文件略大、部分软件无法打开
    LoadIni()

    Conf["AutoPopup"]     := RInt("General", "AutoPopup", 1)
    Conf["ManualHotkey"]  := Trim(IniGet("General", "ManualHotkey", "F1"))
    Conf["CtrlTap"]       := RInt("General", "CtrlTap", 1)
    Conf["CtrlTapMaxMs"]  := RInt("General", "CtrlTapMaxMs", 300)
    Conf["DragThreshold"] := RInt("General", "DragThreshold", 8)
    Conf["ExtractDelay"]  := RInt("General", "ExtractDelay", 80)
    Conf["HideSeconds"]   := RInt("General", "HideSeconds", 5)
    Conf["IBeamCheck"]    := RInt("General", "IBeamCheck", 1)
    Conf["SearchMaxLen"]  := RInt("General", "SearchMaxLen", 100)
    Conf["RoundCorner"]   := RInt("General", "RoundCorner", 1)
    Conf["ProcessMode"]   := StrLower(Trim(IniGet("General", "ProcessMode", "blacklist")))

    Conf["MenuOrder"] := IniGet("Menu", "Order", "Copy|Cut|Paste|OpenUrl|OpenFolder|OpenFile|MailTo|Baidu|Google|BaiduTranslate|Translate")

    Conf["FontName"]  := IniGet("Style", "FontName", "Microsoft YaHei UI")
    Conf["FontSize"]  := RInt("Style", "FontSize", 10)
    Conf["BtnHeight"] := RInt("Style", "ButtonHeight", 32)
    Conf["BtnPad"]    := RInt("Style", "ButtonPadding", 14)
    Conf["ColBg"]     := IniGet("Style", "ColBg", "2B2B2B")
    Conf["ColHover"]  := IniGet("Style", "ColHover", "4A4A4A")
    Conf["ColText"]   := IniGet("Style", "ColText", "FFFFFF")
    Conf["ColBorder"] := IniGet("Style", "ColBorder", "555555")

    ; 搜索/翻译 URL 模板 (占位符: {q} 文本, {tl} 谷歌翻译目标语言)
    Conf["Url_Baidu"]          := IniGet("Search", "Baidu", "https://www.baidu.com/s?wd={q}")
    Conf["Url_Google"]         := IniGet("Search", "Google", "https://www.google.com/search?q={q}")
    Conf["Url_Bing"]           := IniGet("Search", "Bing", "https://www.bing.com/search?q={q}")
    Conf["Url_Translate"]      := IniGet("Search", "Translate", "https://translate.google.com/?sl=auto&tl={tl}&text={q}&op=translate")
    Conf["Url_BaiduTranslate"] := IniGet("Search", "BaiduTranslate", "https://fanyi.baidu.com/mtpe-individual/transText?query={q}")   ; 不传 lang, 百度能自动识别

    for p in StrSplit(IniGet("Process", "List", ""), "|") {
        p := Trim(p)
        if (p != "")
            ProcSet[StrLower(p)] := true
    }
    for p in StrSplit(IniGet("CopyInsert", "List", ""), "|") {
        p := Trim(p)
        if (p != "")
            InsertSet[StrLower(p)] := true
    }
    for p in StrSplit(IniGet("CtrlTapExclude", "List", ""), "|") {
        p := Trim(p)
        if (p != "")
            CtrlExSet[StrLower(p)] := true
    }
}

; 自写 ini 解析器 —— 按 UTF-8 读取, 值里可以放中文
LoadIni() {
    global IniData
    IniData := Map()
    sec := ""
    for line in StrSplit(FileRead(CFG, "UTF-8"), "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
            continue    ; 空行/注释
        if RegExMatch(line, "^\[(.+)\]$", &m) {
            sec := StrLower(Trim(m[1]))
            if !IniData.Has(sec)
                IniData[sec] := Map()
        } else if (sec != "" && (p := InStr(line, "="))) {
            IniData[sec][StrLower(Trim(SubStr(line, 1, p - 1)))] := Trim(SubStr(line, p + 1))
        }
    }
}

; 从 IniData 读取，段名/键名不区分大小写，找不到返回默认值
IniGet(sec, key, def := "") {
    s := StrLower(sec), k := StrLower(key)
    return (IniData.Has(s) && IniData[s].Has(k)) ? IniData[s][k] : def
}

; 读取整数配置项，无效时返回默认值
RInt(sec, key, def) {
    v := IniGet(sec, key, def)
    return IsInteger(v) ? Integer(v) : def
}

; 生成默认配置文件内容
DefaultConfig() {
    txt := "
(
; WinPopClip 配置文件 (修改后双击托盘图标重载生效)
; 注意: 值的后面不要写行内注释; 注释中避免使用英文双引号

[General]
; 自动弹出: 1=开启 0=关闭
AutoPopup=1

; 手动快捷键 (AHK 格式: ! = Alt, ^ = Ctrl, + = Shift, # = Win), 留空=不使用
; 不建议使用带 Alt 的组合: 记事本等带菜单栏的程序里 Alt 会触发菜单栏, 导致取词失败
ManualHotkey=F1

; 单击 Ctrl 弹出菜单: 1=开 0=关
; 只有按下期间没按其他键、且按住不超过 CtrlTapMaxMs 毫秒才算单击; 菜单显示时再单击一次会关闭菜单
CtrlTap=1
CtrlTapMaxMs=300

; 鼠标拖动超过多少像素才视为「选择文本」
DragThreshold=8

; 鼠标松开后延迟多少毫秒再取词
ExtractDelay=80

; 菜单无操作多少秒后自动隐藏 (鼠标停在菜单上不计时, 0=不自动隐藏)
HideSeconds=4

; 自动弹出时仅当鼠标是 I 型光标才触发 (减少误触): 1=开 0=关
IBeamCheck=1

; 搜索/翻译文本的最大长度
SearchMaxLen=100

; 菜单圆角: 1=圆角 (Win11 使用系统原生圆角, Win10 使用裁剪圆角) 0=无圆角
RoundCorner=1

; 进程过滤模式:
;   blacklist = [Process] 列表内的程序不自动弹出
;   whitelist = 仅 [Process] 列表内的程序自动弹出
; 手动快捷键不受此限制; 单击 Ctrl 使用下面的 [CtrlTapExclude] 列表
ProcessMode=blacklist

[Process]
; 进程名用 | 分隔
List=WindowsTerminal.exe|cmd.exe|powershell.exe|pwsh.exe|conhost.exe|mintty.exe|explorer.exe|EXCEL.EXE|mstsc.exe|vmware.exe|vmware-vmx.exe|VirtualBoxVM.exe|KeePass.exe|KeePassXC.exe|1Password.exe|Bitwarden.exe

[CopyInsert]
; 这些进程取词时用 Ctrl+Insert 代替 Ctrl+C (终端里 Ctrl+C 是中断信号)
List=WindowsTerminal.exe|cmd.exe|powershell.exe|pwsh.exe|conhost.exe|mintty.exe|ConEmu64.exe|putty.exe

[CtrlTapExclude]
; 这些进程里单击 Ctrl 不弹出菜单 (虚拟机/远程桌面里的 Ctrl 常有特殊用途), 进程名用 | 分隔
List=mstsc.exe|vmware.exe|vmware-vmx.exe|vmplayer.exe|VirtualBoxVM.exe

[Menu]
; 菜单项及顺序, 删掉某项即隐藏. 可用项:
; Copy Cut Paste OpenUrl OpenFolder OpenFile MailTo Baidu Google Bing BaiduTranslate Translate
Order=Copy|Cut|Paste|OpenUrl|OpenFolder|OpenFile|MailTo|Baidu|Google|BaiduTranslate

[Search]
; {q}  = UTF-8 编码后的选中文本
; {tl} = 谷歌翻译目标语言 (含汉字 -> en, 否则 -> zh-CN)
Baidu=https://www.baidu.com/s?wd={q}
Google=https://www.google.com/search?q={q}
Bing=https://www.bing.com/search?q={q}
Translate=https://translate.google.com/?sl=auto&tl={tl}&text={q}&op=translate
BaiduTranslate=https://fanyi.baidu.com/mtpe-individual/transText?query={q}

[Style]
FontName=Microsoft YaHei UI
FontSize=10
ButtonHeight=32
ButtonPadding=14
ColBg=2B2B2B
ColHover=4A4A4A
ColText=FFFFFF
ColBorder=555555
)"
    return StrReplace(txt, "`n", "`r`n")
}


; ============================================================
;  托盘菜单
; ============================================================

; 初始化系统托盘菜单及状态
SetupTray() {
    A_IconTip := "WinPopClip v" APP_VERSION
    A_TrayMenu.Delete()
    A_TrayMenu.Add("启用", ToggleEnabled)
    A_TrayMenu.Add("自动弹出", ToggleAuto)
    A_TrayMenu.Add()
    A_TrayMenu.Add("编辑配置", (*) => Run('notepad.exe "' CFG '"'))
    A_TrayMenu.Add("重新加载", (*) => Reload())
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出", (*) => ExitApp())
    A_TrayMenu.Default := "重新加载"
    A_TrayMenu.Check("启用")
    if Conf["AutoPopup"]
        A_TrayMenu.Check("自动弹出")
}

; 切换脚本总开关
ToggleEnabled(*) {
    global Enabled
    Enabled := !Enabled
    A_TrayMenu.ToggleCheck("启用")
    if !Enabled
        HideMenu()
}

; 切换自动弹出开关（仅当前运行有效）
ToggleAuto(*) {
    Conf["AutoPopup"] := !Conf["AutoPopup"]   ; 仅本次运行有效, 永久修改需改 WinPopClip_config.ini
    A_TrayMenu.ToggleCheck("自动弹出")
}


; ============================================================
;  触发: 鼠标(自动模式) / 快捷键(手动模式)
; ============================================================

; 记录鼠标按下位置并处理菜单外点击
OnLDown() {
    global DownX, DownY, DownOnMenu, DownSerial
    MouseGetPos(&x, &y, &hw)
    DownSerial++                       ; 用于作废进行中的取词
    SetTimer(AutoExtract, 0)           ; 取消尚未执行的取词(连击时防抖)
    DownOnMenu := IsObject(MenuGui) && (hw = MenuGui.Hwnd)
    if (IsObject(MenuGui) && !DownOnMenu)
        HideMenu()                     ; 点击菜单外部 -> 关闭
    DownX := x, DownY := y
}

; 判断鼠标操作是否满足自动取词条件
OnLUp() {
    global ClickCount, LastUpTick, LastUpX, LastUpY, PendX, PendY
    if (DownOnMenu || !Enabled || !Conf["AutoPopup"])
        return
    MouseGetPos(&x, &y, &hw)

    ; 连击计数 (双击/三击选词选行)
    if (A_TickCount - LastUpTick <= DllCall("GetDoubleClickTime") && Abs(x - LastUpX) <= 4 && Abs(y - LastUpY) <= 4)
        ClickCount++
    else
        ClickCount := 1
    LastUpTick := A_TickCount, LastUpX := x, LastUpY := y

    ; 带 Ctrl/Alt/Win 的点击一般不是选文本
    if (GetKeyState("Ctrl") || GetKeyState("Alt") || GetKeyState("LWin") || GetKeyState("RWin"))
        return

    ; 触发条件: 拖动 / 双击三击 / Shift+点击
    dragged := Sqrt((x - DownX) ** 2 + (y - DownY) ** 2) >= Conf["DragThreshold"]
    if !(dragged || ClickCount >= 2 || GetKeyState("Shift"))
        return

    ; 光标必须是 I 型 (可关闭)
    if (Conf["IBeamCheck"] && A_Cursor != "IBeam")
        return

    ; 排除标题栏/边框/滚动条等非客户区
    if !HitClient(x, y, hw)
        return

    ; 进程过滤 (仅自动模式)
    proc := ""
    try proc := WinGetProcessName("ahk_id " hw)
    if !ProcAllowedAuto(proc)
        return

    PendX := x, PendY := y
    SetTimer(AutoExtract, -Conf["ExtractDelay"])   ; 延迟取词, 等应用更新选区
}

; 延迟读取选中文本并显示菜单
AutoExtract() {
    global Busy
    if Busy
        return
    Busy := true
    serial := DownSerial
    try {
        if !GrabSelection(&text, &clip)
            return
        if (serial != DownSerial)      ; 取词期间用户又点了鼠标 -> 作废
            return
        ShowMenu(text, clip, PendX, PendY)
    } finally {
        Busy := false
    }
}

; silent=true 时没选中文本不提示 (单击 Ctrl 误触发较多)
ManualTrigger(silent := false) {
    global Busy
    if (!Enabled || Busy)
        return
    Busy := true
    try {
        HideMenu()
        ; 等修饰键松开, 否则发出去的 Ctrl+C 会变成 Ctrl+Alt+C 之类
        for k in ["Alt", "Shift", "Ctrl", "LWin", "RWin"]
            KeyWait(k, "T1")
        MouseGetPos(&x, &y)
        if !GrabSelection(&text, &clip) {
            if !silent
                Toast("未检测到选中文本")
            return
        }
        ShowMenu(text, clip, x, y)
    } finally {
        Busy := false
    }
}

; 根据黑白名单配置判断进程是否允许自动弹出
ProcAllowedAuto(proc) {
    inList := ProcSet.Has(StrLower(proc))
    return (Conf["ProcessMode"] = "whitelist") ? inList : !inList
}

; 用 WM_NCHITTEST 判断鼠标是否在窗口客户区(排除标题栏、边框、滚动条等)
HitClient(x, y, hwnd) {
    res := 0
    lParam := ((y & 0xFFFF) << 16) | (x & 0xFFFF)
    ok := DllCall("SendMessageTimeoutW", "Ptr", hwnd, "UInt", 0x84, "Ptr", 0, "Ptr", lParam
        , "UInt", 2, "UInt", 100, "Ptr*", &res)
    if !ok
        return true                    ; 窗口无响应时不拦截
    return !(res >= 2 && res <= 21)    ; HTCAPTION(2) ~ HTHELP(21) 视为非客户区
}


; ============================================================
;  取词: 模拟复制 -> 读剪贴板 -> 恢复原剪贴板
; ============================================================

; 通过模拟复制获取选中文本并恢复原剪贴板
GrabSelection(&text, &selClip) {
    text := "", selClip := ""
    proc := ""
    try proc := WinGetProcessName("A")
    saved := ClipboardAll()            ; 备份用户原剪贴板
    try {
        A_Clipboard := ""
        shiftDown := GetKeyState("Shift")
        if shiftDown
            Send("{Shift up}")         ; 避免 Ctrl+Shift+C (浏览器会打开开发者工具)
        Send(InsertSet.Has(StrLower(proc)) ? "^{Insert}" : "^c")
        if (shiftDown && GetKeyState("Shift", "P"))
            Send("{Shift down}")       ; 物理上仍按着 Shift 则还原
        if ClipWait(0.5) {
            text := A_Clipboard
            selClip := ClipboardAll()  ; 保留选区内容(含格式), 供"复制"菜单使用
        }
    } finally {
        A_Clipboard := saved           ; 无论成败都恢复用户原剪贴板
    }
    return (Trim(text, " `t`r`n") != "")
}


; ============================================================
;  菜单构建 / 显示 / 隐藏
; ============================================================

; 根据选中文本和菜单配置生成菜单项
BuildItems(text) {
    t := Trim(text, " `t`r`n")
    url := ExtractUrl(t)
    path := ParsePath(t)
    isMail := RegExMatch(t, "^[\w.+-]+@[\w-]+(\.[\w-]+)+$")
    q := SubStr(RegExReplace(t, "\s+", " "), 1, Conf["SearchMaxLen"])

    ; 含汉字 -> 译成英文, 否则译成中文 (仅谷歌翻译使用)
    isZh := RegExMatch(t, "[\x{4E00}-\x{9FFF}]")
    tl := isZh ? "en" : "zh-CN"

    items := []                        ; 每项: [显示文字, 动作函数]
    for k in StrSplit(Conf["MenuOrder"], "|") {
        k := Trim(k)
        if (k = "Copy")
            items.Push(["复制", Act_Copy])
        else if (k = "Cut")
            items.Push(["剪切", Act_Cut])
        else if (k = "Paste")
            items.Push(["粘贴", Act_Paste])
        else if (k = "OpenUrl" && url != "")
            items.Push(["打开链接", Act_OpenUrl.Bind(url)])
        else if (k = "OpenFolder" && path != "")
            items.Push(["打开文件夹", Act_OpenFolder.Bind(path)])
        else if (k = "OpenFile" && path != "" && !InStr(FileExist(path), "D"))
            items.Push(["打开文件", Act_OpenFile.Bind(path)])
        else if (k = "MailTo" && isMail)
            items.Push(["发送邮件", Act_MailTo.Bind(t)])
        else if (SearchLabel.Has(k) && Conf.Has("Url_" k))
            items.Push([SearchLabel[k], Act_Search.Bind(Conf["Url_" k], q, tl)])
    }
    return items
}

; 创建并显示悬浮操作菜单
ShowMenu(text, clip, x, y) {
    global MenuGui, MenuBtns, MenuActions, HoverIdx, LastActive, OriginHwnd, SelText, SelClip, KbHook
    HideMenu()
    SelText := text, SelClip := clip
    items := BuildItems(text)
    if (items.Length = 0)
        return

    scale := A_ScreenDPI / 96          ; 手动处理 DPI (Gui 使用 -DPIScale, 坐标与屏幕坐标一致)
    padX := Round(Conf["BtnPad"] * scale)
    btnH := Round(Conf["BtnHeight"] * scale)

    ; NOACTIVATE: 点击菜单不抢焦点, 否则剪切/粘贴会作用到错误窗口
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 -DPIScale", "WinPopClipMenu")
    g.BackColor := Conf["ColBorder"]   ; 背景色即 1px 边框色
    g.MarginX := 0, g.MarginY := 0
    g.SetFont("s" Conf["FontSize"] " c" Conf["ColText"], Conf["FontName"])

    ; Win11 在显示前设置系统圆角(抗锯齿); RoundCorner=0 时明确要求不圆角
    if IsWin11
        SetDwmCorner(g.Hwnd, Conf["RoundCorner"] ? 2 : 1)

    btns := [], acts := []
    cx := 1
    for i, it in items {
        c := g.AddText("x" cx " y1 h" btnH " Center +0x200 +0x100 Background" Conf["ColBg"], it[1])
        c.GetPos(, , &cw)              ; 未指定宽度时自动适应文字宽度
        c.Move(cx, 1, cw + padX * 2)   ; 左右加内边距
        c.GetPos(&px, , &pw)
        cx := px + pw
        c.OnEvent("Click", OnBtnClick.Bind(i))
        btns.Push(c), acts.Push(it[2])
    }
    w := cx + 1
    h := btnH + 2

    ; 定位: 鼠标上方居中, 上方放不下则放下方; 限制在当前显示器工作区内
    GetWorkArea(x, y, &wl, &wt, &wr, &wb)
    px := x - w // 2
    py := y - h - Round(22 * scale)
    if (py < wt)
        py := y + Round(26 * scale)
    px := Max(wl + 4, Min(px, wr - w - 4))
    py := Max(wt + 4, Min(py, wb - h - 4))

    g.Show("NoActivate x" px " y" py " w" w " h" h)

    ; 仅 Win10 (或更早) 且开启圆角时, 才用裁剪区域做圆角 (有锯齿但兼容)
    if (Conf["RoundCorner"] && !IsWin11) {
        r := Round(3 * scale)
        WinSetRegion("0-0 W" w " H" h " R" r "-" r, "ahk_id " g.Hwnd)   ; 圆角
    }

    MenuGui := g, MenuBtns := btns, MenuActions := acts
    HoverIdx := 0
    LastActive := A_TickCount
    OriginHwnd := WinExist("A")

    ; 任意按键(含 Esc)关闭菜单; V=按键仍传给应用, I=忽略脚本自己发出的按键
    KbHook := InputHook("V I")
    KbHook.KeyOpt("{All}", "N")
    KbHook.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-N")  ; 单独按修饰键不关闭
    KbHook.OnKeyDown := (*) => SetTimer(HideMenu, -1)
    KbHook.Start()

    SetTimer(MenuTick, 80)
}

; Win11 系统原生圆角. pref: 1=不圆角 2=圆角; 同时让系统边框色与菜单边框色一致
SetDwmCorner(hwnd, pref) {
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 33, "Int*", pref, "UInt", 4)
    if (pref = 2) {
        try {
            rgb := Integer("0x" Conf["ColBorder"])
            bgr := ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 34, "UInt*", bgr, "UInt", 4)
        }
    }
}

; 停止菜单相关监听并销毁菜单窗口
HideMenu() {
    global MenuGui, MenuBtns, MenuActions, KbHook, HoverIdx
    SetTimer(MenuTick, 0)
    if IsObject(KbHook) {
        try KbHook.Stop()
        KbHook := ""
    }
    if IsObject(MenuGui) {
        try MenuGui.Destroy()
        MenuGui := ""
    }
    MenuBtns := [], MenuActions := [], HoverIdx := 0
}

; 关闭菜单并执行对应按钮动作
OnBtnClick(i, *) {
    if (i > MenuActions.Length)
        return
    act := MenuActions[i]
    HideMenu()                         ; 先关菜单再执行, 焦点仍在原窗口
    act()
}

; 定时器: 悬停高亮 / 自动隐藏 / 窗口切换时关闭
MenuTick() {
    global HoverIdx, LastActive
    if !IsObject(MenuGui) {
        SetTimer(MenuTick, 0)
        return
    }
    if (WinExist("A") != OriginHwnd) { ; 活动窗口变了
        HideMenu()
        return
    }
    MouseGetPos(, , &hw, &hc, 2)       ; 2 = 返回控件的 HWND
    idx := 0
    if (hw = MenuGui.Hwnd) {
        LastActive := A_TickCount      ; 鼠标在菜单上 -> 重置计时
        for i, c in MenuBtns {
            if (c.Hwnd = hc) {
                idx := i
                break
            }
        }
    }
    if (idx != HoverIdx) {
        if (HoverIdx >= 1 && HoverIdx <= MenuBtns.Length) {
            MenuBtns[HoverIdx].Opt("Background" Conf["ColBg"])
            MenuBtns[HoverIdx].Redraw()
        }
        if (idx >= 1) {
            MenuBtns[idx].Opt("Background" Conf["ColHover"])
            MenuBtns[idx].Redraw()
        }
        HoverIdx := idx
    }
    if (Conf["HideSeconds"] > 0 && A_TickCount - LastActive > Conf["HideSeconds"] * 1000)
        HideMenu()
}

; 获取鼠标所在显示器的可用工作区
GetWorkArea(x, y, &l, &t, &r, &b) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        if (x >= ml && x < mr && y >= mt && y < mb) {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            return
        }
    }
    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
}


; ============================================================
;  菜单动作
; ============================================================

; 将取词时保存的内容写回剪贴板
Act_Copy(*) {
    A_Clipboard := SelClip             ; 写回取词时的内容(含格式)
    Toast("已复制")
}

; 向原窗口发送剪切快捷键
Act_Cut(*) {
    Send("^x")
}

; 向原窗口发送粘贴快捷键
Act_Paste(*) {
    Send("^v")                         ; 粘贴的是用户原本的剪贴板
}

; 使用系统默认浏览器打开链接
Act_OpenUrl(url, *) {
    try Run(url)
    catch
        Toast("打开链接失败")
}

; 在资源管理器中打开文件夹或定位文件
Act_OpenFolder(path, *) {
    try {
        if InStr(FileExist(path), "D")
            Run('explorer.exe "' path '"')
        else
            Run('explorer.exe /select,"' path '"')   ; 文件: 打开所在目录并选中
    }
}

; 打开文件，执行可执行文件前进行确认
Act_OpenFile(path, *) {
    ; 可执行/脚本类文件先确认, 防止误点
    if RegExMatch(path, "i)\.(exe|bat|cmd|ps1|vbs|vbe|js|jse|wsf|msi|scr|com|lnk|reg)$") {
        if (MsgBox("即将打开/运行:`n" path "`n`n确定吗?", "WinPopClip", "YesNo Icon?") != "Yes")
            return
    }
    try Run('"' path '"')
    catch
        Toast("打开文件失败")
}

; 调用默认邮件客户端创建邮件
Act_MailTo(addr, *) {
    try Run("mailto:" addr)
}

; 替换搜索模板参数并打开对应网页
Act_Search(tpl, q, tl, *) {
    u := StrReplace(tpl, "{q}", UrlEncode(q))
    u := StrReplace(u, "{tl}", tl)
    try Run(u)
}


; ============================================================
;  工具函数
; ============================================================

; 显示短暂提示信息
Toast(msg) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -900)
}

; 识别 URL, 返回可直接打开的完整 URL, 不是 URL 返回 ""
ExtractUrl(t) {
    if (t = "" || RegExMatch(t, "\s"))
        return ""
    if RegExMatch(t, "i)^(https?|ftp)://\S+$")
        return t
    if RegExMatch(t, "i)^www\.[^\s/]+\.\S*$")
        return "https://" t
    if RegExMatch(t, "i)^(\d{1,3}\.){3}\d{1,3}(:\d+)?(/\S*)?$")
        return "http://" t
    if RegExMatch(t, "i)^([a-z0-9-]+\.)+(com|net|org|cn|io|dev|app|co|me|info|edu|gov|top|xyz|cc|tv|ai|site|tech|cloud|so|us|uk|jp|de|ru|hk|tw)(:\d+)?(/\S*)?$")
        return "https://" t
    return ""
}

; 识别存在的本地路径(盘符/UNC/带引号/file:///), 返回规范路径, 否则 ""
ParsePath(t) {
    s := Trim(t, " `t`r`n`"'")
    if (s = "" || InStr(s, "`n"))
        return ""
    if RegExMatch(s, "i)^file:///(.+)$", &m)
        s := StrReplace(StrReplace(m[1], "/", "\"), "%20", " ")
    if !RegExMatch(s, "^([A-Za-z]:\\|\\\\[^\\/]+\\)")
        return ""
    if RegExMatch(s, "[*?<>|]")        ; 含通配符/非法字符
        return ""
    return FileExist(s) ? s : ""
}

; UTF-8 URL 编码
UrlEncode(s) {
    buf := Buffer(StrPut(s, "UTF-8"))
    StrPut(s, buf, "UTF-8")
    out := ""
    Loop buf.Size - 1 {                ; 去掉末尾 \0
        b := NumGet(buf, A_Index - 1, "UChar")
        if ((b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b = 0x2D || b = 0x2E || b = 0x5F || b = 0x7E)
            out .= Chr(b)
        else
            out .= "%" Format("{:02X}", b)
    }
    return out
}


; ============================================================
; 单击 Ctrl 触发
; ============================================================

; 记录 Ctrl 首次按下的时间
CtrlDown() {
    global CtrlDownTick
    if (CtrlDownTick = 0)              ; 按住时会连续触发, 只记录第一次
        CtrlDownTick := A_TickCount
}

; 判断 Ctrl 是否为单击并触发菜单
CtrlUp() {
    global CtrlDownTick
    if (CtrlDownTick = 0)
        return
    held := A_TickCount - CtrlDownTick
    CtrlDownTick := 0
    if (!Enabled || !Conf["CtrlTap"] || held > Conf["CtrlTapMaxMs"])
        return                         ; 关闭 / 按住太久(不是单击)
    ; 按下期间按过其他键(Ctrl+C、Ctrl+点击、Ctrl+Shift 等)不算单击
    if (A_PriorKey != "LControl" && A_PriorKey != "RControl")
        return
    if (GetKeyState("LControl", "P") || GetKeyState("RControl", "P"))
        return                         ; 另一侧 Ctrl 仍按着
    if IsObject(MenuGui) {             ; 菜单已显示 -> 再单击一次关闭
        HideMenu()
        return
    }
    proc := ""
    try proc := WinGetProcessName("A")
    if CtrlExSet.Has(StrLower(proc))
        return
    SetTimer(() => ManualTrigger(true), -1)   ; 放到新线程执行, 不阻塞热键线程
}


; ============================================================
;  热键
; ============================================================

; * 通配符: 按住 Shift 等修饰键时也能触发(否则 Shift+点击收不到事件)
~*LButton::OnLDown()
~*LButton Up::OnLUp()

; 监听 Ctrl 的按下/松开 (~ 保证 Ctrl 仍正常传给应用)
~LControl::CtrlDown()
~RControl::CtrlDown()
~LControl Up::CtrlUp()
~RControl Up::CtrlUp()

#HotIf IsObject(MenuGui)
~WheelUp::HideMenu()
~WheelDown::HideMenu()
~RButton::HideMenu()
~MButton::HideMenu()
#HotIf
