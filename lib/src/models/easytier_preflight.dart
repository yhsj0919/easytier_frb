import 'easytier_exception.dart';

/// 启动前发现的一个问题。
final class EasyTierPreflightIssue {
  /// 创建一个阻止网络启动的问题。
  const EasyTierPreflightIssue({
    required this.code,
    required this.message,
    this.suggestion,
    this.technicalDetails,
  });

  /// 适合程序分支判断的稳定错误码。
  final EasyTierErrorCode code;

  /// 可以直接展示给用户的简短说明。
  final String message;

  /// 建议用户采取的解决方法。
  final String? suggestion;

  /// 只适合诊断日志使用的底层详情。
  final String? technicalDetails;

  /// 转换为启动操作抛出的统一异常。
  EasyTierException toException() => EasyTierException(
    code: code,
    message: suggestion == null ? message : '$message $suggestion',
    technicalDetails: technicalDetails,
    recoverable: true,
  );
}

/// 一次启动前检查的结果。
final class EasyTierPreflightResult {
  /// 创建一份不可变的启动前检查结果。
  EasyTierPreflightResult(Iterable<EasyTierPreflightIssue> issues)
    : issues = List.unmodifiable(issues);

  /// 检查发现的全部阻塞问题。
  final List<EasyTierPreflightIssue> issues;

  /// 是否可以继续启动网络。
  bool get canStart => issues.isEmpty;
}
