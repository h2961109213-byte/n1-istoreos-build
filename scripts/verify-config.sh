#!/usr/bin/env bash
# 在 openwrt 源码目录、make defconfig 之后运行
set -u
CFG=.config
REQ=../config/istoreos-custom.config

echo "===== 1. 目标设备检查 ====="
if ! grep -qE '^CONFIG_TARGET_amlogic_.*_DEVICE_.*n1.*=y' "$CFG"; then
  echo "::error::未选中 Phicomm N1。当前源码中的 target 与 amlogic 设备如下："
  ls target/linux/
  grep -rhoE '^define Device/[A-Za-z0-9_-]+' target/linux/amlogic/image/ 2>/dev/null | sort -u
  exit 1
fi
grep -E '^CONFIG_TARGET_(BOARD|SUBTARGET|PROFILE)=' "$CFG"

echo "===== 2. 核心必选组件与镜像格式检查（缺失任何一项即立即停止） ====="
fail=0
for item in \
  CONFIG_TARGET_ROOTFS_SQUASHFS=y \
  CONFIG_BUILD_LOG=y \
  CONFIG_PACKAGE_kmod-nfnetlink-queue=y \
  CONFIG_PACKAGE_kmod-nft-queue=y \
  CONFIG_PACKAGE_kmod-sched-bpf=y \
  CONFIG_PACKAGE_kmod-xdp-sockets-diag=y \
  CONFIG_BPF_TOOLCHAIN_NONE=y \
  CONFIG_KERNEL_DEBUG_INFO_BTF=y \
  CONFIG_PACKAGE_kmod-brcmfmac=y \
  CONFIG_BRCMFMAC_SDIO=y \
  CONFIG_PACKAGE_cypress-firmware-43455-sdio=y \
  CONFIG_PACKAGE_brcmfmac-nvram-43455-sdio-generic=y \
  CONFIG_PACKAGE_luci=y \
  CONFIG_PACKAGE_uhttpd=y \
  CONFIG_PACKAGE_luci-mod-admin-full=y \
  CONFIG_PACKAGE_luci-app-firewall=y \
  CONFIG_PACKAGE_luci-app-store=y \
  CONFIG_PACKAGE_quickstart=y \
  CONFIG_PACKAGE_luci-app-quickstart=y \
  CONFIG_PACKAGE_luci-app-diskman=y \
  CONFIG_PACKAGE_luci-app-dockerman=y \
  CONFIG_PACKAGE_luci-app-oaf=y \
  CONFIG_PACKAGE_luci-app-qmodem=y \
  CONFIG_PACKAGE_luci-app-openclash=y \
  CONFIG_PACKAGE_wpad-basic=y \
  CONFIG_PACKAGE_dnsmasq-full=y \
  CONFIG_PACKAGE_tar=y; do
  if grep -qx "$item" "$CFG"; then
    echo "OK   $item"
  else
    echo "::error::核心必选项缺失: $item"
    fail=1
  fi
done

if grep -q '^CONFIG_TARGET_ROOTFS_EXT4FS=y' "$CFG"; then
  echo "::error::CONFIG_TARGET_ROOTFS_EXT4FS 仍处于开启状态，会导致 256MiB ext4 镜像空间不足失败"
  fail=1
else
  echo "OK   CONFIG_TARGET_ROOTFS_EXT4FS 已关闭"
fi

for forbidden in \
  CONFIG_HAS_BPF_TOOLCHAIN=y \
  CONFIG_PACKAGE_dae=y \
  CONFIG_PACKAGE_daed=y \
  CONFIG_PACKAGE_luci-app-daede=y; do
  if grep -qx "$forbidden" "$CFG"; then
    echo "::error::禁止项仍被启用（会触发 bpf-headers）: $forbidden"
    fail=1
  else
    echo "OK   未启用 $forbidden"
  fi
done

echo "===== 3. 禁用项检查（防止 PCI/DAHDI/mt76-pci 模块被重新选回） ====="
while IFS= read -r sym; do
  [ -z "$sym" ] && continue
  if grep -qE "^CONFIG_${sym}=(y|m)$" "$CFG"; then
    echo "::error::禁用项未生效（仍被选中）: CONFIG_${sym}"
    fail=1
  else
    echo "OK   已关闭 CONFIG_${sym}"
  fi
done < <(sed -n 's/^# CONFIG_\(PACKAGE_kmod-[A-Za-z0-9_-]*\) is not set$/\1/p' "$REQ")

echo "===== 4. 其他请求选项（缺失仅警告） ====="
miss=0
while IFS= read -r line; do
  case "$line" in CONFIG_*=*) ;; *) continue ;; esac
  if ! grep -qx "$line" "$CFG"; then echo "::warning::未生效 $line"; miss=$((miss+1)); fi
done < "$REQ"
echo "未生效选项数: $miss"

exit $fail
