"""Tests of tools/convert_roam.py (python3 -m unittest tools.test_convert_roam)."""
import unittest

from tools import convert_roam as c


def note(uuid, title, tags, body, msc="00A00", date="[2026-07-29 Wed]"):
    return (f":PROPERTIES:\n:ID:       {uuid}\n:END:\n#+TITLE: {title}\n#+DATE: {date}\n"
            f"#+FILETAGS: {tags}\n#+MSC: {msc}\n#+HASH: abc\n\n{body}")


GROUP = note("u-group", "Group", ":evergreen:algebra:group_theory:",
             "A /group/ is a set with\nan operation.\n\n#+NAME: def-group\n"
             "#+begin_definition\nA group \\((G,\\ast)\\).\n#+end_definition\n")
ABELIAN = note("u-ab", "Abelian group", ":evergreen:easy:group_theory:",
               "An /abelian group/ is a [[id:u-group][group]] that commutes.\n\n"
               "#+DEPENDS: def-group, def-abelian-group, def-nowhere\n#+NAME: def-abelian-group\n"
               "#+begin_definition\n\\[ ab = ba \\]\n#+end_definition\n")
LAGRANGE = note("u-lag", "Lagrange's theorem", ":growing:algebra:group_theory:",
                "The order of a subgroup divides the order.\n\n#+DEPENDS: def-abelian-group\n"
                "#+NAME: thm-lagrange\n#+begin_proposition\n...\n#+end_proposition\n")
OVERVIEW = note("u-alg", "Algebra", ":growing:algebra:",
                "Algebra studies operations.\n\n* The subjects\n- [[id:u-group][Group]]\n")


class TestConvert(unittest.TestCase):
    def setUp(self):
        self.out = c.convert({"g.org": GROUP, "a.org": ABELIAN, "l.org": LAGRANGE, "o.org": OVERVIEW})

    def test_slug(self):
        self.assertEqual(c.slug("Abelian group"), "abelian-group")
        self.assertEqual(c.slug("Lagrange's theorem"), "lagranges-theorem")
        self.assertEqual(c.slug("Fejér, Parseval: identities"), "fejer-parseval-identities")

    def test_paths_by_domain(self):
        self.assertEqual(sorted(self.out),
                         ["algebra/abelian-group.org", "algebra/algebra.org",
                          "algebra/group.org", "algebra/lagranges-theorem.org"])

    def test_drawer(self):
        t = self.out["algebra/abelian-group.org"]
        self.assertIn(":ID:       abelian-group\n", t)
        self.assertIn(":DOMAIN:   algebra\n", t)
        self.assertIn(":AREA:     group-theory\n", t)
        self.assertIn(":KIND:     definition\n", t)
        self.assertIn(":MSC:      00A00\n", t)
        self.assertIn("#+title: Abelian group\n", t)
        self.assertIn("#+date: [2026-07-29 Wed]\n", t)
        self.assertNotIn("FILETAGS", t)
        self.assertNotIn("HASH", t)

    def test_summary_moved_from_first_paragraph(self):
        t = self.out["algebra/group.org"]
        self.assertIn("#+summary: A /group/ is a set with an operation.\n", t)
        self.assertEqual(t.count("an operation."), 1)

    def test_links_rewritten(self):
        t = self.out["algebra/abelian-group.org"]
        self.assertIn("[[id:group][group]]", t)
        self.assertNotIn("u-group", t)
        # The rest of the body is unchanged.
        self.assertIn("#+NAME: def-abelian-group\n#+begin_definition\n\\[ ab = ba \\]\n#+end_definition\n", t)

    def test_requires_from_depends(self):
        t = self.out["algebra/abelian-group.org"]
        self.assertIn(":REQUIRES: group\n", t)

    def test_unknown_label_dropped(self):
        self.assertNotIn("nowhere", self.out["algebra/abelian-group.org"].split(":END:")[0])

    def test_kind_theorem(self):
        self.assertIn(":KIND:     theorem\n", self.out["algebra/lagranges-theorem.org"])

    def test_kind_overview(self):
        t = self.out["algebra/algebra.org"]
        self.assertIn(":KIND:     overview\n", t)
        self.assertIn(":AREA:     algebra\n", t)

    def test_cycle_broken_into_see(self):
        a = note("u-a", "Alpha", ":algebra:", "Alpha.\n\n#+DEPENDS: def-b\n#+NAME: def-a\n"
                 "#+begin_definition\nx\n#+end_definition\n")
        b = note("u-b", "Beta", ":algebra:", "Beta.\n\n#+DEPENDS: def-a\n#+NAME: def-b\n"
                 "#+begin_definition\ny\n#+end_definition\n")
        out = c.convert({"a.org": a, "b.org": b})
        drawers = out["algebra/alpha.org"] + out["algebra/beta.org"]
        self.assertEqual(drawers.count(":REQUIRES:"), 1)
        self.assertEqual(drawers.count(":SEE:"), 1)
        self.assertEqual(c.REPORT["cycles"], [("beta", "alpha")])

    def test_domain_from_area_tag(self):
        self.assertIn(":DOMAIN:   algebra\n", self.out["algebra/abelian-group.org"])
        n = note("u-c", "Hull", ":convex_geometry:", "Hull.\n")
        self.assertIn("geometry/hull.org", c.convert({"c.org": n}))

    def test_summary_stops_at_blank_line(self):
        t = self.out["algebra/algebra.org"]
        self.assertIn("#+summary: Algebra studies operations.\n", t)

    def test_summary_second_paragraph_kept_in_body(self):
        n = note("u-p", "Para", ":algebra:", "First one.\n\nPart of [[id:u-p][me]].\n")
        t = c.convert({"p.org": n})["algebra/para.org"]
        self.assertIn("#+summary: First one.\n", t)
        self.assertIn("\nPart of [[id:para][me]].\n", t)

    def test_empty_stub_skipped(self):
        n = note("u-s", "untitled", ":seed:", "#+begin_lemma\n\n#+end_lemma\n")
        out = c.convert({"s.org": n, "g.org": GROUP})
        self.assertEqual(list(out), ["algebra/group.org"])
        self.assertEqual(c.REPORT["skipped_empty"], [("untitled", "s.org")])


if __name__ == "__main__":
    unittest.main()
