include_guard()

cmake_policy(PUSH)
cmake_policy(SET CMP0007 NEW) # list command no longer ignores empty elements.
cmake_policy(SET CMP0009 NEW) # GLOB_RECURSE calls should not follow symlinks by default.
cmake_policy(SET CMP0057 NEW) # Support new ``if()`` IN_LIST operator.


set(_MAUD_SELF_DIR "${CMAKE_CURRENT_LIST_DIR}")

# Deriving the working directory even in PROJECT mode requires some hackery
# - define the variable with UNINITIALIZED type so that it's as-if from the CLI
set(_MAUD_CWD "." CACHE UNINITIALIZED "" FORCE)
# - the value already exists and isn't absolute, so it will be coerced by type reassignment
set(_MAUD_CWD "." CACHE FILEPATH "" FORCE)
# - we can't leave this in the cache since it can change for each cmake run
set(MAUD_WORKING_DIR "${_MAUD_CWD}")
unset(_MAUD_CWD CACHE)


function(_maud_set var)
  set(${var} "${ARGN}" CACHE INTERNAL "" FORCE)
endfunction()


function(_maud_set_include var)
  set(val ${${var}} ${ARGN})
  list(REMOVE_DUPLICATES val)
  _maud_set(${var} ${val})
endfunction()


function(_maud_set_value_only var)
  # Set a CACHE var's value but don't touch other properties
  if(DEFINED CACHE{${var}})
    set_property(CACHE ${var} PROPERTY VALUE "${ARGN}")
  else()
    # ${var} has not yet been declared, so leave its type and help in a state
    # which will be overridden by a subsequent call to set().
    set(
      ${var} "${ARGN}" CACHE UNINITIALIZED
      "No help, variable specified on the command line."
    )
    # TODO remove this janky nonsense; I only need it for options anyway.
    # Just add ${OPTION_NAME}_PREDEF_VALUE
  endif()
endfunction()


function(_maud_filter list)
  set(all "${${list}}")
  set(matches)
  if(ARGN STREQUAL "" OR ARGN MATCHES ^!)
    set(matches "${all}")
  endif()
  foreach(pattern ${ARGN})
    if(pattern MATCHES "^!(.*)$")
      list(FILTER matches EXCLUDE REGEX "${CMAKE_MATCH_1}")
      continue()
    endif()
    set(new_matches "${all}")
    list(FILTER new_matches INCLUDE REGEX "${pattern}")
    list(APPEND matches ${new_matches})
  endforeach()
  list(REMOVE_DUPLICATES matches)
  set(${list} "${matches}" PARENT_SCOPE)
endfunction()


function(json_list out_var json)
  cmake_parse_arguments(
    PARSE_ARGV 2
    "" # prefix
    "" # options
    "ERROR_VARIABLE" # single value arguments
    "[]" # multi value arguments
  )

  string(
    JSON doc ERROR_VARIABLE error
    GET "${json}" ${_UNPARSED_ARGUMENTS}
  )
  if(NOT error)
    string(JSON max_i ERROR_VARIABLE error LENGTH "${doc}")
    math_assign(max_i - 1)
  endif()

  if(error AND NOT _ERROR_VARIABLE)
    message(FATAL_ERROR "${error}")
  elseif(error)
    set(${_ERROR_VARIABLE} "${error}" PARENT_SCOPE)
    set(${out_var} NOTFOUND PARENT_SCOPE)
    return()
  endif()

  set(element_path "_[]")
  set(element_path "${${element_path}}")
  set(list)
  string(JSON type TYPE "${doc}")

  foreach(i RANGE ${max_i})
    if(type STREQUAL "ARRAY")
      string(JSON element ERROR_VARIABLE error GET "${doc}" ${i} ${element_path})
    else()
      string(JSON key MEMBER "${doc}" ${i})
      string(
        JSON value ERROR_VARIABLE error
        GET "${doc}" "${key}" ${element_path}
      )
      set(element "${key}=${value}")
    endif()
    string(REPLACE ";" "\\;" element "${element}")
    list(APPEND list "${element}")
  endforeach()

  set(${out_var} "${list}" PARENT_SCOPE)
endfunction()


function(json_destructure out_var_prefix json)
  cmake_parse_arguments(
    PARSE_ARGV 2
    "" # prefix
    "" # options
    "ERROR_VARIABLE" # single value arguments
    "" # multi value arguments
  )

  string(
    JSON doc ERROR_VARIABLE error
    GET "${json}" ${_UNPARSED_ARGUMENTS}
  )
  if(NOT error)
    string(JSON max_i ERROR_VARIABLE error LENGTH "${doc}")
    math_assign(max_i - 1)
  endif()

  if(error AND NOT _ERROR_VARIABLE)
    message(FATAL_ERROR "${error}")
  elseif(error)
    set(${_ERROR_VARIABLE} "${error}" PARENT_SCOPE)
    set(${out_var} NOTFOUND PARENT_SCOPE)
    return()
  endif()

  string(JSON type TYPE "${doc}")
  if(type STREQUAL "ARRAY")
    foreach(i RANGE ${max_i})
      string(JSON element GET "${doc}" ${i})
      set("${out_var_prefix}${i}" "${element}" PARENT_SCOPE)
    endforeach()
  else()
    foreach(i RANGE ${max_i})
      string(JSON key MEMBER "${doc}" ${i})
      string(JSON value GET "${doc}" "${key}")
      set("${out_var_prefix}${key}" "${value}" PARENT_SCOPE)
    endforeach()
  endif()
endfunction()


function(_maud_glob out_var root_dir)
  file(
    GLOB_RECURSE matches
    LIST_DIRECTORIES true
    # Filters are applied to *relative* paths; otherwise directory
    # names above root_dir might spuriously include/exclude.
    RELATIVE "${root_dir}"
    "${root_dir}/*"
  )
  _maud_filter(matches  "!(/|^)[.]")
  set(${out_var} ${matches} PARENT_SCOPE)
endfunction()


function(glob out_var)
  if(DEFINED CACHE{${out_var}})
    return()
  endif()

  cmake_parse_arguments(
    "" # prefix
    "CONFIGURE_DEPENDS;EXCLUDE_RENDERED" # options
    "" # single value arguments
    "" # multi value arguments
    ${ARGN}
  )
  set(patterns ${_UNPARSED_ARGUMENTS})

  set(matches "${_MAUD_ALL}")
  _maud_filter(matches ${patterns})
  list(TRANSFORM matches PREPEND "${CMAKE_SOURCE_DIR}/")

  if(NOT _EXCLUDE_RENDERED)
    set(gen_matches "${_MAUD_ALL_GENERATED}")
    _maud_filter(gen_matches ${patterns})
    list(TRANSFORM gen_matches PREPEND "${MAUD_DIR}/rendered/")
    list(APPEND matches ${gen_matches})
  endif()

  _maud_set(${out_var} "${matches}")
  _maud_set(_MAUD_GLOB_ARGUMENTS_${out_var} "${ARGN}")

  list(APPEND _MAUD_GLOBS ${out_var})
  _maud_set(_MAUD_GLOBS "${_MAUD_GLOBS}")
endfunction()


function(_maud_relative_path path out_var is_gen_var)
  set(rendered_base "${MAUD_DIR}/rendered")
  cmake_path(IS_PREFIX rendered_base "${path}" NORMALIZE is_gen)
  if(is_gen)
    cmake_path(RELATIVE_PATH path BASE_DIRECTORY "${rendered_base}")
  else()
    cmake_path(RELATIVE_PATH path BASE_DIRECTORY "${CMAKE_SOURCE_DIR}")
  endif()
  set(${out_var} "${path}" PARENT_SCOPE)
  set(${is_gen_var} ${is_gen} PARENT_SCOPE)
endfunction()


function(_maud_get_ddi_path source_file out_var)
  _maud_relative_path("${source_file}" source_file is_gen)

  if(is_gen)
    set(ddi_base_directory "${MAUD_DIR}/ddi/rendered")
  else()
    set(ddi_base_directory "${MAUD_DIR}/ddi/source")
  endif()

  if(MSVC)
    set(ddi_path "${ddi_base_directory}/${source_file}.obj.ddi")
  else()
    set(ddi_path "${ddi_base_directory}/${source_file}.o.ddi")
  endif()

  cmake_path(NATIVE_PATH ddi_path NORMALIZE ddi_path)
  set(${out_var} "${ddi_path}" PARENT_SCOPE)
endfunction()


macro(_maud_get_generated_file_tag out_var)
  string(
    CONCAT ${out_var}
    "GENERATED BY ${CMAKE_CURRENT_FUNCTION}()"
    " ${CMAKE_CURRENT_FUNCTION_LIST_FILE}"
    ":${CMAKE_CURRENT_FUNCTION_LIST_LINE}"
  )
endmacro()


