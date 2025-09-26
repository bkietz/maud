import os
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Protocol, Self, Tuple, cast

from git import Commit, Remote, Repo
from sphinx.application import Sphinx
from sphinx.config import Config
from sphinx.util.logging import getLogger
from sphinx.util.typing import ExtensionMetadata

_log = getLogger(__name__)


class Forge(Protocol):
    url: str
    ref_name: str
    root_dir: Path
    doc_dir: Path

    @property
    def icon(self) -> str: ...

    def get_uri(self, file: Path, line: int) -> str: ...

    def first_commit_to(self, path: Path) -> Tuple[str, datetime] | None: ...

    @classmethod
    def infer(cls, doc_dir: Path) -> Self | None: ...


@dataclass
class GitHubLike:
    url: str
    ref_name: str
    root_dir: Path
    doc_dir: Path

    @property
    def icon(self) -> str:
        name = type(self).__name__.lower()
        return f"https://icons.getbootstrap.com/assets/icons/{name}.svg"

    def get_uri(self, file: Path, line: int) -> str:
        relative = file.relative_to(self.root_dir)
        return f"{self.url}/blob/{self.ref_name}/{relative}#L{line}"

    def first_commit_to(self, path: Path) -> Tuple[str, datetime] | None:
        path = path.relative_to(self.root_dir)
        repo = Repo(self.root_dir)
        *_, commit = [None, *Commit.iter_items(repo, self.ref_name, path)]
        if commit and commit.author and commit.author.name:
            return commit.author.name, commit.authored_datetime

    @classmethod
    def infer(cls, doc_dir: Path) -> Self | None:
        try:
            repo = Repo(doc_dir, search_parent_directories=True)
        except Exception as e:
            _log.info(f"├──ⓧ exception while finding repo: {e}")
            return None
        root_dir = Path(repo.working_dir)

        if ci := cls.infer_from_ci_envs(root_dir, doc_dir):
            return ci

        name = cls.__name__.lower()
        trunk, *_ = {_guess_trunk(r) for r in repo.remotes} - {""} or {""}
        _log.info(f"├ {trunk=}")

        if Path(repo.working_dir, f".{name}").is_dir():
            _log.info(f"├ directory .{name}/")
        elif match := [r.url for r in repo.remotes if name in r.url]:
            _log.info(f"├ remote urls {match}")
        else:
            _log.info("├──ⓧ couldn't infer forge type")
            return None

        if not repo.remotes:
            _log.info("├──ⓧ no remotes from which to infer forge url")
            return None
        elif len(repo.remotes) == 1:
            origin, *_ = repo.remotes
            _log.info(f"├ single remote {origin.url=}")
        elif trunk not in repo.branches:
            origin, *_ = repo.remotes
            _log.info(f"├ no local trunk, guess {origin.url=}")
        elif trunk_remote_ref := repo.branches[trunk].tracking_branch():
            origin = repo.remotes[trunk_remote_ref.remote_name]
            _log.info(f"├ remote which trunk tracks {origin.url=}")
        else:
            origin, *_ = repo.remotes
            _log.info(f"├ local trunk has no tracking_branch, guess {origin.url=}")

        if match := re.match(r"^https://(.+)\.git$", origin.url):
            url, *_ = match.groups()
            _log.info(f"├ matched https:// remote {url=}")
        elif match := re.match(r"^git@(.+):(.+)\.git", origin.url):
            host, owner_and_repo = match.groups()
            url = f"https://{host}/{owner_and_repo}"
            _log.info(f"├ matched git@ remote {url=}")
        else:
            _log.info("├──Ⓧ unknown url format")
            return None

        try:
            ref_name = repo.active_branch.remote_head
            _log.info(f"├ use active_branch {ref_name=}")
        except Exception:
            ref_name = trunk
            _log.info(f"├ DETACHED, fall back to trunk {ref_name=}")

        return cls(url, ref_name, root_dir, doc_dir)

    @classmethod
    def infer_from_ci_envs(cls, root_dir: Path, doc_dir: Path) -> Self | None:
        _log.info(f"├ CI.envs not implemented {root_dir=} {doc_dir=}")


