//! EasyTier 多实例 FRB API（参考 astral `p2p.rs`，无业务层封装）。

use easytier::common::config::{ConfigFileControl, ConfigLoader, TomlConfigLoader};
use easytier::instance_manager::NetworkInstanceManager;
use lazy_static::lazy_static;
use serde_json::json;
use tokio::runtime::Runtime;
use uuid::Uuid;

lazy_static! {
    static ref RT: Runtime = Runtime::new().expect("failed to create tokio runtime");
    static ref MANAGER: NetworkInstanceManager = NetworkInstanceManager::new();
}

fn parse_instance_id(instance_id: &str) -> Result<Uuid, String> {
    Uuid::parse_str(instance_id).map_err(|e| format!("invalid instance_id: {e}"))
}

async fn get_instance_info(
    instance_id: &str,
) -> Result<easytier::launcher::NetworkInstanceRunningInfo, String> {
    let id = parse_instance_id(instance_id)?;
    MANAGER
        .get_network_info(&id)
        .await
        .ok_or_else(|| "instance not found".to_string())
}

/// 初始化 FRB（应用启动时调用一次）。
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    lazy_static::initialize(&RT);
}

pub fn easytier_version() -> String {
    easytier::VERSION.to_string()
}

pub fn parse_config(toml: String) -> Result<(), String> {
    TomlConfigLoader::new_from_str(&toml).map(|_| ()).map_err(|e| e.to_string())
}

pub fn run_network_from_toml(toml: String) -> Result<String, String> {
    let cfg =
        TomlConfigLoader::new_from_str(&toml).map_err(|e| format!("invalid config toml: {e}"))?;
    let instance_id = cfg.get_id();
    MANAGER
        .run_network_instance(cfg, false, ConfigFileControl::STATIC_CONFIG)
        .map_err(|e| format!("start instance failed: {e}"))?;
    Ok(instance_id.to_string())
}

pub fn stop_instance(instance_id: String) -> Result<(), String> {
    let id = parse_instance_id(&instance_id)?;
    MANAGER
        .delete_network_instance(vec![id])
        .map(|_| ())
        .map_err(|e| format!("delete instance failed: {e}"))
}

pub fn stop_all_instances() -> Result<(), String> {
    let ids = MANAGER.list_network_instance_ids();
    if ids.is_empty() {
        return Ok(());
    }
    MANAGER
        .delete_network_instance(ids)
        .map(|_| ())
        .map_err(|e| format!("delete instances failed: {e}"))
}

pub fn set_tun_fd(instance_id: String, fd: i32) -> Result<(), String> {
    let id = parse_instance_id(&instance_id)?;
    MANAGER
        .set_tun_fd(&id, fd)
        .map_err(|e| format!("set_tun_fd failed: {e}"))
}

fn ipv4_inet_to_host(v4: &Option<easytier::proto::common::Ipv4Inet>) -> Option<String> {
    let inet = v4.as_ref()?;
    let a = inet.address.as_ref()?.addr;
    if a == 0 {
        return None;
    }
    Some(format!(
        "{}.{}.{}.{}",
        (a >> 24) & 0xff,
        (a >> 16) & 0xff,
        (a >> 8) & 0xff,
        a & 0xff
    ))
}

pub async fn get_running_info_json(instance_id: String) -> String {
    let info = match get_instance_info(&instance_id).await {
        Ok(info) => info,
        Err(_) => return "null".to_string(),
    };

    let virtual_ipv4_host = info
        .my_node_info
        .as_ref()
        .and_then(|n| ipv4_inet_to_host(&n.virtual_ipv4));

    serde_json::to_string(&json!({
        "dev_name": info.dev_name,
        "virtual_ipv4_host": virtual_ipv4_host,
        "my_node_info": info.my_node_info,
        "routes": info.routes,
        "peer_route_pairs": info.peer_route_pairs,
        "peer_count": info.peers.len(),
    }))
    .unwrap_or_else(|_| "null".to_string())
}

pub fn is_instance_running(instance_id: String) -> bool {
    let Ok(id) = parse_instance_id(&instance_id) else {
        return false;
    };
    MANAGER.list_network_instance_ids().contains(&id)
}
