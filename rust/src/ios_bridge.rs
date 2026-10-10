//! iOS 扩展使用的 C ABI。Dart 仍通过 FRB/平台通道调用，不手写 FFI 绑定。
use crate::api::{core, session};
use easytier::common::config::{ConfigLoader, TomlConfigLoader};
use serde_json::{json, Value};
use std::ffi::{c_char, CStr, CString};

fn dispatch(request: Value) -> Result<Value, String> {
    let id = request["id"].as_str().unwrap_or_default().to_owned();
    match request["method"].as_str().unwrap_or_default() {
        "start" => {
            if !core::list_instance_ids().is_empty() {
                return Err("iOS 只能运行一个组网".into());
            }
            let toml = request["toml"].as_str().ok_or("缺少 TOML")?;
            let config = TomlConfigLoader::new_from_str(toml).map_err(|e| e.to_string())?;
            let routes = config
                .get_routes()
                .map(|items| items.iter().map(ToString::to_string).collect::<Vec<_>>());
            let id = core::start_from_toml(toml.to_owned(), true)?;
            let flags = config.get_flags();
            Ok(json!({
                "id": id, "manual_routes": routes, "mtu": flags.mtu,
                "ipv6": config.get_ipv6().map(|ip| ip.to_string()),
                "dns_enabled": flags.accept_dns,
                "dns_server": easytier::instance::dns_server::MAGIC_DNS_FAKE_IP,
                "dns_zone": flags.tld_dns_zone.trim_end_matches('.'),
            }))
        }
        "snapshot" => {
            let source =
                core::core_runtime().block_on(session::get_session_snapshot(id.clone()))?;
            let mut value: Value = serde_json::from_str(&source).map_err(|e| e.to_string())?;
            if value.is_null() {
                return Err("核心实例已停止".into());
            }
            value["instance_id"] = json!(id);
            Ok(value)
        }
        "set_fd" => {
            let fd = request["fd"].as_i64().ok_or("缺少数据通道")?;
            core::set_tun_fd(id, i32::try_from(fd).map_err(|e| e.to_string())?)?;
            Ok(Value::Null)
        }
        "stop" => {
            core::stop_all_instances()?;
            Ok(Value::Null)
        }
        _ => Err("未知扩展请求".into()),
    }
}

/// 输入借用的 UTF-8 JSON；返回分配的 JSON，必须用 et_ios_free 释放。
#[no_mangle]
pub unsafe extern "C" fn et_ios_request(input: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if input.is_null() {
            return Err("请求为空".to_owned());
        }
        let source = unsafe { CStr::from_ptr(input) }
            .to_str()
            .map_err(|e| e.to_string())?;
        dispatch(serde_json::from_str(source).map_err(|e| e.to_string())?)
    });
    let response = match result {
        Ok(Ok(value)) => json!({"ok": true, "value": value}),
        Ok(Err(error)) => json!({"ok": false, "error": error}),
        Err(_) => json!({"ok": false, "error": "核心内部异常"}),
    };
    CString::new(response.to_string()).unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn et_ios_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}
