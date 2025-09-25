add_compile_definitions("BUILD_DIR=\"${CMAKE_BINARY_DIR}\"")

maud_venv("${CMAKE_BINARY_DIR}/pytest_venv" venv-)
if(NOT venv-python)
  return()
endif()

add_custom_target(
  pytest ALL
  COMMENT "Installing pytest to test trike"
  COMMAND
    "${venv-pip_install}"
    --editable "${dir}/cmake_modules/trike[test]"
  COMMAND_EXPAND_LISTS
)
add_test(
  NAME pytest.trike
  COMMAND "${venv-python}" -m pytest -vv "${dir}/cmake_modules/trike"
)
