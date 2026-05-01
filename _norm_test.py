from pipeline.exporters.case_catalog import normalize_title
tests = [
    "Marie\u2019s Caf\xe9",
    "Marie's Caf\xe9",
    "Marie's Cafe",
    "Marie\u2019s Cafe",
]
for t in tests:
    print(repr(t), "->", repr(normalize_title(t)))
