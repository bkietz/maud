macro("project test: empty")
  # With no files at all, maud will still configure a viable build
  run(COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: hello world")
  write(
    hello.cxx
    [[
      #include <iostream>
      import executable;
      int main() {
        std::cout << "hello world!" << std::endl;
      }
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)

  run(COMMAND .build/Debug/hello)
  assert([[OUT STREQUAL "hello world!\n"]])
endmacro()


macro("project test: auto included cmake modules")
  set(crib "<CRIB>${TEST_NAME}</CRIB>")
  file(WRITE cmake_modules/IncludeMe.cmake "")
  write(
    crib.cmake
    "
      # output a recognizable message to search for so we can verify this ran
      message(STATUS [[${crib}]])

      # unless explicit inclusion module directory was discovered, this will error
      include(IncludeMe)
    "
  )

  # ensure that explicit  inclusion modules s won't be run un unless ss included
  set(anticrib "<ANTICRIB>${TEST_NAME}</ANTICRIB>")
  file(WRITE cmake_modules/DontIncludeMe.cmake "message(STATUS [[${anticrib}]])")

  run(COMMAND maud --log-level=VERBOSE)
  assert("OUT MATCHES [[${crib}]]")
  assert("NOT OUT MATCHES [[${anticrib}]]")
endmacro()


macro("project test: auto add sources")
  write(
    foo.cxx
    [[
      export module foo;
      export int foo() { return 0; }
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)

  library_name(STATIC foo libfoo)
  assert([[EXISTS ".build/Debug/${libfoo}"]])

  write(
    bar.cxx
    [[
      export module bar;
      export int bar() { return 0; }
    ]]
  )

  run(COMMAND cmake --build .build --config Debug)
  library_name(STATIC bar libbar)
  assert([[EXISTS ".build/Debug/${libbar}"]])

  write(
    bar.cxx
    [[
      export module bar2; // NOTE altered module name
      export int bar() { return 0; }
    ]]
  )

  run(COMMAND cmake --build .build --config Debug)
  library_name(STATIC bar2 libbar2)
  assert([[EXISTS ".build/Debug/${libbar2}"]])
endmacro()


macro("project test: auto primary interface")
  write(
    foo_a.cxx
    [[
      export module foo:a;
      export int a() { return 'a'; }
    ]]
  )
  write(
    foo_b.cxx
    [[
      export module foo:b;
      export int b() { return 'b'; }
    ]]
  )
  write(
    use.cxx
    [[
      import executable;
      import foo;
      int main() {
        return a() + b();
      }
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: std lib")
  write(
    std_.cxx
    [[
      module;
      #include <string>
      #include <vector>
      // Technically not reserved since it doesn't match ^std[0-9]*$
      export module std_;
      namespace std {
        export using std::string;
        export using std::vector;
      }
    ]]
  )

  write(
    bar.cxx
    [[
      import executable;
      import std_;
      int main() {
        std::vector<std::string> s;
        return 0;
      }
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: broken c++")
  write(
    broken.cxx
    [[
      export module broken;
      exp_rt int foo;
    ]]
  )
  run(COMMAND maud --log-level=VERBOSE --generate-only)
  run(FAILING COMMAND maud --log-level=VERBOSE)
  return()

  # FIXME this passes but should not; instead of
  # silently omitting a source file from the build,
  # generation should fail immediately.
  write(
    broken.cxx
    [[
      #include <string>
      export module broken module declaration
      export int foo;
    ]]
  )
  run(FAILING COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: exported trait")
  write(
    name_trait.cxx
    [[
      export module name_trait;
      export template <typename> auto constexpr Name = "";
    ]]
  )

  write(
    name_trait.integer.cxx
    [[
      export module name_trait.integer;
      export import name_trait;
      export template <> auto constexpr Name<int> = "int";
    ]]
  )

  write(
    assertions.cxx
    [[
      #include <string_view>
      import executable;
      import name_trait.integer;
      using namespace std::literals;
      static_assert(Name<void> == ""sv);
      static_assert(Name<int> == "int"sv);
      int main() {}
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: glob benchmark")
  write(
    benchmark.cmake
    [[
      _maud_set(N 7)
      _maud_set(F 8)

      if($ENV{MAUD_APPROX_LLVM_PROJECT})
        _maud_set(F 19)
      endif()

      find_program(FD NAMES fd)
      find_program(GIT NAMES git)

      set(files)
      foreach(i RANGE ${F})
        foreach(j RANGE ${F})
          foreach(k RANGE ${F})
            foreach(l RANGE ${F})
              list(APPEND files "${i}/${j}/${k}/${l}")
            endforeach()
          endforeach()
        endforeach()
      endforeach()
      _maud_set(files ${files})

      add_custom_target(
        benchmark ALL
        COMMAND
          "${CMAKE_COMMAND}"
          -P "${MAUD_DIR}/eval.cmake"
          -- "include(Time)"
        COMMAND_EXPAND_LISTS
        VERBATIM
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
      )
    ]]
  )

  write(
    cmake_modules/Time.cmake
    [===========[
      message(STATUS "\n\nBENCHMARK")
      function(time code)
        set(sum 0)
        set(min 9999999999)
        cmake_language(
          EVAL CODE
          "
          foreach(i RANGE ${N})
            string(TIMESTAMP before [[%s%f]])
            ${code}
            string(TIMESTAMP d [[%s%f]])
            math_assign(d - \${before})
            math_assign(sum + \${d})
            if(min GREATER d)
              set(min \${d})
            endif()
          endforeach()
          "
        )
        math(EXPR mean "${sum} / (${N} + 1)")
        string(REGEX REPLACE "(...)$" ".\\1" mean ${mean})
        math(EXPR min "${min}")
        string(REGEX REPLACE "(...)$" ".\\1" min ${min})
        set(delta_ms "( mean=${mean}\tmin=${min}\t) " PARENT_SCOPE)
      endfunction()

      time([[
        foreach(f ${files})
          file(WRITE "${f}" "")
        endforeach()
      ]])
      message(STATUS "\tWriting:            ${delta_ms}ms")

      time([[
        foreach(f ${files})
          if("${f}" IS_NEWER_THAN "${f}")
          endif()
        endforeach()
      ]])
      message(STATUS "\tNew checking:       ${delta_ms}ms")

      time([[
        file(
          GLOB_RECURSE _
          LIST_DIRECTORIES true
          RELATIVE "${CMAKE_SOURCE_DIR}"
          "*"
        )
        list(FILTER _ EXCLUDE REGEX "(^|/)\\.")
      ]])
      message(STATUS "\tGlobbing:           ${delta_ms}ms")

      if(FD)
        time([[
          execute_process(
            COMMAND cmake -E chdir "${CMAKE_SOURCE_DIR}" "${FD}" -I
            OUTPUT_VARIABLE _
          )
          string(STRIP "${_}" _)
          string(REGEX REPLACE "/?\n" ";" _ "${_}")
        ]])
      else()
        set(delta_ms fd-NOTFOUND)
      endif()
      message(STATUS "\tGlobbing(fd):       ${delta_ms}ms")

      if(GIT)
        time([[
          execute_process(
            COMMAND "${GIT}" -C "${CMAKE_SOURCE_DIR}"
              ls-files --exclude-standard --ignored --others
            OUTPUT_VARIABLE _
          )
          string(STRIP "${_}" _)
          string(REGEX REPLACE "/?\n" ";" _ "${_}")
        ]])
      else()
        set(delta_ms git-NOTFOUND)
      endif()
      message(STATUS "\tGlobbing(git):      ${delta_ms}ms")

      time([[
        list(FILTER files INCLUDE REGEX ".*")
        list(FILTER files EXCLUDE REGEX "(^|/)\\.")
      ]])
      message(STATUS "\tFiltering:          ${delta_ms}ms")

      time([[
        _maud_load_cache("${CMAKE_BINARY_DIR}")
      ]])
      message(STATUS "\tLoading the cache:  ${delta_ms}ms")

      list(LENGTH files count)
      math(EXPR N "${N} + 1")
      message(STATUS "\n    ${N} iterations with ${count} files")
    ]===========]
  )

  run(COMMAND maud)
  file(WRITE log "${OUT}")
endmacro()


macro("project test: unit testing")
  write(
    basics.cxx
    [[
      #include <string>
      import test_;

      TEST_(DISABLED_failing) {
        EXPECT_(false);
      }
      TEST_(basic) {
        int three = 3, five = 5;
        EXPECT_(three != five);
        EXPECT_(67 > five);
        EXPECT_(three);
        EXPECT_(not std::false_type{});
        int a = 999, b = 88888;
        EXPECT_(a != b);
        int *ptr = &three;
        if (not EXPECT_(ptr != nullptr)) return;
        EXPECT_(*ptr == three);
        EXPECT_("hello world" >>= HasSubstr("llo"));
      }
      Matcher IsEven{
        .match = [](auto n, auto &) { return n % 2 == 0; },
        .description = [](auto &os, bool negated) {
          os << (negated ? "isn't" : "is") << " even";
        },
      };
      TEST_(custom_matcher) {
        int i = 3;
        EXPECT_(i >>= Not(IsEven));
      }
      TEST_(parameterized, {111, 234}) {
        EXPECT_(parameter == parameter);
      }
      TEST_(typed, std::tuple{0, std::string("")}) {
        EXPECT_(parameter + parameter == parameter);
      }
    ]]
  )

  run(COMMAND maud)
  run(COMMAND ctest --test-dir .build --output-on-failure -C Debug)

  file(GLOB built_executable .build/Debug/test_.basics*)
  assert([[built_executable]])

  # Assert that the test executable isn't installed
  run(COMMAND cmake --install .build --prefix .usr --config Debug)
  file(GLOB installed_executable .usr/bin/test_.basics*)
  assert([[NOT installed_executable]])
endmacro()


macro("project test: disabled unit testing")
  write(
    inline_python.test.cxx
    [[
      #include <string>
      import test_;

      TEST_(inline_python) {

        from __future__ import braces
        def foo():
            assert 1 == 0

      }
    ]]
  )

  run(COMMAND maud -DBUILD_TESTING=OFF)
endmacro()


macro("project test: internal unit testing")
  write(
    foo.cxx
    [[
      export module foo:interface;
      // not exported!
      int foo_internal() { return 3; }
    ]]
  )
  write(
    internal.test.cxx
    [[
      module foo:some_test;
      import :interface;
      import test_;

      TEST_(can_access_internal) {
        EXPECT_(foo_internal() == 3);
      }
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: unit testing with custom main module")
  write(
    test_main.cxx
    [[
      module;
      #include <gtest/gtest.h>
      export module test_:main;
      export int foo;
      int main(int argc, char* argv[]) {
        foo = 999;
        testing::InitGoogleTest(&argc, argv);
        return RUN_ALL_TESTS();
      }
    ]]
  )

  write(
    foo.test.cxx
    [[
      import test_;
      TEST_(check_foo_is_999) {
        EXPECT_(foo == 999);
      }
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)
  run(COMMAND ctest --test-dir .build --output-on-failure -C Debug)
endmacro()


macro("project test: non-gtest unit testing")
  write(
    correct_math.test.cxx
    [[
      import test_;
      int main() {
        expect_eq(1 + 2, 3);
      }
    ]]
  )

  write(
    gotcha_math.test.cxx
    [[
      import test_;
      int main() {
        expect_eq(1/2, 0.5);
      }
    ]]
  )

  write(
    .test_.cxx
    [[
      module;
      #include <iostream>
      export module test_;
      export void expect_eq(auto const &l, auto const &r) {
        if (l == r) return;
        std::cerr << "failed: " << l << "==" << r << std::endl;
        throw 1;
      }
    ]]
  )

  write(
    test_.cmake
    [[
      function(maud_add_test source_file out_target_name)
        cmake_path(GET source_file STEM name)
        set(${out_target_name} "test_.${name}" PARENT_SCOPE)

        add_executable(test_.${name})
        add_test(NAME test_.${name} COMMAND $<TARGET_FILE:test_.${name}>)

        target_sources(
          test_.${name}
          PRIVATE FILE_SET test_module TYPE CXX_MODULES
          BASE_DIRS ${CMAKE_SOURCE_DIR} FILES .test_.cxx
        )
      endfunction()
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)
  run(COMMAND ctest -R correct --test-dir .build --output-on-failure -C Debug)
  run(FAILING COMMAND ctest -R gotcha --test-dir .build --output-on-failure -C Debug)
endmacro()


macro("project test: import installed")
  write(
    foo/foo.cxx
    [[
      export module foo;
      export int foo();
    ]]
  )
  write(
    foo/foo_impl.cxx
    [[
      // use a module partition so even p1689 scanners find it
      module foo:impl;
      int foo() { return 0; }
    ]]
  )
  run(
    COMMAND maud --log-level=VERBOSE
    WORKING_DIRECTORY foo
  )
  run(COMMAND cmake --install foo/.build --config Debug --prefix .usr)
  # only module interfaces are installed
  assert([[EXISTS .usr/lib/module_interface/foo/foo.cxx]])
  assert([[NOT EXISTS .usr/lib/module_interface/foo/foo_impl.cxx]])

  write(
    bar/bar.cxx
    [[
      export module bar;
      import foo;
      export int bar() { return foo(); }
    ]]
  )
  run(
    COMMAND maud --log-level=VERBOSE
    WORKING_DIRECTORY bar
  )
  run(COMMAND cmake --install bar/.build --config Debug --prefix .usr)

  write(
    baz/baz.cxx
    [[
      import executable;
      import bar;
      int main() { return bar(); }
    ]]
  )
  run(COMMAND maud --log-level=VERBOSE WORKING_DIRECTORY baz)
  run(COMMAND cmake --install baz/.build --config Debug --prefix .usr)

  run(COMMAND baz)
endmacro()


macro("project test: installed cmake functions")
  write(
    foobar/install.cmake
    [[
      include(GNUInstallDirs)
      install(
        FILES foo-config.cmake
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake"
      )
    ]]
  )
  write(
    foobar/foo-config.cmake
    [[
      file(WRITE foo.txt FOO)
    ]]
  )
  run(
    COMMAND maud --log-level=VERBOSE
    WORKING_DIRECTORY foobar
  )
  run(COMMAND cmake --install foobar/.build --config Debug --prefix .usr)

  write(
    use/use_foo.cmake
    [[
      find_package(foo)
    ]]
  )
  run(
    COMMAND maud --log-level=VERBOSE
    WORKING_DIRECTORY use
  )
  assert([[EXISTS use/foo.txt]])
endmacro()


macro("project test: util_ is not installed")
  write(
    util_.cxx
    [[
      export module util_;
      export int zero() { return 0; }
    ]]
  )
  write(
    noop.cxx
    [[
      import executable;
      import util_;
      int main() { return zero(); }
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)
  run(COMMAND cmake --install .build --config Debug --prefix .usr)

  file(GLOB installed_util .usr/lib/*util_.*)
  assert([[NOT installed_util]])

  run(COMMAND noop)
endmacro()


macro("project test: rendered in2 source")
  write(
    render_foo.cmake
    [[
      file(
        WRITE "${MAUD_DIR}/rendered/foo.cxx"
        [==[
        export module foo;
        import bar;
        static_assert(BOOL);
        static_assert(sizeof(INTS) == sizeof(int) * 11);
        ]==]
      )
    ]]
  )

  write(
    bar.cxx.in2
    [[
      export module bar;
      export int INTS[] = {@
        foreach(i RANGE 10)
          render("${i},")
        endforeach()
      @};
      export bool constexpr BOOL = @MAUD_DIR | if_else(1 0)@;
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)

  library_name(STATIC foo libfoo)
  library_name(STATIC bar libbar)
  assert([[EXISTS ".build/Debug/${libfoo}"]])
  assert([[EXISTS ".build/Debug/${libbar}"]])
endmacro()


macro("project test: rendering one in2 multiple times")
  write(
    constant.cxx.in2
    [[@
      cmake_path(GET RENDER_FILE PARENT_PATH dir)
      foreach(i RANGE 10)
        set(RENDER_FILE "${dir}/constant_${i}.cxx")
        @
        export module constant_@i@;
        export auto constexpr CONSTANT_@i@ = @i@;
        @
      endforeach()
    ]]
  )
  write(
    assertions.cxx
    [[
      import executable;
      import constant_7;
      static_assert(CONSTANT_7 == 7);
      int main() {}
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: c++17 project")
  write(
    src/src-y.cxx
    [[
      int main() {}
    ]]
  )
  write(
    explicit_targets.cmake
    [[
      set(CMAKE_CXX_STANDARD 17)
      glob(SRCS CONFIGURE_DEPENDS "src/.*[.]cxx$")
      add_executable(hello ${SRCS})
    ]]
  )
  run(COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: c++23 project")
  write(
    fib.cxx
    [[
      export module fib;
      auto fib = [](this auto const &self, int i) {
        if (i <= 1) return i;
        return self(i - 1) + self(i - 2);
      };
    ]]
  )
  write(
    cxx23.cmake
    [[
      set(CMAKE_CXX_STANDARD 23)
    ]]
  )
  run(COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: internal decl")
  write(
    foo_part.cxx
    [[
      export module foo:part;

      // declared functions are defined in the implementation units below
      export int foo();
      export int foo_half();
      export int foo_third();

      // not exported, but usable within module foo
      int foo_internal();
    ]]
  )
  write(
    foo_impl.cxx
    [[
      module foo;
      import :part;
      int foo() { return foo_internal(); }
    ]]
  )
  write(
    foo_half_impl.cxx
    [[
      module foo:half_impl;
      import :part;
      int foo_half() { return foo_internal() / 2; }
    ]]
  )
  write(
    foo_third_impl.cxx
    [[
      module foo:third_impl;
      // instead of importing partitions of foo's interface,
      // implementation units may choose to just import the primary
      import foo;
      int foo_half() { return foo_internal() / 3; }
    ]]
  )
  write(
    foo_internal_impl.cxx
    [[
      module foo;
      // implementation units with no partition automatically import
      // the full primary interface
      int foo_internal() { return 6; }
    ]]
  )
  write(
    foo_empty_impl.cxx
    [[
      module foo;
      // any number of implementation units may be written for a module
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: options")
  write(
    options.cmake
    [[
      option(LEGACY_0 "legacy signature, default off" ADD_COMPILE_DEFINITIONS)
      option(LEGACY_1 "legacy signature, default on" ON ADD_COMPILE_DEFINITIONS)

      option(
        B
        BOOL "
          Bool option
          Some help text
        "
        ADD_COMPILE_DEFINITIONS
      )
      option(
        B4
        BOOL "HIDDEN"
      )
      option(
        E
        ENUM A B C ""
        ADD_COMPILE_DEFINITIONS
      )
    ]]
  )
  write(
    assertions.cxx
    [[
      import executable; int main() {}

      static_assert(not LEGACY_0);
      static_assert(LEGACY_1);
      static_assert(not B);

      #if defined(B4)
      #error "should be disabled"
      #endif
    ]]
  )

  run(COMMAND maud --log-level=VERBOSE)

  file(READ CMakeUserPresets.json presets)
  json_destructure(preset_ "${presets}" configurePresets 0 cacheVariables)

  assert([[preset_B STREQUAL "OFF"]])
  assert([[preset_B4 STREQUAL "OFF"]])
  assert([[preset_BUILD_SHARED_LIBS STREQUAL "OFF"]])
  assert([[preset_BUILD_TESTING STREQUAL "ON"]])
  assert([[preset_CMAKE_MESSAGE_LOG_LEVEL STREQUAL "VERBOSE"]])
  assert([[preset_E STREQUAL "A"]])
  assert([[preset_LEGACY_0 STREQUAL "OFF"]])
  assert([[preset_LEGACY_1 STREQUAL "ON"]])
  assert([[preset_SPHINX_BUILDERS STREQUAL "dirhtml"]])
endmacro()


macro("project test: detect option dependency cycle")
  write(
    options.cmake
    [[
      option(A "" REQUIRES B ON)
      option(B "" REQUIRES A ON)
    ]]
  )
  run(FAILING COMMAND maud --log-level=VERBOSE)
endmacro()


macro("project test: option dependencies resolve correctly")
  write(
    options.cmake
    [[
      option(A "" REQUIRES B ON F OFF ADD_COMPILE_DEFINITIONS)
      option(B "" REQUIRES C ON ADD_COMPILE_DEFINITIONS)
      option(C "" REQUIRES D 3 ADD_COMPILE_DEFINITIONS)
      option(
        D ENUM 0 1 2 3 ""
        REQUIRES
          IF 1 E "one"
          IF 2 E "two"
          IF 3 E "three"
        ADD_COMPILE_DEFINITIONS
      )
      option(E STRING "" ADD_COMPILE_DEFINITIONS)
      option(F "" ADD_COMPILE_DEFINITIONS)
    ]]
  )
  write(
    assertions.cxx
    [[
      #include <string_view>
      import executable; int main() {}
      using std::operator""sv;

      static_assert(A and B and C);
      static_assert(D_3);
      static_assert(E == "three"sv);
    ]]
  )
  run(
    COMMAND
      maud
      # Note that only -DA=ON and -DF=OFF will not be overridden
      -DA=ON
      -DB=OFF
      -DE=yo
      -DD=1
      -DF=OFF
  )

  write(
    options.cmake
    [[
      option(A "A help")
      # If A were not already resolved, it could've been mutated here. However,
      # since it was already resolved it cannot be constrained to a new value.
      option(FORCE_A "" REQUIRES A ON)
    ]]
  )
  run(FAILING COMMAND maud -DFORCE_A=ON)

  write(
    options.cmake
    [[
      # Conflicting requirements:
      option(A "" ON REQUIRES C ON)
      option(B "" ON REQUIRES C OFF)
    ]]
  )
  run(FAILING COMMAND maud)
endmacro()


macro("project test: resolve undeclared options correctly")
  write(
    options.cmake
    [[
      option(A "A help" REQUIRES B ON ADD_COMPILE_DEFINITIONS)
      option(B "B help" ADD_COMPILE_DEFINITIONS)
    ]]
  )
  write(
    assertions.cxx
    [[
      import executable; int main() {}
      static_assert(A and B);
    ]]
  )
  # we expect the requirements to override user flags:
  run(COMMAND maud --log-level=VERBOSE -DA=ON -DB=OFF)
endmacro()


macro("project test: path option")
  write(
    options.cmake
    [[
      option(
        P PATH "
        Some path option
        Some more description
        "
      )
      option(Q FILEPATH "")
    ]]
  )
  write(foo/bar/baz/quux "")
  run(
    COMMAND
      maud
      --log-level=VERBOSE
      --source-dir=../../..
      -DP=../../..
      -DQ=quux
    WORKING_DIRECTORY foo/bar/baz
  )
  cmake_path(NATIVE_PATH MAUD_WORKING_DIR expected_P)

  set(expected_Q "${MAUD_WORKING_DIR}/foo/bar/baz/quux")
  cmake_path(NATIVE_PATH expected_Q expected_Q)

  # Path options are always relative to the working directory of the cmake
  # process so that `-DFOO=./foo<TAB>` won't break even if we're not in the source root
  assert("OUT MATCHES [[ P = ${expected_P} ]]")
  assert("OUT MATCHES [[ Q = ${expected_Q} ]]")
endmacro()


macro("project test: validate options")
  write(
    options.cmake
    [[
      option(B "")
    ]]
  )
  # BOOL options must be ON or OFF
  run(COMMAND maud -DB=ON)
  run(FAILING COMMAND maud -DB=NEITHER_ON_NOR_OFF)

  write(
    options.cmake
    [[
      option(
        E
        ENUM A B C ""
      )
    ]]
  )
  # ENUM options must be one of their allowed values
  run(COMMAND maud -DE=A)
  run(FAILING COMMAND maud -DE=-999)

  write(
    options.cmake
    [=[
      option(
        NONZERO
        STRING ""
        VALIDATE CODE [[
          if(NONZERO EQUAL 0)
            message(FATAL_ERROR "Was the name unclear?")
          endif()
        ]]
      )
    ]=]
  )
  # an explicit VALIDATE CODE block can enforce
  # arbitrary conditions
  run(COMMAND maud  -DNONZERO=10)
  run(FAILING COMMAND maud  -DNONZERO=0)
endmacro()


macro("project test: documentation")
  write(
    options.cmake
    [[
      option(
        SOME_DOC_OPTION
        ENUM A B C "Some documentation option"
      )
    ]]
  )
  write(
    index.rst
[[
Weeeeee
=======

.. trike-put:: cpp:struct Foo
]]
  )
  write(
    sphinx_configuration/conf.py
[[
from maud.cache import SOME_DOC_OPTION, BUILD_TESTING, CMAKE_SOURCE_DIR
extensions = ['maud', 'trike']
assert SOME_DOC_OPTION == 'B'
assert type(BUILD_TESTING) == bool
exclude_patterns = ["CMAKE_SOURCE_DIR", "Thumbs.db", ".DS_Store"]
trike_files = list(CMAKE_SOURCE_DIR.glob("*.hxx"))
from pathlib import Path
def setup(app):
    app.srcdir = CMAKE_SOURCE_DIR
]]
  )

  write(
    s.hxx
    [[
      /// a simple foobar struct
      struct Foo {
        /// metasyntactic variable
        int bar;

        /// metasyntactic variable
        int baz;
      };
    ]]
  )
  run(COMMAND maud -DSOME_DOC_OPTION=B)
  run(COMMAND cmake --build .build --target documentation)
  assert([[EXISTS .build/documentation/dirhtml/index.html]])
  file(READ .build/documentation/dirhtml/index.html index)
  assert([[index MATCHES "Weeeeee"]])
  assert([[index MATCHES "a simple foobar struct"]])
endmacro()


macro("project test: import installed with header dependencies")
  write(
    fmt_42/fmt_42.cxx
    [[
      module;
      #include <fmt/format.h>
      export module fmt_42;
      export std::string fmt_42() { return fmt::format("{}", 42); }
    ]]
  )
  write(
    fmt_42/fmt_42.cmake
    [[
      find_package(fmt REQUIRED)
      add_library(fmt_42)
      target_link_libraries(fmt_42 INTERFACE fmt::fmt)
    ]]
  )
  run(COMMAND maud --log-level=VERBOSE WORKING_DIRECTORY fmt_42)
  run(COMMAND cmake --install fmt_42/.build --config Debug --prefix .usr)

  write(
    use/use.cxx
    [[
      import executable;
      import fmt_42;
      int main() { return fmt_42().size(); }
    ]]
  )
  run(COMMAND maud --log-level=VERBOSE WORKING_DIRECTORY use)
endmacro()


###########################################################


function(assert condition)
  set(vars)
  cmake_language(
    EVAL CODE "
      if(${condition})
        set(failed OFF)
      else()
        set(failed ON)
        foreach(maybe_var ${condition})
          if(DEFINED \"\${maybe_var}\")
            list(APPEND vars \"\${maybe_var}\")
          endif()
        endforeach()
      endif()
    "
  )

  if(NOT failed)
    return()
  endif()

  message("failed assert(${condition})")
  foreach(var ${vars})
    if(var MATCHES "^(OUT)$")
      continue()
    endif()

    message("  ${var}='${${var}}'")
  endforeach()
  cmake_language(EXIT 1)
endfunction()


function(run)
  set(failing)
  if(ARGN MATCHES "^FAILING;(.+)$")
    set(ARGN "${CMAKE_MATCH_1}")
    set(failing FAILING)
  endif()

  execute_process(
    ${ARGN}
    OUTPUT_VARIABLE OUT
    ERROR_VARIABLE OUT
    RESULT_VARIABLE error_code
  )
  set(OUT "${OUT}" PARENT_SCOPE)

  string(JOIN " " command ${failing} ${ARGN})

  set(begin "-------------------------------------")
  if(failing)
    set(end "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
  else()
    set(end ".....................................")
  endif()

  message(
    "${command}\n"
    "${begin}[${error_code}]\n"
    "${OUT}🔚\n"
    "${end}[${error_code}]\n"
  )
  if(NOT failing)
    assert([[NOT error_code]])
  else()
    assert([[error_code]])
  endif()
endfunction()


function(write path content)
  file(WRITE "${path}" "${content}")
  message(
    "WRITE ${path}\n"
    "----------------------------------------\n"
    "${content}🔚\n"
    "........................................\n"
  )
endfunction()


function(run_test)
  if(NOT MAUD_WORKING_DIR STREQUAL "${MAUD_DIR}/project_test/${TEST_NAME}")
    message(
      FATAL_ERROR
      "
      Aborting project test; expected
        ${MAUD_DIR}/project_test/${TEST_NAME}
      but working directory is
        ${MAUD_WORKING_DIR}
      "
    )
  endif()

  message("\nproject testing in ${MAUD_WORKING_DIR}\n")

  # clear test directory
  file(GLOB entries *)
  if(entries)
    file(REMOVE_RECURSE ${entries})
  endif()

  # install maud to .usr
  run(COMMAND cmake --install "${CMAKE_BINARY_DIR}" --config Debug --prefix .usr)

  # set env
  prepend_to_path_list(Path .usr/bin)
  prepend_to_path_list(PATH .usr/bin)
  prepend_to_path_list(CMAKE_PREFIX_PATH .usr/lib/cmake)
  set(ENV{CXX} "${CMAKE_CXX_COMPILER}")
  # TODO use the same generator

  cmake_language(CALL "project test: ${TEST_NAME}")
endfunction()


function(prepend_to_path_list list_var path)
  cmake_path(CONVERT "$ENV{${list_var}}" TO_CMAKE_PATH_LIST list NORMALIZE)

  cmake_path(ABSOLUTE_PATH path)
  cmake_path(NATIVE_PATH path NORMALIZE path)
  list(PREPEND list "${path}")

  cmake_path(CONVERT "${list}" TO_NATIVE_PATH_LIST list NORMALIZE)

  set(ENV{${list_var}} "${list}")
endfunction()


function(library_name kind target_name out_var)
  set(ns CMAKE_${kind}_LIBRARY)
  set(out_var "${${ns}_PREFIX}${name}${${ns}_SUFFIX}" PARENT_SCOPE)
endfunction()


function(setup_tests)
  get_directory_property(names MACROS)
  list(FILTER names INCLUDE REGEX "^project test: (.+)$")
  list(TRANSFORM names REPLACE "^project test: (.+)$" "\\1")
  file(REMOVE_RECURSE "${MAUD_DIR}/project_test")
  foreach(name ${names})
    # create test directory
    set(test_dir "${MAUD_DIR}/project_test/${name}")
    file(MAKE_DIRECTORY "${test_dir}")

    # The test is just this same cmake file in script mode.
    # Including it from eval.cmake ensures access to cache variables,
    # like Maud's correct build directory.
    set(test_code "include([====[${CMAKE_CURRENT_LIST_FILE}]====])")

    add_test(
      NAME "project_test.${name}"
      COMMAND
        "${CMAKE_COMMAND}"
        -D "TEST_NAME=${name}"
        -D "MAUD_CODE=${test_code}"
        -P "${MAUD_DIR}/eval.cmake"
      WORKING_DIRECTORY "${test_dir}"
    )
  endforeach()
endfunction()

if(DEFINED TEST_NAME)
  run_test()
else()
  setup_tests()
endif()