function(_maud_write_scan_script)
  if(MSVC)
    # https://learn.microsoft.com/en-us/cpp/build/building-on-the-command-line?view=msvc-170#developer_command_file_locations
    set(devcmd "${CMAKE_VS_MSBUILD_COMMAND}/../../Common7/Tools/VsDevCmd.bat")
    cmake_path(NATIVE_PATH devcmd NORMALIZE devcmd)
    _maud_get_generated_file_tag(generated_tag)
    string(
      CONCAT scan
      "
        :: ${generated_tag}
        @echo off
        setlocal
        :: invoke VsDevCmd.bat to load the necessary environment for scanning
        call ${devcmd}
      "
      [[
        :: Input is read from stdin or a file
        if "%1"=="-" (set IN='more') else (set IN=%~f1)
        set SUFFIX=%2
        for /f "tokens=*" %%l in (%IN%) do (call :line "%%l")
        exit


        :line :: lines are "source file path;output ddi path"
          for /f "tokens=1,2 delims=;" %%s in (%1) do (call :scan "%%s" "%%t")
        exit /b
      ]]
      "
        :scan :: expanded from CMAKE_CXX_SCANDEP_SOURCE
          echo SCANNING <SOURCE>
          echo     ==^> <DYNDEP_FILE>
          ${CMAKE_CXX_SCANDEP_SOURCE}
        exit /b
      "
    )
  else()
    # https://www.etalabs.net/sh_tricks.html
    _maud_set_shebang()
    _maud_get_generated_file_tag(generated_tag)
    string(
      CONCAT scan
      "${_MAUD_SHEBANG}\n"
      "# ${generated_tag}\n"
      "
        scan() { # expanded from CMAKE_CXX_SCANDEP_SOURCE
          echo 'SCANNING' <SOURCE>
          echo '     ==>' <DYNDEP_FILE>
          ${CMAKE_CXX_SCANDEP_SOURCE}
        }
      "
      [[
        SUFFIX=$2
        cat "$1" |
        while IFS= read line # lines are "source file path;output ddi path"
        do
          source="${line%%;*}"
          ddi="${line#${source};}"
          scan "$source" "$ddi"
        done
      ]]
    )
  endif()

  if(MSVC)
    set(source "%1")
    set(object "%2.obj")
  else()
    set(source [["$1"]])
    set(object [["$2.o"]])
  endif()

  get_directory_property(defines COMPILE_DEFINITIONS)
  list(TRANSFORM defines REPLACE "^(.+)$" "${_MAUD_DEFINE} \\1")

  get_directory_property(includes INCLUDE_DIRECTORIES)
  list(TRANSFORM includes REPLACE "^(.+)$" "${_MAUD_INCLUDE_DIR} \"\\1\"")
  list(JOIN includes " " includes)

  get_directory_property(flags COMPILE_OPTIONS)
  list(JOIN flags " " flags)
  string(PREPEND flags " `cat <OBJECT>.flags` ")
  string(PREPEND flags " ${CMAKE_CXX${CMAKE_CXX_STANDARD}_STANDARD_COMPILE_OPTION} ")
  string(PREPEND flags " ${_MAUD_INCLUDE} \"${MAUD_DIR}/options.h\"")
  string(REPLACE "SHELL:" "" flags "${flags}")

  if(MSVC)
    set(dyndep_file "<OBJECT>.ddi%SUFFIX%")
  else()
    set(dyndep_file "<OBJECT>.ddi$SUFFIX")
  endif()
  set(dep_file "<OBJECT>.ddi.d")
  set(preprocessed_source "<OBJECT>.ddi.preprocessed")

  foreach(
    var

    source
    defines
    includes
    flags
    dyndep_file
    dep_file
    preprocessed_source
    CMAKE_CXX_COMPILER
    object
  )
    string(TOUPPER <${var}> placeholder)
    string(REPLACE ${placeholder} "${${var}}" scan "${scan}")
  endforeach()

  if(MSVC)
    file(WRITE "${MAUD_DIR}/scan.bat" "${scan}")
  else()
    file(WRITE "${MAUD_DIR}/scan" "${scan}")
    file(
      CHMOD "${MAUD_DIR}/scan"
      FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
    )
  endif()

  if(scan MATCHES "<[A-Z_]+>")
    message(FATAL_ERROR "CMAKE_CXX_SCANDEP_SOURCE expansion incomplete!")
  endif()
endfunction()


function(_maud_include_directories)
  glob(_MAUD_INCLUDE_DIRS CONFIGURE_DEPENDS "(/|^)include$")
  foreach(include_dir ${_MAUD_INCLUDE_DIRS})
    message(VERBOSE "Detected include directory: ${include_dir}")
    include_directories("${include_dir}")
  endforeach()
endfunction()


function(_maud_cxx_sources)
  if(NOT CMAKE_CXX_STANDARD)
    set(CMAKE_CXX_STANDARD 20)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
  elseif(CMAKE_CXX_STANDARD LESS 20)
    message(STATUS "Building with modules requires at least C++20, however")
    message(STATUS "  this project is configured for C++${CMAKE_CXX_STANDARD}.")
    message(STATUS "  Abandoning automatic target scanning...")
    return()
  endif()

  glob(
    MAUD_CXX_MODULE_SOURCES
    CONFIGURE_DEPENDS
    "[.](cxxm?|cppm?|ccm?|c[+][+]m?|ixx|mxx)$"
  )

  _maud_write_scan_script()
  set(input)
  foreach(source_file ${MAUD_CXX_MODULE_SOURCES})
    _maud_get_ddi_path("${source_file}" ddi)
    cmake_path(REMOVE_EXTENSION ddi LAST_ONLY OUTPUT_VARIABLE obj_path)
    get_source_file_property(
      flags
      "${source_file}"
      MAUD_PREPROCESSING_SCAN_OPTIONS
    )
    if(NOT flags)
      set(flags)
    else()
      list(JOIN flags " " flags)
    endif()
    file(WRITE "${obj_path}.flags" "${flags}\n")

    cmake_path(REMOVE_EXTENSION obj_path LAST_ONLY OUTPUT_VARIABLE ddi_stem)
    string(APPEND input "${source_file};${ddi_stem}\n")
  endforeach()

  file(WRITE "${MAUD_DIR}/scan_input.list" "${input}")
  execute_process(
    COMMAND "${MAUD_DIR}/scan" "${MAUD_DIR}/scan_input.list"
    OUTPUT_FILE "${MAUD_DIR}/scan_input.list.log"
    COMMAND_ERROR_IS_FATAL ANY
  )
  foreach(source_file ${MAUD_CXX_MODULE_SOURCES})
    _maud_scan("${source_file}")
  endforeach()
endfunction()


function(_maud_setup_clang_format)
  set(config "")
  if(EXISTS "${CMAKE_SOURCE_DIR}/.clang-format")
    file(READ "${CMAKE_SOURCE_DIR}/.clang-format" config)
  endif()

  set_property(
    DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS 
    "${CMAKE_SOURCE_DIR}/.clang-format"
  )

  if(config MATCHES "# Version: ([0-9]+)")
    string(version "${CMAKE_MATCH_1}")
  else()
    message(
      VERBOSE
      "Couldn't read required clang-format version"
      "\n--   add a comment to ${CMAKE_SOURCE_DIR}/.clang-format"
      "\n--   like # Version: 18"
    )
    return()
  endif()

  function(_maud_clang_format_validator out_var candidate)
    execute_process(COMMAND "${candidate}" --version OUTPUT_VARIABLE candidate)
    if(candidate MATCHES [[^clang-format version ([0-9]+)]])
      if(${CMAKE_MATCH_1} EQUAL ${version})
        return()
      endif()
    endif()
    set(out_var FALSE PARENT_SCOPE)
  endfunction()

  find_program(
    CLANG_FORMAT_COMMAND
    NAMES clang-format clang-format-${version}
    VALIDATOR _maud_clang_format_validator
  )
  if(CLANG_FORMAT_COMMAND)
    glob(
      MAUD_CXX_FORMATTED_SOURCES
      EXCLUDE_RENDERED
      CONFIGURE_DEPENDS
      "[.]([ch]xxm?|[ch]ppm?|ccm?|hh|[ch][+][+]m?|ixx|mxx|h)$"
    )
    list(JOIN MAUD_CXX_FORMATTED_SOURCES "\n" formatted_files)
    file(WRITE "${MAUD_DIR}/formatted_files.list" "${formatted_files}\n")
    add_test(
      NAME check.clang-formatted
      COMMAND "${CLANG_FORMAT_COMMAND}"
        --dry-run -Werror "--files=${MAUD_DIR}/formatted_files.list"
      WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
    )
    add_custom_target(
      fix.clang-format
      COMMAND "${CLANG_FORMAT_COMMAND}" -i "--files=${MAUD_DIR}/formatted_files.list"
      WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
    )
  else()
    message(VERBOSE "Could not find clang-format program with version ${version}")
  endif()
endfunction()


function(math_assign var)
  list(JOIN ARGN " " half_expr)
  math(EXPR result "${${var}} ${half_expr}")
  set(${var} ${result} PARENT_SCOPE)
endfunction()


