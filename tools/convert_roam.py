#!/usr/bin/env python3
"""Convert the org-roam math notes of cerebro to the knowledge-base reader format.

    python3 tools/convert_roam.py SRC_DIR OUT_DIR

SRC_DIR holds the org-roam notes (``notes/math`` of the ``feature/emacs-ui`` branch);
OUT_DIR receives ``<domain>/<slug>.org``.  One-shot, kept for reproducibility.

- ``:ID:`` becomes a slug of the title; every ``[[id:UUID]]`` is rewritten to it.
- DOMAIN and AREA come from ``#+FILETAGS`` (status tags dropped): the first topic tag
  names the domain when it is one, else the domain of the area; AREA is the last topic tag.
- KIND from the first theorem-like block; a note without one is an ``overview``.
- ``#+summary:`` is the first paragraph, moved out of the body (not copied).
- REQUIRES: the notes owning the ``#+DEPENDS`` labels; edges closing a cycle go to SEE.
- MSC and DATE are kept; the rest of the body is unchanged.
- A note that is only an empty template (no text at all) is skipped and reported.
"""
import re
import sys
import unicodedata
from pathlib import Path

STATUS = {"growing", "evergreen", "easy", "medium", "hard", "seed", "seedling"}
DOMAINS = {"foundations": "foundations", "algebra": "algebra", "analysis": "analysis",
           "topology": "topology", "geometry": "geometry", "probability": "probability",
           "mathematical_physics": "physics", "dynamics": "physics"}
AREA_DOMAIN = {
    "logic": "foundations", "set_theory": "foundations", "model_theory": "foundations",
    "proof_theory": "foundations", "computability": "foundations",
    "group_theory": "algebra", "ring_theory": "algebra", "field_theory": "algebra",
    "commutative_algebra": "algebra", "linear_algebra": "algebra",
    "real_analysis": "analysis", "complex_analysis": "analysis",
    "functional_analysis": "analysis", "measure_theory": "analysis",
    "harmonic_analysis": "analysis", "ordinary_differential_equations": "analysis",
    "partial_differential_equations": "analysis", "calculus_of_variations": "analysis",
    "approximation_theory": "analysis",
    "general_topology": "topology", "algebraic_topology": "topology",
    "differential_topology": "topology",
    "convex_geometry": "geometry", "differential_geometry": "geometry",
    "symplectic_geometry": "geometry", "algebraic_geometry": "geometry",
    "probability_theory": "probability", "statistics": "probability",
    "classical_mechanics": "physics", "quantum_theory": "physics",
    "dynamical_systems": "physics",
}
DEFAULT_DOMAIN = "foundations"
KINDS = {"definition": "definition", "axiom": "definition", "theorem": "theorem",
         "proposition": "theorem", "lemma": "theorem", "corollary": "theorem"}
HEADER = re.compile(r"^#\+(TITLE|DATE|FILETAGS|MSC|HASH):[ \t]*(.*)$", re.M)
REPORT = {"cycles": [], "unknown_labels": [], "unknown_links": [], "skipped_empty": []}


def slug(title):
    s = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode()
    s = re.sub(r"['’]", "", s.lower())
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def parse(text):
    """Fields of one org-roam note."""
    uuid = re.search(r"^:ID:[ \t]+(\S+)", text, re.M).group(1)
    head = {k: v.strip() for k, v in HEADER.findall(text)}
    body = text[text.index(":END:\n") + len(":END:\n"):]
    body = HEADER.sub("", body)
    body = re.sub(r"\A\n+", "", body)
    tags = [t for t in head.get("FILETAGS", "").split(":") if t and t not in STATUS]
    if tags and tags[0] in DOMAINS:
        domain = DOMAINS[tags[0]]
    elif tags:
        domain = AREA_DOMAIN.get(tags[-1], DEFAULT_DOMAIN)
    else:
        domain = DEFAULT_DOMAIN
    area = (tags[-1] if tags else "overview").replace("_", "-")
    kinds = [KINDS[b.lower()] for b in re.findall(r"^#\+begin_(\w+)", body, re.M | re.I)
             if b.lower() in KINDS]
    labels = re.findall(r"^#\+NAME:[ \t]*(\S+)", body, re.M)
    depends = [d.strip() for line in re.findall(r"^#\+DEPENDS:(.*)$", body, re.M)
               for d in line.split(",") if d.strip()]
    # Summary: the first paragraph, if the body starts with prose.
    m = re.match(r"((?:(?!#\+|\*+ |- |[ \t]*$).*\n)+)\n*", body, re.M)
    summary = None
    if m:
        summary = re.sub(r"\s+", " ", m.group(1)).strip()
        body = body[m.end():]
    return {"uuid": uuid, "title": head.get("TITLE", uuid), "date": head.get("DATE"),
            "msc": head.get("MSC"), "domain": domain, "area": area,
            "kind": kinds[0] if kinds else "overview", "labels": labels,
            "depends": depends, "summary": summary or head.get("TITLE", uuid), "body": body}