@dataclass
class GitHub(GitHubLike):
    @classmethod
    def infer_from_ci_envs(cls, root_dir: Path, doc_dir: Path) -> Self | None:
        if os.getenv("CI") == "true":
            names = "GITHUB_SERVER_URL GITHUB_REPOSITORY GITHUB_REF_NAME".split()
            env = {name: os.getenv(name) for name in names}
            _log.info(f"├ CI.{env=}")
            if all(env.values()):
                url, repo, ref_name = cast(dict[str, str], env).values()
                return cls(f"{url}/{repo}", ref_name, root_dir, doc_dir)
            _log.info(f"├──Ⓧ undefined: {[n for n, v in env.items() if not v]}")


@dataclass
class GitLab(GitHubLike):
    @classmethod
    def infer_from_ci_envs(cls, root_dir: Path, doc_dir: Path) -> Self | None:
        if os.getenv("CI") == "true":
            names = "CI_PROJECT_URL CI_COMMIT_REF_NAME".split()
            env = {name: os.getenv(name) for name in names}
            _log.info(f"├ CI.{env=}")
            if all(env.values()):
                url, ref_name = cast(dict[str, str], env).values()
                return cls(url, ref_name, root_dir, doc_dir)
            _log.info(f"├──Ⓧ undefined: {[n for n, v in env.items() if not v]}")


def _guess_trunk(remote: Remote) -> str:
    """
    Usually, a repository is checked out with a full set of remote refs.
    Also usually those refs include HEAD, which tracks with trunk.
    Using these probabilities, we can guess the name of trunk.
    """
    if "HEAD" in remote.refs:
        for trunk in {*remote.refs} - {remote.refs.HEAD}:
            if trunk.commit == remote.refs.HEAD.commit:
                return trunk.name.removeprefix(f"{remote.name}/")
    return ""


def set_author_and_copyright_from_root_doc(forge: Forge, config: Config):
    for root_doc in map(
        (forge.doc_dir / config.root_doc).with_suffix, config.source_suffix.keys()
    ):
        if first := forge.first_commit_to(root_doc):
            name, date = first
            if config.author == "Author name not set":
                config.author = name
                _log.info(f"  ╰──> {config.author=} from first commit to {root_doc}")
            if config.copyright == "":
                config.copyright = f"{date.year}, {config.author}"
                _log.info(
                    f"  ╰──> {config.copyright=} from first commit to {root_doc}"
                )


def set_furo_html_theme_options(forge: Forge, config: Config):
    if config.html_theme != "furo":
        return

    config.html_theme_options["footer_icons"].extend(
        {
            "name": type(forge).__name__,
            "url": forge.url,
            "html": f'<img loading="lazy" src="{forge.icon}" {style} />',
            "class": cls,
        }
        for cls, style in {
            "only-light": "",
            "only-dark": 'style="filter: invert(100%);"',
        }.items()
    )
    _log.info(f"  ╰──> appended to html_theme_options[footer_icons] {forge.icon=}")
    keys_before = set(config.html_theme_options.keys())
    config.html_theme_options.setdefault("top_of_page_buttons", ["view", "edit"])
    config.html_theme_options.setdefault("source_repository", forge.url)
    config.html_theme_options.setdefault("source_branch", forge.ref_name)
    config.html_theme_options.setdefault(
        "source_directory", forge.doc_dir.relative_to(forge.root_dir).name
    )
    keys_after = set(config.html_theme_options.keys())
    _log.info(f"  ╰──> set html_theme_options[{keys_after - keys_before}]")


classes: list[type[Forge]] = [GitHub, GitLab]


def infer_forge(app: Sphinx) -> Forge | None:
    """
    Infer which forge is used to manage the project being built.
    Extensible by appending to maud.forge.classes.
    """
    _log.info(f"Starting forge inferrence from {app.srcdir=}")
    for cls in classes:
        _log.info(f"├──> trying {cls.__name__=}")
        if forge := cls.infer(Path(app.srcdir)):
            break
    else:
        forge = None

    _log.info(f"╰──> {forge=}")
    return forge


def _config_inited(app: Sphinx, config: Config):
    if forge := infer_forge(app):
        set_author_and_copyright_from_root_doc(forge, config)
        set_furo_html_theme_options(forge, config)
        config.trike_get_uri = forge.get_uri


def setup(app: Sphinx) -> ExtensionMetadata:
    app.connect(
        "config-inited",
        _config_inited,
        priority=1000,  # after convert_highlight_options
    )

    return {
        "version": "0.1",
        "env_version": 1,
        "parallel_read_safe": True,
        "parallel_write_safe": True,
    }
