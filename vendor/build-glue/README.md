# build-glue：MTK 自己的打包 glue（原封不动）

这两份是从原始 drop 里**原样取出**的，没有改动：

```
mt_wifi_ap/{Makefile,Kconfig}    AP 模式：编 mt_wifi.ko + mt_wifi_ap 相关
mt_wifi_sta/{Makefile,Kconfig}   STA 模式：编 mt_wifi_sta.ko
```

它们是 MTK 官方"这个驱动怎么编"的地面真值 —— 是 MTK SDK 的风格（`make -C` 直接进
内核树、靠 `Kconfig` 里的 `MT_WIFI_PATH` 之类变量选路径），不是 OpenWrt 的风格。

**怎么用**：将来写我们自己的 OpenWrt 打包层时，对着这两个文件把编译参数逐项翻译成
OpenWrt 的写法：

| MTK 的写法 | OpenWrt 的写法 |
|---|---|
| `Kconfig` 里几十个 `MT_*` 开关 | `config.in` 里的 `config MTK_*`（或直接硬编码成我们需要的组合） |
| `Makefile` 里 `-C $(LINUX_DIR) M=$(PWD)` | `KernelPackage/mt_wifi` + `Build/Compile` 里的 `$(MAKE) -C "$(LINUX_DIR)" M="$(PKG_BUILD_DIR)/mt_wifi_ap"` |
| 固件从 `bin/mt7981/rebb/` 装 | `Package/mt_wifi/install` 里 `$(INSTALL_BIN) ... $(1)/lib/firmware/` |
| 芯片选择靠 `CONFIG_MTK_CHIP_*` | 同上（OpenWrt 里也保留这套变量名，方便对照） |

对应地，现在 `main` 分支上的 `package/mtk/drivers/mt_wifi/Makefile` 就是别人做完这套
翻译的结果，可以拿来对照 —— 但那不是我们写的，将来要自己重写一份。
