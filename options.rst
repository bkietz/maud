.. _options:

Options
-------

Options are CMake ``CACHE`` variables which parameterize a project,
augmented for :ref:`presentation to users <options-summary>` and
:ref:`consistency checking <option-resolution>`.
If an aspect of your project needs to be easily tunable by users, an
option declaration is probably the most accessible way to expose it.

``option``
==========

.. _option-function:

.. code-block:: cmake

  option(
    name    < | BOOL | PATH | FILEPATH | STRING | ENUM enum_values... >
    help_string
    [DEFAULT default_value]
    [MARK_AS_ADVANCED]
    [REQUIRES [IF condition [dependency required_value]...]...]
    [VALIDATE CODE validation_code]
    [ADD_COMPILE_DEFINITIONS]
  )

Declare an option with the provided ``name``.

``< | BOOL | PATH | FILEPATH | STRING | ENUM enum_values... >``
    The :cmake:`type <prop_cache/TYPE.html>` of the ``CACHE`` variable.
    Options which are not explicitly typed are implicitly of type ``BOOL``.

    ``ENUM`` is an alias for ``STRING`` which additionally specifies allowed values
    by setting the :cmake:`STRINGS property <prop_cache/STRINGS.html>`.

    Every value (default, required values, ...) associated with options of
    ``PATH`` or ``FILEPATH`` type are converted to
    :cmake:`normalized, native paths <command/cmake_path.html#native-path>`.
    Additionally, if such a value is a relative path then it is assumed to be
    relative to ``CMAKE_SOURCE_DIR`` and will be converted to an
    :cmake:`absolute path <command/cmake_path.html#absolute-path>`.

    ``BOOL`` options are always validated to be either ``ON`` or ``OFF``.
    ``ENUM`` options are always checked against their value set. Additional
    validation can be specified using :ref:`VALIDATE CODE <option-custom-validation>`.

``help_string``
    The :cmake:`help string <prop_cache/HELPSTRING.html>` of the ``CACHE`` variable.

    An explanation of the option's purpose, displayed in ``ccmake`` and other
    GUIs. :ref:`Predefined macros <option-compile-definitions>` for the option will
    be decorated with a doxygen-style comment containing this text (which should be
    accessible to your language server). It will also be displayed in the
    :ref:`summary <options-summary>` when configuration completes.

    .. note::

      An escaped representation of the help string is stored, which will be shown
      directly in ``ccmake`` and other viewers which only support single line
      help strings.

``DEFAULT default_value``
    The option's value if no explicit value is provided and no requirements
    constrain it.

    .. note::

      In fresh builds, environment variables can be used to assign to options.
      For example if an option named ``FOO_LEVEL`` is not otherwise defined but
      ``ENV{FOO_LEVEL}`` is defined, then the environment variable will be used
      instead of the default. (This can be disabled by setting
      ``ENV{MAUD_DISABLE_ENVIRONMENT_OPTIONS} = ON``.)

    .. list-table:: Implicit defaults

      * - ``BOOL``
        - ``OFF``
      * - ``PATH`` or ``FILEPATH``
        - ``${CMAKE_SOURCE_DIR}``
      * - ``STRING``
        - ``""``
      * - ``ENUM``
        - the enum's first member

``MARK_AS_ADVANCED``
    Mark this ``CACHE`` variable :cmake:`advanced <prop_cache/ADVANCED.html>`.
    Its value will not be displayed by default in the :ref:`summary <options-summary>`
    (it will be displayed if its value is non-default) and GUIs (``ccmake`` for example
    provides an explicit toggle).

.. _requirement-block-syntax:

``REQUIRES``
    Begin a set of :ref:`requirement <option-resolution>` blocks. Each block
    begins with ``IF condition`` where ``condition`` is a possible value of the
    option. The block continues with a sequence of ``dependency required_value``
    pairs where each ``dependency`` names another option. If the option's
    value is resolved to ``condition``, then each ``dependency`` in its block
    will be set to the corresponding ``required_value``.

    .. note::

      A ``dependency`` need not be declared with ``option()`` before it is
      referenced in a requirement block.

    .. note::

      To simplify the common case of a ``BOOL`` option which only has
      requirements when it is ``ON``, ``REQUIRES IF ON`` may be shortened to
      just ``REQUIRES``.

