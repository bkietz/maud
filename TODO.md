NEXT
----

- provide a hook for missing imports; then we can have others drop in
  "not only link but also do package management with $mine"
- write doc
  - getting_started.rst
  - doc c++17 project
  - we need an "introduction to C++20 modules" page too; there won't just be C++
    experts needing to build stuff
  - validation of dependencies is left to c++; if the result is just an error
    that sends the user back to the dependency provider then a `static_assert`
    is just as good as whatever cmake might raise
- more test projects
  - use a maud based project with fetchcontent
  - build man pages and install
  - install the project test framework
- improve docs
  - make zero conf docs actually work
  - generate a default full depth toctree and all-target glossary page
  - sphinx should stage its own rsts; conf runs before sphinx reads index.rst
  - strip common base dirs from docs; somebody won't be able to resist stuffing all the
    .rsts into a docs/ subdirectory and then docs/ should be considered the root of
    the documentation
  - compile html documentation to a docset
- harden and test the scanner
  - support this when preprocessing isn't required
- git ls-files starts up *quick*, so we could use it even for small projects,
  let `_maud_glob` use that
- glob `.configure_preset.json` and build `CMakePresets.json`


TODO: break Maud.cmake up into distinct modules
-----------------------------------------------

It'd be friendlier to folks who just want `option()` if there's
one or two files to copy. Currently Maud is monolithic and will
break if you're not using the full module scan system.

- `option()`
- Sphinx and maud_apidoc targets
- globbing and configurable regen
- loading the cache
- .in2 templates


TODO: provide more CLI functionality
------------------------------------

With `compile_commands.json` copied to source root, we can
infer the most recent build dir and from that probably the
default config.

With an optional dependency as minimal as "`fzf` or `sk` on the PATH",
a much nicer CLI can be built. For example this could provide a vast
improvement over ctest's (even with gtest_discover_tests):

```
~/proj $ maud --test
> projectenum
  7/32 ───────────────────────────────────────────────────────────────────────────────────────────
▌ project/27/validate enum option
  project/8/unit testing main
  project/7/internal unit testing
  project/29/documentation
  project/13/rendered in2 source
  project/9/custom unit testing
  project/19/internal decl faux parts
```

The same basic approach could be applied to building specific targets,
running some fixer, ...

All of this should still uphold the basic form of the `maud` tool:
A build is a complex but unitary transformation, and running the tool
should always complete that transformation. It just happens that by
default we don't run the tests or install (but they logically belong
to that same singular flow).


TODO: document how to do optional dependencies
----------------------------------------------

How do we deal with optional dependencies? If there is an
option named `YAML_ENABLED` and we switch it off, then we
should not need to ensure `import yaml;` still works.
However surrounding the import with an `#if` is transparent
to maud_scan so it wouldn't remove the dependency.

We have two methods built-in:
- enable pre-processing scan for a unit which `export import`
  the optional dependencies guarded by CPP conditions
- write that unit as a `.in2` template and guard optional
  imports with cmake conditions

One thing which is potentially brittle is a dependency which
is only imported for debugging; in the case of a multi config
generator we cannot know which config is selected at build time.
I guess we just have to assume that if any configuration would
import a dependency then it must be available for linking to any
configuration. In the example above, the import will still be
linked in release but not used.


TODO: allow deferring past the cmake_modules stage
--------------------------------------------------

The maud sequence is:
- init
- cmake_modules
- in2
- include
- cxx_sources
- module_scan
- targets
- docs
... but what if we need to insert something somewhere other than
`cmake_modules`? For example: cpp2.in2 - the cpp2 glob is run in
`cmake_modules`, before in2 renders, so rendered cpp2 are not scanned.
Since the stages are an implementation detail I'd rather not expose
explicitly, we could just provide a function named `maud_defer`
which checks conditions:

```cmake
maud_defer(
  CODE [[
    glob(CPP2_SOURCES CONFIGURE_DEPENDS "[.]cpp2$")
    cppfront(${CPP2_SOURCES})
  ]]
  UNTIL EXISTS "${MAUD_DIR}/rendered/one_of_the.cpp2"
)
```

This would also be handy for cmake code which must manipulate targets:

```cmake
find_package(nlohmann_json REQUIRED)
find_package(fmt REQUIRED)
maud_defer(
  CODE [[
    target_link_libraries(
      use_json_fmt
      PRIVATE
      nlohmann_json::nlohmann_json
      fmt::fmt-header-only
    )
  ]]
  UNTIL TARGET use_json_fmt
)
```


TODO: consolidate tests
-----------------------

