#!/usr/bin/env bash
set -euo pipefail

# 普通用户编译，只对测试应用进程提权。
test -n "$LINUX_TEST_ADB_TARGET" || { echo '请设置 LINUX_TEST_ADB_TARGET Secret'; exit 1; }
echo "::add-mask::$LINUX_TEST_ADB_TARGET"
echo "::add-mask::${LINUX_TEST_ADB_TARGET%:*}"
test -c /dev/net/tun || { echo '/dev/net/tun 不可用'; exit 1; }
config_file="$RUNNER_TEMP/linux-tun-test.json"
trap 'rm -f "$config_file"' EXIT
jq -n '{LINUX_TEST_TOML_BASE64: (env.LINUX_TEST_TOML | @base64)}' > "$config_file"
echo "::add-mask::$(jq -r '.LINUX_TEST_TOML_BASE64' "$config_file")"
flutter build linux --debug --target=integration_test/linux_tun_test.dart --dart-define-from-file="$config_file"
xvfb-run -a bash scripts/linux_tun_drive.sh
