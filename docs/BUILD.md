# 构建环境与依赖

本文说明从源码构建 `easytier_frb` 插件及 `example` 应用所需的系统环境、需安装的工具链与运行时库。

## 目录

1. [环境总览](#环境总览)
2. [通用依赖（所有平台）](#通用依赖所有平台)
3. [按目标平台](#按目标平台)
4. [可选：修改 Rust API 后](#可选修改-rust-api-后)
5. [首次构建步骤](#首次构建步骤)
6. [验证环境](#验证环境)
7. [构建产物与运行时库](#构建产物与运行时库)
8. [常见构建问题](#常见构建问题)

---

## 环境总览

| 组件 | 用途 | 建议版本 |
|------|------|----------|
| **Flutter SDK** | Dart UI、插件集成、cargokit 触发构建 | ≥ 3.3（本仓库 `pubspec` 要求 Dart **≥ 3.12**） |
| **Dart SDK** | 随 Flutter 提供 | 与 Flutter 捆绑版本一致 |
| **Rust (rustup)** | 编译 `rust/` 为各平台原生库 | **stable**（建议 ≥ 1.77；开发机实测 1.95 可编） |
| **Cargo** | 依赖解析、编译 | 随 Rust 安装 |
| **Git** | 拉取 `easytier` 的 git 依赖 | 任意较新版本 |
| **网络** | 首次 `cargo build` 克隆 EasyTier 源码 | 需能访问 GitHub |

插件通过 **cargokit** 在 `flutter build` / `flutter run` 时自动调用 `cargo` 编译 Rust，一般**不需要**手动安装 `easytier-core` 可执行文件。

---

## 通用依赖（所有平台）

### 1. Flutter

安装 [Flutter SDK](https://docs.flutter.dev/get-started/install)，并配置 `PATH`。

```bash
flutter doctor
flutter doctor -v
```

确保目标平台对应项为 ✓（Android toolchain、Visual Studio、Xcode 等）。

本仓库根目录与 `example/` 均需：

```bash
flutter pub get
cd example && flutter pub get
```

### 2. Rust（rustup）

安装 [rustup](https://rustup.rs/)，使用 **stable** 工具链：

```bash
rustup default stable
rustup update stable
rustc --version
cargo --version
```

按需添加交叉编译目标（示例）：

```bash
# Android（cargokit 构建 .so 时会用到对应 triple）
rustup target add aarch64-linux-android
rustup target add armv7-linux-androideabi
rustup target add x86_64-linux-android

# Windows（在 Linux/macOS 上交叉编译时）
rustup target add x86_64-pc-windows-msvc

# Linux / macOS 桌面
rustup target add x86_64-unknown-linux-gnu   # Linux
rustup target add aarch64-apple-darwin       # macOS Apple Silicon
rustup target add x86_64-apple-darwin        # macOS Intel
```

> 在对应平台上用 `flutter run` 时，cargokit 通常会引导安装所需 target；若报 `target not found`，再手动 `rustup target add`。

### 3. LLVM / libclang（部分构建场景需要）

**不是** Windows 桌面链接器（桌面仍走 **MSVC + Visual Studio**），但在编译 EasyTier 传递依赖 **`kcp-sys`** 时，其 `build.rs` 会通过 **bindgen** 调用 **libclang** 生成 C 绑定。

| 构建目标 | LLVM 是否常用 |
|----------|----------------|
| **Windows 桌面** (`flutter build windows`) | 链接用 MSVC；**编译阶段** bindgen 若找不到 libclang 可能报错——已安装的 LLVM（`bin` 含 `libclang.dll`）或设置环境变量可避免 |
| **Android**（在 Windows/macOS/Linux 上交叉编译） | **更需要**：链接用 NDK 自带 `clang`，但 bindgen 用**主机**上的 libclang；cargokit 会查找 `LIBCLANG_PATH`、`LLVM_HOME`、`PATH` 及 `C:\Program Files\LLVM\bin` 等 |
| **Linux 桌面** | 通常用系统 `clang` / `libclang-dev`；独立安装的 LLVM 也可 |
| **macOS** | 多用 Xcode 自带 clang；Homebrew `llvm` 亦可 |

若已安装 LLVM，建议将 **`bin` 加入 PATH**，或设置：

```bash
# Windows PowerShell 示例
$env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"
# 或
$env:LLVM_HOME = "C:\Program Files\LLVM"
```

cargokit 实现见 `rust_builder/cargokit/build_tool/lib/src/android_environment.dart` 中的 `_resolveLibClangPath()`。

### 4. Git

`rust/Cargo.toml` 中 `easytier` 为 **git 依赖**（非 crates.io），首次编译会从 GitHub 拉取指定 revision 的源码：

```toml
easytier = { git = "https://github.com/EasyTier/EasyTier.git", rev = "8428a89d2dabc94c97d370ec607c6ca142473626", ... }
```

请保证：

- 已安装 `git` 且在 `PATH` 中  
- 网络可访问 `github.com`（企业环境需配置代理或镜像）

### 5. 磁盘与时间

- 首次完整编译 EasyTier 核心体积较大，**建议预留 5～15 GB** 磁盘（含 `target/` 与 git checkout）。  
- Release / 多 ABI 构建耗时可达 **数十分钟**，属正常现象。

---

## 按目标平台

### Android

| 依赖 | 说明 |
|------|------|
| **Android SDK** | 通过 Android Studio 或命令行工具安装 |
| **Android NDK** | 由 Flutter 指定版本（`flutter.ndkVersion`）；`flutter doctor` 会提示缺失项 |
| **JDK 17** | 与当前 Flutter/Gradle 模板一致（example 使用 Java 17） |
| **CMake** | NDK 自带 / SDK CMake，供 cargokit 构建原生库 |

安装示例（Android Studio）：

1. SDK Platforms：按需 API Level  
2. SDK Tools：Android SDK Build-Tools、**NDK**、CMake、Android SDK Command-line Tools  

构建示例：

```bash
cd example
flutter build apk --debug
# 或
flutter run -d <android-device-id>
```

插件已合并 `INTERNET`、`VpnService` 等声明，见 `android/src/main/AndroidManifest.xml`。

---

### Windows

| 依赖 | 说明 |
|------|------|
| **Visual Studio 2022** | 工作负载：**使用 C++ 的桌面开发**（MSVC、Windows SDK） |
| **CMake ≥ 3.14** | 通常随 VS 安装；Flutter 桌面构建也会用到 |
| **Rust MSVC 目标** | `x86_64-pc-windows-msvc`（默认） |

构建示例：

```bash
cd example
flutter build windows --debug
flutter run -d windows
```

**运行时 DLL（非安装项，由构建生成/拷贝）：**

| 文件 | 来源 |
|------|------|
| `wintun.dll` | EasyTier 仓库 `third_party`，由 `rust/build.rs` 拷至 `rust_builder/prebuilt/windows` |
| `Packet.dll` | 同上 |
| `rust_lib_easytier_frb.dll` | cargokit 编译产物 |

首次 Windows 构建前需成功跑过一次 Rust 编译，以便 `prebuilt/windows` 中有上述 DLL；否则 CMake 会 **WARNING** 缺少文件。

组网使用系统 TUN 时，运行阶段建议 **以管理员身份** 启动应用。

---

### Linux

| 依赖 | 说明 |
|------|------|
| **clang / gcc** | `build-essential` 或 `clang` 工具链 |
| **CMake、ninja**（推荐） | Flutter Linux 桌面构建 |
| **pkg-config、openssl 开发包** | 部分 Rust 传递依赖可能需要 |

Debian/Ubuntu 示例：

```bash
sudo apt update
sudo apt install -y \
  build-essential \
  cmake \
  ninja-build \
  pkg-config \
  libssl-dev \
  clang
```

构建示例：

```bash
cd example
flutter build linux --debug
flutter run -d linux
```

**运行时**：库内 TUN 通常需要 **root** 或 `CAP_NET_ADMIN`。

---

### macOS

| 依赖 | 说明 |
|------|------|
| **Xcode** | 含 Command Line Tools |
| **CocoaPods** | 仅构建 **iOS** 时需要：`sudo gem install cocoapods` |

```bash
xcode-select --install
cd example
flutter build macos --debug
flutter run -d macos
```

iOS：

```bash
cd example
flutter build ios --debug --no-codesign
```

**运行时**：TUN 通常需要 root 或 Network Extension 能力（见 `EasyTier.platformRequirements`）。

---

## 可选：修改 Rust API 后

仅当修改 `rust/src/api/` 并需重新生成 Dart 绑定时安装：

```bash
# 版本需与 pubspec / Cargo.toml 中 flutter_rust_bridge 一致（当前 2.12.0）
cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked
```

在仓库根目录执行：

```bash
flutter_rust_bridge_codegen generate
```

配置文件：[`flutter_rust_bridge.yaml`](../flutter_rust_bridge.yaml)。

---

## 首次构建步骤

```bash
# 1. 克隆仓库
git clone <your-repo-url> easytier_frb
cd easytier_frb

# 2. 检查环境
flutter doctor -v
rustc --version

# 3. 拉取 Dart 依赖
flutter pub get
cd example && flutter pub get && cd ..

# 4. 静态分析（可选）
flutter analyze

# 5. 构建示例（任选平台，会触发 cargokit 编译 Rust）
cd example
flutter build windows --debug    # Windows
flutter build apk --debug        # Android
flutter build linux --debug      # Linux
flutter build macos --debug      # macOS
```

首次构建会下载 Rust crates 与 EasyTier git 源码，耗时较长。

---

## 验证环境

| 检查项 | 命令 |
|--------|------|
| Flutter | `flutter doctor` |
| Rust | `rustc --version` / `cargo --version` |
| Git | `git --version` |
| Windows MSVC | Visual Studio Installer → 已安装「使用 C++ 的桌面开发」 |
| Android NDK | `flutter doctor --android-licenses` 后无 NDK 报错 |

---

## 构建产物与运行时库

```
easytier_frb/
├── rust/                    # Rust 源码（FRB + easytier git 依赖）
├── rust_builder/            # cargokit FFI 插件
│   └── prebuilt/windows/    # build.rs 拷贝的 wintun.dll、Packet.dll
├── lib/src/bridge/          # FRB 生成的 Dart 绑定（已入库或可 regenerate）
└── example/                 # 示例 App
```

**不需要**单独安装：

- `easytier-core` 独立可执行文件（本插件进程内嵌库）  
- 手动下载 wintun（Windows 构建链会从 EasyTier `third_party` 拷贝）

**需要**在宿主机器上具备：

- 对应平台的 Flutter + 原生工具链（见上文）  
- 能完成 `cargo` 编译的网络与磁盘空间  

---

## 常见构建问题

| 现象 | 处理 |
|------|------|
| `failed to load source for dependency easytier` | 检查 Git、代理、GitHub 可达性 |
| `target xxx not found` | `rustup target add <triple>` |
| Windows 缺少 `wintun.dll` / `Packet.dll` | 先在本机成功执行一次 `flutter build windows`，确认 `rust_builder/prebuilt/windows` 存在 DLL |
| Android NDK 未安装 | Android Studio SDK Manager 安装 NDK，或按 `flutter doctor` 提示 |
| `请先调用 EasyTier.initialize()` | 运行时问题：先 `initialize()` 再调组网 API |
| 编译极慢 | 首次正常；可暂时用 `--debug`；Release 开 LTO 会更慢（见 `rust/Cargo.toml` 注释） |
| `flutter_rust_bridge_codegen` 找不到 | `cargo install flutter_rust_bridge_codegen --version 2.12.0` |

---

## 相关文档

- [README.md](../README.md) — 项目概览与快速开始  
- [USAGE.md](USAGE.md) — 宿主 App 集成与 API 用法  
