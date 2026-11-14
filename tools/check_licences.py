"""Read the licence of every third-party asset out of CREDITS.md (#406).

CREDITS.md is the one record of what the game ships under which licence. Two
things about it were unenforced:

  * A section could name no licence at all. The WAR-BOT's model sat under a
    "source is not identified yet" heading for months (#435).
  * One shipped model was non-commercial: the HOWITZER's first model was a
    CC-BY-NC 4.0 download (#406). That allows the free itch.io build and
    forbids a paid one, and nothing would have stopped a Steam release from
    carrying it. The model has since been replaced by one built in this
    repository; CI runs the commercial check so no such asset comes back.

Default run (CI): every `###` section under "Third-party assets" must state at
least one licence this script knows, and every bold phrase that reads like a
licence must be one it knows. Prints the count per licence.

    python tools/check_licences.py

Commercial run: the same, and it fails while any asset is under a licence that
forbids commercial use, naming the files. A licence whose terms need reading
first (Sketchfab Standard) is printed as a warning. Run it before any build that is sold
or takes money (Steam, a paid itch tier, pay-what-you-want).

    python tools/check_licences.py --commercial

    python tools/check_licences.py --self-test     # the parser against known text
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CREDITS = os.path.join(ROOT, "CREDITS.md")

# (pattern on the bold phrase, class, may it ship in a build that is sold?)
# True: yes. False: no. None: read the terms first (printed as a warning).
# First match wins, so the non-commercial pattern stands before plain CC-BY.
LICENCES = (
    (r"CC-BY-NC|NonCommercial|non-commercial", "CC-BY-NC (non-commercial)", False),
    (r"CC0|public domain", "CC0 (public domain)", True),
    (r"CC-BY|Creative Commons Attribution", "CC-BY (attribution)", True),
    (r"SIL Open Font Licen[cs]e|OFL", "SIL OFL (font)", True),
    # Sketchfab's store licence (https://sketchfab.com/licenses, read
    # 2026-11-11): no ban on commercial use (that is the Editorial licence), but
    # section 2.2(b) forbids making the file available "as a stand-alone file"
    # or so that third parties can "download, extract or access" it.
    (r"Sketchfab Standard", "Sketchfab Standard", None),
)
LOOKS_LIKE_A_LICENCE = re.compile(r"licen[cs]e|\bCC\b|CC-|CC0|OFL|GPL|MIT|Apache|public domain|copyright", re.I)
BOLD = re.compile(r"\*\*([^*]+)\*\*")
FILE = re.compile(r"`([^`]+\.(?:glb|gltf|fbx|png|jpg|hdr|ogg|wav|ttf|tres))`")
SECTION_FILE = re.compile(r"`([^`]+)`")


def classify(phrase):
    """(class, commercial_ok) for a bold phrase that is a known licence, else None."""
    for pattern, name, commercial in LICENCES:
        if re.search(pattern, phrase, re.I):
            return name, commercial
    return None


def parse(text):
    """-> (sections, unknown). A section is {title, licences: [(class, ok, line, files)]}.

    Only `###` sections under the "## Third-party assets" heading are read.
    `unknown` lists bold phrases that read like a licence and match none.
    """
    sections, unknown = [], []
    inside = False
    current = None
    for n, line in enumerate(text.splitlines(), 1):
        if line.startswith("## "):
            inside = line[3:].strip().lower().startswith("third-party")
            current = None
            continue
        if not inside:
            continue
        if line.startswith("### "):
            current = {"title": line[4:].strip(), "line": n, "licences": []}
            sections.append(current)
            continue
        if current is None:
            continue
        for phrase in BOLD.findall(line):
            found = classify(phrase)
            if found is not None:
                files = FILE.findall(line) or SECTION_FILE.findall(current["title"])
                current["licences"].append((found[0], found[1], n, files))
            elif LOOKS_LIKE_A_LICENCE.search(phrase):
                unknown.append((n, phrase))
    return sections, unknown


def check(text, commercial):
    """-> (problems, counts, warnings). `counts` maps licence class to how often it is stated."""
    sections, unknown = parse(text)
    problems, counts, warnings = [], {}, []
    if not sections:
        problems.append("CREDITS.md: no `###` section under a '## Third-party assets' heading")
    for s in sections:
        if not s["licences"]:
            problems.append("CREDITS.md:%d: section '%s' states no licence this check knows"
                            % (s["line"], s["title"]))
        for name, ok, n, files in s["licences"]:
            counts[name] = counts.get(name, 0) + 1
            if commercial and ok is False:
                problems.append("CREDITS.md:%d: %s forbids a commercial build: %s"
                                % (n, name, ", ".join(files) or s["title"]))
            elif commercial and ok is None:
                warnings.append("CREDITS.md:%d: %s: read its terms before selling a build with %s"
                                % (n, name, ", ".join(files) or s["title"]))
    for n, phrase in unknown:
        problems.append("CREDITS.md:%d: '%s' reads like a licence but is not in LICENCES "
                        "(add it there, with whether it may be sold)" % (n, phrase))
    return problems, counts, warnings


def self_test():
    sample = """# Credits
## Third-party assets
### Robots (`assets/models/robots/`)
- **"A"** by **Someone**, **CC-BY 4.0**: `a.glb`.
- **"B"** by **Other**, **CC-BY-NC 4.0 (non-commercial)**: `b.glb`, the THING.
- **"C"** by **Third**, **Sketchfab Standard licence** (https://sketchfab.com/licenses): `c.glb`.
### Font (`assets/fonts/x.ttf`)
Licensed under the **SIL Open Font License 1.1**.
### Mystery (`assets/models/m.glb`)
No one knows.
### Odd
Under the **Do What You Want Licence**.
## Tools
### Not an asset
Nothing here needs a licence.
"""
    problems, counts, warnings = check(sample, commercial=False)
    expect = [
        any("'Mystery" in p and "states no licence" in p for p in problems),
        any("'Odd'" in p and "states no licence" in p for p in problems),
        any("Do What You Want Licence" in p and "not in LICENCES" in p for p in problems),
        not any("Not an asset" in p for p in problems),
        not any("forbids" in p for p in problems),
        counts == {"CC-BY (attribution)": 1, "CC-BY-NC (non-commercial)": 1, "SIL OFL (font)": 1,
                   "Sketchfab Standard": 1},
        warnings == [],
    ]
    sold, _, review = check(sample, commercial=True)
    expect.append(any("forbids a commercial build: b.glb" in p for p in sold))
    expect.append(not any("a.glb" in p or "c.glb" in p for p in sold))
    expect.append(len(review) == 1 and "c.glb" in review[0])
    if all(expect):
        print("check_licences self-test OK (%d cases)" % len(expect))
        return 0
    print("check_licences self-test FAILED: %s" % expect)
    return 1


def main(argv):
    if "--self-test" in argv:
        return self_test()
    commercial = "--commercial" in argv
    problems, counts, warnings = check(open(CREDITS, encoding="utf-8").read(), commercial)
    for name in sorted(counts):
        print("  %-28s %d" % (name, counts[name]))
    for w in warnings:
        print("WARNING " + w)
    if problems:
        print("Licence check FAILED%s:" % (" for a commercial build" if commercial else ""))
        for p in problems:
            print("  " + p)
        return 1
    print("Licences OK%s: every third-party section in CREDITS.md states one"
          % (" for a commercial build" if commercial else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