def is_empty(n):
    """A template never filled in: nothing but empty blocks (it stays in the git history)."""
    rest = re.sub(r"^#\+(begin|end)_\w+.*$", "", n["body"], flags=re.M | re.I)
    return not rest.strip() and n["summary"] == n["title"]


def _break_cycles(requires):
    """Drop the edges that close a cycle (DFS by slug); return them as (from, to)."""
    state, dropped = {}, []

    def visit(n):
        state[n] = 1
        for r in sorted(requires[n]):
            if state.get(r) == 1:
                dropped.append((n, r))
            elif r not in state:
                visit(r)
        state[n] = 2

    for n in sorted(requires):
        if n not in state:
            visit(n)
    for a, b in dropped:
        requires[a].discard(b)
    return dropped


def convert(sources):
    """{filename: text} of org-roam notes -> {"domain/slug.org": text}."""
    REPORT.update(cycles=[], unknown_labels=[], unknown_links=[], skipped_empty=[])
    notes = []
    for name, text in sources.items():
        n = parse(text)
        if is_empty(n):
            REPORT["skipped_empty"].append((n["title"], name))
        else:
            notes.append(n)
    ids = {n["uuid"]: slug(n["title"]) for n in notes}
    owner = {lab: ids[n["uuid"]] for n in notes for lab in n["labels"]}
    requires = {}
    for n in notes:
        me = ids[n["uuid"]]
        reqs = set()
        for d in n["depends"]:
            if d not in owner:
                REPORT["unknown_labels"].append((me, d))
            elif owner[d] != me:
                reqs.add(owner[d])
        requires[me] = reqs
    dropped = _break_cycles(requires)
    REPORT["cycles"] = dropped
    see = {}
    for a, b in dropped:
        see.setdefault(a, set()).add(b)

    def relink(text, me):
        def sub(m):
            if m.group(1) in ids:
                return f"[[id:{ids[m.group(1)]}]"
            REPORT["unknown_links"].append((me, m.group(1)))
            return m.group(0)
        return re.sub(r"\[\[id:([^]]+)\]", sub, text)

    out = {}
    for n in notes:
        me = ids[n["uuid"]]
        drawer = [":PROPERTIES:", f":ID:       {me}", f":DOMAIN:   {n['domain']}",
                  f":AREA:     {n['area']}", f":KIND:     {n['kind']}"]
        if requires[me]:
            drawer.append(":REQUIRES: " + " ".join(sorted(requires[me])))
        if me in see:
            drawer.append(":SEE:      " + " ".join(sorted(see[me])))
        if n["msc"]:
            drawer.append(f":MSC:      {n['msc']}")
        drawer.append(":END:")
        head = drawer + [f"#+title: {n['title']}", f"#+summary: {relink(n['summary'], me)}"]
        if n["date"]:
            head.append(f"#+date: {n['date']}")
        out[f"{n['domain']}/{me}.org"] = "\n".join(head) + "\n\n" + relink(n["body"], me)
    return out


def main(src, dst):
    sources = {p.name: p.read_text() for p in sorted(Path(src).glob("*.org"))}
    out = convert(sources)
    if len(out) != len(sources) - len(REPORT["skipped_empty"]):
        sys.exit(f"slug collision: {len(sources)} notes -> {len(out)} files")
    for rel, text in out.items():
        p = Path(dst) / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    print(f"notes: {len(out)}")
    for k, v in REPORT.items():
        print(f"{k}: {len(v)}")
        for e in v:
            print(f"  {e[0]} -> {e[1]}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
