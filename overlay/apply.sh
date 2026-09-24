#!/bin/sh
#
# 把 MTK 闭源 WiFi 整套（mt_wifi + warp + HNAT + wifi_utility）和 OpenFi 6C 的
# 设备适配，打到一棵**干净的 ImmortalWrt 发行分支源码树**上。
#
# 用法（在底座源码树根目录）：
#     sh /path/to/openfi6c-mtk-wifi/overlay/apply.sh
#
# 设计要点：
#   - 底座树保持零改动，所有改动都从本仓库打上去 → 底座永远能直接 merge 上游；
#   - 删开源驱动（mt76）就一行 rm，不用手工做；
#   - 上游文件用 patch_upstream.py 定点改，匹配不上就 fail，绝不猜。
#
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)   # <port>/overlay
PORT=$(cd "$HERE/.." && pwd)          # <port>
BASE=$(pwd)                           # 底座源码树

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 0. 前置检查 ----------
[ -f "$BASE/rules.mk" ] && [ -d "$BASE/target/linux/mediatek" ] \
	|| die "当前目录不是 OpenWrt/ImmortalWrt 源码树：$BASE"
[ -f "$PORT/package/mtk/drivers/mt_wifi/Makefile" ] \
	|| die "本仓库内容不完整：找不到 $PORT/package/mtk/drivers/mt_wifi/Makefile"

log "底座：$BASE"
log "移植包：$PORT"

# ---------- 1. 删掉开源 WiFi 驱动（mt76） ----------
if [ -d "$BASE/package/kernel/mt76" ]; then
	rm -rf "$BASE/package/kernel/mt76"
	log "已删除开源 WiFi 驱动 package/kernel/mt76（含 kmod-mt7915e / kmod-mt7981-firmware）"
else
	log "package/kernel/mt76 不存在，跳过（可能已删过）"
fi

# ---------- 2. 打包层：package/mtk ----------
log "装入闭源打包层 package/mtk（mt_wifi / warp / conninfra / wifi-profile / 用户态工具）"
cp -a "$PORT/package/mtk" "$BASE/package/mtk"

# ---------- 3. 内核侧：files-6.12 + patches-6.12 ----------
log "装入内核侧 mtk_hnat / wifi_utility / wapp uapi / MTK 补丁"
cp -a "$PORT/target/linux/mediatek/files-6.12/." "$BASE/target/linux/mediatek/files-6.12/"
cp -a "$PORT/target/linux/mediatek/patches-6.12/." "$BASE/target/linux/mediatek/patches-6.12/"

# ---------- 4. 设备树 ----------
log "覆盖设备树 mt7981b-openfi-6c.dts（wbsys + mtd-eeprom + lte_* gpio + &hnat 绑定）"
cp -f "$PORT/overlay/dts/mt7981b-openfi-6c.dts" \
	"$BASE/target/linux/mediatek/dts/mt7981b-openfi-6c.dts"

# ---------- 5. 板级文件 ----------
BF="$BASE/target/linux/mediatek/filogic/base-files"
log "装入板级脚本（MAC 写入 / USB-WAN 热插拔 / init.d / uci-defaults）"
mkdir -p "$BF/etc/hotplug.d/net" "$BF/etc/init.d" "$BF/etc/uci-defaults" "$BF/usr/sbin"
cp -f "$PORT"/overlay/files/hotplug.d/net/* "$BF/etc/hotplug.d/net/"
cp -f "$PORT"/overlay/files/init.d/* "$BF/etc/init.d/"
cp -f "$PORT"/overlay/files/uci-defaults/* "$BF/etc/uci-defaults/"
cp -f "$PORT"/overlay/files/usr/sbin/* "$BF/usr/sbin/"
chmod 0755 "$BF"/etc/hotplug.d/net/* "$BF"/etc/init.d/* "$BF"/etc/uci-defaults/* "$BF"/usr/sbin/*

# ---------- 6. 自家 LuCI 插件 ----------
log "装入 luci-app-openfi（风扇/LED/拨动开关）与 luci-app-openfi-modem"
mkdir -p "$BASE/package/openfi"
cp -a "$PORT/overlay/package/mtk/applications/luci-app-openfi" \
	"$BASE/package/mtk/applications/luci-app-openfi"
cp -a "$PORT/overlay/package/openfi/luci-app-openfi-modem" \
	"$BASE/package/openfi/luci-app-openfi-modem"

# ---------- 7. 上游文件定点修改 ----------
python3 "$PORT/overlay/patch_upstream.py" "$BASE"

# ---------- 8. 汇报内核版本 ----------
KV=$(sed -n 's/^LINUX_VERSION-6\.12 = \.\?\(.*\)/\1/p' \
	"$BASE/target/linux/generic/kernel-6.12" 2>/dev/null || echo "?")
VERIFIED=$(sed -n 's/^verified_kernel:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$PORT/port.yml" 2>/dev/null || echo "?")
log "底座内核：6.12.${KV}    本移植已验证：6.12.${VERIFIED}"
if [ "$KV" != "$VERIFIED" ]; then
	log "⚠  内核版本与已验证版本不一致 —— 闭源驱动大概率编不过，需要移植（见 README）"
fi

log "完成。接下来：./scripts/feeds update -a && ./scripts/feeds install -a"
