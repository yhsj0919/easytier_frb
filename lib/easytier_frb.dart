/// EasyTier Flutter 插件公共导出。
///
/// 宿主应用通常只需 `import 'package:easytier_frb/easytier_frb.dart';`，
/// 使用 [EasyTier] 作为唯一入口。若需单独初始化 FRB，可引用 [RustLib]。
library;

export 'src/easytier.dart';
export 'src/easytier_event.dart';
export 'src/models/connection_state.dart';
export 'src/models/network_instance.dart';
export 'src/models/peer_traffic_info.dart';
export 'src/models/start_result.dart';

// FRB 初始化（宿主若需单独 init 可引用）
export 'src/bridge/frb_generated.dart';
