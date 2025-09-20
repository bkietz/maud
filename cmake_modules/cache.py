def _read():
    from pathlib import Path
    import re

    ENTRY = re.compile("([^#/].*):(.+)=(.*)")
    FALSE_STRINGS = {*"0 FALSE OFF N NO IGNORE NOTFOUND".split()}
    INTERNAL_PATHS = {*"CMAKE_SOURCE_DIR CMAKE_BINARY_DIR MAUD_DIR".split()}

    cache_txt = Path(__file__) / "../../../../CMakeCache.txt"
    for line in cache_txt.resolve().open():
        if match := ENTRY.match(line):
            name, typename, value = match.groups()

            if typename == "BOOL":
                value = not (
                    value.upper() in FALSE_STRINGS
                    or value == ""
                    or value.endswith("-NOTFOUND")
                )
            elif "PATH" in typename or name in INTERNAL_PATHS:
                value = Path(value)

            globals()[name] = value


_read()
