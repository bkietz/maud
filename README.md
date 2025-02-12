Maud
====

Maud simplifies building C++ projects by reducing configuration boilerplate.

```sh-session
$ ls
hello.cxx

$ cat hello.cxx
#include <iostream>

import executable;

int main() {
  std::cout << "hello world!" << std::endl;
}

$ maud --quiet

$ .build/Debug/hello
hello world!
```

Maud bootstraps a cmake build directory with excellent defaults and batteries
included. Maud makes building with C++20 modules straightforward. Other
features include performant and expressive
[globbing](https://bkietz.github.io/maud/globbing),
first class support for
[generated files](https://bkietz.github.io/maud/#generated-files-blurb),
inference of
[compilation/link/test targets](https://bkietz.github.io/maud/modules#module-library)
from source files,
built-in targets for rendering
[gorgeous documentation](https://bkietz.github.io/maud/documentation),
expanded capabilities for declaring and resolving
[build options](https://bkietz.github.io/maud/options), and more.

Getting Started
---------------

Maud is itself a Maud-based project. Build with:

```sh-session
$ git clone https://github.com/bkietz/maud.git && cd maud

# get dependencies with flox
$ flox activate

$ maud --log-level=VERBOSE # Pass cmake -D options etc here

# optionally, install:
$ cmake --install .build --config Debug
```

Maud uses
[Ninja Multi-Config](https://cmake.org/cmake/help/latest/manual/cmake-generators.7.html#ninja-generators)
by default, but recent versions of MSVC/Visual Studio also support C++20 modules.

If you don't already have the `maud` executable on your PATH, you can bootstrap using:

```shell-session
$ cmake -P cmake_modules/maud_cli.cmake -- --log-level=VERBOSE
# ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^
#   (the maud executable is just an alias for this anyway)
```
