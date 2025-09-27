import re
from pathlib import Path

import maud.cache
import pygments.lexers.c_cpp
import sphinx.highlighting
from sphinx.application import Sphinx
from sphinx.util.typing import ExtensionMetadata

CACHE = maud.cache.read()

project = str(CACHE["PROJECT_NAME"])

nitpicky = True

primary_domain = "cpp"
highlight_language = "cpp"
extensions = []
exclude_patterns = ["Thumbs.db", ".*", "**/[A-Z_][A-Z_][A-Z_][A-Z_]*"]
source_suffix = {
    ".rst": "restructuredtext",
}


html_title = str(CACHE["PROJECT_NAME"])
html_theme = "furo"
html_theme_options = {
    "footer_icons": [],
    "navigation_with_keys": True,
    # more options set by maud.forge
}

pygments_style = "default"
pygments_dark_style = "monokai"

extensions += ["sphinx.ext.autosectionlabel"]
autosectionlabel_maxdepth = 2
autosectionlabel_prefix_document = True

extensions += ["sphinx.ext.ifconfig"]

extensions += ["sphinx.ext.duration"]
extensions += ["sphinx_inline_tabs"]
extensions += ["sphinx_copybutton"]

extensions += ["sphinx.ext.extlinks"]
extlinks_detect_hardcoded_links = True
extlinks = {
    "cxx20": ("https://timsong-cpp.github.io/cppwp/n4868/%s", "C++20:%s"),
    # TODO this should be intersphinx instead
    "cmake": ("https://cmake.org/cmake/help/latest/%s", None),
    "mastering-cmake": (
        "https://cmake.org/cmake/help/book/mastering-cmake/chapter/%s",
        None,
    ),
    "gtest": ("https://google.github.io/googletest/%s", None),
    "sphinx": ("https://www.sphinx-doc.org/en/master/usage/%s", None),
}

extensions += ["trike"]

_trike_file = re.compile(".*[.]([ch]xxm?|[ch]ppm?|ccm?|hh|[ch][+][+]m?|ixx|mxx|h)$")
trike_files = [
    Path(str(CACHE["CMAKE_SOURCE_DIR"]), file)
    for file in str(CACHE["_MAUD_ALL"]).split(";")
    if _trike_file.match(file)
]
# FIXME with c++20 libclang parses exported decls to UNEXPOSED_DECL
trike_clang_args = ["-std=gnu++20", "-Dexport="]
# trike_get_uri is set by maud.forge


def setup(app: Sphinx) -> ExtensionMetadata:
    app.add_config_value(
        name="CACHE",
        description="dict accessor to the CMake CACHE",
        default=CACHE,
        rebuild="",
    )

    app.setup_extension("maud.forge")

    sphinx.highlighting.lexers["c++.in2"] = pygments.lexers.c_cpp.CppLexer()
    # def lexer(*args, **kwargs):
    #     print(args, kwargs)
    #     return pygments.lexers.c_cpp.CppLexer(*args, **kwargs)
    # app.add_lexer("c++.in2", lexer)
    # TODO make a utility for building in2 lexers and embed cmake's syntax
    # http://pygments.org/docs/lexerdevelopment/#using-multiple-lexers
    return {
        "version": "0.1",
        "env_version": 1,
        "parallel_read_safe": True,
        "parallel_write_safe": True,
    }
