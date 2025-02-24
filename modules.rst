.. _modules:

=======
Modules
=======

.. default-domain:: c++
.. highlight:: c++

C++20 introduced a new way to share declarations between translation units.
Instead of repeating declarations manually or implicitly through header inclusion,
they can be directly imported from a binary file.

To define a module, write a :cxx20:`module interface unit <module.unit#2>`-
a C++ source file with an export module declaration:

.. code-block::

  export module foo;
  export int foo_score() { return 3; }
  export int doubled_foo_score();

Module interface units may export declarations. Those exported declarations will
be usable in any translation unit which imports the module:

.. code-block::

  import foo;
  bool foo_score_is_critical() { return foo_score() > 5; }

In addition to interface units, module implementation units can be written which
include definitions and implementation details for the declarations exported by
interface units:

.. code-block::

  module foo;
  int doubled_foo_score() { return foo_score() * 2; }

The details for how to compile source files into object files, libraries, and
executables are compiler-specific. For further information, consult the
`Clang <https://clang.llvm.org/docs/StandardCPlusPlusModules.html>`_,
`GCC <https://gcc.gnu.org/onlinedocs/gcc/C_002b_002b-Modules.html>`_, and
`Microsoft <https://learn.microsoft.com/en-us/cpp/cpp/modules-cpp>`_
documentation on C++ modules.

Module = library
~~~~~~~~~~~~~~~~

In a ``Maud`` project, we (mostly) make the extra stipulation that modules
correspond to libraries. This is *not* part of the C++ spec for modules but
it is a natural simplification for a build system, since it maps them onto
well-understood cmake objects. The way sources should be compiled is inferred
from the module declarations in the C++ sources: C++ sources are scanned as
part of the cmake configure step and their imports and exports enumerated.

- For each module declared, a library will be built from all the interface
  and implementation units of that module.
- For each module imported, a library will be linked- either one built by
  your project or one discovered using
  :cmake:`find_package() <command/find_package.html>`.
- For each module declared, installation of its library will be configured
  along with installation of its module interface units. This includes
  ``find_package()``-compatible cmake scripts which will enable other
  ``Maud`` based projects to find your library with no hand-written cmake;
  just ``import``.

  .. note::

    Modules whose name ends in ``_`` produce non-installed ``OBJECT``
    libraries. This is useful for projects which organize internal functions into
    libraries, but require those not be installed.

Executables are generated from each source which imports the special
module ``executable``. The executable's name the
:cmake:`STEM <command/cmake_path.html#decomposition>`
(source file name, stripped of all extensions).

:ref:`testing` are generated from sources which import the special
module ``test_``.

Executables and tests can both be implementation units of a module.
This can be helpful when testing a module's non-exported declaration or when
an executable is a trivial front end to a module.

Source files with no module declaration or special import will not be
automatically attached to any target, and other target types require
explicit cmake. To manipulate a target before ``Maud`` has attached
sources to it, you can write ``add_library(foo SHARED)`` in cmake.
Sources which declare ``module foo`` will still be attached to it.

.. note::

  Whether libraries are static or shared by default is controlled by
  :cmake:`option(BUILD_SHARED_LIBS) <variable/BUILD_SHARED_LIBS.html>`

Module partitions:
~~~~~~~~~~~~~~~~~~

Module partitions are a useful way to compartmentalize a module interface:

.. code-block::

  // foo-bar.cxx
  export module foo:bar;
  export int foo_bar();

  // foo-quux.cxx
  export module foo:quux;
  import :bar;
  export int foo_quux() { return foo_bar() + 1; }

  // foo-bar-impl.cxx
  module foo;
  int foo_bar() { return 0; }

Partitioning your module interface is a purely internal organizational choice;
only whole partitions can be imported outside their module of origin.

.. code-block::

  export module foo;
  // import bar:alpha; // ERROR!
  import bar; // includes bar:alpha anyway

If you want to define independently importable but still related modules, note that
module names may be dot-separated identifiers. ``export module foo.base;`` and
``export module foo.extensions;`` will produce two entirely distinct libraries.

.. note::

  The :cxx20:`standard <module.unit#3>` requires that a **primary** module
  interface unit must be provided with an ``export import`` declaration for
  every partition interface unit.

  .. code-block::

    export module foo;
    export import :bar;
    export import :quux;

  In a ``Maud`` project a correct primary module interface unit will be
  generated if none is detected; if you have written partitions then you
  *probably* don't require anything but those ``export import`` declarations
  in your primary module interface unit.

Questionable support:
~~~~~~~~~~~~~~~~~~~~~

- Translation units other than module interface units are not necessarily
  :cxx20:`reachable <module.reach#1>` and importing translation units other than
  necessarily reachable ones is implementation defined. For example this includes
  importing a partition which is not an interface unit.
- As of this writing GCC 14 does not support ``module:private``.
- Header units are not currently supported by ``Maud``.
- ``import std`` might be supported by your compiler, but ``Maud`` does not guarantee it.

Preprocessing
~~~~~~~~~~~~~

By default, maud uses a custom module scanner which ignores preprocessing
for efficiency and stops reading source files after the import declarations.
This works in the most common case where the preprocessor only encounters
``#include`` directives and an occasional ``#define``, which leaves
the module dependency graph unaffected. However it is possible for the
preprocessor to affect module and import declarations. For example:

- an import declaration could be inside a conditional preprocessing block

.. code-block::

  module foo;
  #if BAR_VERSION >= 3
  import bar;
  #endif

- a set of import declarations could be included

.. code-block::

  module foo;
  #include "common_imports.hxx"

- a macro could expand to a pragma directive which modifies an ``#include``

.. code-block::

  module;
  #include "macros.hxx"
  PUSH_INGORED_WARNING(-Wunused-variable);
  #include "dodgy.hxx"
  POP_INGORED_WARNING();
  module foo;

- a macro could be used to derive the name of the module

.. code-block::

  module;
  #include "macros.hxx"
  module PP_CAT(foo_, FOO_VERSION);

(I'm actually not sure that the last two are even legal since a global
module fragment should exclusively contain preprocessing directives
:cxx20:`module.global.frag#1`, however clang allows both.)

IMHO, it is not desirable to write interface blocks which depend on preprocessing.
Moreover C++26 will restrict usage of the preprocessor severely in module declarations
as described in `P3034R1 <https://isocpp.org/files/papers/P3034R1.html>`_.

.. _maud-preprocessing-scan-options:

For source files which require it, the property ``MAUD_PREPROCESSING_SCAN_OPTIONS``
can be set in cmake. This property should contain all compile options
necessary to correctly preprocess the source file, for example
``-I /home/i/foo/include -isystem /home/i/boost/include -DFOO_ENABLE_BAR=1``.

Note that the output of these tools is in the JSON format described by `p1689
<https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p1689r5.html>`_
and does not distinguish between a module implementation unit of ``foo`` from a
source file which happens to import ``foo``. Without information about which module
an implementation unit is associated with, it cannot be automatically added to
the corresponding target. As a workaround if you must have a preprocessing scan
of an implementation unit, you can split the implementation unit into partitions
whose primary module is exposed.

