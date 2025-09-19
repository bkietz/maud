====
Maud
====

A low configuration convention for C++ projects.

``Maud`` arose from the observed high overhead in setting up new C++
projects. Leaving documentation unwritten or in comments or in ``.md``
files, copy-pasting scripts from older projects, unit testing with
bare ``assert()``, ... These are all things I've done because I wanted
to start work on one part of a project and all the other parts were
not already there.

The more conventional solution to this problem is to provide a starter
project. There are a number of good ones out there, but starter projects
have a drawback: they are tantamount to a dependency which you fork into
your own repo. This makes it far harder to tell where the copypasta came
from and it means you probably can't just apply upstream fixes to
known issues.

To me it seems better to provide a minimal, uniform project structure which
is mostly defined by things that aren't there; an **empty** directory is
a valid ``Maud`` project. If you want to start by writing a unit test,
you can do so by writing its :ref:`C++ source <testing>` and nothing else.
If you want to start by writing documentation, you can do so by writing its
:ref:`rst source <documentation>` and nothing else. Without consulting any
script or manifest, it's possible to read a C++ source and know what it's
compiled and linked to and how the build artifact will be installed.

Explicit configuration is always available when necessary, but I think it's
beautiful to (mostly) sidestep it.

Features
--------

:ref:`Turbocharged CMake <cmake>`
    ``Maud`` is built on :cmake:`CMake </>`, but works hard to eliminate
    boilerplate. For simple projects, **no** hand written ``cmake`` is required.
    Whenever explicit configuration becomes necessary, minimal and focused ``cmake``
    can be written wherever makes the most sense for your project.

:ref:`Globbing <globbing-case>`
    ``Maud`` extends CMake's built in globbing support with more expressive
    patterns, support for exclusion as well as inclusion, and greater performance.

    To briefly summarize, :ref:`built-in-globs` are used to find:

    - ``cmake_modules`` directories, which are added to the module path
    - ``.cmake`` modules, which are automatically included
    - ``.in2`` template files, which are rendered
    - ``include`` directories, which are added to the include path
    - C++ source files, which are scanned for modules and automatically
      attached to build targets
    - ``.rst`` files, which are rendered to HTML

:ref:`Documentation <documentation>`
    Rendering **really** usable documentation is a priority for ``Maud``.
    All we really need for that is a Python3 interpreter, which is used to
    run `Sphinx <https://www.sphinx-doc.org/>`_ and render all ``.rst`` files
    to lovely HTML (or other formats).

:ref:`Inferrence of targets from C++ modules <modules>`
    The executables, libraries, and tests defined by a project are inferred from
    automatic scans of C++ sources. Hello world with ``Maud`` is a single source
    file:

    .. code-block:: c++

      #include <iostream>
      import executable;
      int main() {
        std::cout << "hello world!" << std::endl;
      }

    Targets are also automatically linked to anything they import and are
    set up for installation. For library targets, installation includes
    making them automatically :cmake:`discoverable <command/find_package.html>`
    by other ``Maud`` projects which import them.

:ref:`More sophisticated options <options>`
    Maud backwards-compatibly overloads cmake's built-in
    :cmake:`option <command/option.html>` function to provide
    support for more sophisticated
    configuration options:

    - uniform declaration for all types of option
    - resolution of interdependent option values
    - easy access to options in C++ as predefined macros
    - clean summarization of all options, complete with multiline help strings
    - serialization to :cmake:`preset JSON <manual/cmake-presets.7.html#configure-preset>`
      for repeatability

    .. code-block:: cmake

      option(
        FOO_LEVEL
          ENUM LOW MED HI
        "
        What level of FOO API should be requested.
        LOW is primarily used for testing and is not otherwise recommended.
        "
        DEFAULT MED

        REQUIRES
        IF HI
          # LOW or MED levels can be emulated but HI requires a physical FOO endpoint.
          FOO_EMULATED OFF

        ADD_COMPILE_DEFINITIONS
      )


.. _generated files blurb:

First class support for generated files
    A common source of cmake boilerplate is wiring up rendering of template files,
    running schema compilers, and otherwise generating code. ``Maud`` provides a
    single build subdirectory for these files to land in and natively supports
    including them in any file set: all globs will include matching files in
    ``${MAUD_DIR}/rendered`` as well as those in ``${CMAKE_SOURCE_DIR}``
    (unless :ref:`explicitly excluded <glob-function-exclude_rendered>`).

    Additionally, projects using ``Maud`` can use a built-in
    :ref:`template format <in2-templates>` inspired by ``configure_file()``
    to smoothly render configuration information into generated code.
    If the template file ``${CMAKE_SOURCE_DIR}/dir/foo.cxx.in2`` exists,
    it will automatically be rendered to ``${MAUD_DIR}/rendered/dir/foo.cxx``
    and included in compilation alongside non-generated C++:

    .. code-block:: c++.in2

      #define FOO_ENABLED @FOO_ENABLED | if_else(1 0)@
      // renders to
      #define FOO_ENABLED 1

Table of Contents
-----------------

.. toctree::
  :glob:

  *
