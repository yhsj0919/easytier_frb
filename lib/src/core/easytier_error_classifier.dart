import '../models/easytier_exception.dart';

const _resourceConflictMarkers = <String>[
  'address already in use',
  'wsaeaddrinuse',
  'os error 10048',
  'only one usage of each socket address',
  'device or resource busy',
  'resource busy',
  'adapter is in use',
  'used by another process',
  'being used by another process',
  'locked by another process',
  'instance already exists',
  'network instance already exists',
  'cannot create a file when that file already exists',
  'os error 17',
  'file exists',
  '地址已在使用',
  '设备或资源忙',
  '另一个程序正在使用',
  '已被其他进程占用',
  '实例已存在',
];

EasyTierException classifyCoreStartFailure(Object error) {
  final details = error.toString();
  final normalized = details.toLowerCase();
  final isConflict = _resourceConflictMarkers.any(normalized.contains);

  if (isConflict) {
    return EasyTierException(
      code: EasyTierErrorCode.resourceConflict,
      message: '无法启动 EasyTier 网络：所需端口、网络设备或系统资源已被占用。',
      technicalDetails: details,
      recoverable: true,
      cause: error,
    );
  }

  return EasyTierException(
    code: EasyTierErrorCode.coreStartFailed,
    message: '启动 EasyTier 网络失败。',
    technicalDetails: details,
    recoverable: true,
    cause: error,
  );
}
