.. _in2-templates:

``.in2`` Templates
------------------

``.in2`` templates are an efficient way to render CMake or build system
state to generated files, and are a built-in capability of projects which
use ``Maud``. Template file format is intended to evoke what's accepted
by :cmake:`configure_file() <command/configure_file.html>`. In the most
basic case, ``@VAR@`` gets replaced with ``${VAR}``'s value from cmake

.. code-block:: c++.in2

  auto foo_string = "@FOO_STRING@"; // substitution of cmake variables
  char at_char = '@@';              // if you need a literal @@
  // renders to
  auto foo_string = "foo and bar"; // substitution of cmake variables
  char at_char = '@';              // if you need a literal @

However, arbitrary commands can also be inserted between pairs of ``@``

.. code-block:: c++.in2

  const char* foo_feature_names[] = {@
    foreach(feature ${FOO_FEATURE_NAMES})
      render("  \"${feature}\",\n")
    endforeach()
  @};
  // renders to
  const char* foo_feature_names[] = {
    "FOO",
    "BAR",
    "BAZ",
  };

In a ``Maud`` project,
``.in2`` files are automatically globbed up and their templates rendered.
The template file ``${CMAKE_SOURCE_DIR}/dir/f.txt.in2`` will be rendered to
``${MAUD_DIR}/rendered/dir/f.txt``. Since globs are also be applied to files in
``${MAUD_DIR}/rendered``, rendered source files and headers will be included in
the build automatically.

Template files are compiled to cmake modules which render the template on inclusion.
As such they have access to all the capabilities of a cmake module, including
calling arbitrary commands. Rendering uses a dedicated scope, so ``set()`` will not
affect the enclosing scope (unless ``PARENT_SCOPE`` is specified, but are you *sure* you
want to do that?) In addition to everything available to auto-included cmake modules, the
following variables are available inside a template file:

- ``${RENDER_PATH}`` the path to which the template file will be rendered.
  It is a relative to ``${MAUD_DIR}/rendered``. A template file can also override
  its output path by writing to this variable.

- ``render(args...)`` appends its arguments into the rendered file.

- ``${IT}`` the current value in a pipeline.

Template compilation traces
~~~~~~~~~~~~~~~~~~~~~~~~~~~

For debugging purposes, each template's compiled CMake module includes
extensive traces from the compilation process encoded in comments:

.. code-block:: cmake

  # reference 1:9-1:19
  ##################################################################################
  # f_bar: @FOO_${BAR}@
  #         ^~~~~~~~~^
  ##################################################################################
  render("${FOO_${BAR}}")

If CMake raises an error while compiling or rendering a buggy template,
hopefully that will be sufficient to diagnose the problem. If not, these
traces can be helpful.

.. _in2-pipeline-syntax:

Pipeline syntax
===============

For additional syntactic sugar in the common case of modifying a
value before rendering, pipeline syntax is also supported. Pipelines
are a variable reference followed by one or more filters, separated
by ``|``.

.. code-block:: c++.in2

  bool foo_enabled = @FOO_ENABLED | if_else(1 0)@;
  // renders to
  bool foo_enabled = 1;

The pipeline's value is initialized from the referenced variable and
is stored in the variable ``${IT}``. Each pipeline filter is a cmake
command which reads and then overwrites ``${IT}``. After all filters
have been applied, the final value of ``${IT}`` is rendered.

In the example above, the pipeline is initialized with the value of
``${FOO_ENABLED}``, which is then passed to the filter ``if_else(1 0)``.
The filter finds the value :cmake:`truthy <command/if.html#constant>`,
and sets the pipeline's value to its first argument (a frequently
useful transformation since C++ doesn't recognize ``ON`` as truthy or
``foo-NOTFOUND`` as falsy.) Since there are no further filters, the
``1`` gets rendered.

Pipeline filters
~~~~~~~~~~~~~~~~

