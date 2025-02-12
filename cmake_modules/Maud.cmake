include_guard()

cmake_policy(PUSH)
cmake_policy(SET CMP0007 NEW) # list command no longer ignores empty elements.
cmake_policy(SET CMP0009 NEW) # GLOB_RECURSE calls should not follow symlinks by default.
cmake_policy(SET CMP0057 NEW) # Support new ``if()`` IN_LIST operator.


set(_MAUD_SELF_DIR "${CMAKE_CURRENT_LIST_DIR}")


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


function(_maud_write_scan_script source_file)
  _maud_preprocessing_scan_options("${source_file}" flags)

  # The scan script accepts one argument:
  # a suffix to apply to the ddi file (so we can write .ddi.new)
  _maud_get_ddi_path("${source_file}" ddi_path)
  cmake_path(REMOVE_EXTENSION ddi_path LAST_ONLY OUTPUT_VARIABLE obj_path)

  cmake_path(NATIVE_PATH source_file NORMALIZE source_file)

  if(MSVC)
    set(arg "%1")
  else()
    set(arg "$1")
  endif()
  set(scan "${CMAKE_CXX_SCANDEP_SOURCE}\n")
  string(REPLACE <CMAKE_CXX_COMPILER> "\"${CMAKE_CXX_COMPILER}\"" scan "${scan}")
  string(REPLACE <FLAGS> "${flags}" scan "${scan}")
  string(REPLACE <DEFINES> "" scan "${scan}")
  string(REPLACE <INCLUDES> "" scan "${scan}")
  string(REPLACE <SOURCE> "\"${source_file}\"" scan "${scan}")
  string(REPLACE <OBJECT> "\"${obj_path}\"" scan "${scan}")
  string(REPLACE <DEP_FILE> "\"${ddi_path}.d\"" scan "${scan}")
  string(REPLACE <DYNDEP_FILE> "\"${ddi_path}${arg}\"" scan "${scan}")
  string(REPLACE <PREPROCESSED_SOURCE> "\"${ddi_path}.preprocessed\"" scan "${scan}")
  if(MSVC)
    file(WRITE "${ddi_path}.scan.bat" "${scan}\n")
  else()
    file(WRITE "${ddi_path}.scan.sh" "${scan}\n")
  endif()
endfunction()


function(_maud_preprocessing_scan_options source_file out_var)
  get_source_file_property(
    flags
    "${source_file}"
    MAUD_PREPROCESSING_SCAN_OPTIONS
  )
  if(NOT flags)
    set(flags "")
  endif()
  string(APPEND flags " ${CMAKE_CXX${CMAKE_CXX_STANDARD}_STANDARD_COMPILE_OPTION}")
  get_directory_property(dirs INCLUDE_DIRECTORIES)
  foreach(dir ${dirs})
    string(APPEND flags " ${CMAKE_INCLUDE_FLAG_CXX} \"${dir}\"")
  endforeach()
  set(${out_var} "${flags}" PARENT_SCOPE)
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

  set(ext_regex ${MAUD_CXX_SOURCE_EXTENSIONS})
  string(REPLACE "+" "[+]" ext_regex "${ext_regex}")
  string(REPLACE " " "|" ext_regex "${ext_regex}")

  glob(_MAUD_CXX_SOURCES CONFIGURE_DEPENDS "[.](${ext_regex})$")

  # TODO handle this (and other glob exclusions) with a source property
  # rather than another glob. Then if a glob is desired, we can write
  # glob(CXX_EXCLUDED_SOURCES "cmake_modules/.*[.]cxx")
  # foreach(source ${CXX_EXCLUDED_SOURCES})
  #   # set the excluded property
  # endforeach()
  if(MAUD_CXX_SOURCE_EXCLUSION_PATTERN)
    list(
      # This doesn't alter the value in the cache, just the local value
      FILTER _MAUD_CXX_SOURCES
      EXCLUDE REGEX "${MAUD_CXX_SOURCE_EXCLUSION_PATTERN}"
    )
  endif()
  _maud_set(_MAUD_CXX_SCANNED_SOURCES "${_MAUD_CXX_SOURCES}")

  foreach(source_file ${_MAUD_CXX_SCANNED_SOURCES})
    _maud_scan("${source_file}")
  endforeach()
endfunction()


