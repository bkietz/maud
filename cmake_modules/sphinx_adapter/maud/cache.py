from pathlib import Path
import re
import sys


def read(cache_txt: Path | None = None) -> dict[str, str | bool]:
    if cache_txt is None:
        cache_txt = Path(sys.prefix, "../../CMakeCache.txt").resolve()

    ENTRY = re.compile("([^#/].*):(.+)=(.*)")
    FALSE_STRINGS = "0 FALSE OFF N NO IGNORE NOTFOUND".split()

    out = {}
    for line in cache_txt.open():
        if match := ENTRY.match(line):
            name, typename, value = match.groups()

            if typename == "BOOL":
                value = not (
                    value.upper() in FALSE_STRINGS
                    or value == ""
                    or value.endswith("-NOTFOUND")
                )

            out[name] = value

    return out
