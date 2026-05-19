//! 从 Cargo 解析到的 easytier 依赖目录链接 third_party，并将运行时 DLL 拷到 rust_builder/prebuilt。

use std::fs;
use std::path::{Path, PathBuf};

fn easytier_crate_root() -> Option<PathBuf> {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
    let metadata = cargo_metadata::MetadataCommand::new()
        .manifest_path(&manifest)
        .exec()
        .ok()?;
    let pkg = metadata.packages.iter().find(|p| p.name == "easytier")?;
    pkg.manifest_path
        .parent()
        .map(|p| PathBuf::from(p.as_std_path()))
}

#[cfg(target_os = "windows")]
fn third_party_lib_dir(easytier_root: &Path) -> PathBuf {
    let target = std::env::var("TARGET").unwrap_or_default();
    let base = easytier_root.join("third_party");
    if target.contains("aarch64") {
        base.join("arm64")
    } else if target.contains("i686") {
        base.join("i686")
    } else if target.contains("x86_64") {
        base.join("x86_64")
    } else {
        base
    }
}

/// 拷贝到插件内相对路径，供 CMake 打包（无绝对路径硬编码）。
#[cfg(target_os = "windows")]
fn copy_runtime_dlls(from_dir: &Path) -> std::io::Result<()> {
    let out_dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../rust_builder/prebuilt/windows");
    fs::create_dir_all(&out_dir)?;
    for name in ["Packet.dll", "wintun.dll"] {
        let src = from_dir.join(name);
        if src.is_file() {
            fs::copy(&src, out_dir.join(name))?;
            println!("cargo:rerun-if-changed={}", src.display());
        }
    }
    Ok(())
}

fn main() {
    let Some(root) = easytier_crate_root() else {
        println!("cargo:warning=未在 cargo metadata 中找到 easytier 包");
        return;
    };

    println!("cargo:rerun-if-changed={}", root.join("third_party").display());

    #[cfg(all(windows, target_env = "msvc"))]
    {
        let lib_dir = third_party_lib_dir(&root);
        if lib_dir.join("Packet.lib").is_file() {
            let native = lib_dir.display().to_string().replace('\\', "/");
            println!("cargo:rustc-link-search=native={native}");
            if let Err(e) = copy_runtime_dlls(&lib_dir) {
                println!("cargo:warning=拷贝 third_party DLL 失败: {e}");
            }
        } else {
            println!(
                "cargo:warning=未找到 {}（请确认 git 依赖的 easytier 含 third_party）",
                lib_dir.join("Packet.lib").display()
            );
        }
    }

    #[cfg(not(all(windows, target_env = "msvc")))]
    let _ = root;
}
