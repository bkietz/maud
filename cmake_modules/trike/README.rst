.. image:: /cmake_modules/trike/trike.png
  :class: only-light

.. image:: /cmake_modules/trike/trike-dark.png
  :class: only-dark

Trike
=====

    Simple doc comments for C++

A `Sphinx <https://www.sphinx-doc.org/>`_ extension which scans C++ sources
for ``///`` comments. `libclang <https://libclang.readthedocs.io>`_
is used to associate these with declarations. These can then be
referenced in reStructuredText.

For example, given the following C++ and rst sources in your project:

``frob.cxx``
    .. code-block:: c++

      /// Frobnicates the :cpp:var:`whatsit` register.
      ///
      /// :return: false if no frobnication was necessary
      bool frobnicate();

``index.rst``
    .. code-block:: rst

      .. trike-function:: bool frobnicate()

      .. cpp:var:: volatile int whatsit

The ``trike-function`` directive above will render equivalently to
a `cpp:function <https://www.sphinx-doc.org/en/master/usage/domains/cpp.html#directive-cpp-function>`_
directive with content drawn from the ``///``.

.. cpp:function:: bool frobnicate()

  Frobnicates the :cpp:var:`whatsit` register.

  :return: false if no frobnication was necessary

.. cpp:var:: volatile int whatsit

The content of ``///`` is interpreted as reStructuredText, so
they can be as expressive as the rest of your documentation. Of particular
note for those who have used other apidoc systems: cross references from
``///`` comments to labels defined in ``*.rst`` (or other ``///``) will just work.

Usage
-----

In C++, document a declaration by writing a ``///`` comment on the line above it.
Then in reStructuredText, use

.. rst:directive:: .. trike-put:: directive_name directive_argument

  .. rst:directive:option:: members: also include members of the referenced declaration

  Renders associated ``///`` content, optionally with nested member documentation.
  For example if ``class Foo`` was documented, this could be referenced with

  .. code-block:: rst

    .. trike-put:: cpp:class Foo

  Only the current namespace and module (as set by ``.. cpp:namespace::`` and
  ``.. cpp:module::``) are searched for matching ``///``. (Note that
  macros are never in a namespace; they must always be looked up at global scope.)

  For purposes of lookup, any whitespace is collapsed to a single
  :cpp:expr:`" "` and all ``\`` are ignored. So for example

  .. code-block:: c++

    template <typename T, typename U, typename V> class Bar

  could be referenced with

  .. code-block:: rst

    .. trike-put:: cpp:class template <typename T, \
                                       typename U, \
                                       typename V> \
                             Bar

Since :rst:dir:`trike-put` produces ``cpp`` domain objects, those objects can be cross
referenced with ``cpp`` domain roles. Convenience aliases for :rst:dir:`trike-put`
are provided which allow concise reference to the most common directives:

+-----------------------+---------------------+
| directive name        | produces            |
+=======================+=====================+
| ``trike-class``       | ``cpp:class``       |
+-----------------------+---------------------+
| ``trike-struct``      | ``cpp:struct``      |
+-----------------------+---------------------+
| ``trike-function``    | ``cpp:function``    |
+-----------------------+---------------------+
| ``trike-member``      | ``cpp:member``      |
+-----------------------+---------------------+
| ``trike-var``         | ``cpp:var``         |
+-----------------------+---------------------+
| ``trike-type``        | ``cpp:type``        |
+-----------------------+---------------------+
| ``trike-enum``        | ``cpp:enum``        |
+-----------------------+---------------------+
| ``trike-enum-struct`` | ``cpp:enum-struct`` |
+-----------------------+---------------------+
| ``trike-enum-class``  | ``cpp:enum-class``  |
+-----------------------+---------------------+
| ``trike-enumerator``  | ``cpp:enumerator``  |
+-----------------------+---------------------+
| ``trike-union``       | ``cpp:union``       |
+-----------------------+---------------------+
| ``trike-concept``     | ``cpp:concept``     |
+-----------------------+---------------------+
| ``trike-macro``       | ``c:macro``         |
+-----------------------+---------------------+

