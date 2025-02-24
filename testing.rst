.. _testing:

Testing
-------

While scanning modules, ``Maud`` will detect and
:cmake:`register <command/add_test.html>` C++ unit tests.
(This can be disabled by setting ``BUILD_TESTING = OFF``.)
Unit testing is based on :gtest:`GTest </>`, and many basic
concepts like suites of test cases are inherited whole.
Many other aspects of writing tests are simplified.
Instead of duplicating GTest's documentation or explaining
unit tests from the ground up, this documentation will
assume familiarity and mostly describe the ways ``Maud``'s
usage differs.

Instead of defining test suites explicitly with classes,
one test suite is produced for each C++ source which includes
the special import declaration ``import test_``. Each test suite
is compiled into an executable target named ``test_.${STEM}``.

In a suite source file, two macros are included in the predefines
buffer (an explicit ``#include`` is unnecessary):
test cases are defined with :c:macro:`TEST_`,
and in a test case assertions are made with :c:macro:`EXPECT_`.

GTest is added to the include path, so explicit
``#include <gtest/gtest.h>`` is always available if necessary.

.. code-block:: c++

  import test_;

  TEST_(basic) {
    int three = 3, five = 5;
    EXPECT_(three == five);
    // ~/maud/.build/_maud/project_tests/unit testing/basics.cxx:12: Failure
    // Expected: three == five
    //   Actual:     3 vs 5
    EXPECT_(not three);
    // ~/maud/.build/_maud/project_tests/unit testing/basics.cxx:14: Failure
    // Expected: three
    //     to be false

    // EXPECT_(...) is an expression contextually convertible to bool
    if (not EXPECT_(&three != nullptr)) return;
    EXPECT_(&three != nullptr) or [](std::ostream &os) {
      // A lambda can hook expectation failure and add more context
    };

    // GMock's matchers are available
    EXPECT_("hello world" >>= HasSubstr("llo"));
  }

  // To check a test body against multiple values, parameterize with a range.
  TEST_(parameterized, {111, 234}) {
    EXPECT_(parameter > 0);
  }

  // To instantiate the test body with multiple types, parameterize with a tuple.
  TEST_(typed, 0, std::string("")) {
    EXPECT_(parameter + parameter == parameter);
  }


Unit test API
~~~~~~~~~~~~~

.. trike-macro:: TEST_(case_name, parameters...)

.. trike-macro:: EXPECT_(condition...)

.. cpp:module:: test_

.. trike-class:: template <typename Match, \
                           typename Description = DefaultDescription<Match>> \
                 Matcher

.. trike-var:: template <typename T> std::string const type_name

.. TODO document Main or whatever helper, setting up state in main()

Custom ``main()``
=================

Each suite is linked to ``gtest_main``. Since that defines ``main``
as a weak symbol, a custom main function can be written in a
test suite and it will override ``gtest_main``'s default.

To write a custom main function for all test executables,
write an interface unit with ``export module test_:main;`` and
that will be linked to each test executable instead of ``gtest_main``.

Overriding ``test_``
====================

If it is preferable to override ``test_`` entirely (for
example to use a different test library like
`Catch2 <https://github.com/catchorg/Catch2/tree/devel/docs>`_
instead of ``GTest``), write an interface unit with
``export module test_`` and define the cmake function ``maud_add_test``:

.. code-block:: cmake

  maud_add_test(source_file out_target_name)

If defined, this function will be invoked on each source file which
declares ``import test_``, ``module test_``, or any partition of it.
If ``out_target_name`` is set to a
:mastering-cmake:`target name <Key Concepts.html#targets>`,
the source file will be attached to it and imports automatically
processed as with other ``Maud`` targets. For example, if you would
prefer to unit test with a minimal custom framework you could define
your own ``module test_``:

``.test_.cxx``
    .. code-block:: c++

      module;
      #include "my_test_framework.hxx"
      export module test_;
      export using my_test_framework::expect_equals;
      // ...

Then inject this into unit tests by defining ``maud_add_test``:

``test_.cmake``
    .. code-block:: cmake

      function(maud_add_test source_file out_target_name)
        cmake_path(GET source_file STEM name)
        set(${out_target_name} "test_.${name}" PARENT_SCOPE)

        # Create a test executable and register it
        add_executable(test_.${name})
        add_test(NAME test_.${name} COMMAND $<TARGET_FILE:test_.${name}>)

        # Link the unit test with test_.cxx:
        target_sources(
          test_.${name}
          PRIVATE FILE_SET module_providers TYPE CXX_MODULES
          BASE_DIRS ${CMAKE_SOURCE_DIR} FILES .test_.cxx
        )
      endfunction()

Then this could be used in a unit test:

``math.test.cxx``
    .. code-block:: c++

      import test_;
      int main() {
        expect_equals(1 + 2, 3);
      }

.. _formatting-test:

Formatting test
~~~~~~~~~~~~~~~

By default, if `clang-format <https://clang.llvm.org/docs/ClangFormat.html>`_ is
detected then a test will be added which asserts that files are formatted
consistently::

  $ ctest --build-config Debug --tests-regex formatted --output-on-failure
  Test project ~/maud/.build
      Start 4: check.clang-formatted
  1/1 Test #4: check.clang-formatted ............***Failed    0.07 sec
  Clang-formating 16 files
  ~/maud/in2.cxx:15:42: error: code should be clang-formatted [-Wclang-format-violations]
  export void compile_in2(std::istream &is,   std::ostream &os);
                                           ^

A ``fix`` target will also be added which formats files in place::

  $ ninja fix.clang-format

Since the set of files which should be formatted is not necessarily
identical to the set which should be compiled, the separate
:ref:`glob(MAUD_CXX_FORMATTED_SOURCES) <built-in-globs>`
configures which files ``clang-format`` will be applied to. Since different
major versions of ``clang-format`` will frequently have different and
backwards-incompatible behavior and parameter spaces, the target version must
be specified in a ``.clang-format`` file::

  # Versions: 18
  BasedOnStyle: Google
  ColumnLimit: 90

.. TODO later
