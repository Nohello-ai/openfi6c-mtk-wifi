# openfi6c-mtk-wifi

OpenFi 6C（MT7981B + MT7976CN）用的**联发科闭源 WiFi 整套**移植包，挂在 **ImmortalWrt 发行分支**上。

底座仓库**一行不改**，所有改动都在 CI 里由本仓库打上去 —— 所以底座永远能直接跟上游同步，
不需要每次手工删驱动、也不需要解合并冲突。

```
        ImmortalWrt 发行分支（openwrt-25.12，零改动）
                        │
   CI: rm -rf package/kernel/mt76          ← 「删掉开源 WiFi 驱动」
       + 本仓库 package/mtk/               ← 闭源驱动打包层
       + 本仓库 files-6.12 / patches-6.12  ← 内核侧 HNAT / wifi_utility / MTK 补丁
       + 本仓库 overlay/                   ← 设备适配（DTS / 板级脚本 / LuCI）
                        ▼
                  OpenFi 6C 固件
```

## 里面是什么

| 路径 | 内容 |
|---|---|
| `package/mtk/drivers/mt_wifi` | 闭源 WiFi 驱动（7.6.7.3），AP + STA 两个模块 |
| `package/mtk/drivers/warp` | WARP v2 WiFi 硬件加速 |
| `package/mtk/drivers/conninfra`、`wifi-profile` | 驱动依赖 |
| `package/mtk/applications/*` | `mtwifi-cfg`、`mtwifi-cfg-ucode`、`luci-app-mtwifi-cfg`、`l1parser`、`datconf` 等用户态 |
| `target/linux/mediatek/files-6.12` | 内核侧 `mtk_hnat/`、`wifi_utility/`、`wapp` uapi 头 |
| `target/linux/mediatek/patches-6.12` | MTK 以太网/PPE/HNAT/WED 补丁 + 本地 `999-zzz-5xxx` 系列（共 535 个） |
| `overlay/dts` | 设备树：`mediatek,wbsys` + `mediatek,mtd-eeprom`（绕开 mt76 的 4 KiB nvmem cell 限制）、`lte_*` gpio-export、`&fan` 交给用户态、`&hnat` 绑定 |
| `overlay/files` | 板级脚本：`09-fix-mtwifi-mac`（往驱动 `.dat` 写 MAC）、`openfi-usb-wan`（USB 模组自动当 WAN） |
| `overlay/package` | `luci-app-openfi`（风扇/LED/拨动开关）、`luci-app-openfi-modem`（模组信息 + 卡槽切换） |
| `overlay/patch_upstream.py` | 对底座上游文件的定点修改（改不到就 fail） |
| `overlay/apply.sh` | 一键把上面全部打到一棵干净的底座树上 |
| `defconfig/` | 构建配置 |
| `port.yml` | 移植清单：底座、驱动版本、`verified_kernel` |

> ⚠️ 闭源 WiFi 和 HNAT 是绑死的：`mt_wifi.ko` 的模块依赖里有 `mtkhnat`，
> 所以不能"只留 WiFi 驱动、把 HNAT 删掉"。

## 怎么编

**CI**：推 `main` 或手动触发 workflow 即可。工作流会：

1. checkout 干净的底座（默认**最新发行 tag**，如 `v25.12.2`；手动填 `base_ref` 可换成 `openwrt-25.12` 跟分支）
2. `rm -rf package/kernel/mt76`
3. 跑 `overlay/apply.sh` 打上闭源驱动 + 设备适配
4. feeds → `make defconfig` → `make download` → `make -j`
5. 产物上传为 artifact；手动选 `publish=true` 时发 Release

> **为什么默认钉发行 tag 而不是跟分支**：分支是移动靶。
> 实测（2026-09-24）：`openwrt-25.12` 分支 HEAD 的内核已经是 **6.12.108**，
> 而最新发行 tag `v25.12.2` 是 **6.12.103** —— 闭源驱动只对后者验证过。
> 钉 tag 能保证"编出来的固件 = 移植验证过的那套"；分支更新由 CI 的
> 版本闸门负责发现（发现即失败 + 开 issue），不会悄悄编出没验证过的固件。

**本地**（需要一台 Linux，内存 ≥ 8 GB、磁盘 ≥ 30 GB）：

```sh
git clone -b v25.12.2 https://github.com/Nohello-ai/immortalwrt.git base
git clone https://github.com/Nohello-ai/openfi6c-mtk-wifi.git port
cd base
sh ../port/overlay/apply.sh
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../port/defconfig/mt7981-ax3000-openfi6c.config .config
make defconfig
make -j$(nproc)
```