If the automatic directive/declaration detection is unsatisfactory, specifying
those explicitly is also supported. For example, in C++ variadic macros have an
uninformative ``...`` where you might prefer a named parameter, in which case
you could document the macro with:

.. code-block:: c

  ///.. c:macro:: ASSERT(condition...)
  ///
  /// :param condition: the condition to be checked for truthiness
  #define ASSERT(...) ::assertion_helpers::DoAssert( \
    __VA_ARGS__, STRINGIFY(__VA_ARGS__), __FILE__, __LINE__)

The macro will now be referencable as ``ASSERT(condition...)`` (Lookup of
``ASSERT(...)`` will fail.) The namespace of the documented declaration will
be unchanged. In order to be recognized, the explicit directive must be the
first line of the ``///``, and there must be no space in the prefix ``///..``

Alternatively, you might want to hide a
`CRTP <https://en.cppreference.com/w/cpp/language/crtp>`_
base class from documentation:

.. code-block:: c++

  ///.. cpp:class:: template <typename T> Stream
  template <typename T>
  class Stream : impl::StreamMixin<T>

... that base class doesn't appear in the explicit directive, so sphinx will
never know about it.

Configuration
-------------

Minimally, add ``trike`` to your extensions list and enumerate
the C++ sources which should be parsed for ``///``:

``conf.py``
    .. code-block:: python

      extensions = ["trike"]
      trike_files = list(Path("src").glob("**/*.hxx"))

If a function is provided which maps C++ file/lines to URIs, it will be
used to produce links to the source of any ``///`` referenced by
:rst:dir:`trike-put`, in the style of
`linkcode. <https://www.sphinx-doc.org/en/master/usage/extensions/linkcode.html>`_

``conf.py``
    .. code-block:: python

      def trike_get_uri(file: Path, line: int) -> str:
          return f"https://my.src/{file.relative_to(REPO)}#L{line}"

Optionally, the compile options which should be passed to ``libclang``
when parsing can be passed as a list of strings. If the compile options
required by your C++ sources are not uniform, a mapping can be specified
instead of a single list:

``conf.py``
    .. code-block:: python

      # default: no arguments will be passed to libclang

      # this list will be passed to libclang for all C++ sources
      trike_clang_args = ["-std=c++23"]

      # use C++23 for most files, but override for special_case.cxx
      trike_clang_args = defaultdict(lambda: ["-std=c++23"])
      trike_clang_args[Path("special_case.cxx")] = ["-std=c++11", "-DFOO=1"]

.. seealso::

  `Hawkmoth <https://jnikula.github.io/hawkmoth/stable>`_
      Another Sphinx extension which uses ``libclang`` to extract C/C++ doc
      comments. Compared to trike, Hawkmoth supports C as well as C++, scans
      only for ``/**`` comments, allows for custom transformations of comment
      text on insertion, and uses the AST more extensively (for example,
      Hawkmoth can produce documentation for a struct's members even if
      those members are not themselves documented). By contrast trike
      emphasizes C++ support, predictability of declaration strings, and
      easy override with explicit directives when necessary.

  `Doxygen <https://www.doxygen.nl>`_
      The best known apidoc system for C++.

  `Breathe <https://www.breathe-doc.org>`_
      A Sphinx extension which provides directives for accessing
      Doxygen's XML output. Doxygen is robust and
      well understood, but represents an extra hurdle in building your docs.

  `Autodoc2 <https://sphinx-autodoc2.readthedocs.io>`_
      A rewrite of ``autodoc``, the archetypal apidoc integration for Sphinx.
      Nothing to do with C++, but inspirational in its excellence and simplicity.

  `clang-doc <https://clang.llvm.org/extra/clang-doc.html>`_
      A tool for extracting documentation from C++ source;
      similar to Doxygen, but powered by clang's LibTooling.
      Still in development.

.. I remember seeing a project that had the same basic idea using
   tree-sitter to parse c++ but I can't find it now

