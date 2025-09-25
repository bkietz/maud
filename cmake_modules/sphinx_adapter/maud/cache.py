def _read():
    from pathlib import Path
    import re
    import sys

    ENTRY = re.compile("([^#/].*):(.+)=(.*)")
    FALSE_STRINGS = "0 FALSE OFF N NO IGNORE NOTFOUND".split()

    for line in Path(sys.prefix, "../../CMakeCache.txt").resolve().open():
        if match := ENTRY.match(line):
            name, typename, value = match.groups()

            if typename == "BOOL":
                value = not (
                    value.upper() in FALSE_STRINGS
                    or value == ""
                    or value.endswith("-NOTFOUND")
                )

            globals()[name] = value


_read()
