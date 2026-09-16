import 'easytier_session_snapshot.dart';

/// EasyTier 会话产生的事件。
sealed class EasyTierEvent {
  const EasyTierEvent({required this.receivedAt});

  /// Dart 层收到该事件的时间。
  final DateTime receivedAt;
}

/// 核心运行快照已经更新。
final class EasyTierSnapshotUpdated extends EasyTierEvent {
  const EasyTierSnapshotUpdated({
    required this.snapshot,
    required super.receivedAt,
  });

  /// 本次收到的完整运行快照。
  final EasyTierSessionSnapshot snapshot;
}

/// EasyTier 核心发出的原始事件。
///
/// 普通页面通常不需要处理此事件；调试、日志或高级功能可以读取 [json]。
final class EasyTierCoreEvent extends EasyTierEvent {
  const EasyTierCoreEvent({required this.json, required super.receivedAt});

  /// 核心事件的原始 JSON。
  final String json;
}