function(_maud_scan source_file)
  # TODO I'd like the scanning to be multithreaded for speed.
  # This is pretty easy since execute_process with multiple
  # COMMANDS runs them all as a pipeline (with single shared
  # stderr). Therefore all we really need is a cross platform
  # `nproc` to find out how many commands we want and a
  # `-P DoScan.cmake` which receives a subset of the files to
  # scan.
  message(VERBOSE "scanning ${source_file}")

  _maud_get_ddi_path("${source_file}" ddi)
  file(READ "${ddi}" ddi)

  # collect all imports
  json_list(imports "${ddi}" ERROR_VARIABLE error rules 0 requires [] logical-name)
  if(NOT imports)
    set(imports)
  endif()
  message(VERBOSE "  imports ${imports}")

  string(JSON module ERROR_VARIABLE error GET "${ddi}" rules 0 _maud_module-name)
  if(NOT error)
    message(FATAL_ERROR "FIXME not yet supported")
    list(REMOVE_ITEM imports "${module}")
  else()
    set(module "")
  endif()

  string(JSON provides ERROR_VARIABLE error GET "${ddi}" rules 0 provides 0)
  if(NOT error)
    string(JSON logical-name GET ${provides} logical-name)
    string(JSON is-interface GET ${provides} is-interface)
    if(logical-name MATCHES "(.+):(.+)")
      set(module ${CMAKE_MATCH_1})
      set(partition ${CMAKE_MATCH_2})
    else()
      set(module ${logical-name})
      set(partition "")
    endif()

    if(is-interface)
      set(type INTERFACE)
    else()
      set(type PROVIDER)
    endif()
  else()
    set(is-interface OFF)
  endif()

  if(module AND NOT type)
    set(type IMPLEMENTATION)
  endif()

  # set properties for later introspection
  set_source_files_properties(
    ${source_file}
    PROPERTIES
    MAUD_IMPORTS "${imports}"
    MAUD_TYPE "${type}"
    MAUD_MODULE "${module}"
    MAUD_PARTITION "${partition}"
    MAUD_IS_INTERFACE ${is-interface}
  )

  if("executable" IN_LIST imports)
    message(VERBOSE "  executable")
    cmake_path(GET source_file STEM target_name)
    if(NOT TARGET ${target_name})
      add_executable(${target_name})
      message(VERBOSE "  creating executable ${target_name}")
    endif()
  elseif("test_" IN_LIST imports OR module STREQUAL "test_")
    message(VERBOSE "  unit test")
    if(NOT BUILD_TESTING)
      message(VERBOSE "  Testing disabled, ORPHANED")
      return()
    endif()
    if(COMMAND "maud_add_test")
      maud_add_test("${source_file}" target_name)
    else()
      _maud_add_test("${source_file}" target_name)
    endif()
  endif()

  if(module)
    message(VERBOSE "  module ${type} ${module}:${partition}")
    if(NOT target_name)
      set(target_name ${module})
    endif()

    if(NOT TARGET ${target_name})
      if(module MATCHES "^.*_$")
        add_library(${target_name} OBJECT)
        message(VERBOSE "  creating internal library ${target_name}")
      else()
        add_library(${target_name})
        message(VERBOSE "  creating library ${target_name}")
      endif()
    endif()
  endif()

  if(NOT TARGET "${target_name}")
    message(VERBOSE "  not automatically associated with any target")
    return()
  endif()
  message(VERBOSE "  attaching to ${target_name}")

  set_property(TARGET ${target_name} APPEND PROPERTY MAUD_IMPORTS "${imports}")
  if(is-interface)
    set_property(
      TARGET ${target_name} APPEND PROPERTY MAUD_INTERFACE_IMPORTS "${imports}"
    )
  endif()
  set_target_properties(
    ${target_name}
    PROPERTIES
    MAUD_SCANNED ON
    MAUD_MODULE "${module}"
  )
  target_compile_features(
    ${target_name}
    PUBLIC
    cxx_std_${CMAKE_CXX_STANDARD}
  )

  # attach sources
  if(type STREQUAL "INTERFACE" OR type STREQUAL "PROVIDER")
    if(type STREQUAL "INTERFACE")
      set(file_set PUBLIC FILE_SET module_interfaces)
    else()
      set(file_set PRIVATE FILE_SET module_providers)
    endif()
    target_sources(
      ${target_name}
      ${file_set}
      TYPE CXX_MODULES
      BASE_DIRS ${_MAUD_BASE_DIRS}
      FILES "${source_file}"
    )
  else()
    target_sources(${target_name} PRIVATE "${source_file}")
  endif()

  if(type STREQUAL "INTERFACE")
    set(internal_imports "${imports}")
    list(FILTER internal_imports INCLUDE REGEX "_$")
    # Every module imported by an interface must also be installed, so
    # ensure that no internal modules were imported here.
    if(internal_imports)
      message(
        FATAL_ERROR
        "${source_file} is an interface for an installed target but imports ${internal_imports}"
      )
    endif()

    if(partition)
      set_property(
        TARGET ${target_name}
        APPEND PROPERTY
        MAUD_INTERFACE_PARTITIONS "${partition}"
      )
    else()
      set_target_properties(
        ${target_name}
        PROPERTIES
        MAUD_INTERFACE "${source_file}"
      )
    endif()
  endif()
endfunction()


function(_maud_add_test source_file out_target_name)
  get_source_file_property(partition "${source_file}" MAUD_PARTITION)

  if(partition STREQUAL "main")
    if(_MAUD_TEST_MAIN)
      message(
        FATAL_ERROR
        "
    Only one definition of test_:main is supported, but got
        ${source_file}
        ${_MAUD_TEST_MAIN}
        "
      )
    endif()
    set(_MAUD_TEST_MAIN "${source_file}" CACHE INTERNAL "" FORCE)
    return()
  endif()

  cmake_path(GET source_file STEM name)
  set(${out_target_name} "test_.${name}" PARENT_SCOPE)

  if(NOT TARGET "test_.${name}")
    add_executable(test_.${name})
  endif()
  add_test(NAME test_.${name} COMMAND $<TARGET_FILE:test_.${name}> --gtest_brief=1)
  target_sources(
    test_.${name}
    PUBLIC FILE_SET module_interfaces
    TYPE CXX_MODULES
    ${_MAUD_BASE_DIRS}
    FILES "${_MAUD_SELF_DIR}/test_.cxx"
  )
  set_property(
    TARGET test_.${name}
    APPEND PROPERTY
    COMPILE_OPTIONS "${_MAUD_INCLUDE} \"${_MAUD_SELF_DIR}/test_.hxx\""
  )
endfunction()


function(_maud_finalize_import target access import)
  if(TARGET ${import})
    target_link_libraries(${target} ${access} ${import})
    return()
  endif()

  if(import MATCHES "^(.*)::(.*)$")
    set(args "${CMAKE_MATCH_1}")
  else()
    set(args "${import}.maud" CONFIG)
  endif()
  find_package(${args})

  if(NOT TARGET ${import})
    message(
      FATAL_ERROR
      "find_package(${args}) did not produce TARGET ${import} required by ${target}"
    )
  endif()
  target_link_libraries(${target} ${access} ${import})

  get_target_property(transitive_imports ${import} INTERFACE_LINK_LIBRARIES)
  if(transitive_imports)
    foreach(import ${transitive_imports})
      _maud_finalize_import(${target} ${access} ${import})
    endforeach()
  endif()
endfunction()


function(_maud_finalize_targets)
  include(GNUInstallDirs)
  message(STATUS "TARGETS:")
  get_property(
    targets
    DIRECTORY .
    PROPERTY BUILDSYSTEM_TARGETS
  )
  foreach(target ${targets})
    if(target MATCHES "^_maud")
      continue()
    endif()

    get_target_property(target_type ${target} TYPE)
    if(target_type STREQUAL "UTILITY")
      continue()
    endif()

    message(STATUS "${target}: ${target_type}")
    get_target_property(scanned ${target} MAUD_SCANNED)
    if(NOT scanned)
      message(VERBOSE "  NOT A MAUD TARGET")
      continue()
    endif()

    get_target_property(imports ${target} MAUD_IMPORTS)
    get_target_property(interface_imports ${target} MAUD_INTERFACE_IMPORTS)
    if(NOT imports)
      set(imports "")
    endif()
    get_target_property(module ${target} MAUD_MODULE)
    if(module AND target_type STREQUAL "EXECUTABLE")
      list(APPEND imports "${module}")
    endif()
    message(VERBOSE "  IMPORTS: ${imports}")

    # Link targets to imported modules
    list(FILTER imports EXCLUDE REGEX ":")
    list(FILTER interface_imports EXCLUDE REGEX ":")
    foreach(import ${imports})
      if(NOT import MATCHES "^(${target}|executable|test_)$")
        if(import IN_LIST interface_imports)
          _maud_finalize_import(${target} PUBLIC ${import})
        else()
          _maud_finalize_import(${target} PRIVATE ${import})
        endif()
      endif()
    endforeach()

    get_target_property(interface ${target} MAUD_INTERFACE)
    if(NOT interface AND NOT TEST ${target})
      if(target_type STREQUAL "EXECUTABLE")
        set(access PRIVATE)
        set(interface "${_MAUD_SELF_DIR}/executable.cxx")
      else()
        set(access PUBLIC)
        set(interface "${MAUD_DIR}/injected/${target}.cxx")
        message(VERBOSE "  No primary interface supplied, injecting ${interface}")

        get_target_property(src ${target} MAUD_INTERFACE_PARTITIONS)
        list(TRANSFORM src PREPEND "\nexport import :")
        list(PREPEND src "export module ${target}")
        file(WRITE "${interface}" "${src};\n")
        set_source_files_properties("${interface}" PROPERTIES MAUD_TYPE INTERFACE)
      endif()
      target_sources(
        ${target}
        ${access} FILE_SET module_interfaces
        TYPE CXX_MODULES
        ${_MAUD_BASE_DIRS}
        FILES "${interface}"
      )
    endif()

    print_target_sources(${target})

    if(TEST ${target} AND NOT COMMAND "maud_add_test")
      if(_MAUD_TEST_MAIN)
        set(test_main "${_MAUD_TEST_MAIN}")
        target_link_libraries(${target} PRIVATE GTest::gtest)
      else()
        set(test_main "${_MAUD_SELF_DIR}/test_main_.cxx")
        target_link_libraries(${target} PRIVATE GTest::gtest_main)
      endif()

      target_sources(
        ${target}
        PUBLIC FILE_SET module_interfaces
        TYPE CXX_MODULES
        BASE_DIRS ${_MAUD_BASE_DIRS}
        FILES "${test_main}"
      )
      continue()
    endif()

    target_compile_options(
      ${target} PRIVATE
      "$<BUILD_INTERFACE:${_MAUD_INCLUDE} \"${MAUD_DIR}/options.h\">"
    )

    if(target MATCHES _$)
      continue()
    endif()

    if(target_type STREQUAL "EXECUTABLE")
      install(
        TARGETS ${target}
        EXPORT ${target}
        DESTINATION "${CMAKE_INSTALL_BINDIR}"
        CXX_MODULES_BMI
        DESTINATION "${MAUD_DIR}/junk/${target}"
      )
      continue()
    endif()

    set(module_dir "${CMAKE_INSTALL_LIBDIR}/module_interface/${target}")

    install(
      TARGETS ${target}
      EXPORT ${target}
      DESTINATION "${CMAKE_INSTALL_LIBDIR}"
      FILE_SET module_interfaces
      DESTINATION "${module_dir}"
      CXX_MODULES_BMI
      DESTINATION "${module_dir}/${CMAKE_CXX_COMPILER_ID}.bmi"
    )

    set(installed_options "${_MAUD_INCLUDE} \"\${_IMPORT_PREFIX}/${module_dir}/options.h\"")
    target_compile_options(${target} PRIVATE "$<INSTALL_INTERFACE:${installed_options}>")
    install(FILES "${MAUD_DIR}/options.h" DESTINATION "${module_dir}")

    install(
      EXPORT ${target}
      DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake"
      FILE ${target}.maud-config.cmake
    )
  endforeach()

  get_directory_property(tests TESTS)
  _maud_set(_MAUD_TESTS "${tests}")
