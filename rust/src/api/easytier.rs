//! EasyTier 多实例 FRB API（参考 astral `p2p.rs`，无业务层封装）。

use crate::frb_generated::StreamSink;
use easytier::common::config::{ConfigFileControl, ConfigLoader, TomlConfigLoader};
use easytier::common::global_ctx::GlobalCtxEvent;
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
    TomlConfigLoader::new_from_str(&toml)
        .map(|_| ())
        .map_err(|e| e.to_string())
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
    let Ok(id) = parse_instance_id(&instance_id) else {
        return "null".to_string();
    };
    build_running_info_json(&id).await
}

pub fn is_instance_running(instance_id: String) -> bool {
    let Ok(id) = parse_instance_id(&instance_id) else {
        return false;
    };
    MANAGER.list_network_instance_ids().contains(&id)
}

fn instance_event_receiver(
    instance_id: &Uuid,
) -> Option<easytier::common::global_ctx::EventBusSubscriber> {
    MANAGER
        .iter()
        .find(|item| item.key() == instance_id)
        .and_then(|item| item.value().subscribe_event())
}

fn instance_stop_notifier(instance_id: &Uuid) -> Option<std::sync::Arc<tokio::sync::Notify>> {
    MANAGER
        .iter()
        .find(|item| item.key() == instance_id)
        .and_then(|item| item.value().get_stop_notifier())
}

fn running_info_triggers_refresh(event: &GlobalCtxEvent) -> bool {
    !matches!(
        event,
        GlobalCtxEvent::Connecting(_)
            | GlobalCtxEvent::ConnectError(_, _, _)
            | GlobalCtxEvent::ConnectionAccepted(_, _)
            | GlobalCtxEvent::ConnectionError(_, _, _)
            | GlobalCtxEvent::ListenerAcceptFailed(_, _)
    )
}

fn push_session_message(sink: &StreamSink<String>, value: serde_json::Value) {
    let _ = sink.add(value.to_string());
}

async fn push_snapshot(instance_id: &Uuid, sink: &StreamSink<String>) {
    let json = build_running_info_json(instance_id).await;
    push_session_message(
        sink,
        json!({
            "type": "snapshot",
            "json": json,
        }),
    );
}

fn push_core_event(sink: &StreamSink<String>, event: &GlobalCtxEvent) {
    let event_value = serde_json::to_value(event).unwrap_or(json!(null));
    push_session_message(
        sink,
        json!({
            "type": "core_event",
            "event": event_value,
        }),
    );
}

fn push_stopped(sink: &StreamSink<String>) {
    push_session_message(sink, json!({ "type": "stopped" }));
}

async fn build_running_info_json(instance_id: &Uuid) -> String {
    let info = match get_instance_info(&instance_id.to_string()).await {
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
        "error_msg": info.error_msg,
    }))
    .unwrap_or_else(|_| "null".to_string())
}

/// 订阅实例会话：核心事件 + 快照 + stopped。
pub async fn watch_session(instance_id: String, sink: StreamSink<String>) {
    let Ok(id) = parse_instance_id(&instance_id) else {
        push_stopped(&sink);
        return;
    };

    let Some(mut events) = instance_event_receiver(&id) else {
        push_snapshot(&id, &sink).await;
        push_stopped(&sink);
        return;
    };

    push_snapshot(&id, &sink).await;

    let stop_notifier = instance_stop_notifier(&id);
    let mut traffic_tick = tokio::time::interval(std::time::Duration::from_secs(1));
    traffic_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

    loop {
        if !MANAGER.list_network_instance_ids().contains(&id) {
            push_stopped(&sink);
            break;
        }

        tokio::select! {
            _ = async {
                if let Some(notifier) = stop_notifier.as_ref() {
                    notifier.notified().await;
                } else {
                    std::future::pending::<()>().await;
                }
            } => {
                push_stopped(&sink);
                break;
            }
            event = events.recv() => {
                match event {
                    Ok(event) => {
                        push_core_event(&sink, &event);
                        if running_info_triggers_refresh(&event) {
                            push_snapshot(&id, &sink).await;
                        }
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                        if let Some(new_events) = instance_event_receiver(&id) {
                            events = new_events;
                        } else {
                            events = events.resubscribe();
                        }
                        push_snapshot(&id, &sink).await;
                    }
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                        push_stopped(&sink);
                        break;
                    }
                }
            }
            _ = traffic_tick.tick() => {
                push_snapshot(&id, &sink).await;
            }
        }
    }
}
