# 进程内 TUN 所需运行时 DLL（替代 easytier_flutter 的 embed easytier-core CMake）。
# build.rs 从 easytier git 依赖的 third_party 目录拷贝到 rust_builder/prebuilt/windows。

if(WIN32)
  get_filename_component(
    EASYTIER_PREBUILT_DLL_DIR
    "${CMAKE_CURRENT_LIST_DIR}/../prebuilt/windows"
    ABSOLUTE
  )
  foreach(_dll Packet.dll wintun.dll)
    if(EXISTS "${EASYTIER_PREBUILT_DLL_DIR}/${_dll}")
      list(APPEND EASYTIER_THIRD_PARTY_DLLS "${EASYTIER_PREBUILT_DLL_DIR}/${_dll}")
    else()
      message(WARNING
        "缺少 ${_dll}，请先执行一次 cargo/flutter 构建以从 easytier 仓库拷贝 prebuilt")
    endif()
  endforeach()
endif()
