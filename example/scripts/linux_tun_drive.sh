#!/usr/bin/env bash
set -euo pipefail

log_file="$RUNNER_TEMP/linux-tun-app.log"
sudo --preserve-env=DISPLAY,XAUTHORITY,LINUX_TEST_ADB_TARGET build/linux/x64/debug/bundle/easytier_frb_example > "$log_file" 2>&1 &
app_pid=$!
trap 'sudo kill "$app_pid" 2>/dev/null || true; cat "$log_file"' EXIT

# 等待 Debug 应用输出 VM Service 地址，再让普通权限的测试驱动连接。
vm_url=''
for attempt in $(seq 1 60); do
  vm_url=$(sed -nE 's/.*(http:\/\/127\.0\.0\.1:[0-9]+\/[^ ]+).*/\1/p' "$log_file" | head -n 1)
  if [ -n "$vm_url" ]; then break; fi
  sleep 1
done
test -n "$vm_url" || { echo '未获得测试应用 VM Service 地址'; exit 1; }
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/linux_tun_test.dart -d linux --use-existing-app="$vm_url"
