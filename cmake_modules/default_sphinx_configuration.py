import re
from pathlib import Path
from typing import Tuple

import maud.cache
import pygments.lexers.c_cpp
import sphinx.highlighting
from git import Commit, Remote, Repo
from sphinx.application import Sphinx
from sphinx.config import Config
from sphinx.util.logging import getLogger
from sphinx.util.typing import ExtensionMetadata

_logger = getLogger(__name__)

project = maud.cache.PROJECT_NAME
html_title = maud.cache.PROJECT_NAME

nitpicky = True

primary_domain = "cpp"
highlight_language = "cpp"
extensions = []
exclude_patterns = ["Thumbs.db", ".*", "**/[A-Z_][A-Z_][A-Z_][A-Z_]*"]
source_suffix = {
    ".rst": "restructuredtext",
}


def _trunk(remote: Remote) -> str:
    # FIXME fetch should not be necessary here
    remote.fetch()
    head = remote.refs["HEAD"]
    for trunk in {*remote.refs} - {head}:
        if trunk.commit == head.commit:
            return trunk.name.removeprefix(f"{remote.name}/")
    return ""


def _forge(origin: str) -> Tuple[str, str, str]:
    if match := re.match(r"(git@|https://)(github|github)\.com[:/](.+)\.git", origin):
        _, name, repo = match.groups()
        url = f"https://{name}.com/{repo}"
        icon = f"https://icons.getbootstrap.com/assets/icons/{name}.svg"
        return name, url, icon

    return "", "", ""


try:
    srcdir = Path(maud.cache.MAUD_DOCUMENTATION_DIR)

    repo = Repo(srcdir, search_parent_directories=True)
    assert repo.working_tree_dir, "no bare repos"
    working_tree_dir = Path(repo.working_tree_dir)

    _trunks = {_trunk(r) for r in repo.remotes} - {""}
    trunk = _trunks.pop() if len(_trunks) == 1 else ""

    origin = ""
    if trunk in repo.branches:
        if trunk_on_remote := repo.branches[trunk].tracking_branch():
            origin = repo.remotes[trunk_on_remote.remote_name].url

    forge, forge_url, forge_icon = _forge(origin)

    html_theme_options = {
        "footer_icons": [],
        "navigation_with_keys": True,
    }

    if forge:
        html_theme_options.update(
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
            source_directory=srcdir.relative_to(working_tree_dir).name,
        )

    def first_commit_to(path: Path) -> Commit | None:
        assert repo is not None
        if commits := [
            *Commit.iter_items(repo, trunk, path.relative_to(working_tree_dir))
        ]:
            return commits.pop()

    def set_from_git(app: Sphinx, config: Config):
        root_doc = app.srcdir / config.root_doc
        for ext in config.source_suffix.keys():
            first = first_commit_to(root_doc.with_suffix(ext))
            if first and first.author and first.author.name:
                if config.author == "Author name not set":
                    config.author = first.author.name
                if config.copyright == "":
                    year = first.authored_datetime.year
                    config.copyright = f"{year}, {config.author}"


except Exception as e:
    _logger.error(
        f"Exception while inferring options from git: {e}", extra={"Exception": e}
    )
    repo = None


html_theme = "furo"

pygments_style = "default"
pygments_dark_style = "monokai"

extensions += ["sphinx.ext.autosectionlabel"]
autosectionlabel_maxdepth = 2
autosectionlabel_prefix_document = True

extensions += ["sphinx.ext.ifconfig"]

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

_trike_file = re.compile(".*[.]([ch]xxm?|[ch]ppm?|ccm?|hh|[ch][+][+]m?|ixx|mxx|h)")
trike_files = [
    maud.cache.CMAKE_SOURCE_DIR / file
    for file in maud.cache._MAUD_ALL.split(";")
    if _trike_file.match(file)
]
# FIXME with c++20 libclang parses exported decls to UNEXPOSED_DECL
trike_clang_args = ["-std=gnu++20", "-Dexport="]

if repo is not None:

    def trike_get_uri(file, line):
        # FIXME what if file was generated?
        relative = file.relative_to(working_tree_dir)
        # FIXME this won't work for all forges
        return f"{forge_url}/blob/{trunk}/{relative}#L{line}"


def setup(app: Sphinx) -> ExtensionMetadata:
    app.add_config_value(
        name="maud",
        description="maud.cache provides access to the cmake CACHE",
        default=__import__("maud"),
        rebuild="",
    )

    if repo is not None:
        app.connect(
            "config-inited",
            set_from_git,
            priority=1000,  # after convert_highlight_options
        )

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
