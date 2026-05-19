# rust_builder

Flutter FFI 插件（cargokit），在应用进程内链接 `rust_lib_easytier_frb`。

- **不**在 CMake 中构建或打包 `easytier-core` 可执行文件
- Windows 仅通过 `cmake/easytier_third_party.cmake` 附带 `wintun.dll`、`Packet.dll`（由 `rust/build.rs` 从 easytier 仓库拷贝）

桌面组网请使用 Dart → FRB → `NetworkInstanceManager`，见 `lib/src/easytier_controller.dart`。
