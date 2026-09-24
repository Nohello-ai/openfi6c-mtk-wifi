# vendor：MTK 原始闭源 WiFi 驱动（未做任何修改）

这是我们的**原版基线** —— 联发科直接发布的驱动 drop，**一个字节都没改**。

- `main` 分支现在用的是**社区移植好的打包层**（`chasey-dev/immortalwrt-mt798x-rebase`），能用、先这么用；
- 将来要"自己写适配"时，就从**这份原版**出发，而不是从别人的二手适配出发。

## 这份东西的来历

| 项 | 值 |
|---|---|
| 驱动版本 | **7.6.7.3** |
| 文件名 | `mt79xx_20250408-705eb4.tar.xz` |
| 大小 | 18,150,972 字节 |
| sha256 | `b029d7b43c498193092dc6a3c857361c8835ce34bb306561c550ac0539784a78` |
| 打包日期 | 2025-04-08（见文件名 `705eb4` 之后的日期段） |
| 我们取它的地方 | `hanwckf/immortalwrt-mt798x` 分支 `openwrt-21.02` 的 `dl/` |
| 再往上一步 | MediaTek 官方 feed `https://git01.mediatek.com/openwrt/feeds/mtk-openwrt-feeds`（合作方账号，公网只能拿到镜像） |

它是**专有代码**：源码头里带 MediaTek 的密级声明 ——
`contains confidential trade secret material of MediaTek`。
公网上流传的都是再发布。

## 里面有什么

| 目录 | 内容 | 体积 / 文件数 |
|---|---|---|
| `mt_wifi/` | 驱动源码本体（AP 与 STA 共用），1020 个文件 | 115 MB |
| `bin/` | 四颗芯片的 WiFi 固件 blob：`mt7915` `mt7916` `mt7981` `mt7986` | 77 MB |
| `warp_driver/` | WARP 硬件加速驱动源码 | 1.8 MB |
| `wlan_service/` | | 888 KB |
| `mt_wifi_ap/` | **MTK 自己的 OpenWrt 打包 glue**（`Makefile` + `Kconfig`） | 3 个文件 |
| `mt_wifi_sta/` | 同上，STA 模式 | 3 个文件 |

> `mt_wifi_ap/` 和 `mt_wifi_sta/` 是这份 drop 里最值钱的两小块：
> 它们是 MTK 官方"怎么把这个驱动编出来"的地面真值。
> 将来我们写自己的 OpenWrt 打包层时，就是把它翻译成 OpenWrt 的 `KernelPackage` 写法。
> 这两份我已经展开放在 `build-glue/` 里，方便直接看。

## 怎么用

```sh
sh raw/extract.sh          # 解包到 ./src/，得到上面 6 个目录
```

校验：

```sh
cd raw && sha256sum -c SHA256SUMS
```

## 这份原版 vs 我们现在用的（main 分支）

| | 原版（本目录） | main 现在用的 |
|---|---|---|
| 驱动本体 | 7.6.7.3 原始 drop | 同一个 tarball（`PKG_SOURCE_URL` + `PKG_HASH` 指向它） |
| OpenWrt 打包层 | MTK 的 `mt_wifi_ap/Makefile`（非 OpenWrt 风格） | `chasey-dev` 写的 `KernelPackage` 包装（~300 行） |
| 内核兼容补丁 | 无 | 41 个（`patches-7673/`，社区维护） |
| 用户态 | 无 | `mtwifi-cfg` / `mtwifi-cfg-ucode` / `wifi-dats` / `wifi-scripts` |

也就是说：**驱动本体本来就是原版**，社区动的是外面那层壳。
"自己写适配"真正要重写的是那层壳（打包层 + 补丁 + 用户态），不是驱动本身。
