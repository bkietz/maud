# maud_cli.cmake must always be in the same directory as Maud.cmake
set(maud_path "${CMAKE_CURRENT_LIST_DIR}/Maud.cmake")

set(cmake_args)

foreach(i RANGE 4 ${CMAKE_ARGC})
  if(i EQUAL CMAKE_ARGC)
    break()
  endif()
  set(arg "${CMAKE_ARGV${i}}")

  if(arg MATCHES "^-[DWCTA].*$")
    list(APPEND cmake_args "${CMAKE_ARGV${i}}")
  elseif(arg MATCHES "^-+([^-][^= ]*)=(.*)$")
    # handle kebab case
    string(REPLACE - _ arg_name ARG_${CMAKE_MATCH_1})
    set(${arg_name} "${CMAKE_MATCH_2}")
  elseif(arg MATCHES "^-+([^-][^= ]*)$")
    string(REPLACE - _ arg_name ARG_${CMAKE_MATCH_1})
    set(${arg_name} ${arg})
  else()
    message(FATAL_ERROR "Unrecognized argument ${CMAKE_ARGV${i}}")
  endif()
endforeach()

function(argument name default help)
  if(NOT "${ARG_${name}}" STREQUAL "")
    set(value "${ARG_${name}}")
  elseif(default STREQUAL "OFF")
    set(value "")
  else()
    set(value "${default}")
  endif()

  set(${name} "${value}" PARENT_SCOPE)

  if(default STREQUAL "OFF")
    set(default "\t")
  elseif(help STREQUAL "")
    set(default "\t[=${default}]")
  else()
    set(default "\t[=${default}]\n\t\t\t")
  endif()

  string(REPLACE _ - name ${name})
  set(help_str "${help_str}  --${name}${default}${help}\n" PARENT_SCOPE)
endfunction()

set(
  help_str
  "
Maud CLI - generate with cmake then build

"
)
argument(help OFF "-h\tShow help text")
if(ARG_h)
  set(help ON)
endif()
string(APPEND help_str "\n")

argument(quiet OFF "Make cmake and the build tool quiet")
string(APPEND help_str "\n")

argument(log_level STATUS "Log level for cmake")
argument(generator "Ninja Multi-Config" "Build tool for generated build")
argument(
  source_dir "${CMAKE_SOURCE_DIR}"
  "Directory in which to generate CMakeLists.txt"
)
argument(
  build_dir "${CMAKE_SOURCE_DIR}/.build"
  "Path where build directory should be generated"
)

string(APPEND help_str "\n")
cmake_path(GET source_dir FILENAME project_name)
argument(
  cmake_minimum "cmake_minimum_required(VERSION 3.28)"
  ""
)
argument(
  project_command "project(\"${project_name}\" LANGUAGES CXX)"
  ""
)

string(APPEND help_str "\n")
argument(fresh OFF "\tClear the cache and regenerate")
argument(generate_only OFF "Only generate a build directory")

if(log_level STREQUAL "VERBOSE")
  message(STATUS "This is Larry's spirit guide, Maud. I am looking into the box...")
endif()
if(quiet)
  set(log_level ERROR)
endif()

if(help)
  message("${help_str}")
  return()
endif()

cmake_path(ABSOLUTE_PATH source_dir)
cmake_path(NORMAL_PATH source_dir)

cmake_path(ABSOLUTE_PATH build_dir)
cmake_path(NORMAL_PATH build_dir)

if(fresh OR NOT EXISTS "${source_dir}/CMakeLists.txt")
  file(
    WRITE "${source_dir}/CMakeLists.txt"
    "
    ${cmake_minimum}
    ${project_command}

    include(\"${maud_path}\")

    _maud_setup()

    include(CTest)

    _maud_cmake_modules()
    foreach(module \${_MAUD_CMAKE_MODULES})
      cmake_path(GET module PARENT_PATH dir)
      include(\"\${module}\")
    endforeach()

    # if any module appended to the PATH, save that to the cache
    _maud_set(CMAKE_MODULE_PATH \"\${CMAKE_MODULE_PATH}\")

    # resolve any remaining options
    _maud_resolve_options()

    if(BUILD_TESTING AND NOT COMMAND \"maud_add_test\")
      # TODO fallback to FetchContent
      find_package(GTest)
      include_directories(\${GTEST_INCLUDE_DIRS})
    endif()

    _maud_in2()
    _maud_finalize_generated()
    _maud_include_directories()

    _maud_cxx_sources()
    _maud_setup_clang_format()
    _maud_finalize_targets()
    _maud_setup_doc()
    _maud_options_summary()
    _maud_setup_regenerate()
    "
  )
  execute_process(
    COMMAND
    "${CMAKE_COMMAND}"
    -B "${build_dir}"
    -S "${source_dir}"
    -G "${generator}"
    ${cmake_args}
    --log-level=${log_level}
    ${fresh}
    RESULT_VARIABLE result
  )

  if(NOT result EQUAL 0)
    message(FATAL_ERROR "Generation failed.")
  endif()
endif()

if(generate_only)
  return()
endif()

set(verify)
while(NOT (verify MATCHES "INJECTED BY MAUD"))
  if(EXISTS "${build_dir}/CMakeFiles/VerifyGlobs.cmake")
    file(READ "${build_dir}/CMakeFiles/VerifyGlobs.cmake" verify)
  endif()
endwhile()

execute_process(
  COMMAND
  "${CMAKE_COMMAND}"
  --build "${build_dir}"
  --
  ${quiet}
  RESULT_VARIABLE result
)

if(NOT result EQUAL 0)
  message(FATAL_ERROR "Build failed.")
endif()