.. _option-custom-validation:

``VALIDATE CODE validation_code``
    Provide code to validate the option. The code block will be evaluated after
    requirements have been resolved and the option's final value is known. For
    example this could be used to assert that a ``FILEPATH`` option specifies a
    readable file.

.. _option-compile-definitions:

``ADD_COMPILE_DEFINITIONS``
    If specified, macros will be added to the predefines buffer to expose
    option values to C++ code.

    .. list-table::

      * - For a boolean option an identically named macro
          will be defined to 0 or 1

        - .. code-block:: c

            // FOO_EMULATED: BOOL
            #define FOO_EMULATED 0

      * - The name of an enumeration option will be concatenated with
          each potential value to get macro names, each of which are
          defined to 0 or 1

        - .. code-block:: c

            // FOO_LEVEL: ENUM LOW MED HI
            #define FOO_LEVEL_LOW 0
            #define FOO_LEVEL_MED 0
            #define FOO_LEVEL_HI 1

      * - For options of any other type an identically named macro will be
          defined to a string literal

        - .. code-block:: c

            // FOO_SOCKET_PATH: FILEPATH
            #define FOO_SOCKET_PATH "/var/run/foo"

.. _options-summary:

Options summary
===============

After configuration is complete, a summary of option values is printed.
The resolved value of each option is printed, along with the reason for that
value and the option's help string.

Groups of associated options can be declared by writing
``set(OPTION_GROUP "FOO-related options")`` before declaring the options.
This adds a heading in the summary.

.. code-block:: lua

  -- FOO-related options:
  --
  -- FOO_EMULATED = OFF [constrained by FOO_LEVEL]
  --      Emulate FOO functionality rather than requesting a real FOO endpoint.
  -- FOO_LEVEL = HI (of LOW;MED;HI) [user configured]
  --      What level of FOO API should be requested.
  --      LOW is primarily used for testing and is not otherwise recommended.
  -- FOO_SOCKET_PATH = /var/run/foo [default]
  --      Explicit socket for FOO endpoint.

.. TODO add a special target to summarize the options again

As part of the options summary, a cmake
:cmake:`configure preset <manual/cmake-presets.7.html#configure-preset>`
is appended to ``CMakeUserPresets.json`` for easy copy-pasting, reproduction, etc.

.. _option-resolution:

Option Requirements and Resolution
==================================

Project options are frequently interdependent; for example enabling one feature
might be impossible without enabling its dependencies. Manually resolving these
interdependencies to a consistent state across all options in the project is
frequently messy and error prone.
:ref:`option() <option-function>` integrates a solution to this problem in
the :ref:`REQUIRES <requirement-block-syntax>` argument. The requirements of
each option can be specified in terms of assignments to other options on which
it depends. 

.. code-block:: cmake

  option(
    FOO_LEVEL ENUM LOW MED HI
    REQUIRES            # requirements of FOO_LEVEL follow
    IF HI               # if FOO_LEVEL is HI ...
      FOO_EMULATED OFF  # ... FOO_EMULATED must be set to OFF
  )

The first time an option is accessed, its value and the values of
its dependencies are resolved. This ensures all requirements are met (or reports
an error if unsatisfiable requirements are encountered).

.. tab:: ✅ Valid

  .. code-block:: cmake

    option(alpha BOOL DEFAULT ON REQUIRES beta 3)
    option(beta ENUM 1 2 3)

    # beta accessed; triggers resolution of alpha
    #   no requirements on alpha; alpha resolved to ON
    # alpha=ON requires beta=3; beta resolved to 3
    if(beta EQUAL 1)
      # ...
    endif()

.. tab:: ❌ Conflict

  .. code-block:: cmake

    option(alpha BOOL DEFAULT ON REQUIRES beta 3)
    option(beta ENUM 1 2 3)
    option(omega BOOL DEFAULT ON REQUIRES beta 1)

    # beta accessed; triggers resolution of alpha and omega
    #   no requirements on alpha or omega; both are resolved to ON

    # CMake Error at /tmp/usr/lib/cmake/Maud/Maud.cmake:1455 (message):
    #
    #       Option constraint conflict: beta is constrained
    #       by alpha to be
    #         "3"
    #       but omega requires it to be
    #         "1"
    if(beta EQUAL 1)
      # ...
    endif()

