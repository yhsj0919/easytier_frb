# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "rust_lib_easytier_frb")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
get_filename_component(_cargokit_cmake_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
get_filename_component(_cargokit_cmake_dir "${_cargokit_cmake_dir}" REALPATH)
get_filename_component(CARGOKIT_RUST_MANIFEST_DIR "${_cargokit_cmake_dir}/../../rust" ABSOLUTE)
apply_cargokit(${PROJECT_NAME} "${CARGOKIT_RUST_MANIFEST_DIR}" rust_lib_easytier_frb "")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(rust_lib_easytier_frb_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
