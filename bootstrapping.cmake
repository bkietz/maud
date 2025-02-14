# Exclude Maud's own "system" c++ when bootstrapping
set(
  MAUD_CXX_SOURCE_EXCLUSION_PATTERN
  "cmake_modules/"
)

# When building Muad itself, we need the maud_inject_regenerate
# program to be compiled and runnable *before* configuration ends.
# This can be accomplished with try_compile:

shim_script_as("${CMAKE_SOURCE_DIR}/maud" "${_MAUD_SELF_DIR}/maud_cli.cmake")

set(
  _MAUD_INJECT_REGENERATE
  "${MAUD_DIR}/maud_inject_regenerate"
  CACHE INTERNAL
  "try_compile'd maud_inject_regenerate for bootstrapping Maud"
)

if(
  "${dir}/filesystem.cxx" IS_NEWER_THAN "${_MAUD_INJECT_REGENERATE}"
  OR
  "${dir}/cmake_modules/executable.cxx" IS_NEWER_THAN "${_MAUD_INJECT_REGENERATE}"
)
  file(
    WRITE "${MAUD_DIR}/injected/maud_minimal_.cxx"
    "export module maud_;\nexport import :filesystem;\n"
  )

  # TODO we don't even need a target for this; just install the bootstrapped one
  #      (rename to .maud_inject_regenerate.cxx to exclude from the glob)
  try_compile(
    success
    SOURCES "${dir}/maud_inject_regenerate.cxx"
    SOURCES_TYPE CXX_MODULE
    SOURCES
      "${MAUD_DIR}/injected/maud_minimal_.cxx"
      "${dir}/filesystem.cxx"
      "${dir}/cmake_modules/executable.cxx"
    COPY_FILE "${_MAUD_INJECT_REGENERATE}"
    OUTPUT_VARIABLE errors
    CXX_STANDARD 20
    NO_CACHE
  )

  if(NOT success)
    message(FATAL_ERROR "try_compile failed: ${errors}")
  endif()
endif()

_maud_set(_MAUD_IN2 "ERROR_PLACEHOLDER_MAUD_IN2_NOT_BOOTSTRAPPED")
