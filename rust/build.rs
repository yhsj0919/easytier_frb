use std::fs;
use std::path::{Path, PathBuf};

fn easytier_crate_root() -> Option<PathBuf> {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
    let metadata = cargo_metadata::MetadataCommand::new()
        .manifest_path(&manifest)
        .exec()
        .ok()?;
    let package = metadata
        .packages
        .iter()
        .find(|item| item.name == "easytier")?;
    package
        .manifest_path
        .parent()
        .map(|path| PathBuf::from(path.as_std_path()))
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

#[cfg(target_os = "windows")]
fn copy_runtime_dlls(from_dir: &Path) -> std::io::Result<()> {
    let out_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../cargokit/prebuilt/windows");
    fs::create_dir_all(&out_dir)?;
    for name in ["Packet.dll", "wintun.dll"] {
        let source = from_dir.join(name);
        if source.is_file() {
            fs::copy(&source, out_dir.join(name))?;
            println!("cargo:rerun-if-changed={}", source.display());
        }
    }
    Ok(())
}

fn main() {
    let Some(root) = easytier_crate_root() else {
        println!("cargo:warning=EasyTier package was not found in Cargo metadata");
        return;
    };

    println!(
        "cargo:rerun-if-changed={}",
        root.join("third_party").display()
    );

    #[cfg(all(windows, target_env = "msvc"))]
    {
        let lib_dir = third_party_lib_dir(&root);
        if lib_dir.join("Packet.lib").is_file() {
            let native = lib_dir.display().to_string().replace('\\', "/");
            println!("cargo:rustc-link-search=native={native}");
            if let Err(error) = copy_runtime_dlls(&lib_dir) {
                println!("cargo:warning=failed to copy EasyTier runtime DLLs: {error}");
            }
        } else {
            println!(
                "cargo:warning=Packet.lib was not found at {}",
                lib_dir.display()
            );
        }
    }

    #[cfg(not(all(windows, target_env = "msvc")))]
    let _ = root;
}
