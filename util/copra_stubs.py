"""Fix up the DUT type stubs that Copra generates.

GHDL reports every VHDL identifier in lower case, so Copra writes stubs with
names like ``load_sb_add``. Lookups by name are case-insensitive at runtime, but
the type checker isn't, so testbenches that use the declared casing
(``load_SB_ADD``) would still be flagged. This restores the casing used in the
VHDL source.
"""

import re
from pathlib import Path

_COMMENT = re.compile(r"--.*$", re.MULTILINE)
_LITERAL = re.compile(r"'.'|\"[^\"]*\"")
_IDENTIFIER = re.compile(r"\b[A-Za-z][A-Za-z0-9_]*\b")

_ATTRIBUTE = re.compile(r"^(\s+)(\w+)(: )", re.MULTILINE)
_LITERAL_KEY = re.compile(r"Literal\['(\w+)'\]")


def source_casing(sources: list[str]) -> dict[str, str]:
    """Map each lower-cased identifier to its first spelling in the sources.

    Ports and signals are declared before they're used, so the first spelling
    is the declared one.
    """
    casing: dict[str, str] = {}
    for source in sources:
        text = Path(source).read_text()
        text = _LITERAL.sub(" ", _COMMENT.sub("", text))
        for name in _IDENTIFIER.findall(text):
            casing.setdefault(name.lower(), name)
    return casing


def restore_casing(stub: Path, sources: list[str]) -> None:
    casing = source_casing(sources)

    def recase(name: str) -> str:
        return casing.get(name.lower(), name)

    text = stub.read_text()
    text = _ATTRIBUTE.sub(lambda m: m[1] + recase(m[2]) + m[3], text)
    text = _LITERAL_KEY.sub(lambda m: f"Literal['{recase(m[1])}']", text)
    stub.write_text(text)
