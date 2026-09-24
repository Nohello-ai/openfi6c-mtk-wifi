#!/bin/sh
# 把 MTK 原始驱动 drop 解包到 raw/src/（该目录已 gitignore，不进版本库）
set -eu
cd "$(dirname "$0")"

TARBALL=mt79xx_20250408-705eb4.tar.xz

[ -f "$TARBALL" ] || { echo "!! 找不到 $TARBALL"; exit 1; }

echo "==> 校验"
sha256sum -c SHA256SUMS

echo "==> 解包"
mkdir -p src
tar -xJf "$TARBALL" -C src

echo "==> 完成：$(pwd)/src"
ls -1 src