### 编译缓存（第二次开始快很多）

三层，都走 `actions/cache`，key 以底座引用为前缀：

| 缓存 | 路径 | 体积 | 省掉什么 |
|---|---|---|---|
| 源码包 | `base/dl` | ~1.5 GB | 重复下载内核/软件包 tarball |
| 工具链 | `base/staging_dir`、`base/toolchain` | ~2.5 GB | 重建 host 工具 + 交叉工具链（约 40 分钟） |
| 编译产物 | `base/.ccache` | ≤ 3 GB | 重复编译 C/C++（包编译的大头） |

**两个坑（已经踩过并修掉）**：

1. **只设 `CCACHE_*` 环境变量是没用的** —— OpenWrt 必须在 `.config` 里有 `CONFIG_CCACHE=y` 才会把 ccache 套到编译器前面（`include/rules.mk` 里 `TARGET_CC:=$(if $(CONFIG_CCACHE),ccache) $(TARGET_CC)`）。而这个选项被 `if DEVEL` 门控，所以要同时开 `CONFIG_DEVEL=y`。这两个已经在 `defconfig` 里加好。
2. **`CCACHE_DIR` 环境变量会被覆盖** —— `include/rules.mk` 里 `export CCACHE_DIR:=$(CONFIG_CCACHE_DIR)`，默认 `$(TOPDIR)/.ccache`，优先级高于 CI 里设的环境变量。所以缓存路径必须是 `base/.ccache`，而不是工作区根目录的 `.ccache`；之前缓存的是个空目录。

工作流现在会显式断言 `CONFIG_CCACHE=y`，没开就直接失败 —— 不会再出现"配了缓存但其实没生效"。
缓存总量控制在 ~7 GB，低于 GitHub 每仓库 10 GB 的上限。

## 内核更新了怎么办（这就是"移植一次"）

本仓库唯一需要人工维护的地方就是 `port.yml` 里的：

```yaml
verified_kernel: "6.12.103"
```

工作流每次都会读底座 `target/linux/generic/kernel-6.12` 里的 `LINUX_VERSION-6.12`，
和 `verified_kernel` 比对：

- **相同** → 正常编译、出固件；
- **不同** → 直接失败 + 自动开 issue「需要移植：底座内核已升级到 6.12.xxx」。

移植步骤（通常半天到两天）：

1. 拉最新底座，`sh overlay/apply.sh`，看第一处报错在哪；
2. `target/linux/mediatek/patches-6.12/999-*.patch` 里失效的补丁 rebase 到新内核
   （大头是 `999-eth-*` / `999-ppe-*` / `999-hnat-*` / `999-wed-*` / `999-zzz-5xxx`）；
3. 修 `package/mtk/drivers/mt_wifi` 在 `files/` 与 `patches-7673/` 里的编译错误；
4. 编过、实机验过之后，把 `port.yml` 的 `verified_kernel` 改成新版本，
   并在 `ports:` 下加一条记录。
5. 已有的旧版本记录**保留**，方便回退。

## 来源与致谢

| 东西 | 出处 |
|---|---|
| 闭源驱动包（`mt79xx_20250408-705eb4.tar.xz`，7.6.7.3） | [`hanwckf/immortalwrt-mt798x`](https://github.com/hanwckf/immortalwrt-mt798x) 分支 `openwrt-21.02` 的 `dl/` |
| 打包层 `package/mtk`、内核侧 `files-6.12` / `patches-6.12` | [`chasey-dev/immortalwrt-mt798x-rebase`](https://github.com/chasey-dev/immortalwrt-mt798x-rebase) |
| 上游闭源驱动源头 | MediaTek `mtk-openwrt-feeds` |
| 底座 | [`immortalwrt/immortalwrt`](https://github.com/immortalwrt/immortalwrt) 分支 `openwrt-25.12` |
| `luci-app-openfi`（风扇/LED/开关） | OpenFi 官方固件内的 `luci-app-openfi`（Apache-2.0，`Copyright (C) Hua Shao`），经 tcpqueue 转到 25.12 |

## 当前状态

- 底座：`openwrt-25.12`（ImmortalWrt v25.12.2 起，内核 **6.12.103**）
- 驱动：`mt_wifi` **7.6.7.3** + `warp` **20250408**
- 合并固件：`mt_wifi`（闭源）+ `warp` + `kmod-mediatek_hnat`（无 mt76）
- `verified_kernel: 6.12.103` —— 与底座发行版一致，首次移植未对驱动源码做任何改动
