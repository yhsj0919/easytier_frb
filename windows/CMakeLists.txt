cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "easytier_frb")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../rust rust_lib_easytier_frb "")

set(EASYTIER_RUNTIME_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../cargokit/prebuilt/windows")
set(easytier_frb_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  "${EASYTIER_RUNTIME_DIR}/Packet.dll"
  "${EASYTIER_RUNTIME_DIR}/wintun.dll"
  PARENT_SCOPE
)
