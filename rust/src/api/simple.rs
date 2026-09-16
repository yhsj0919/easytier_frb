/// Flutter 与 Rust 桥接协议的版本。
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

/// 用于集成测试和运行诊断的最小往返调用。
#[flutter_rust_bridge::frb(sync)]
pub fn ping(payload: String) -> String {
    payload
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    super::core::initialize_core();
}