.. warning::

  Since option resolution is implemented using
  :cmake:`variable_watch <command/variable_watch.html>`, accessing an option's
  value through ``$CACHE{FOO}`` or ``get_property(... CACHE FOO PROPERTY VALUE)``
  will circumvent resolution.

Options are considered to form a directed acyclic graph: each option may
declare a requirement on any other option as long as no cycles are formed.
Options with no requirements placed on them will have their default or
user configured value. Otherwise requirements determine the option's value
(even if the value required happens to be a the dependency's default).

.. tab:: ✅ Valid

  .. code-block:: cmake

    option(foo0 BOOL DEFAULT ON REQUIRES foo1 ON)
    option(foo1 BOOL DEFAULT ON REQUIRES foo2 ON)
    option(foo2 BOOL DEFAULT ON REQUIRES foo3 ON)
    option(foo3 BOOL DEFAULT ON)

    # foo3 accessed; triggers resolution of foo2
    #   ... triggers resolution of foo1
    #     ... triggers resolution of foo0
    #       no requirements on foo0; foo0 resolved to ON
    #     foo0=ON requires foo1=ON; foo1 resolved to ON
    #   foo1=ON requires foo2=ON; foo2 resolved to ON
    # foo2=ON requires foo3=ON; foo3 resolved to ON
    if(foo3)
      # ...
    endif()

.. tab:: ❌ Cyclic dependency

  .. code-block:: cmake

    option(foo0 BOOL DEFAULT ON REQUIRES foo1 ON)
    option(foo1 BOOL DEFAULT ON REQUIRES foo2 ON)
    option(foo2 BOOL DEFAULT ON REQUIRES foo3 ON)
    option(foo3 BOOL DEFAULT ON REQUIRES foo0 ON)

    # foo3 accessed; triggers resolution of foo2
    #   ... triggers resolution of foo1
    #     ... triggers resolution of foo0
    #       ... re-enters resolution of foo3

    # CMake Error at /tmp/usr/lib/cmake/Maud/Maud.cmake:1436 (message):
    #
    #       Circular constraint between options
    #         foo3;foo2;foo1;foo0
    if(foo3)
      # ...
    endif()

.. note::

  User provided values (via ``-DFOO=0`` on the command line, through preset
  JSON, from an environment variable, ...) are not considered a hard constraint
  and will always be overridden if necessary to satisfy declared requirements.
  On a fresh configuration it is possible to detect such an override and a
  warning will be issued to facilitate avoidance of inconsistent user provided
  values.

Conflicting requirements will result in a ``FATAL_ERROR``. Likewise if a
requirement is placed on an option which has been accessed, that requirement can
only check for consistency with the option's already resolved value. Whenever
possible I recommend grouping declarations of interdependent options, which
makes it easier to avoid this error.

.. tab:: ✅ Valid

  .. code-block:: cmake

    option(alpha BOOL DEFAULT ON REQUIRES beta 3)
    option(beta ENUM 1 2 3)

    # beta accessed; triggers resolution of alpha
    #   no requirements on alpha; alpha resolved to ON
    # alpha=ON requires beta=3; beta resolved to 3
    if(beta EQUAL 1)
      # ...
    endif()

.. tab:: ❌ Constraining resolved

  .. code-block:: cmake

    # alpha is declared later
    option(beta ENUM 1 2 3)

    # beta accessed; no requirements on beta; beta resolved to 1
    if(beta EQUAL 1)
      setup_beta_feature(1)
    endif()

    # beta's value is already resolved by the access above
    option(alpha BOOL DEFAULT ON REQUIRES beta 3)

    # CMake Error at /tmp/usr/lib/cmake/Maud/Maud.cmake:1468 (message):
    #
    #       Option constraint conflict: beta was already resolved to
    #         "1"
    #       but alpha requires it to be
    #         "3"
