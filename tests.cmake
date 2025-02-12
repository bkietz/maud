add_compile_definitions("BUILD_DIR=\"${CMAKE_BINARY_DIR}\"")

add_test(
  NAME pytest.trike
  COMMAND
    "${CMAKE_BUILD_DIR}/documentation/venv/bin/pytest" -vv
    "${CMAKE_SOURCE_DIR}/cmake_modules/trike"
)
