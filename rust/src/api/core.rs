use easytier::common::config::{ConfigFileControl, ConfigLoader, TomlConfigLoader};
use easytier::instance_manager::NetworkInstanceManager;
use lazy_static::lazy_static;
use tokio::runtime::Runtime;
use uuid::Uuid;

lazy_static! {
    static ref RUNTIME: Runtime = Runtime::new().expect("failed to create EasyTier runtime");
    static ref MANAGER: NetworkInstanceManager = NetworkInstanceManager::new();
}

pub(crate) fn instance_manager() -> &'static NetworkInstanceManager {
    &MANAGER
}

pub(crate) fn parse_core_instance_id(instance_id: &str) -> Result<Uuid, String> {
    parse_instance_id(instance_id)
}
fn parse_instance_id(instance_id: &str) -> Result<Uuid, String> {
    Uuid::parse_str(instance_id).map_err(|error| format!("invalid instance id: {error}"))
}

/// 初始化 EasyTier 运行时；重复调用是安全的。
#[flutter_rust_bridge::frb(ignore)]
pub fn initialize_core() {
    lazy_static::initialize(&RUNTIME);
    lazy_static::initialize(&MANAGER);
}

/// 内嵌 EasyTier 核心报告的版本。
#[flutter_rust_bridge::frb(sync)]
pub fn easytier_version() -> String {
    easytier::VERSION.to_owned()
}

/// 解析并校验 EasyTier TOML 配置，但不启动网络。
pub fn validate_toml(toml: String) -> Result<(), String> {
    TomlConfigLoader::new_from_str(&toml)
        .map(|_| ())
        .map_err(|error| error.to_string())
}

/// 启动一个 EasyTier 网络并返回核心实例 UUID。
pub fn start_from_toml(toml: String, force_no_tun: bool) -> Result<String, String> {
    let config = TomlConfigLoader::new_from_str(&toml)
        .map_err(|error| format!("invalid EasyTier TOML: {error}"))?;
    // 只有用户同时省略静态 IPv4 和 DHCP 开关时，才默认启用 DHCP。
    let dhcp_is_configured = toml::from_str::<toml::Value>(&toml)
        .ok()
        .and_then(|value| value.get("dhcp").cloned())
        .is_some();
    if config.get_ipv4().is_none() && !dhcp_is_configured {
        config.set_dhcp(true);
    }
    if force_no_tun {
        let mut flags = config.get_flags();
        flags.no_tun = true;
        config.set_flags(flags);
    }
    let instance_id = config.get_id();
    MANAGER
        .run_network_instance(config, false, ConfigFileControl::STATIC_CONFIG)
        .map_err(|error| format!("failed to start EasyTier instance: {error}"))?;
    Ok(instance_id.to_string())
}

/// 将 Android VpnService 创建的 TUN 文件描述符交给 EasyTier。
pub fn set_tun_fd(instance_id: String, fd: i32) -> Result<(), String> {
    let id = parse_instance_id(&instance_id)?;
    MANAGER
        .set_tun_fd(&id, fd)
        .map_err(|error| format!("failed to set TUN fd: {error}"))
}
/// 停止一个 EasyTier 网络实例。
pub fn stop_instance(instance_id: String) -> Result<(), String> {
    let id = parse_instance_id(&instance_id)?;
    MANAGER
        .delete_network_instance(vec![id])
        .map(|_| ())
        .map_err(|error| format!("failed to stop EasyTier instance: {error}"))
}

/// 停止当前插件进程拥有的全部 EasyTier 网络实例。
pub fn stop_all_instances() -> Result<(), String> {
    let ids = MANAGER.list_network_instance_ids();
    if ids.is_empty() {
        return Ok(());
    }
    MANAGER
        .delete_network_instance(ids)
        .map(|_| ())
        .map_err(|error| format!("failed to stop EasyTier instances: {error}"))
}

/// 返回指定实例当前是否已注册到核心管理器。
#[flutter_rust_bridge::frb(sync)]
pub fn is_instance_running(instance_id: String) -> bool {
    let Ok(id) = parse_instance_id(&instance_id) else {
        return false;
    };
    MANAGER.list_network_instance_ids().contains(&id)
}

/// 列出当前插件进程拥有的全部 EasyTier 实例 UUID。
#[flutter_rust_bridge::frb(sync)]
pub fn list_instance_ids() -> Vec<String> {
    MANAGER
        .list_network_instance_ids()
        .into_iter()
        .map(|id| id.to_string())
        .collect()
}
#[cfg(test)]
mod tests {
    use super::validate_toml;

    #[test]
    fn validates_advanced_typed_config_shape() {
        let toml = r#"
instance_name = "flutter-demo"
instance_id = "11111111-1111-1111-1111-111111111111"
ipv6 = "fd00::2/64"
ipv6_public_addr_provider = true
ipv6_public_addr_auto = false
ipv6_public_addr_prefix = "2001:db8:1::/64"
listeners = []
mapped_listeners = ["tcp://203.0.113.10:11010"]
tcp_whitelist = ["80", "8000-9000"]
udp_whitelist = []
stun_servers = []
stun_servers_v6 = ["stun://[2001:db8::1]:3478"]
credential_file = "credentials.json"

[network_identity]
network_name = "advanced-network"
network_secret = ""

[[port_forward]]
bind_addr = "0.0.0.0:8080"
dst_addr = "10.126.126.1:80"
proto = "tcp"

[vpn_portal_config]
client_cidr = "10.14.14.0/24"
wireguard_listen = "0.0.0.0:11011"

[secure_mode]
enabled = false

[acl.acl_v1]

[acl.acl_v1.group]
members = ["admins"]

[[acl.acl_v1.group.declares]]
group_name = "admins"
group_secret = "secret"

[[acl.acl_v1.chains]]
name = "protect-forward"
chain_type = 3
description = ""
enabled = true
default_action = 2

[[acl.acl_v1.chains.rules]]
name = "allow-web"
description = ""
priority = 0
enabled = true
protocol = 1
ports = ["80", "443"]
source_ips = ["10.0.0.0/8"]
destination_ips = []
source_ports = []
action = 1
rate_limit = 0
burst_limit = 0
stateful = true
source_groups = []
destination_groups = []
"#;

        validate_toml(toml.to_owned()).expect("高级类型化配置应能被 EasyTier 解析");
    }
}
