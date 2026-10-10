# 用 CocoaPods 已有的 xcodeproj 库配置 demo 的扩展目标；重复运行不会重复添加。
require 'xcodeproj'

project = Xcodeproj::Project.open(File.join(__dir__, 'Runner.xcodeproj'))
runner = project.targets.find { |target| target.name == 'Runner' }
raise '未找到 Runner 目标' unless runner

tunnel = project.targets.find { |target| target.name == 'EasyTierTunnel' }
unless tunnel
  tunnel = project.new_target(:app_extension, 'EasyTierTunnel', :ios, '15.0')
  group = project.main_group.new_group('EasyTierTunnel', 'EasyTierTunnel')
  source = group.new_file('PacketTunnelProvider.swift')
  group.new_file('Info.plist')
  group.new_file('EasyTierTunnel.entitlements')
  tunnel.source_build_phase.add_file_reference(source)
  tunnel.add_system_framework('NetworkExtension')
  runner.add_dependency(tunnel)
  embed = runner.new_copy_files_build_phase('Embed EasyTier Tunnel')
  embed.dst_subfolder_spec = '13' # 应用内 PlugIns 目录
  build_file = embed.add_file_reference(tunnel.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end

tunnel.add_build_configuration('Profile', :release) unless tunnel.build_configurations.any? { |configuration| configuration.name == 'Profile' }
group = project.main_group.find_subpath('EasyTierTunnel', false)
unless tunnel.source_build_phase.files.any? { |file| file.file_ref&.path == 'TunnelAddress.swift' }
  source = group.new_file('TunnelAddress.swift')
  tunnel.source_build_phase.add_file_reference(source)
end
unless tunnel.shell_script_build_phases.any? { |phase| phase.name == 'Build EasyTier Rust' }
  phase = tunnel.new_shell_script_build_phase('Build EasyTier Rust')
  phase.shell_script = <<~SCRIPT
    set -e
    export PODS_ROOT="${SRCROOT}/Pods"
    export PODS_TARGET_SRCROOT="${SRCROOT}/../../ios"
    export PODS_CONFIGURATION_BUILD_DIR="${CONFIGURATION_BUILD_DIR}"
    bash "${SRCROOT}/../../cargokit/build_pod.sh" ../rust rust_lib_easytier_frb
  SCRIPT
  phase.output_paths = ['$(CONFIGURATION_BUILD_DIR)/EasyTierTunnel/librust_lib_easytier_frb.a']
  tunnel.build_phases.delete(phase)
  tunnel.build_phases.unshift(phase)
end
tunnel.add_system_framework('SystemConfiguration') unless tunnel.frameworks_build_phase.files.any? { |file| file.file_ref&.path&.include?('SystemConfiguration') }
tunnel.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    # 必须显式设置名称，否则扩展可能被输出为没有文件名的 `.appex`。
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_MODULE_NAME' => 'EasyTierTunnel',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'xyz.yhsj.easytierFrbExample.EasyTierTunnel',
    'INFOPLIST_FILE' => 'EasyTierTunnel/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'EasyTierTunnel/EasyTierTunnel.entitlements',
    'SWIFT_VERSION' => '5.0',
    'SWIFT_OBJC_BRIDGING_HEADER' => 'EasyTierTunnel/Bridge.h',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
    'OTHER_LDFLAGS' => '$(inherited) -force_load $(CONFIGURATION_BUILD_DIR)/EasyTierTunnel/librust_lib_easytier_frb.a',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'SKIP_INSTALL' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'IPHONEOS_DEPLOYMENT_TARGET' => '15.0',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  })
end
runner.build_configurations.each do |configuration|
  configuration.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end
project.save
puts 'EasyTier VPN 扩展目标已配置。'