endfunction()


function(_maud_diff_sets old new out_added out_removed)
  set(added "${new}")
  list(REMOVE_ITEM added ${old})
  set(removed "${old}")
  list(REMOVE_ITEM removed ${new})
  set(${out_added} "${added}" PARENT_SCOPE)
  set(${out_removed} "${removed}" PARENT_SCOPE)
endfunction()


function(_maud_print_glob_changes old new)
  if(CMAKE_MESSAGE_LOG_LEVEL MATCHES "ERROR|WARNING|NOTICE|STATUS")
    return()
  endif()
  _maud_diff_sets("${old}" "${new}" added removed)
  list(TRANSFORM added PREPEND "ADD ")
  list(TRANSFORM removed PREPEND "REMOVE ")
  foreach(change ${added} ${removed})
    message(VERBOSE "  ${change}")
  endforeach()
endfunction()


function(_maud_maybe_regenerate)
  set(total_set_changed FALSE)

  _maud_glob(all "${CMAKE_SOURCE_DIR}")
  if(NOT "${all}" STREQUAL "${_MAUD_ALL}")
    message(VERBOSE "change to _MAUD_ALL detected")
    _maud_print_glob_changes("${_MAUD_ALL}" "${all}")

    set(total_set_changed TRUE)
    _maud_set(_MAUD_ALL "${all}")
    file(WRITE "${MAUD_DIR}/cache_updates/_MAUD_ALL" "${all}")
  endif()

  _maud_glob(all "${MAUD_DIR}/rendered")
  if(NOT "${all}" STREQUAL "${_MAUD_ALL_GENERATED}")
    message(VERBOSE "change to _MAUD_ALL_GENERATED detected")
    _maud_print_glob_changes("${_MAUD_ALL_GENERATED}" "${all}")

    set(total_set_changed TRUE)
    _maud_set(_MAUD_ALL_GENERATED "${all}")
    file(WRITE "${MAUD_DIR}/cache_updates/_MAUD_ALL_GENERATED" "${all}")
  endif()

  unset(all)

  set(glob_mismatch OFF)
  if(NOT total_set_changed)
    message(VERBOSE "total file set is unchanged, skipping glob verification")
  else()
    foreach(glob ${_MAUD_GLOBS})
      message(VERBOSE "checking for different matches to: ${_MAUD_GLOB_ARGUMENTS_${glob}}")
      set(old "${${glob}}")
      unset(${glob} CACHE)
      glob(${glob} ${_MAUD_GLOB_ARGUMENTS_${glob}})

      if("${old}" STREQUAL "${${glob}}")
        continue()
      endif()

      message(STATUS "change in glob ${glob} detected")
      _maud_print_glob_changes("${old}" "${${glob}}")
      file(WRITE "${MAUD_DIR}/cache_updates/${glob}" "${${glob}}")
      _maud_set(${glob} "${${glob}}")

      if("CONFIGURE_DEPENDS" IN_LIST _MAUD_GLOB_ARGUMENTS_${glob})
        set(glob_mismatch ON)
        message(STATUS "  will regenerate")
      endif()
    endforeach()

    unset(old)
  endif()

  if(glob_mismatch)
    file(TOUCH_NOCREATE "${CMAKE_BINARY_DIR}/CMakeFiles/cmake.verify_globs")
    return()
  endif()

  if(NOT MAUD_CXX_MODULE_SOURCES)
    return()
  endif()

  set(input)
  foreach(source_file ${MAUD_CXX_MODULE_SOURCES})
    _maud_get_ddi_path("${source_file}" ddi)
    if("${ddi}" IS_NEWER_THAN "${source_file}")
      message(VERBOSE "skipping rescan of ${source_file}")
      continue()
    endif()
    message(VERBOSE "rescanning ${source_file}")
    cmake_path(REMOVE_EXTENSION ddi LAST_ONLY OUTPUT_VARIABLE obj_path)
    cmake_path(REMOVE_EXTENSION obj_path LAST_ONLY OUTPUT_VARIABLE ddi_stem)
    string(APPEND input "${source_file};${ddi_stem}\n")
  endforeach()

  file(WRITE "${MAUD_DIR}/rescan_input.list" "${input}")
  execute_process(
    COMMAND "${MAUD_DIR}/scan" "${MAUD_DIR}/rescan_input.list" .new
    OUTPUT_FILE "${MAUD_DIR}/rescan_input.list.log"
    COMMAND_ERROR_IS_FATAL ANY
  )

  foreach(source_file ${MAUD_CXX_MODULE_SOURCES})
    _maud_get_ddi_path("${source_file}" ddi)
    if("${ddi}" IS_NEWER_THAN "${source_file}")
      message(VERBOSE "skipping rescan of ${source_file}")
      continue()
    endif()

    file(READ "${ddi}" old_ddi)
    file(READ "${ddi}.new" new_ddi)
    string(COMPARE NOTEQUAL "${old_ddi}" "${new_ddi}" equal)
    if(equal)
      message(STATUS "change detected\n  will regenerate")
      message(VERBOSE "  BEFORE=${old_ddi}\n   AFTER=${new_ddi}")
      file(TOUCH_NOCREATE "${CMAKE_BINARY_DIR}/CMakeFiles/cmake.verify_globs")
    endif()

    file(REMOVE "${ddi}.new")
    file(TOUCH "${ddi}")
  endforeach()
endfunction()


function(_maud_setup_regenerate)
  if("${_MAUD_INJECT_REGENERATE}" STREQUAL "")
    find_program(_MAUD_INJECT_REGENERATE maud_inject_regenerate REQUIRED)
  endif()

  if(WIN32)
    file(
      WRITE "${MAUD_DIR}/inject.bat"
      "@ECHO OFF\r\n"
      "start /b \"${_MAUD_INJECT_REGENERATE}\" \"${CMAKE_BINARY_DIR}\"\r\n"
    )
    set(command "${MAUD_DIR}/inject.bat")
  else()
    find_program(_MAUD_SETSID setsid REQUIRED)
    mark_as_advanced(_MAUD_SETSID)
    set(
      command
      "${_MAUD_SETSID}" --fork
      "${_MAUD_INJECT_REGENERATE}" "${CMAKE_BINARY_DIR}"
    )
  endif()

  if(EXISTS "${MAUD_DIR}/maud_inject_regenerate.error")
    file(REMOVE "${MAUD_DIR}/maud_inject_regenerate.error")
    message(WARNING "Maud failed to inject regeneration patch")
    file(READ "${MAUD_DIR}/maud_inject_regenerate.log" log)
    message(VERBOSE "  log: '\n${log}'")
  endif()

  execute_process(
    COMMAND ${command}
    OUTPUT_FILE "${MAUD_DIR}/maud_inject_regenerate.log"
    ERROR_FILE "${MAUD_DIR}/maud_inject_regenerate.log"
    COMMAND_ERROR_IS_FATAL ANY
  )
  # GLOB once to ensure VerifyGlobs will be generated.
  # This also ensures that if injection fails we will
  # regenerate anyway (because a new .error file will be
  # detected), report the error in the block above, and try again.
  file(GLOB _ CONFIGURE_DEPENDS "${MAUD_DIR}/maud_inject_regenerate.error")
endfunction()


function(_maud_load_cache build_dir)
  # Script mode doesn't load CMakeCache.txt, so when cache is required
  # load those variables from the cmake file api.

  # Unset vars which are just CWD in script mode.
  unset(CMAKE_SOURCE_DIR PARENT_SCOPE)
  unset(CMAKE_BINARY_DIR PARENT_SCOPE)

  file(GLOB index "${build_dir}/.cmake/api/v1/reply/index-*.json")
  if(NOT index OR index MATCHES ";")
    message(FATAL_ERROR "expected single index file, got '${index}'")
  endif()
  file(READ "${index}" index)

  string(JSON cache GET "${index}" reply cache-v2 jsonFile)
  file(READ "${build_dir}/.cmake/api/v1/reply/${cache}" cache)
  json_list(cache "${cache}" entries [])

  foreach(entry ${cache}})
    string(JSON name GET "${entry}" name)
    string(JSON type GET "${entry}" type)
    string(JSON value GET "${entry}" value)
    set(${name} "${value}" CACHE ${type} "" FORCE)

    json_list(names "${entry}" properties [] name)
    json_list(values "${entry}" properties [] value)
    foreach(n v IN ZIP_LISTS names values)
      if(n STREQUAL "MODIFIED")
        continue()
      endif()
      set_property(CACHE ${name} PROPERTY ${n} "${v}")
    endforeach()
  endforeach()
endfunction()


function(_maud_load_cache_updates)
  _maud_glob(updates "${MAUD_DIR}/cache_updates")
  foreach(var ${updates})
    file(READ "${MAUD_DIR}/cache_updates/${var}" val)
    _maud_set(${var} "${val}")
  endforeach()
endfunction()


