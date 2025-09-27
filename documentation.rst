.. _documentation:

Documentation
-------------

``Maud`` builds include a target named ``documentation``.
Building this target globs up all ``reStructuredText (.rst)``
files and renders them with `Sphinx. <https://www.sphinx-doc.org/>`__

.. code-block:: shell-session

  $ ninja -C .build documentation
  [73/76] Building dirhtml with sphinx

  # output from each builder is in .build/documentation/$builder
  $ python -m http.server -d .build/documentation/dirhtml 8000
  Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...

  $ xdg-open http://localhost:8000

By default only ``dirhtml`` will be built. ``option(SPHINX_BUILDERS)``
controls which :sphinx:`builder <builders>` are used or disables
building documentation if no builders are specified.

All dependencies necessary for building documentation are installed to a
`virtual environment <https://docs.python.org/3/library/venv.html>`_
located in ``.build/documentation/venv``.
The versions of all dependencies are frozen.
This ensures isolation from other Python environments and improves
repeatability of builds. If a Python3 interpreter is not discovered,
then documentation will be disabled.

The documentation root directory is the project's root directory.
Write documentation throughout your project, directly alongside the code
it explains. (If nothing else it makes :sphinx:`inclusion directives
<restructuredtext/directives.html#directive-literalinclude>`
easier.)
If you need docs in their own dir or you need generated docs,
``set(MAUD_DOCUMENTATION_DIR)`` in cmake... but first try writing a
`sphinx extension. <https://www.sphinx-doc.org/en/master/development/index.html#extending-sphinx>`__

..
    I have never seen a project which wasn't littered with markdown
    files and other informal doc... (TODO.md yes I know) most of it
    difficult to promote into Real Doc
    because it was in a different format or in the wrong directory or
    ... I hope Maud makes it easy enough to write Real Doc that I can
    break my habit of writing Miscellaneous Doc in irredeemable places.

Configuration
=============

If explicit configuration becomes necessary for your project, create a directory
named ``sphinx_configuration/`` at the root of your documentation sources.
This directory will be passed to Sphinx as
`--conf-dir <https://www.sphinx-doc.org/en/master/man/sphinx-build.html#cmdoption-sphinx-build-c>`__
so it should contain your ``conf.py``. The default configuration is provided as
a module, so if you only need to make a small tweak
(for example adding an extension), you can just write

.. code-block:: python

  from maud.default_sphinx_configuration import *
  extensions += ["my_local_ext"]

(The default ``conf.py`` is just
``from maud.default_sphinx_configuration import *``)

If the file ``sphinx_configuration/requirements.txt`` exists, then it will
be used to install dependencies to Sphinx' virtual environment. The default
configuration includes sphinx and the following extensions:

.. list-table::

  * - `Furo <https://pradyunsg.me/furo/>`__
    - my favorite Sphinx theme
  * - :ref:`trike`
    - extracts APIdoc for easy inclusion
  * - `sphinx_inline_tabs <https://sphinx-inline-tabs.readthedocs.io>`__
    - adds ``.. tab::`` for writing inline tabbed content
  * - `sphinx_copybutton <https://sphinx-copybutton.readthedocs.io>`__
    - adds a little “copy” button to the right of your code blocks
  * - :sphinx:`ifconfig <extensions/ifconfig.html>`
    - conditionally includes content based on configuration values

Maud also injects itself as a sphinx extension and sets some
configuration when the values are obvious or can be inferred:

- the Sphinx
  :sphinx:`project name <configuration.html#confval-project>`
  will be the same as the CMake
  :cmake:`PROJECT_NAME <variable/PROJECT_NAME.html>`
- The identity and URL of your
  `forge <https://en.m.wikipedia.org/wiki/Forge_(software)>`__
  will be inferred and used to set up
  `Furo's buttons <https://pradyunsg.me/furo/customisation/top-of-page-buttons>`__
- Author and copyright will be guessed from the first commit to
  the Sphinx root document

this extension also provides ``conf.py`` access to the cmake ``CACHE``,
which includes build :ref:`options`.
For example, ``option(ENABLE_DIAGRAMS)`` might be used in ``conf.py``
to conditionally enable an extension:

.. code-block:: python

   from maud import CACHE
   if CACHE["ENABLE_DIAGRAMS"]:
       extensions += ['awesome-diagrams-ext']

... or ``option(DOCUMENT_EXPERIMENTAL)`` might be used with
:sphinx:`ifconfig <extensions/ifconfig.html>`:

.. code-block:: rst

  .. ifconfig:: CACHE["DOCUMENT_EXPERIMENTAL"]

    .. experimental features doc

 .. note:: This last example does not require explicit ``conf.py``
