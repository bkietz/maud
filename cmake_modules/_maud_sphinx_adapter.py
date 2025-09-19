from pathlib import Path
import re

def read_cache(build_dir: str, cache):
    ENTRY = re.compile("([^#/].*):(.+)=(.*)")
    FALSE_STRINGS = {"", *"0 FALSE OFF N NO IGNORE NOTFOUND".split()}
    INTERNAL_PATHS = set("CMAKE_SOURCE_DIR CMAKE_BINARY_DIR MAUD_DIR".split())

    cache_txt = Path(build_dir) / "CMakeCache.txt"
    for line in cache_txt.open():
        if match := ENTRY.match(line):
            name, typename, value = match.groups()

            if typename == "BOOL":
                value = value.upper() in FALSE_STRINGS or value.endswith("-NOTFOUND")
            elif "PATH" in typename or name in INTERNAL_PATHS:
                value = Path(value)

            setattr(cache, name, value)

