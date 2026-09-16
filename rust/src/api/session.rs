use crate::frb_generated::StreamSink;
use easytier::common::global_ctx::GlobalCtxEvent;
use serde_json::json;
use tokio::sync::broadcast::error::RecvError;
use uuid::Uuid;

use super::core::{instance_manager, parse_core_instance_id};

/// EasyTier 核心会话发出的内部消息。
pub struct CoreSessionMessage {
    pub kind: String,
    pub json: String,
}

fn event_receiver(instance_id: &Uuid) -> Option<easytier::common::global_ctx::EventBusSubscriber> {
    instance_manager()
        .iter()
        .find(|item| item.key() == instance_id)
        .and_then(|item| item.value().subscribe_event())
}

fn stop_notifier(instance_id: &Uuid) -> Option<std::sync::Arc<tokio::sync::Notify>> {
    instance_manager()
        .iter()
        .find(|item| item.key() == instance_id)
        .and_then(|item| item.value().get_stop_notifier())
}

fn message(kind: &str, value: serde_json::Value) -> CoreSessionMessage {
    CoreSessionMessage {
        kind: kind.to_owned(),
        json: value.to_string(),
    }
}

fn push(sink: &StreamSink<CoreSessionMessage>, value: CoreSessionMessage) -> bool {
    sink.add(value).is_ok()
}

fn core_event_needs_snapshot(event: &GlobalCtxEvent) -> bool {
    !matches!(
        event,
        GlobalCtxEvent::Connecting(_)
            | GlobalCtxEvent::ConnectError(_, _, _)
            | GlobalCtxEvent::ConnectionAccepted(_, _)
            | GlobalCtxEvent::ConnectionError(_, _, _)
            | GlobalCtxEvent::ListenerAcceptFailed(_, _)
    )
}

async fn running_info_json(instance_id: &Uuid) -> String {
    let Some(info) = instance_manager().get_network_info(instance_id).await else {
        return "null".to_owned();
    };

    let virtual_ipv4 = info
        .my_node_info
        .as_ref()
        .and_then(|node| node.virtual_ipv4.as_ref())
        .and_then(|inet| inet.address.as_ref())
        .map(|address| address.addr)
        .filter(|address| *address != 0)
        .map(|address| {
            format!(
                "{}.{}.{}.{}",
                (address >> 24) & 0xff,
                (address >> 16) & 0xff,
                (address >> 8) & 0xff,
                address & 0xff
            )
        });

    json!({
        "dev_name": info.dev_name,
        "virtual_ipv4_host": virtual_ipv4,
        "my_node_info": info.my_node_info,
        "routes": info.routes,
        "peer_route_pairs": info.peer_route_pairs,
        "peer_count": info.peers.len(),
        "error_msg": info.error_msg,
    })
    .to_string()
}

/// 返回一个 EasyTier 实例的原始 JSON 快照。
pub async fn get_session_snapshot(instance_id: String) -> Result<String, String> {
    let id = parse_core_instance_id(&instance_id)?;
    Ok(running_info_json(&id).await)
}

/// 发送指定实例的 `snapshot`、`core_event` 和 `stopped` 消息。
pub async fn watch_session(instance_id: String, sink: StreamSink<CoreSessionMessage>) {
    let Ok(id) = parse_core_instance_id(&instance_id) else {
        let _ = push(&sink, message("stopped", json!(null)));
        return;
    };

    let Some(mut events) = event_receiver(&id) else {
        let snapshot = running_info_json(&id).await;
        let _ = push(
            &sink,
            CoreSessionMessage {
                kind: "snapshot".to_owned(),
                json: snapshot,
            },
        );
        let _ = push(&sink, message("stopped", json!(null)));
        return;
    };

    let snapshot = running_info_json(&id).await;
    if !push(
        &sink,
        CoreSessionMessage {
            kind: "snapshot".to_owned(),
            json: snapshot,
        },
    ) {
        return;
    }

    let stopped = stop_notifier(&id);
    let mut tick = tokio::time::interval(std::time::Duration::from_secs(1));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

    loop {
        if !instance_manager().list_network_instance_ids().contains(&id) {
            let _ = push(&sink, message("stopped", json!(null)));
            break;
        }

        tokio::select! {
            _ = async {
                if let Some(notifier) = stopped.as_ref() {
                    notifier.notified().await;
                } else {
                    std::future::pending::<()>().await;
                }
            } => {
                let _ = push(&sink, message("stopped", json!(null)));
                break;
            }
            event = events.recv() => {
                match event {
                    Ok(event) => {
                        let event_json = serde_json::to_value(&event).unwrap_or(serde_json::Value::Null);
                        if !push(&sink, message("core_event", event_json)) {
                            break;
                        }
                        if core_event_needs_snapshot(&event) {
                            let snapshot = running_info_json(&id).await;
                            if !push(&sink, CoreSessionMessage { kind: "snapshot".to_owned(), json: snapshot }) {
                                break;
                            }
                        }
                    }
                    Err(RecvError::Lagged(_)) => {
                        if let Some(replacement) = event_receiver(&id) {
                            events = replacement;
                        } else {
                            events = events.resubscribe();
                        }
                        let snapshot = running_info_json(&id).await;
                        if !push(&sink, CoreSessionMessage { kind: "snapshot".to_owned(), json: snapshot }) {
                            break;
                        }
                    }
                    Err(RecvError::Closed) => {
                        let _ = push(&sink, message("stopped", json!(null)));
                        break;
                    }
                }
            }
            _ = tick.tick() => {
                let snapshot = running_info_json(&id).await;
                if !push(&sink, CoreSessionMessage { kind: "snapshot".to_owned(), json: snapshot }) {
                    break;
                }
            }
        }
    }
}
