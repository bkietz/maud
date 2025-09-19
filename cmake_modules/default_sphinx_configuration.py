from pathlib import Path
from git import Repo

import maud
import re
import pygments.lexers.c_cpp
import sphinx.highlighting

project = maud.cache.PROJECT_NAME
html_title = maud.cache.PROJECT_NAME

extensions = []
exclude_patterns = ["Thumbs.db", ".*", "**/[A-Z_][A-Z_][A-Z_][A-Z_]*"]
source_suffix = {
    ".rst": "restructuredtext",
}


def _trunk(remote):
    head = remote.refs["HEAD"]
    for trunk in {*remote.refs} - {head}:
        if trunk.commit == head.commit:
            return trunk.name.removeprefix(f"{remote.name}/")
    return ""


def _forge(origin):
    if match := re.match(r"(git@|https://)(github|github)\.com[:/](.+)\.git", origin):
        _, name, repo = match.groups()
        url = f"https://{name}.com/{repo}"
        icon = f"https://icons.getbootstrap.com/assets/icons/{name}.svg"
        return name, url, icon

    return None, None, None


def _infer_options():
    path = Path(maud.cache.CMAKE_SOURCE_DIR)
    repo = Repo(path, search_parent_directories=True)

    trunks = {_trunk(r) for r in repo.remotes} - {""}
    trunk = trunks.pop() if len(trunks) == 1 else ""

    try:
        origin_name = repo.branches[trunk].tracking_branch().remote_name
        origin = repo.remotes[origin_name].url
    except Exception:
        origin = ""

    forge, forge_url, forge_icon = _forge(origin)

    options = {
        "footer_icons": [],
        "navigation_with_keys": True,
    }

    if not forge:
        return options

    options.update(
        footer_icons=[
            {
                "name": forge,
                "url": forge_url,
                "html": f'<img loading="lazy" src="{forge_icon}" {style} />',
                "class": cls,
            }
            for cls, style in {
                "only-light": "",
                "only-dark": 'style="filter: invert(100%);"',
            }.items()
        ],
        top_of_page_buttons=["view", "edit"],
        source_repository=forge_url,
        source_branch=trunk,
        source_directory=path.relative_to(Path(repo.working_tree_dir)).name,
    )

    # TODO infer author from the first committer to root_doc
    return options


html_theme = "furo"
html_theme_options = _infer_options()

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

extensions += ["trike"]
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
    # http://pygments.org/docs/lexerdevelopment/#using-multiple-lexers
