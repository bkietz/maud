import sphinx.util.docutils
import sphinx.util.logging
import pygments.lexers.c_cpp
import sphinx.highlighting

from pathlib import Path

# TODO instead of trying to provide defaults for config settings,
# let the maud extension just assert that config doesn't have any errors
# (like failure to exclude CMAKE_SOURCE_DIR).
import maud

logger = sphinx.util.logging.getLogger(__name__)

project = maud.cache.PROJECT_NAME
extensions = ["maud", "trike"]
templates_path = []
exclude_patterns = ["CMAKE_SOURCE_DIR", "Thumbs.db", ".DS_Store"]
html_static_path = []
source_suffix = {
    ".rst": "restructuredtext",
}

author = "Benjamin Kietzman <bengilgit@gmail.com>"

html_title = "Maud"
html_theme = "furo"
html_theme_options = {
    "footer_icons": [
        {
            "name": "GitHub",
            "url": "https://github.com/bkietz/maud",
            "html": """
            <svg stroke="currentColor" fill="currentColor" stroke-width="0" viewBox="0 0 16 16">
              <path fill-rule="evenodd" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"></path>
            </svg>
          """,
            "class": "",
        },
    ],
    "top_of_page_buttons": ["view", "edit"],
    "navigation_with_keys": True,
    "source_repository": "https://github.com/bkietz/maud/",
    "source_branch": "trunk",
    "source_directory": "",
}
html_context = {
    "github_user": "bkietz",
    "github_repo": "maud",
    "github_version": "trunk",
    "doc_path": "",
}

pygments_style = "default"
pygments_dark_style = "monokai"

extensions += ["sphinx.ext.autosectionlabel"]
autosectionlabel_maxdepth = 2
autosectionlabel_prefix_document = True

extensions += ["sphinx.ext.duration"]
extensions += ["sphinx_inline_tabs"]

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

trike_files = [
    *maud.cache.CMAKE_SOURCE_DIR.glob("*.cxx"),
    *maud.cache.CMAKE_SOURCE_DIR.glob("cmake_modules/*.cxx"),
    *maud.cache.CMAKE_SOURCE_DIR.glob("cmake_modules/*.hxx"),
]
# FIXME with c++20 libclang parses exported decls to UNEXPOSED_DECL
trike_clang_args = ["-std=gnu++20", "-Dexport="]


def trike_get_uri(file, line):
    # FIXME what if file was generated?
    relative = file.relative_to(maud.cache.CMAKE_SOURCE_DIR)
    return f"https://github.com/bkietz/maud/blob/trunk/{relative}#L{line}"


def setup(app):
    sphinx.highlighting.lexers["c++.in2"] = pygments.lexers.c_cpp.CppLexer()
    # def lexer(*args, **kwargs):
    #     print(args, kwargs)
    #     return pygments.lexers.c_cpp.CppLexer(*args, **kwargs)
    # app.add_lexer("c++.in2", lexer)
    # TODO make a utility for building in2 lexers and embed cmake's syntax
    # https://pygments.org/docs/lexerdevelopment/#using-multiple-lexers
    app.add_config_value(
        name="maud",
        description="the Maud CMake adapter",
        default=None,
        rebuild="",
    )

    from trike import _extend_with_formatted_path
    from sphinx.directives.code import LiteralInclude
    from sphinx.directives.other import Include
    app.add_directive("f-include", _extend_with_formatted_path(Include))
    app.add_directive("f-literalinclude", _extend_with_formatted_path(LiteralInclude))