``Maud`` provides several built in filters, but they are also easy
to define: just prefix the new filter's name with ``in2_pipeline_filter_``
and define a function which modifies ``IT``. For example, the filter
``if_else`` is implemented with

.. code-block:: cmake

  function(in2_pipeline_filter_if_else then otherwise)
    if(IT)
      set(IT "${then}" PARENT_SCOPE)
    else()
      set(IT "${otherwise}" PARENT_SCOPE)
    endif()
  endfunction()

Lambda filters with arbitrary inline commands can also be written using
the special ``|()`` pipe. For example

.. code-block:: c++.in2

  @SOME_JSON_FILE |()
  execute_process(
    COMMAND jq ${QUERY} INPUT_FILE "${IT}" OUTPUT_VARIABLE IT
  )@

could be used to apply `jq <https://jqlang.github.io/jq/manual>`_
as part of a pipeline.

Built-in pipeline filters
~~~~~~~~~~~~~~~~~~~~~~~~~

``if_else(then otherwise)``
    Yields ``then`` if ``IT`` is truthy or ``otherwise`` if ``IT`` is falsy.

    .. code-block:: c++.in2

      bool foo_enabled = @FOO_ENABLED | if_else(1 0)@;
      // renders to
      bool foo_enabled = 1;

    .. seealso:: CMake's criteria for :cmake:`truthiness <command/if.html#constant>`.

``string_literal([RAW])``
    Wraps the value into a
    :cxx20:`string literal or raw string literal <lex.string#nt:string-literal>`

    .. code-block:: c++.in2

      auto str = @csv | string_literal(RAW)@;
      // renders to
      auto str = R"(foo,12
      bar,57)";

``set(argument)``
    Set the pipeline value to the argument; can be
    used to append or prepend within the pipeline

    .. code-block:: c++.in2

      int i = @SOME_COUNT | set("+${IT}ULL")@;
      // renders to
      int i = +789ULL;

``string([ TOLOWER | TOUPPER | STRIP | HEX | MAKE_C_IDENTIFIER | <HASH> ])``
    Map the pipeline value using a unary signature of
    :cmake:`string() <command/string.html>`

``string(JSON [ GET | TYPE | MEMBER | LENGTH | LIST ] path...)``
    Map the pipeline value using :cmake:`string(JSON) <command/string.html>`.

    ``JSON LIST`` maps a json array to a cmake ;-list

    .. code-block:: c++.in2

      @set(
        OBJ
        [[
          {"arr": [{"num": 42}, {"num": 77}]}
        ]]
      )@
      @OBJ | string(JSON LIST arr [] num)@
      // renders to
      42;77

    ... which is probably most useful in conjunction with
    :ref:`foreach filters <foreach-filters>`.

``string([ REPLACE substring | REGEX REPLACE regex ] replacement)``
    Map the pipeline value by replacing exact or regex matching
    substrings as with :cmake:`string(REPLACE) <command/string.html#replace>`
    or :cmake:`string(REGEX REPLACE) <command/string.html#regex-replace>`

``string(REGEX MATCHALL regex)``
    Split the pipeline value into a list as with
    :cmake:`string(REGEX MATCHALL) <command/string.html#regex-matchall>`

``join(glue)``
    Join the elements of a list pipeline value using the specified glue,
    as with :cmake:`list(JOIN) <command/list.html#join>`

    .. code-block:: c++.in2

      "@FOO_FEATURE_NAMES | join(" ")@"
      // renders to
      "FOO BAR BAZ"

.. _foreach-filters:

Foreach filters
~~~~~~~~~~~~~~~

When the input to a filter is a list it is frequently desirable to
transform each list member. Foreach filters allow pipeline syntax
to express that member transformation inline. Filters between
``|foreach|`` and ``|endforeach|`` are applied to each element of
an input list.

.. code-block::

  const char* foo_feature_names[] = {@
    FOO_FEATURE_NAMES |foreach| string_literal() |endforeach| join(", ")
  @};
  // renders to
  const char* foo_feature_names[] = {"FOO", "BAR", "BAZ"};
