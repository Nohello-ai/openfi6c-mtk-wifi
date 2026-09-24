#!/usr/bin/env python3
"""
对 ImmortalWrt 底座里的上游文件做定点修改。

设计原则：**宁可失败，不要猜**。
  - 每处修改都要求精确匹配到且只匹配到 1 次；
  - 匹配 0 处或多处 → 直接退出并报错，提示"上游漂移，需要人工移植"。
这样底座滚动到新版本时，一旦上游改了这几处，CI 会在 30 秒内停下来告诉你，
而不是悄悄编出一个错了的固件。
"""
import pathlib
import sys

base = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()


def sub(path, old, new, what):
    p = base / path
    if not p.exists():
        sys.exit(f"!! {what}: 找不到 {p}")
    s = p.read_text()
    if new in s and old not in s:
        print(f"  = {path}: 已经是目标状态，跳过")
        return
    n = s.count(old)
    if n != 1:
        sys.exit(
            f"!! {what}: 在 {path} 里匹配到 {n} 处（期望恰好 1 处）\n"
            f"   上游漂移了，需要人工移植。匹配片段开头：\n"
            f"   {old.splitlines()[0][:80]!r}"
        )
    p.write_text(s.replace(old, new))
    print(f"  + {path}: {what}")


FILOGIC = "target/linux/mediatek/image/filogic.mk"
LEDS = "target/linux/mediatek/filogic/base-files/etc/board.d/01_leds"
NET = "target/linux/mediatek/filogic/base-files/etc/board.d/02_network"

print("==> 定点修改上游文件")

# 1) filogic.mk：openfi_6c 的包列表 —— 干掉 mt76，换上闭源套件
sub(
    FILOGIC,
    """define Device/openfi_6c
  DEVICE_VENDOR := OpenFi
  DEVICE_MODEL := 6C
  DEVICE_DTS := mt7981b-openfi-6c
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 automount""",
    """define Device/openfi_6c
  DEVICE_VENDOR := OpenFi
  DEVICE_MODEL := 6C
  DEVICE_DTS := mt7981b-openfi-6c
  DEVICE_DTS_DIR := ../dts
  SUPPORTED_DEVICES += openfi,6c1
  DEVICE_PACKAGES := kmod-usb3 automount kmod-usb-net-rndis \\
\tkmod-usb-serial-option kmod-fs-f2fs kmod-mmc f2fsck losetup mkf2fs \\
\tkmod-mt_wifi luci-app-mtwifi-cfg luci-app-openfi""",
    "filogic.mk: openfi_6c 去掉 kmod-mt7915e/mt7981-firmware，加闭源 WiFi 套件",
)

# 2) 01_leds：闭源驱动的 op_led.sh 直接写 /sys/class/leds/{internet,wifi}
sub(
    LEDS,
    """openfi,6c)
\tucidef_set_led_netdev "lan" "LAN" "green:lan" "eth0" "link tx rx"
\t;;""",
    """openfi,6c)
\tucidef_set_led_netdev "lan" "LAN" "internet" "eth0" "link tx rx"
\tucidef_set_led_netdev "wlan" "WLAN" "wifi" "rax0" "link tx rx"
\t;;""",
    "01_leds: LED 名对齐本仓库 DTS 的 label 命名",
)

# 3) 02_network：官方把 openfi,6c 归进"只有 LAN"那组，先把它摘出来
sub(
    NET,
    """\tnetgear,wax220|\\
\topenfi,6c|\\
\ttplink,f65-v1|\\""",
    """\tnetgear,wax220|\\
\ttplink,f65-v1|\\""",
    "02_network: 从'只有 LAN'的设备组里摘掉 openfi,6c",
)

# 4) 02_network：单独给 openfi,6c 一个分支 —— 网口当 LAN，5G 模块(usb0)当 WAN
sub(
    NET,
    """\tzyxel,nwa50ax-pro)
\t\tucidef_set_interface_lan "eth0"
\t\t;;
\tairpi,ap3000m|\\""",
    """\tzyxel,nwa50ax-pro)
\t\tucidef_set_interface_lan "eth0"
\t\t;;
\topenfi,6c)
\t\tucidef_set_interfaces_lan_wan "eth0" "usb0"
\t\t;;
\tairpi,ap3000m|\\""",
    "02_network: openfi,6c 独立分支，LAN=eth0 / WAN=usb0",
)

print("==> 上游文件定点修改完成")
