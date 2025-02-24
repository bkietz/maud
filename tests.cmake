add_compile_definitions("BUILD_DIR=\"${CMAKE_BINARY_DIR}\"")

if(NOT EXISTS "${CMAKE_BINARY_DIR}/documentation/venv/bin/pytest")
  return()
endif()

add_test(
  NAME pytest.trike
  COMMAND
    "${CMAKE_BINARY_DIR}/documentation/venv/bin/pytest" -vv
    "${CMAKE_SOURCE_DIR}/cmake_modules/trike"
)