function(_maud_setup_clang_format)
  set(config "")
  # FIXME support clang-format files anywhere
  if(EXISTS "${CMAKE_SOURCE_DIR}/.clang-format")
    file(READ "${CMAKE_SOURCE_DIR}/.clang-format" config)
    list(APPEND CMAKE_CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/.clang-format")
    set(CMAKE_CONFIGURE_DEPENDS "${CMAKE_CONFIGURE_DEPENDS}" PARENT_SCOPE)
  endif()

  if(config MATCHES "# Maud: ([{]([^\n]|\n *#)+[}])")
    string(REGEX REPLACE " *\n *# *" " " json "${CMAKE_MATCH_1}")
    string(JSON version GET "${json}" version)
    json_list(patterns "${json}" patterns)
  else()
    message(
      VERBOSE
      "Couldn't read required clang-format version"
      "\n--   add a comment to ${CMAKE_SOURCE_DIR}/.clang-format"
      "\n--   like "
      [[# Maud: {"version": 18, "patterns": ["[.][ch]xx$", "!thirdparty/"]}]]
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
    glob(formatted_files CONFIGURE_DEPENDS EXCLUDE_RENDERED ${patterns})
    list(JOIN formatted_files "\n" formatted_files)
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

  _maud_write_scan_script("${source_file}")
  _maud_get_ddi_path("${source_file}" ddi)

  if(MSVC)
    set(command "${ddi}.scan.bat")
  else()
    set(command sh "${ddi}.scan.sh")
  endif()
  execute_process(COMMAND ${command} COMMAND_ERROR_IS_FATAL ANY)

  # ... and read back the ddi
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
    target_sources(
      ${target_name}
      PUBLIC
      FILE_SET module_providers
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
    PUBLIC
    FILE_SET module_providers
    TYPE CXX_MODULES
    ${_MAUD_BASE_DIRS}
    FILES "${_MAUD_SELF_DIR}/test_.cxx"
  )
  set_target_properties(
    test_.${name}
    PROPERTIES
    COMPILE_OPTIONS "${_MAUD_INCLUDE} \"${_MAUD_SELF_DIR}/test_.hxx\""
  )
endfunction()


function(_maud_rescan source_file out_var)
  set(${out_var} "" PARENT_SCOPE)
  _maud_get_ddi_path("${source_file}" ddi)

  if(NOT EXISTS "${ddi}")
    set(${out_var} "UNSCANNED ${source_file}" PARENT_SCOPE)
    return()
  endif()

  if("${ddi}" IS_NEWER_THAN "${source_file}")
    message(VERBOSE "skipping rescan of ${source_file}")
    return()
  endif()

  message(VERBOSE "rescanning ${source_file}")
  if(MSVC)
    set(command "${ddi}.scan.bat" .new)
  else()
    set(command sh "${ddi}.scan.sh" .new)
  endif()
  execute_process(COMMAND ${command} COMMAND_ERROR_IS_FATAL ANY)

  file(READ "${ddi}" old_ddi)
  file(READ "${ddi}.new" new_ddi)
  string(COMPARE EQUAL "${old_ddi}" "${new_ddi}" equal)
  if(NOT equal)
    set(${out_var} "BEFORE=${old_ddi}\nAFTER=${new_ddi}" PARENT_SCOPE)
  else()
    file(REMOVE "${ddi}.new")
    file(TOUCH "${ddi}")
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
    foreach(import ${imports})
      if(import STREQUAL "executable" OR import STREQUAL "test_")
        continue()
      endif()
      if(NOT TARGET ${import})
        find_package("${import}.maud" REQUIRED CONFIG)
      endif()
      if(import STREQUAL target) # for example a partition might import the primary
        continue()
      endif()
      target_link_libraries(${target} PRIVATE ${import})
    endforeach()

    get_target_property(interface ${target} MAUD_INTERFACE)
    if(NOT interface AND NOT TEST ${target})
      if(target_type STREQUAL "EXECUTABLE")
        set(interface "${_MAUD_SELF_DIR}/executable.cxx")
      else()
        get_target_property(src ${target} MAUD_INTERFACE_PARTITIONS)
        set(interface "${MAUD_DIR}/injected/${target}.cxx")
        list(TRANSFORM src PREPEND "\nexport import :")
        list(PREPEND src "export module ${target}")
        file(WRITE "${MAUD_DIR}/injected/${target}.cxx" "${src};\n")
        set_source_files_properties(
          "${MAUD_DIR}/injected/${target}.cxx"
          PROPERTIES
          MAUD_TYPE INTERFACE
        )
        message(VERBOSE "  No primary interface supplied, injecting ${interface}")
      endif()
      target_sources(
        ${target}
        PUBLIC
        FILE_SET module_providers
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
        PUBLIC
        FILE_SET module_providers
        TYPE CXX_MODULES
        BASE_DIRS ${_MAUD_BASE_DIRS}
        FILES "${test_main}"
      )
      continue()
    endif()

    set(is_exe $<STREQUAL:$<TARGET_PROPERTY:${target},TYPE>,EXECUTABLE>)
    set(
      install_dir
      "$<IF:${is_exe},${CMAKE_INSTALL_BINDIR},${CMAKE_INSTALL_LIBDIR}>"
    )
    if(target MATCHES _$)
      set(junk_prefix "${MAUD_DIR}/junk/")
    else()
      set(junk_prefix "")
    endif()

    install(
      TARGETS ${target}
      EXPORT ${target}
      DESTINATION "${junk_prefix}${install_dir}"
      CXX_MODULES_BMI
      DESTINATION "${junk_prefix}${install_dir}/bmi/${CMAKE_CXX_COMPILER_ID}"
      FILE_SET module_providers
      DESTINATION "${junk_prefix}${install_dir}/module_interface/${target}"
    )
    install(
      EXPORT ${target}
      DESTINATION "${junk_prefix}${CMAKE_INSTALL_LIBDIR}/cmake"
      FILE ${target}.maud-config.cmake
      # TODO support injecting more cmake into maud-config.cmake
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

      message(STATUS "change in glob ${glob} detected, will regenerate")
      _maud_print_glob_changes("${old}" "${${glob}}")
      file(WRITE "${MAUD_DIR}/cache_updates/${glob}" "${${glob}}")
      _maud_set(${glob} "${${glob}}")

      if("CONFIGURE_DEPENDS" IN_LIST _MAUD_GLOB_ARGUMENTS_${glob})
        file(TOUCH_NOCREATE "${CMAKE_BINARY_DIR}/CMakeFiles/cmake.verify_globs")
      endif()
    endforeach()

    unset(old)
  endif()

  foreach(source_file ${_MAUD_CXX_SCANNED_SOURCES})
    _maud_rescan("${source_file}" scan-results-differ)
    if(scan-results-differ)
      message(STATUS "change detected ${scan-results-differ}, will regenerate")
      file(TOUCH_NOCREATE "${CMAKE_BINARY_DIR}/CMakeFiles/cmake.verify_globs")
    endif()
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
    message(FATAL_ERROR "expected single index file, got '${index}")
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

  if(build_dir STREQUAL "CONFIGURING")
    # cache updates will be persisted so cache_updates/ can be cleared
    file(REMOVE_RECURSE "${MAUD_DIR}/cache_updates")
  endif()
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

  _maud_set(_MAUD_INCLUDE "SHELL: $<IF:$<CXX_COMPILER_ID:MSVC>,/Fi,-include>")
  _maud_set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

  _maud_load_cache_updates()
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
  add_compile_options("${_MAUD_INCLUDE} \"${MAUD_DIR}/options.h\"")

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

  option(
    MAUD_CXX_SOURCE_EXTENSIONS
    STRING "Files with any of these extensions will be scanned as C++ modules."
    DEFAULT "cxx cxxm ixx mxx cpp cppm cc ccm c++ c++m"
    MARK_AS_ADVANCED
  )

  option(
    MAUD_CXX_SOURCE_EXCLUSION_PATTERN
    STRING "If provided, files matching this pattern will not be scanned as C++ modules."
    MARK_AS_ADVANCED
  )

  option(
    MAUD_CXX_HEADER_EXTENSIONS
    STRING "Files with any of these extensions will be recognized as C++ headers."
    DEFAULT "hxx hpp h hh h++"
    MARK_AS_ADVANCED
  )

  cmake_language(GET_MESSAGE_LOG_LEVEL level)
  option(
    CMAKE_MESSAGE_LOG_LEVEL
    ENUM ERROR WARNING NOTICE STATUS VERBOSE DEBUG TRACE
      "Log level for the message() comand."
    DEFAULT "${level}"
    MARK_AS_ADVANCED
  )

  option(
    # Should this be multiple boolean options like SPHINX_BUILD_DIRHTML?
    SPHINX_BUILDERS
    STRING "A ;-list of builders which will be used with Sphinx."
    DEFAULT "dirhtml"
  )
  # PATH options are always coerced to absolute, relative to the working directory
  # of the configuring cmake process. Therefore we need to have that directory correctly
  # detect changes to PATH options.

  # define the variable with UNINITIALIZED type so that it's as-if from the CLI
  set(_MAUD_CWD "." CACHE UNINITIALIZED "")
  # the value already exists and isn't absolute, so it will be coerced by set() now
  set(_MAUD_CWD "." CACHE FILEPATH "")
  # finally, hide this ugliness from GUIs
  _maud_set(_MAUD_CWD "${_MAUD_CWD}")
endfunction()


function(_maud_finalize_generated)
  if(NOT DEFINED _MAUD_ALL_GENERATED)
    _maud_glob(_MAUD_ALL_GENERATED "${MAUD_DIR}/rendered")
    _maud_set(_MAUD_ALL_GENERATED ${_MAUD_ALL_GENERATED})
  endif()
endfunction()


function(_maud_cmake_modules)
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
  if("${_MAUD_IN2}" STREQUAL "")
    find_program(_MAUD_IN2 maud_in2 REQUIRED)
  endif()

  glob(_MAUD_IN2_TEMPLATES CONFIGURE_DEPENDS EXCLUDE_RENDERED "[.]in2$")
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


function(_maud_setup_doc)
  find_package(Python3)
  if(NOT TARGET Python3::Interpreter)
    # TODO instead, error here (but include instructions to disable doc)
    message(VERBOSE "Could not find Python3, abandoning doc")
    return()
  endif()

  glob(
    _MAUD_RST
    CONFIGURE_DEPENDS
    "[.]rst$"
    "!(^|/)[A-Z_0-9]+[.]rst$"
    "!(/|^)_"
  )
  if(NOT _MAUD_RST)
    message(VERBOSE "Not one doc file was detected 😞")
    return()
  endif()

  # TODO document that conf can't be generated
  glob(
    _MAUD_SPHINX_CONF
    CONFIGURE_DEPENDS
    EXCLUDE_RENDERED
    "(^|/)sphinx_configuration/conf.py$"
  )
  if(_MAUD_SPHINX_CONF MATCHES "^(.*;.*|)$")
    # TODO if no conf.py is found, dump a decent default into the source tree
    message(FATAL_ERROR "Sphinx requires exactly one conf.py file but found '${_MAUD_SPHINX_CONF}'")
    return()
  endif()
  cmake_path(GET _MAUD_SPHINX_CONF PARENT_PATH conf_dir)

  set(doc "${CMAKE_BINARY_DIR}/documentation")

  file(REMOVE_RECURSE "${doc}")
  file(MAKE_DIRECTORY "${doc}/stage")
  # TODO verify that this link is sufficient to literalinclude and document it
  file(CREATE_LINK "${CMAKE_SOURCE_DIR}" "${doc}/stage/CMAKE_SOURCE_DIR" SYMBOLIC)

  file(
    WRITE "${MAUD_DIR}/maud_sphinx_adapter/pyproject.toml"
    [[
      [build-system]
      requires = ["setuptools"]
      build-backend = "setuptools.build_meta"
      [project]
      name = "maud"
      version = "0.0.1"
      dependencies = []
    ]]
  )
  file(WRITE "${MAUD_DIR}/maud_sphinx_adapter/maud/cache/__init__.py")
  file(
    WRITE "${MAUD_DIR}/maud_sphinx_adapter/maud/__init__.py"
    "import sys\n"
    "sys.path.append('${_MAUD_SELF_DIR}')\n"
    "from _maud_sphinx_adapter import setup, read_cache\n"
    "sys.path = sys.path[:-1]\n"
    "import maud.cache\n"
    "read_cache('${CMAKE_BINARY_DIR}', maud.cache)\n"
  )

  message(STATUS "Building virtual env ${doc}/venv for Sphinx")
  execute_process(COMMAND "${Python3_EXECUTABLE}" -m venv --clear "${doc}/venv")
  execute_process(
    COMMAND
      "${doc}/venv/bin/pip" install
      --editable "${MAUD_DIR}/maud_sphinx_adapter"
      --editable "${_MAUD_SELF_DIR}/trike"
      --requirement "${_MAUD_SELF_DIR}/sphinx_requirements.txt"
      --isolated
      --require-virtualenv
      --ignore-installed
      --disable-pip-version-check
      --no-input
      --quiet
      --log "${doc}/venv/pip.log"
      --report "${doc}/venv/pip.report.json"
    COMMAND_ERROR_IS_FATAL ANY
  )
  set(SPHINX_BUILD "${doc}/venv/bin/sphinx-build")

  set(ext_regex "${MAUD_CXX_HEADER_EXTENSIONS}")
  string(REPLACE "+" "[+]" ext_regex "${ext_regex}")
  string(REPLACE " " "|" ext_regex "${ext_regex}")

  set(all_staged)
  foreach(file ${_MAUD_RST})
    _maud_relative_path("${file}" staged is_gen)
    cmake_path(GET staged STEM LAST_ONLY stem)
    if(stem STREQUAL "index")
      cmake_path(GET staged PARENT_PATH html)
    else()
      cmake_path(REMOVE_EXTENSION staged LAST_ONLY OUTPUT_VARIABLE html)
    endif()
    cmake_path(ABSOLUTE_PATH staged BASE_DIRECTORY "${doc}/stage")

    add_custom_command(
      OUTPUT "${staged}"
      DEPENDS "${file}"
      COMMAND "${CMAKE_COMMAND}" -E copy "${file}" "${staged}"
      COMMENT "Staging${file}$<$<BOOL:${is_gen}>: (generated)> to ${staged}"
    )
    list(APPEND all_staged "${staged}")
  endforeach()

  # TODO assert there are no dupes in all_staged = collision between source/generated

  add_custom_target(documentation ALL)

  # We run sphinx multithreaded. This can pessimize throughput since ninja
  # is probably *also* running `nproc` tasks. If this becomes a problem later,
  # there will need to be an option or some other way to mediate between sphinx
  # and ninja. In the meantime, ensure that at least sphinx isn't trying to build
  # manpages and html at the same time.
  set_property(GLOBAL APPEND PROPERTY JOB_POOLS sphinx_build=1)

  set(all_build_logs)
  foreach(
    builder

    html dirhtml singlehtml
    htmlhelp qthelp devhelp applehelp
    epub latex texinfo
    man
    text gettext
    doctest linkcheck
    xml pseudoxml
  )
    add_custom_command(
      OUTPUT "${doc}/${builder}.log"
      DEPENDS
        ${all_staged}
        # FIXME note all of these with Sphinx.env.note_dependency()
        # if they aren't already noted.
        "${conf_dir}/conf.py"
      WORKING_DIRECTORY "${doc}"
      COMMAND
        "${SPHINX_BUILD}"
        --builder ${builder}
        --conf-dir "${conf_dir}"
        --doctree-dir doctrees
        --jobs auto
        stage       # use stage as source directory
        ${builder}  # provide an independent build directory to each builder
        > ${builder}.log
      JOB_POOL sphinx_build
      COMMAND_EXPAND_LISTS
      COMMENT "Building ${builder} with sphinx"
    )
    add_custom_target(documentation.${builder} DEPENDS "${doc}/${builder}.log")

    if("${builder}" IN_LIST SPHINX_BUILDERS)
      add_dependencies(documentation documentation.${builder})
    endif()
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

  if("$ENV{SHELL}" STREQUAL "")
    find_program(env env NO_CACHE)
    if(NOT env)
      message(
        FATAL_ERROR
        "Could not infer shim script style, set \$ENV{SHELL}."
      )
    else()
      set(shebang "#!${env} -S sh -e")
    endif()
  else()
    set(shebang "#!$ENV{SHELL} -e")
  endif()

  message(
    VERBOSE
    "Posix-compatible `${shebang}` assumed, shimming ${script} -> ${destination}"
  )
  file(
    WRITE "${destination}"
    "${shebang}\n"
    "\"${CMAKE_COMMAND}\" -P \"${script}\" -- \"\$@\"\n"
  )
  file(
    CHMOD "${destination}"
    FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
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
    DEFINED ENV{${name}}
    AND NOT DEFINED CACHE{${name}}
    AND NOT EXISTS "${CMAKE_BINARY_DIR}/CMakeCache.txt"
    AND NOT "$ENV{MAUD_DISABLE_ENVIRONMENT_OPTIONS}"
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
      cmake_path(NATIVE_PATH ${name} NORMALIZE path)
      cmake_path(ABSOLUTE_PATH path BASE_DIRECTORY "${_MAUD_CWD}")
      _maud_set_value_only(${name} "${path}")
    endif()
  endif()

  if(
    DEFINED CACHE{${name}}
    AND NOT EXISTS "${CMAKE_BINARY_DIR}/CMakeCache.txt"
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
  if(NOT EXISTS "${CMAKE_BINARY_DIR}/CMakeCache.txt")
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
      DEFINED ENV{${name}}
      AND "$CACHE{${name}}" STREQUAL "$ENV{${name}}"
      AND NOT "$ENV{MAUD_DISABLE_ENVIRONMENT_OPTIONS}"
      AND NOT EXISTS "${CMAKE_BINARY_DIR}/CMakeCache.txt"
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