By default we produce 1:1:1 test source:test suite:executable.
In a larger project with many tests, it can be useful to consolidate
suites into fewer executables in order to save link time when the
goal is simply to build and run all of them. Therefore we should have an
option which defaults to suite-per-executable and can be enabled to
redistribute test sources into larger test executables (which are named
`test-executable-1` etc but ctest uses `--gtest_filter` so that we can
still see individual suite names).

Maybe this could be done with a directory; we still have 1:1 source:suite,
but in a directory named `test_.${name}/` we link the suites into the
executable `test_.${name}`.

Alternatively, this could be a distinct special module like
`import test_.suite_of.${name};` and we collect all suites of `${name}`
into the executable `test_.${name}`.

... there really isn't any point to
[`SUITE_`](https://github.com/bkietz/maud/commit/1ae8031a0a1a94d344d36ad52b0bba5ac3002293)
until this is available; as long as there is only one suite per executable you might
as well do setup/teardown in a custom `main()`.


TODO: cmake compendium
----------------------

What things are built into cmake that don't see enough use?

- include_guard()
- variable_watch()
- multi-line strings
- glob()
- list(TRANSFORM)
- `option(BUILD_TESTING)` is automatic, don't add an option for that!
- `option(BUILD_SHARED_LIBS)` too
- use a gui to view options; it's better


TODO: install BMIs?
-------------------

What happens when: cmake installs/packages a header-only library with a
dependency on another header-only library? It seems the imported targets
must use `find_package()` to specify that anything which links to them
must also link to the dependency. TODO try this in docker and see what
happens

I would really prefer to install BMIs, but this requires consumers to use
the same compiler (which if we're packaging... they might not even have).
I think we need to install module interface sources along with enough
cmake to compile them with whatever compiler is present...
This is certainly what automatic cmake exporting does; we are forbidden
*not* to install those sources.

Note somewhere that just like header files, module interfaces cannot
depend on language flags or other things which break the ABI

Alternatively: install BMIs to `$prefix/lib/bmi/$CompilerID/$module.*`.
If you try to use a module with a mismatched compiler there's an error.
We provide a reserved target called `interfaces`, so if you switch
compilers you can clone the project and build/install just BMIs.
Nice enough for demos where everything is a wrapper around FetchContent,
and we leave a TODO saying that we need a better way to cache these.

TODO:
-----

Since we generate installed cmake, warn if `CMAKE_CXX_FLAGS` and other
ambiguous options are set. (Or just document that these options will
implicitly be private and not part of the installed package.)

Good example modules: sse4, fmt, nlohmann_json, std stand-ins

Mauds and ROCRs haha... runtime option configuration resource is a GROFF
formatted help page which is used to generate CLI/env accessors and a
.rst doc file.

```
# set compile_options for scanned sources to point to maud's DDI
https://cmake.org/cmake/help/latest/prop_sf/COMPILE_OPTIONS.html
# then set cmake's scanning to OFF
https://cmake.org/cmake/help/latest/prop_sf/CXX_SCAN_FOR_MODULES.html
```

Investigate `IMPORTED_CXX_MODULES_COMPILE_DEFINITIONS`. Is this a shortcut to
the way I want to associate options?

Notes: dep scan
---------------

target.dir/source.cxx.o.ddi contains the names of exports and imports
`ninja -t commands | grep scan-deps` shows the command to generate it
https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2022/p1689r5.html
CMake vars of note:
- `CMAKE_CXX_COMPILER_CLANG_SCAN_DEPS` clang-scan-deps program
- `CMAKE_CXX_SCANDEP_SOURCE` compiler-indepenent command template for scan deps
  - https://github.com/Kitware/CMake/blob/v3.29.0/Modules/Compiler/GNU-CXX.cmake#L77
  - https://github.com/Kitware/CMake/blob/v3.29.0/Modules/Compiler/Clang-CXX.cmake#L48
  - https://github.com/Kitware/CMake/blob/v3.29.0/Modules/Compiler/MSVC-CXX.cmake#L82
- ... but I don't see this template being used anywhere? seems it should be in GetScanRule()
  https://github.com/Kitware/CMake/blob/v3.29.0/Source/cmNinjaTargetGenerator.cxx#L606
- Looks like it's a hidden sub-rule in every compile rule; no non-internal way to trigger it
  https://github.com/Kitware/CMake/blob/v3.29.0/Source/cmNinjaTargetGenerator.cxx#L678
- ... but we don't want to define targets then get a module graph, we want to
  derive targets from the module graph. Therefore we need to do the scan manually

#### Module implementation units of primary modules

`clang-scan-deps` does *not* populate a provider for these.
This is extremely annoying since I want to attach those implementation units
to the target for the module. TL;DR: this seems to be intended and correct
behavior, so this is another thing the custom scanner will need to do differently
(probably by storing `rule::_maud_implementation_unit_of`).

```c++
// foo-interface.cxx
export module foo;
// -> provides foo with is-interface=true
// -> { ... "rules": [ { ... "provides": [ { ... "is-interface": true, "logical-name": "foo" } ] } ] }

// foo-implementation.cxx
module foo;
// -> requires foo???
// -> { ... "rules": [ { ... "requires": [ { "logical-name": "foo" } ] } ] }

// ... but module implementation units for partitions *are* providers
// foo-part-implementation.cxx
module foo:bar;
// -> provides foo:bar with is-interface=false, no requires
// -> { ... "rules": [ { ... "provides": [ { ... "is-interface": false, "logical-name": "foo:bar" } ] } ] }
```

#### Why? How?

Clang's module collection is handled by the [preprocessor](
https://github.com/llvm/llvm-project/blob/llvmorg-17.0.6/clang/include/clang/Lex/Preprocessor.h#L2377-L2383)
and then by other classes which query it like [ModuleDepCollectorPP](
https://github.com/llvm/llvm-project/blob/llvmorg-17.0.6/clang/lib/Tooling/DependencyScanning/ModuleDepCollector.cpp#L346)

The preprocessor's ModuleDeclState picks up the [module name and type](
https://github.com/llvm/llvm-project/blob/llvmorg-17.0.6/clang/unittests/Lex/ModuleDeclStateTest.cpp#L145-L148)
and we are *in a named module*. (This test is unchanged in main, so it doesn't seem to have been a
bug to correct.) According to the unit test, a module partition is [neither impl nor interface unit](
https://github.com/llvm/llvm-project/blob/llvmorg-17.0.6/clang/unittests/Lex/ModuleDeclStateTest.cpp#L164-L167)
see also the [isImplementationUnit() accessor](
https://github.com/llvm/llvm-project/blob/llvmorg-17.0.6/clang/include/clang/Lex/Preprocessor.h#L570)
That *is* a bug or at least a mis-naming because it's not an interface unit *therefore* it is an
implementation unit.

ModuleDepCollectorPP is not unit tested unfortunately.
It produces P1689ModuleInfo in the [EndOfMainFile callback](
https://github.com/llvm/llvm-project/blob/llvmorg-17.0.6/clang/lib/Tooling/DependencyScanning/ModuleDepCollector.cpp#L377) and... here's a [comment describing this annoyance](
https://github.com/llvm/llvm-project/blob/llvmorg-17.0.6/clang/lib/Tooling/DependencyScanning/ModuleDepCollector.cpp#L382-L384)
(but I'm still wondering *why*):
```c++
    // Don't put implementation (non partition) unit as Provide.
    // Put the module as required instead. Since the implementation
    // unit will import the primary module implicitly.
```

Aha: [`CXX(20:module.unit#3)`](https://timsong-cpp.github.io/cppwp/n4868/module.unit#3)
"A named module shall not contain multiple module partitions with the same module-partition."
Therefore even module partition implementation units must be unique, which explains the
different treatment.

#### What do GCC/MSVC do?

MSVC also treats an implementation unit as a requirer rather than a provider,
at least when the generator is ninja. Visual Studio generators don't seem
to use p1689:

```json
# foo-interface.cxx.ifc.d.json
{
    "Version": "1.2",
    "Data": {
        "Source": "c:\\users\\ben\\source\\repos\\modulestest\\modulestest\\foo-interface.cxx",
        "ProvidedModule": "foo",
        "Includes": [],
        "ImportedModules": [],
        "ImportedHeaderUnits": []
    }
}
```

These .ifc files are generated for foo-interface.cxx, but nothing is generated for non-interfaces.
These are referenced later when compiling (but not when linking) CL.command.1.tlog:

```
^C:\USERS\BEN\SOURCE\REPOS\MODULESTEST\MODULESTEST\FOO-INTERFACE.CXX
/c /ZI /nologo /W1 /WX- /diagnostics:column /Od /Ob0 /D _MBCS /D WIN32 /D _WINDOWS /D "CMAKE_INTDIR=\"Debug\"" /Gm- /EHsc /RTC1 /MDd /GS /fp:precise /Zc:wchar_t /Zc:forScope /Zc:inline /std:c++20 /ifcOutput "C:\USERS\BEN\SOURCE\REPOS\MODULESTEST\OUT\VS-BUILD\MODULESTEST\MODULESTEST.DIR\DEBUG\FOO-INTERFACE.CXX.IFC" /Fo"MODULESTEST.DIR\DEBUG\\" /Fd"MODULESTEST.DIR\DEBUG\VC143.PDB" /sourceDependencies "C:\USERS\BEN\SOURCE\REPOS\MODULESTEST\OUT\VS-BUILD\MODULESTEST\MODULESTEST.DIR\DEBUG\FOO-INTERFACE.CXX.IFC.D.JSON" /external:W1 /Gd /interface  /TP C:\USERS\BEN\SOURCE\REPOS\MODULESTEST\MODULESTEST\FOO-INTERFACE.CXX

^C:\USERS\BEN\SOURCE\REPOS\MODULESTEST\MODULESTEST\MAIN.CXX
/c /reference "FOO=C:\USERS\BEN\SOURCE\REPOS\MODULESTEST\OUT\VS-BUILD\MODULESTEST\MODULESTEST.DIR\DEBUG\FOO-INTERFACE.CXX.IFC" /ZI /nologo /W1 /WX- /diagnostics:column /Od /Ob0 /D _MBCS /D WIN32 /D _WINDOWS /D "CMAKE_INTDIR=\"Debug\"" /Gm- /EHsc /RTC1 /MDd /GS /fp:precise /Zc:wchar_t /Zc:forScope /Zc:inline /std:c++20 /Fo"MODULESTEST.DIR\DEBUG\\" /Fd"MODULESTEST.DIR\DEBUG\VC143.PDB" /external:W1 /Gd /TP C:\USERS\BEN\SOURCE\REPOS\MODULESTEST\MODULESTEST\MAIN.CXX

^C:\USERS\BEN\SOURCE\REPOS\MODULESTEST\MODULESTEST\FOO.CXX
/c /reference "FOO=C:\USERS\BEN\SOURCE\REPOS\MODULESTEST\OUT\VS-BUILD\MODULESTEST\MODULESTEST.DIR\DEBUG\FOO-INTERFACE.CXX.IFC" /ZI /nologo /W1 /WX- /diagnostics:column /Od /Ob0 /D _MBCS /D WIN32 /D _WINDOWS /D "CMAKE_INTDIR=\"Debug\"" /Gm- /EHsc /RTC1 /MDd /GS /fp:precise /Zc:wchar_t /Zc:forScope /Zc:inline /std:c++20 /Fo"MODULESTEST.DIR\DEBUG\\" /Fd"MODULESTEST.DIR\DEBUG\VC143.PDB" /external:W1 /Gd /TP C:\USERS\BEN\SOURCE\REPOS\MODULESTEST\MODULESTEST\FOO.CXX
```

Compare to the command used during ninja gen:
```
C:\PROGRA~1\MICROS~1\2022\COMMUN~1\VC\Tools\MSVC\1439~1.335\bin\Hostx64\x64\cl.exe   /DWIN32 /D_WINDOWS /W3 /GR /EHsc /MDd /Ob0 /Od /RTC1 -std:c++20 -MDd -ZI C:\Users\ben\source\repos\ModulesTest\ModulesTest\main.cxx -nologo -TP -showIncludes -scanDependencies ModulesTest\CMakeFiles\ModulesTest.dir\main.cxx.obj.ddi -FoModulesTest\CMakeFiles\ModulesTest.dir\main.cxx.obj
```

... anyways, it seems I can invoke the p1689 output whenever I need it

TODO: generator expressions
---------------------------

nlohmann_json's COMPILE_OPTIONS property produces this horror:

```
$<
  $<NOT:$<BOOL:ON>>:JSON_USE_GLOBAL_UDLS=0>;
  $<$<NOT:$<BOOL:ON>>:JSON_USE_IMPLICIT_CONVERSIONS=0>;
  $<$<BOOL:OFF>:JSON_DISABLE_ENUM_SERIALIZATION=1>;
  $<$<BOOL:OFF>:JSON_DIAGNOSTICS=1>;
  $<$<BOOL:OFF>:JSON_USE_LEGACY_DISCARDED_VALUE_COMPARISON=1
>
```
It really ought to be possible to expand *most* generator
expressions at configure time. Someday it'd be amusing to write
a library to just do that.

(not) TODO: cmake-format
------------------------

it would be nice to use cmake format to get consistent formatting, however:

1. cmake is not too much of a pain to format by hand
2. it does not support the kind of nested commands which I like to write

(not) TODO: conversion traits
-----------------------------

Having tried this out, it's not as dead simple as I would want
it to be. Using rapidyaml with minimal wrapping will be fine for
maud and I'll save these traits for a downstream package later.