function(_maud_eval)
  if(DEFINED MAUD_CODE)
    cmake_language(EVAL CODE "${MAUD_CODE}")
    return()
  endif()

  _maud_set(_MAUD_DO_EVAL OFF)
  foreach(i RANGE ${CMAKE_ARGC})
    set(arg "${CMAKE_ARGV${i}}")
    if("${arg}" STREQUAL "--")
      _maud_set(_MAUD_DO_EVAL ON)
      continue()
    endif()
    if(_MAUD_DO_EVAL)
      cmake_language(EVAL CODE "${arg}")
    endif()
  endforeach()
endfunction()


function(_maud_setup)
  cmake_file_api(QUERY API_VERSION 1 CACHE 2.0)
  _maud_set(CMAKE_SOURCE_DIR "${CMAKE_SOURCE_DIR}")
  _maud_set(CMAKE_BINARY_DIR "${CMAKE_BINARY_DIR}")
  _maud_set(PROJECT_NAME "${PROJECT_NAME}")
  _maud_set(MAUD_DIR "${CMAKE_BINARY_DIR}/_maud")

  if(NOT EXISTS "${CMAKE_BINARY_DIR}/CMakeCache.txt")
    set(_MAUD_FRESH ON PARENT_SCOPE)
  else()
    set(_MAUD_FRESH OFF PARENT_SCOPE)
  endif()

  if(_MAUD_FRESH AND NOT "$ENV{MAUD_DISABLE_ENVIRONMENT_OPTIONS}")
    set(_MAUD_ENV_OPTIONS ON PARENT_SCOPE)
  else()
    set(_MAUD_ENV_OPTIONS OFF PARENT_SCOPE)
  endif()

  # I'd like to use CMAKE_INCLUDE_FLAG_CXX but I need
  # to be able to resolve genexprs first
  if(MSVC)
    _maud_set(_MAUD_INCLUDE "SHELL: /Fi")
    _maud_set(_MAUD_INCLUDE_DIR "/I")
    _maud_set(_MAUD_DEFINE "/D")
  else()
    _maud_set(_MAUD_INCLUDE "SHELL: -include")
    _maud_set(_MAUD_INCLUDE_DIR "-I")
    _maud_set(_MAUD_DEFINE "-D")
  endif()
  _maud_set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

  if(NOT _MAUD_FRESH)
    _maud_load_cache_updates()
  endif()
  file(REMOVE_RECURSE "${MAUD_DIR}/cache_updates")
  unset(_MAUD_ALL_OPTIONS CACHE)
  unset(_MAUD_ALL_OPTIONS_RESOLVED CACHE)

  if(NOT DEFINED _MAUD_ALL)
    _maud_glob(_MAUD_ALL "${CMAKE_SOURCE_DIR}")
    _maud_set(_MAUD_ALL ${_MAUD_ALL})
  endif()

  file(REMOVE "${CMAKE_BINARY_DIR}/CMakeFiles/VerifyGlobs.cmake")

  file(
    WRITE "${MAUD_DIR}/eval.cmake"
    "
    include(\"${_MAUD_SELF_DIR}/Maud.cmake\")
    _maud_load_cache(\"${CMAKE_BINARY_DIR}\")
    _maud_load_cache_updates()
    _maud_eval()
    "
  )
  file(WRITE "${CMAKE_BINARY_DIR}/.gitignore" "*")

  file(MAKE_DIRECTORY "${MAUD_DIR}/junk" "${MAUD_DIR}/rendered")
  file(WRITE "${MAUD_DIR}/options.h" "")

  cmake_path(IS_PREFIX CMAKE_SOURCE_DIR "${CMAKE_BINARY_DIR}" is_prefix)
  cmake_path(GET CMAKE_BINARY_DIR FILENAME build)
  if(is_prefix AND NOT build MATCHES "^[.]")
    message(
      FATAL_ERROR
      "Build directory is not excluded from CMAKE_SOURCE_DIR globs: rename to .build"
    )
  endif()

  set_source_files_properties(
    "${_MAUD_SELF_DIR}/executable.cxx"
    "${_MAUD_SELF_DIR}/test_.cxx"
    "${_MAUD_SELF_DIR}/test_main_.cxx"
    PROPERTIES
    MAUD_TYPE INTERFACE
  )

  # Assemble the minimal list of FILE_SET BASE_DIRS
  set(base_dirs "${CMAKE_SOURCE_DIR};${MAUD_DIR};${_MAUD_SELF_DIR}")
  foreach(base_dir ${base_dirs})
    foreach(other_dir ${base_dirs})
      if(base_dir STREQUAL other_dir)
        continue()
      endif()

      cmake_path(IS_PREFIX base_dir "${other_dir}" is_prefix)
      if(is_prefix)
        list(REMOVE_ITEM base_dirs "${other_dir}")
      endif()
    endforeach()
  endforeach()
  set(_MAUD_BASE_DIRS BASE_DIRS ${base_dirs} PARENT_SCOPE)

  option(
    BUILD_SHARED_LIBS
    BOOL "Build shared libraries by default."
    DEFAULT OFF
  )

  cmake_language(GET_MESSAGE_LOG_LEVEL level)
  option(
    CMAKE_MESSAGE_LOG_LEVEL
    ENUM ERROR WARNING NOTICE STATUS VERBOSE DEBUG TRACE
      "Log level for the message() comand."
    DEFAULT "${level}"
    MARK_AS_ADVANCED
  )

  set(valid0 html dirhtml singlehtml htmlhelp qthelp devhelp applehelp epub)
  set(valid1 latex texinfo man text gettext doctest xml pseudoxml linkcheck)
  _maud_set(_MAUD_VALID_SPHINX_BUILDERS ${valid0} ${valid1})
  option(
    SPHINX_BUILDERS
    STRING "
    A ;-list of builders which will be used with Sphinx.
    Valid builders are:
    ${valid0};
    ${valid1}
    "
    DEFAULT "dirhtml"
    VALIDATE CODE "
      set(invalid \"\${SPHINX_BUILDERS}\")
      list(REMOVE_ITEM invalid ${_MAUD_VALID_SPHINX_BUILDERS})
      if(invalid)
        message(
          FATAL_ERROR
          \"
          SPHINX_BUILDERS included \${invalid}
          valid entries are ${_MAUD_VALID_SPHINX_BUILDERS}
          \"
        )
      endif()
    "
  )
endfunction()


function(_maud_finalize_generated)
  if(DEFINED _MAUD_ALL_GENERATED)
    return()
  endif()

  _maud_glob(_MAUD_ALL_GENERATED "${MAUD_DIR}/rendered")
  _maud_set(_MAUD_ALL_GENERATED ${_MAUD_ALL_GENERATED})

  foreach(glob ${_MAUD_GLOBS})
    set(patterns "${_MAUD_GLOB_ARGUMENTS_${glob}}")
    if("EXCLUDE_RENDERED" IN_LIST patterns)
      continue()
    endif()
    list(REMOVE_ITEM patterns CONFIGURE_DEPENDS)
    set(gen_matches "${_MAUD_ALL_GENERATED}")
    _maud_filter(gen_matches ${patterns})
    list(TRANSFORM gen_matches PREPEND "${MAUD_DIR}/rendered/")
    list(APPEND ${glob} ${gen_matches})
    _maud_set(${glob} "${${glob}}")
  endforeach()
endfunction()


function(_maud_cmake_modules)
  # TODO this really only needs a single call to glob(), from which we
  # can extract the auto-included and module dirs.
  glob(_MAUD_CMAKE_MODULE_DIRS CONFIGURE_DEPENDS EXCLUDE_RENDERED "(/|^)cmake_modules$")
  foreach(module_dir ${_MAUD_CMAKE_MODULE_DIRS})
    list(APPEND CMAKE_MODULE_PATH "${module_dir}")
    message(STATUS "Detected CMake module directory: ${module_dir}")
  endforeach()
  list(REMOVE_DUPLICATES CMAKE_MODULE_PATH)
  _maud_set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}")

  glob(
    _MAUD_CMAKE_MODULES
    CONFIGURE_DEPENDS
    EXCLUDE_RENDERED
    "[.]cmake$"
    "!(/|^)cmake_modules/"
  )
endfunction()


function(_maud_in2)
  glob(_MAUD_IN2_TEMPLATES CONFIGURE_DEPENDS EXCLUDE_RENDERED "[.]in2$")
  if(NOT _MAUD_IN2_TEMPLATES)
    return()
  endif()

  if(NOT _MAUD_IN2)
    find_program(_MAUD_IN2 maud_in2 REQUIRED)
  endif()

  foreach(template ${_MAUD_IN2_TEMPLATES})
    cmake_path(GET template PARENT_PATH dir)
    cmake_path(GET template STEM LAST_ONLY stem)
    cmake_path(
      RELATIVE_PATH dir
      BASE_DIRECTORY "${CMAKE_SOURCE_DIR}"
      OUTPUT_VARIABLE relative_dir
    )

    set(compiled "${MAUD_DIR}/compiled_templates/${relative_dir}/${stem}.in2.cmake")
    set(RENDER_FILE "${MAUD_DIR}/rendered/${relative_dir}/${stem}")
    _maud_render_in2()
  endforeach()
endfunction()


function(_maud_render_in2)
  file(WRITE "${compiled}" "")
  file(WRITE "${RENDER_FILE}" "")

  execute_process(
    COMMAND "${_MAUD_IN2}"
    INPUT_FILE "${template}"
    OUTPUT_FILE "${compiled}"
    COMMAND_ERROR_IS_FATAL ANY
  )

  include("${compiled}")
endfunction()


function(maud_venv dir out_name_prefix)
  set(${out_name_prefix}python "" PARENT_SCOPE)
  set(${out_name_prefix}pip_install "" PARENT_SCOPE)

  find_package(Python3)
  if(NOT TARGET Python3::Interpreter)
    message(VERBOSE "Could not find Python3, can't create venv ${dir}")
    return()
  endif()

  execute_process(COMMAND "${Python3_EXECUTABLE}" -m venv "${dir}")

  find_program(
    python python REQUIRED NO_CACHE
    NO_DEFAULT_PATH PATHS "${dir}/bin" "${dir}/Scripts"
  )
  set(${out_name_prefix}python "${python}" PARENT_SCOPE)
  set(
    ${out_name_prefix}pip_install

    "${python}" -m
    pip install
    --isolated
    --require-virtualenv
    --ignore-installed
    --disable-pip-version-check
    --no-input
    --quiet
    --log "${dir}/pip.log"
    --report "${dir}/pip.report.json"

    PARENT_SCOPE
  )
endfunction()


function(_maud_setup_doc)
  if(NOT SPHINX_BUILDERS)
    message(VERBOSE "No Sphinx builders enabled, abandoning doc")
    return()
  endif()

  set(doc "${CMAKE_BINARY_DIR}/documentation")

  maud_venv("${doc}/venv" venv-)
  if(NOT venv-python)
    message(WARNING "Could not set up Python3 venv for documentation build.")
    return()
  endif()

  if(DEFINED MAUD_DOCUMENTATION_DIR)
    set(src "${MAUD_DOCUMENTATION_DIR}")
  else()
    set(src "${CMAKE_SOURCE_DIR}")
  endif()
  _maud_set(MAUD_DOCUMENTATION_DIR "${src}")

  if(IS_DIRECTORY "${src}/sphinx_configuration")
    set(conf "${src}/sphinx_configuration")
  else()
    set(conf "${doc}/default_sphinx_configuration")
    file(
      WRITE "${conf}/conf.py"
      "from maud.default_sphinx_configuration import *\n"
    )
  endif()
  # TODO provide TARGET fix.generate_sphinx_configuration which dumps the default

  if(EXISTS "${conf}/requirements.txt")
    set(requirements "${conf}/requirements.txt")
  else()
    set(requirements "${_MAUD_SELF_DIR}/default_sphinx_requirements.txt")
  endif()

  add_custom_command(
    COMMENT "Building virtual env ${doc}/venv for Sphinx"
    DEPENDS "${requirements}"
    OUTPUT "${doc}/venv/pip.log"
    COMMAND
      "${venv-pip_install}"
      --requirement "${requirements}"
      --editable "${_MAUD_SELF_DIR}/trike"
      --editable "${_MAUD_SELF_DIR}/sphinx_adapter"
    COMMAND_EXPAND_LISTS
  )

  # We run sphinx multithreaded. This can pessimize throughput since ninja
  # is probably *also* running `nproc` tasks. If this becomes a problem later,
  # there will need to be an option or some other way to mediate between sphinx
  # and ninja. In the meantime, ensure that at least sphinx isn't trying to build
  # manpages and html at the same time.
  set_property(GLOBAL APPEND PROPERTY JOB_POOLS sphinx_build=1)

  add_custom_target(documentation)
  foreach(builder ${SPHINX_BUILDERS})
    add_custom_target(
      documentation.${builder}
      COMMENT "Building ${builder} with sphinx"
      DEPENDS
        "${doc}/venv/pip.log"
        "${conf}/conf.py"
      COMMAND
        "${venv-python}" -m
        sphinx
        --builder ${builder}
        --conf-dir "${conf}"
        --doctree-dir doctrees
        --jobs auto
        "${src}"
        ${builder}  # each builder gets its own build directory
        > ${builder}.log
      WORKING_DIRECTORY "${doc}"
      JOB_POOL sphinx_build
    )
    add_dependencies(documentation documentation.${builder})
  endforeach()
endfunction()


function(shim_script_as destination script)
  cmake_path(ABSOLUTE_PATH script)

  string(TOLOWER "$ENV{PathExt}" path_ext)
  if(path_ext MATCHES [[(^|;)\.bat($|;)]])
    message(
      VERBOSE
      "Windows cmd.exe detected, shimming ${script} -> ${destination}.bat"
    )
    file(
      WRITE "${destination}.bat"
      "@ECHO OFF\r\n"
      "\"${CMAKE_COMMAND}\" -P \"${script}\" -- %*\r\n"
    )
    return()
  endif()

  _maud_set_shebang()
  file(
    WRITE "${destination}"
    "${_MAUD_SHEBANG}\n"
    "\"${CMAKE_COMMAND}\" -P \"${script}\" -- \"\$@\"\n"
  )
  file(
    CHMOD "${destination}"
    FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
  )
endfunction()


function(_maud_set_shebang)
  if(DEFINED CACHE{_MAUD_SHEBANG})
    return()
  endif()

  find_program(env env NO_CACHE)
  if(env)
    _maud_set(_MAUD_SHEBANG "#!${env} -S sh -e")
    return()
  endif()

  find_program(sh sh NO_CACHE)
  if(NOT sh)
    set(sh "$ENV{SHELL}")
  endif()
  if(sh)
    _maud_set(_MAUD_SHEBANG "#!${sh} -e")
    return()
  endif()

  message(
    FATAL_ERROR
    "Could not infer shim script style, set \$ENV{SHELL}."
  )
endfunction()


function(string_escape str out_var)
  string(JSON escaped_key ERROR_VARIABLE error SET "{}" "${str}" null)
  if(NOT error AND escaped_key MATCHES "\"(.*)\"")
    set(${out_var} "${CMAKE_MATCH_1}" PARENT_SCOPE)
  else()
    message(FATAL_ERROR "Couldn't escape `${str}`")
  endif()
endfunction()


function(string_unescape str out_var)
  string(JSON unescaped ERROR_VARIABLE error MEMBER "{\"${str}\": 0}" 0)
  set(${out_var} "${unescaped}" PARENT_SCOPE)
  if(error)
    message(FATAL_ERROR "Couldn't unescape `${str}`")
  endif()
endfunction()


################################################################################
# options
################################################################################


function(option name type)
  if(DEFINED CACHE{_MAUD_ALL_OPTIONS_RESOLVED})
    message(
      FATAL_ERROR
      "Option declaration for ${name} after all options have been resolved"
    )
  endif()

  cmake_parse_arguments(
    PARSE_ARGV 1
    "" # prefix
    "MARK_AS_ADVANCED;ADD_COMPILE_DEFINITIONS" # options
    "BOOL;PATH;FILEPATH;STRING;DEFAULT" # single value arguments
    "REQUIRES;VALIDATE;ENUM" # multi value arguments
  )

  if(type MATCHES "^(BOOL|PATH|FILEPATH|STRING)$")
    set(help "${_${type}}")
  elseif(type STREQUAL ENUM)
    list(POP_BACK _ENUM help)
    set(type STRING)
  else()
    set(help "${ARGV1}")
    set(type BOOL)
    if(ARGV2 STREQUAL "ON")
      # handle legacy default
      set(_DEFAULT ON)
    endif()
  endif()

  if(DEFINED CACHE{_MAUD_DECLARED_${name}})
    return() # silently ignore duplicate declaration of the same option
  endif()
  _maud_set(_MAUD_DECLARED_${name} ON)
  _maud_set(_MAUD_OPTION_GROUP_${name} "${OPTION_GROUP}")
  _maud_set_include(_MAUD_ALL_OPTIONS ${name})

  if(
    _MAUD_ENV_OPTIONS
    AND DEFINED ENV{${name}}
    AND NOT DEFINED CACHE{${name}}
  )
    # set the option's value from the environment if appropriate
    _maud_set_value_only(${name} "$ENV{${name}}")
  endif()

  if(type MATCHES "PATH")
    # ensure we have native, absolute paths
    if(DEFINED _DEFAULT)
      cmake_path(ABSOLUTE_PATH _DEFAULT)
      cmake_path(NATIVE_PATH _DEFAULT NORMALIZE _DEFAULT)
    endif()
    if(DEFINED CACHE{${name}})
      # PATH options are always coerced to absolute, relative to the working
      # directory of the configuring cmake process.
      cmake_path(NATIVE_PATH ${name} NORMALIZE path)
      cmake_path(ABSOLUTE_PATH path BASE_DIRECTORY "${MAUD_WORKING_DIR}")
      set_property(CACHE ${name} PROPERTY VALUE "${path}")
    endif()
  endif()

  if(
    DEFINED CACHE{${name}}
    AND _MAUD_FRESH
    AND "${_MAUD_CONSTRAINTS_ON_${name}}" STREQUAL ""
  )
    # this is a fresh build and the user has definitely configured this option
    _maud_set(_MAUD_DEFINITELY_USER_${name} "$CACHE{${name}}")
  endif()

  # dedent and escape HELP (set(CACHE) only allows one line)
  string(STRIP "${help}" help)
  string(REGEX REPLACE "(\n *)+" "\n" help "${help}")
  string_escape("${help}" help)

  # store the default
  if("${type}" STREQUAL "BOOL") # coerce BOOL to ON/OFF
    if(_DEFAULT)
      set(_DEFAULT ON)
    else()
      set(_DEFAULT OFF)
    endif()
  elseif(DEFINED _ENUM AND NOT DEFINED _DEFAULT)
    list(GET _ENUM 0 _DEFAULT)
  endif()
  _maud_set(_MAUD_DEFAULT_${name} "${_DEFAULT}")

  # declare the option's cache entry
  set(${name} "${_DEFAULT}" CACHE ${type} "${help}")
  _maud_type_check_option(${name} "${_DEFAULT}")

  if(_MARK_AS_ADVANCED)
    mark_as_advanced(${name})
  endif()

  # store the enumeration of allowed STRING values
  if(DEFINED _ENUM)
    set_property(CACHE ${name} PROPERTY STRINGS "${_ENUM}")
  endif()

  if(DEFINED _VALIDATE)
    string_escape("${_VALIDATE}" _VALIDATE)
    _maud_set(_MAUD_VALIDATE_${name} "${_VALIDATE}")
  endif()

  if(_ADD_COMPILE_DEFINITIONS)
    _maud_set(_MAUD_ADD_COMPILE_DEFINITIONS_${name} ON)
  endif()

  # store requirements for this option
  set(condition ON) # as a special case, `IF ON` is implicit for BOOL options
  while(_REQUIRES)
    list(POP_FRONT _REQUIRES dependency required_value)
    if(type MATCHES "PATH")
      cmake_path(ABSOLUTE_PATH required_value)
      cmake_path(NATIVE_PATH required_value NORMALIZE required_value)
    endif()

    if("${dependency}" STREQUAL "IF")
      # this isn't a requirement, it's the start of a new requirement block
      set(condition "${required_value}")
      continue()
    endif()

    _maud_assert_or_store_requirement(
      ${name} ${condition}
      ${dependency} ${required_value}
    )
  endwhile()
  _maud_watch_option(${name})
endfunction()


function(_maud_assert_or_store_requirement name condition dependency required_value)
  _maud_set_include(_MAUD_MAYBE_CONSTRAINED_BY_${dependency} ${name})
  _maud_set_include(_MAUD_ALL_OPTIONS ${dependency})
  string(SHA512 hash "${dependency}-${name}-${condition}")

  if(NOT DEFINED CACHE{_MAUD_RESOLVED_${name}})
    # Just store the requirement for later;
    # we can't do anything until ${name} is resolved
    _maud_type_check_option(${dependency} "${required_value}")
    _maud_set(_MAUD_REQUIREMENT_${hash} "${required_value}")
    _maud_set_include(_MAUD_RESOLVE_BEFORE_${dependency} ${name})
    _maud_set_include(_MAUD_REQUIREMENTS ${hash})
    _maud_watch_option(${dependency})
    return()
  endif()

  string(SHA512 hash "${dependency}-${name}-$CACHE{${name}}")
  if(NOT DEFINED CACHE{_MAUD_REQUIREMENT_${hash}})
    # ${name} does not place a requirement on ${dependency}
    return()
  endif()
  set(required_value "${_MAUD_REQUIREMENT_${hash}}")
  _maud_type_check_option(${dependency} "${required_value}")

  _maud_set_include(_MAUD_CONSTRAINTS_ON_${dependency} ${name})

  if(NOT DEFINED CACHE{_MAUD_RESOLVED_${dependency}})
    # ${name} is resolved but ${dependency} isn't; apply the requirement
    _maud_set_value_only(${dependency} "${required_value}")
    _maud_set(_MAUD_RESOLVED_${dependency} ON)
    return()
  endif()

  # Both are resolved; assert the requirement
  if("$CACHE{${dependency}}" STREQUAL "${required_value}")
    return()
  endif()

  # ${dependency} did not have the required value; why?
  list(REMOVE_ITEM _MAUD_CONSTRAINTS_ON_${dependency} ${name})
  if("${_MAUD_CONSTRAINTS_ON_${dependency}}" STREQUAL "")
    message(
      FATAL_ERROR
      "
    Option constraint conflict: ${dependency} is constrained
    by ${_MAUD_CONSTRAINTS_ON_${dependency}} to be
      \"$CACHE{${dependency}}\"
    but ${name} requires it to be
      \"${required_value}\"
      "
    )
  else()
    message(
      FATAL_ERROR
      "
    Option constraint conflict: ${dependency} was already resolved to
      \"$CACHE{${dependency}}\"
    but ${name} requires it to be
      \"${required_value}\"
      "
    )
  endif()
endfunction()


function(_maud_type_check_option name value)
  get_property(type CACHE ${name} PROPERTY TYPE)
  get_property(enum CACHE ${name} PROPERTY STRINGS)

  if(enum AND NOT "${value}" IN_LIST enum)
    message(FATAL_ERROR "ENUM option ${name} must be one of ${enum}")
  elseif(
    type STREQUAL "BOOL"
    AND NOT ("${value}" STREQUAL "ON" OR "${value}" STREQUAL "OFF")
  )
    message(FATAL_ERROR "BOOL option ${name} must be ON or OFF")
  endif()
endfunction()


function(_maud_ensure_option_resolved name path)
  if(DEFINED CACHE{_MAUD_RESOLVED_${name}})
    return()
  endif()

  if(name IN_LIST path)
    message(
      FATAL_ERROR
      "
    Cyclic constraint between options
      ${path}
      "
    )
  endif()

  foreach(dependent ${_MAUD_RESOLVE_BEFORE_${name}})
    _maud_ensure_option_resolved(${dependent} "${path};${name}")
    _maud_assert_or_store_requirement(
      ${dependent} $CACHE{${dependent}}
      ${name} ""
    )
  endforeach()
  # whether it was required or not, we consider ${name}'s value resolved now
  _maud_type_check_option(${name} "$CACHE{${name}}")
  _maud_set(_MAUD_RESOLVED_${name} ON)

  get_property(type CACHE ${name} PROPERTY TYPE)
  get_property(enum CACHE ${name} PROPERTY STRINGS)

  if(DEFINED CACHE{_MAUD_VALIDATE_${name}})
    string_unescape("${_MAUD_VALIDATE_${name}}" validate)
    cmake_language(EVAL ${validate})
  endif()

  if(
    DEFINED CACHE{_MAUD_DEFINITELY_USER_${name}}
    AND NOT "${_MAUD_DEFINITELY_USER_${name}}" STREQUAL "$CACHE{${name}}"
  )
    message(WARNING "Detected override of user-provided value for ${name}")
  endif()

  if(NOT DEFINED CACHE{_MAUD_ADD_COMPILE_DEFINITIONS_${name}})
    return()
  endif()

  get_property(help CACHE ${name} PROPERTY HELPSTRING)
  string_unescape("${help}" help)
  string(REPLACE "\n" "\n/// " help "\n${help}")

  if(type STREQUAL "BOOL")
    if($CACHE{${name}})
      file(APPEND "${MAUD_DIR}/options.h" "${help}\n#define ${name} 1\n")
    else()
      file(APPEND "${MAUD_DIR}/options.h" "${help}\n#define ${name} 0\n")
    endif()
  elseif(enum)
    foreach(e ${enum})
      file(APPEND "${MAUD_DIR}/options.h" "${help}\n/// ($CACHE{${name}} of ${enum})")
      if("$CACHE{${name}}" STREQUAL "${e}")
        file(APPEND "${MAUD_DIR}/options.h" "\n#define ${name}_${e} 1\n")
      else()
        file(APPEND "${MAUD_DIR}/options.h" "\n#define ${name}_${e} 0\n")
      endif()
    endforeach()
  else()
    string_escape("$CACHE{${name}}" esc)
    file(APPEND "${MAUD_DIR}/options.h" "${help}\n#define ${name} \"${esc}\"\n")
  endif()
endfunction()


function(_maud_watch_option name)
  if(DEFINED CACHE{_MAUD_WATCHED_${name}})
    return()
  endif()

  function(_maud_option_watcher name access value current_list_file stack)
    if(DEFINED CACHE{_MAUD_ALL_OPTIONS_RESOLVED})
      # Without this global cutoff for variable_watch(), CMake can get caught in an infinite
      # loop. AFAICT, _maud_set() somehow touches a file Ninja is watching, so we generate
      # again... that seems insane, but anyway this cutoff seems to work.
      return()
    endif()
    if(access MATCHES "MODIFIED" AND DEFINED CACHE{_MAUD_RESOLVED_${name}})
      message(
        FATAL_ERROR
        "Manually setting option ${name} whose value is already resolved"
      )
    endif()
    _maud_ensure_option_resolved(${name} "")
  endfunction()

  variable_watch(${name} _maud_option_watcher)
  _maud_set(_MAUD_WATCHED_${name} ON)
endfunction()


function(_maud_resolve_options)
  foreach(name ${_MAUD_ALL_OPTIONS})
    if(NOT DEFINED CACHE{_MAUD_DECLARED_${name}})
      message(
        WARNING
        "
    CACHE variable ${name} was was not declared with option() but was
    constrained by ${_MAUD_CONSTRAINTS_ON_${name}}
        "
      )
    endif()

    _maud_ensure_option_resolved(${name} "")
  endforeach()

  foreach(hash ${_MAUD_REQUIREMENTS})
    unset(_MAUD_REQUIREMENT_${hash} CACHE)
  endforeach()
  unset(_MAUD_REQUIREMENTS CACHE)

  _maud_set(_MAUD_ALL_OPTIONS_RESOLVED TRUE)
endfunction()


function(_maud_options_summary)
  set(cache_json "{}")

  set(group "")
  message(
    STATUS
    "\n"
    "----------------\n"
    "options summary:\n"
    "----------------"
  )
  if(_MAUD_FRESH)
    message(VERBOSE "(fresh build: options can be set from environment variables)")
    message(VERBOSE "(fresh build: explicit user configuration can be detected)")
  else()
    message(VERBOSE "(UNfresh build: options won't be set from environment variables)")
    message(VERBOSE "(UNfresh build: explicit user configuration cannot be detected)")
  endif()

  message(STATUS)
  foreach(name ${_MAUD_ALL_OPTIONS})
    unset(user_value)
    if(DEFINED CACHE{_MAUD_DEFINITELY_USER_${name}})
      set(user_value "${_MAUD_DEFINITELY_USER_${name}}")
      unset(_MAUD_DEFINITELY_USER_${name} CACHE)
      # We can't detect user configuration on non-fresh builds so clear this flag
    endif()

    if(NOT group STREQUAL "${_MAUD_OPTION_GROUP_${name}}")
      set(group "${_MAUD_OPTION_GROUP_${name}}")
      message(STATUS "${group}:")
      message(STATUS)
    endif()

    string_escape("$CACHE{${name}}" quoted)
    set(quoted "\"${quoted}\"")
    string(JSON cache_json SET "${cache_json}" ${name} "${quoted}")

    get_property(advanced CACHE ${name} PROPERTY ADVANCED)
    if(advanced AND "$CACHE{${name}}" STREQUAL "${_MAUD_DEFAULT_${name}}")
      continue() # Don't display defaulted, advanced options in the summary
    endif()

    set(reasons)
    if(DEFINED user_value AND "$CACHE{${name}}" STREQUAL "${user_value}")
      list(APPEND reasons "user configured")
    endif()

    if("$CACHE{${name}}" STREQUAL "${_MAUD_DEFAULT_${name}}")
      list(APPEND reasons "default")
    endif()

    list(JOIN _MAUD_CONSTRAINTS_ON_${name} " " constraints)
    if(constraints)
      list(APPEND reasons "constrained by ${constraints}")
    endif()

    if(
      _MAUD_ENV_OPTIONS
      AND DEFINED ENV{${name}}
      AND "$CACHE{${name}}" STREQUAL "$ENV{${name}}"
    )
      list(APPEND reasons "environment")
    endif()

    if(NOT reasons)
      # User configuration is not always detectable but has low precedence,
      # so if we have not detected anything else then that is what we assume
      # to be responsible for this value.
      set(reasons "user configured")
    endif()

    set(tags "")
    if(advanced)
      string(PREPEND tags "(advanced) ")
    endif()

    get_property(enum CACHE ${name} PROPERTY STRINGS)
    if(enum)
      string(PREPEND tags "(of ${enum}) ")
    endif()

    get_property(help CACHE ${name} PROPERTY HELPSTRING)
    string_unescape("${help}" help)
    string(REPLACE "\n" "\n--      " help "\n${help}")

    get_property(type CACHE ${name} PROPERTY TYPE)
    if(type STREQUAL "STRING" AND NOT enum)
      message(STATUS "${name} = ${quoted} ${tags}[${reasons}]${help}")
    else()
      message(STATUS "${name} = $CACHE{${name}} ${tags}[${reasons}]${help}")
    endif()
  endforeach()
  message(STATUS)

  set(preset "{}")
  string(TIMESTAMP timestamp)
  string(JSON preset SET "${preset}" name "\"${timestamp}\"")
  string(JSON preset SET "${preset}" generator "\"${CMAKE_GENERATOR}\"")
  string(JSON preset SET "${preset}" cacheVariables "${cache_json}")
  string(
    JSON preset SET "${preset}"
    environment "{\"MAUD_DISABLE_ENVIRONMENT_OPTIONS\": \"ON\"}"
  )

  set(
    presets
    [[{
        "version": 6,
        "cmakeMinimumRequired": {"major": 3, "minor": 28, "patch": 0},
        "configurePresets": []
    }]]
  )
  if(EXISTS "${CMAKE_SOURCE_DIR}/CMakeUserPresets.json")
    file(READ "${CMAKE_SOURCE_DIR}/CMakeUserPresets.json" presets)
  endif()

  string(JSON i LENGTH "${presets}" configurePresets)
  string(JSON presets SET "${presets}" configurePresets ${i} "${preset}")
  file(WRITE "${CMAKE_SOURCE_DIR}/CMakeUserPresets.json" "${presets}\n")

  # Clear temporaries
  foreach(name ${_MAUD_ALL_OPTIONS})
    foreach(
      prefix
      DEFAULT
      DECLARED
      RESOLVED
      WATCHED
      DEFINITELY_USER
      ADD_COMPILE_DEFINITIONS
      VALIDATE
      MAYBE_CONSTRAINED_BY
      CONSTRAINTS_ON
    )
      unset(_MAUD_${prefix}_${name} CACHE)
    endforeach()
  endforeach()
endfunction()


################################################################################
# in2 helpers and pipeline filters
################################################################################

# render directly to file
function(render content)
  file(APPEND "${RENDER_FILE}" "${content}")
endfunction()

function(in2_pipeline_filter_)
endfunction()

function(in2_pipeline_filter_set)
  set(IT "${ARGN}" PARENT_SCOPE)
endfunction()

function(in2_pipeline_filter_if_else then otherwise)
  if(IT)
    set(IT "${then}" PARENT_SCOPE)
  else()
    set(IT "${otherwise}" PARENT_SCOPE)
  endif()
endfunction()

function(in2_pipeline_filter_string)
  if(ARGV0 MATCHES "^(TOLOWER|TOUPPER|STRIP|MAKE_C_IDENTIFIER|HEX)$")
    string(${ARGV0} "${IT}" IT)
    set(IT "${IT}" PARENT_SCOPE)
    return()
  endif()

  if(ARGV0 STREQUAL "JSON")
    list(POP_FRONT ARGN _ _)
    if(ARGV1 STREQUAL "LIST")
      json_list(IT "${IT}" ${ARGN})
    else()
      string(JSON IT ${ARGV1} "${IT}" ${ARGN})
    endif()
    set(IT "${IT}" PARENT_SCOPE)
    return()
  endif()

  string(${ARGV} IT "${IT}")
  set(IT "${IT}" PARENT_SCOPE)
endfunction()

function(in2_pipeline_filter_string_literal)
  if(ARGV0 STREQUAL "RAW")
    set(tag "")
    while(IT MATCHES "\\)(${tag}_*)\"")
      set(tag "${CMAKE_MATCH_1}_")
    endwhile()
    set(IT "R\"${tag}(${IT})${tag}\"" PARENT_SCOPE)
    return()
  endif()

  string_escape("${IT}" str)
  set(IT "\"${str}\"" PARENT_SCOPE)
endfunction()

function(in2_pipeline_filter_join glue)
  list(JOIN IT "${glue}" joined)
  set(IT "${joined}" PARENT_SCOPE)
endfunction()


################################################################################
# DEBUG helpers
################################################################################
function(print_target_properties target)
  execute_process(COMMAND cmake --help-property-list OUTPUT_VARIABLE properties)
  string(REGEX REPLACE ";" "\\\\;" properties "${properties}")
  string(REGEX REPLACE "\n" ";" properties "${properties}")
  list(REMOVE_DUPLICATES properties)

  foreach(property ${properties})
    # https://cmake.org/cmake/help/latest/policy/CMP0026.html
    if(property MATCHES "(^LOCATION$|^LOCATION_|_LOCATION$)")
      continue()
    endif()

    get_property(has-property TARGET ${target} PROPERTY ${property} SET)
    if(has-property)
      get_target_property(value ${target} ${property})
      message("${property} = ${value}")
    endif()
  endforeach()
endfunction()


function(print_directory_properties dir)
  execute_process(COMMAND cmake --help-property-list OUTPUT_VARIABLE properties)
  string(REGEX REPLACE ";" "\\\\;" properties "${properties}")
  string(REGEX REPLACE "\n" ";" properties "${properties}")
  list(REMOVE_DUPLICATES properties)

  foreach(property ${properties})
    # https://cmake.org/cmake/help/latest/policy/CMP0026.html
    if(property MATCHES "(^LOCATION$|^LOCATION_|_LOCATION$)")
      continue()
    endif()

    get_property(has-property SOURCE "${dir}" PROPERTY ${property} SET)
    if(has-property)
      get_directory_property(value DIRECTORY "${dir}" ${property})
      message("${property} = ${value}")
    endif()
  endforeach()
endfunction()


function(print_source_file_properties src)
  execute_process(COMMAND cmake --help-property-list OUTPUT_VARIABLE properties)
  string(REGEX REPLACE ";" "\\\\;" properties "${properties}")
  string(REGEX REPLACE "\n" ";" properties "${properties}")
  list(REMOVE_DUPLICATES properties)

  foreach(property ${properties})
    # https://cmake.org/cmake/help/latest/policy/CMP0026.html
    if(property MATCHES "(^LOCATION$|^LOCATION_|_LOCATION$)")
      continue()
    endif()

    get_property(has-property SOURCE "${src}" PROPERTY ${property} SET)
    if(has-property)
      get_source_file_property(value "${src}" ${property})
      message("${property} = ${value}")
    endif()
  endforeach()
endfunction()


function(print_target_sources target)
  set(source_property_names SOURCES)

  get_target_property(module_sets ${target} CXX_MODULE_SETS)
  if(NOT module_sets STREQUAL module_sets-NOTFOUND)
    foreach(module_set ${module_sets})
      list(APPEND source_property_names CXX_MODULE_SET_${module_set})
    endforeach()
  endif()

  foreach(prop ${source_property_names})
    get_target_property(sources ${target} ${prop})
    if(sources STREQUAL sources-NOTFOUND)
      continue()
    endif()
    foreach(source ${sources})
      get_source_file_property(type ${source} MAUD_TYPE)
      if(type STREQUAL type-NOTFOUND)
        set(type "NOT SCANNED")
      endif()
      message(VERBOSE "  ${source}: ${type}")
    endforeach()
  endforeach()
endfunction()


function(print_variables)
  get_cmake_property(variables VARIABLES)
  list(SORT variables)
  foreach (v ${variables})
    message(STATUS "${v}=${${v}}")
  endforeach()
endfunction()


function(add_generator_expression_display_target target_name)
  # "$<INTERFACE_INCLUDE_DIRECTORIES:fmt::fmt-header-only>"
  list(JOIN ARGN "\\' \\'" str)
  add_custom_target(
    ${target_name}
    COMMAND "${CMAKE_COMMAND}" -E echo "\\'${str}\\'"
  )
endfunction()


function(dump_file path)
  file(READ "${CMAKE_BINARY_DIR}/${path}" f)
  message(STATUS "${path}: '${f}'")
endfunction()

cmake_policy(POP)
