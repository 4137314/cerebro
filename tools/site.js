// cerebro: search, keyboard navigation, link previews and in-page contents.
// No dependencies; every page works without it.  tools/site.el copies it to site.js.
(() => {
  "use strict";
  const root = document.body.dataset.root || "";
  const norm = s => (s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

  // ---- search index (loaded on first use) ----
  let index = null, loading = null;
  const load = () => loading || (loading = fetch(root + "search.json")
    .then(r => r.json())
    .then(d => (index = d.map(e => Object.assign(e, {
      _t: norm(e.t),
      _al: norm(e.al),
      _r: norm([e.s, e.a, e.d, e.b, e.k].join(" ")),
    })))));

  const score = (e, terms) => {
    let s = 0;
    // Title first (at its start, at a word, inside a word), then aliases, then the rest.
    for (const t of terms) {
      const i = e._t.indexOf(t);
      if (i === 0) s += 30;
      else if (i > 0) s += /[\s(–-]/.test(e._t[i - 1]) ? 20 : 10;
      else if (e._al.includes(t)) s += 8;
      else if (e._r.includes(t)) s += 3;
      else return 0;
    }
    return s + (e.k === "area" ? 2 : 0) - e.t.length / 200;
  };

  const q = document.getElementById("q");
  const box = document.createElement("ol");
  box.id = "results";
  box.hidden = true;
  let hits = [], sel = 0;

  const draw = () => {
    box.replaceChildren(...hits.map((e, i) => {
      const li = document.createElement("li");
      const a = document.createElement("a");
      a.href = root + e.u;
      const b = document.createElement("b"); b.textContent = e.t;
      const w = document.createElement("span"); w.className = "where";
      w.textContent = [e.b, e.d, e.a, e.k].filter(Boolean).join(" › ");
      const s = document.createElement("span"); s.className = "sum"; s.textContent = e.s || "";
      a.append(b, w, s);
      li.append(a);
      if (i === sel) { li.className = "sel"; }
      return li;
    }));
    box.hidden = !hits.length;
    const cur = box.querySelector(".sel");
    if (cur) cur.scrollIntoView({ block: "nearest" });
  };

  const search = async () => {
    await load();
    const terms = norm(q.value).split(/\s+/).filter(Boolean);
    hits = terms.length
      ? index.map(e => [score(e, terms), e]).filter(x => x[0] > 0)
          .sort((a, b) => b[0] - a[0]).slice(0, 20).map(x => x[1])
      : [];
    sel = 0;
    draw();
  };

  if (q) {
    q.after(box);
    q.addEventListener("focus", load, { once: true });
    q.addEventListener("input", search);
    q.addEventListener("keydown", ev => {
      if (ev.key === "ArrowDown" || (ev.ctrlKey && ev.key === "n")) { sel = Math.min(sel + 1, hits.length - 1); draw(); ev.preventDefault(); }
      else if (ev.key === "ArrowUp" || (ev.ctrlKey && ev.key === "p")) { sel = Math.max(sel - 1, 0); draw(); ev.preventDefault(); }
      else if (ev.key === "Enter" && hits[sel]) { location.href = root + hits[sel].u; }
      else if (ev.key === "Escape") { q.value = ""; hits = []; draw(); q.blur(); }
    });
    document.addEventListener("click", ev => {
      if (!q.contains(ev.target) && !box.contains(ev.target)) box.hidden = true;
    });
  }

  // ---- keys ----
  const keys = [
    ["/  s", "search every note"],
    ["j  n", "next note in study order"],
    ["k  p", "previous note in study order"],
    ["u", "up: the area of this note, or the bases"],
    ["h", "home: all the bases"],
    ["l", "open the learning path of this note"],
    ["c", "open the contents"],
    ["r", "a random note"],
    ["g", "top of the page"],
    ["?", "this help"],
  ];
  let help = null;
  const toggleHelp = () => {
    if (!help) {
      help = document.createElement("dialog");
      help.className = "help";
      help.innerHTML = "<h2>Keyboard</h2><dl></dl><p>Esc closes. In the search field: ↑ ↓ to choose, Enter to open.</p>";
      for (const [k, d] of keys) {
        const dt = document.createElement("dt");
        dt.innerHTML = k.split("  ").map(x => `<kbd>${x}</kbd>`).join(" ");
        const dd = document.createElement("dd"); dd.textContent = d;
        help.querySelector("dl").append(dt, dd);
      }
      help.addEventListener("click", ev => { if (ev.target === help) help.close(); });
      document.body.append(help);
    }
    help.open ? help.close() : help.showModal();
  };
  const follow = selector => { const a = document.querySelector(selector); if (a) location.href = a.href; };
  const toggle = selector => {
    const d = document.querySelector(selector);
    if (d) { d.open = !d.open; d.scrollIntoView({ block: "nearest", behavior: "smooth" }); }
  };

  document.addEventListener("keydown", ev => {
    if (ev.ctrlKey || ev.metaKey || ev.altKey) return;
    if (ev.target.closest && ev.target.closest("input, textarea, select, [contenteditable]")) return;
    switch (ev.key) {
      case "/": case "s": if (q) { ev.preventDefault(); q.focus(); q.select(); } break;
      case "j": case "n": follow('a[rel="next"]'); break;
      case "k": case "p": follow('a[rel="prev"]'); break;
      case "u": follow('a[rel="up"]'); break;
      case "h": location.href = root + "index.html"; break;
      case "l": toggle("details.path"); break;
      case "c": toggle("details.toc"); break;
      case "g": scrollTo({ top: 0, behavior: "smooth" }); break;
      case "r": load().then(() => {
        const notes = index.filter(e => e.k !== "area");
        location.href = root + notes[Math.floor(Math.random() * notes.length)].u;
      }); break;
      case "?": toggleHelp(); break;
      case "Escape": hidePreview(); break;
    }
  });

  // ---- contents of a long note ----
  const main = document.querySelector("main.note");
  if (main) {
    const hs = [...main.querySelectorAll("h2, h3")];
    if (hs.length >= 3) {
      const d = document.createElement("details");
      d.className = "toc";
      d.innerHTML = "<summary>Contents</summary><ol></ol>";
      hs.forEach((h, i) => {
        if (!h.id) h.id = "s" + i;
        const li = document.createElement("li");
        li.className = h.tagName.toLowerCase();
        const a = document.createElement("a");
        a.href = "#" + h.id;
        a.textContent = h.textContent;
        li.append(a);
        d.querySelector("ol").append(li);
      });
      main.before(d);
    }
  }

  // ---- previews of linked notes (hover) ----
  const cache = new Map();
  let tip = null, timer = null;
  const hidePreview = () => { clearTimeout(timer); if (tip) { tip.remove(); tip = null; } };
  const preview = async a => {
    let html = cache.get(a.href);
    if (html === undefined) {
      try {
        const r = await fetch(a.href);
        if (!r.ok) return;
        const doc = new DOMParser().parseFromString(await r.text(), "text/html");
        doc.querySelectorAll("img").forEach(i => { i.src = new URL(i.getAttribute("src"), a.href).href; });
        const part = s => { const x = doc.querySelector(s); return x ? x.innerHTML : ""; };
        html = `<p class="meta">${part("header .meta")}</p><p class="t">${part("h1")}</p><p>${part("header .summary")}</p>`;
      } catch (e) { html = ""; }
      cache.set(a.href, html);
    }
    if (!html || !a.matches(":hover")) return;
    hidePreview();
    tip = document.createElement("div");
    tip.className = "preview";
    tip.innerHTML = html;
    document.body.append(tip);
    const r = a.getBoundingClientRect();
    const left = Math.max(8, Math.min(r.left, innerWidth - tip.offsetWidth - 8));
    const below = r.bottom + tip.offsetHeight + 8 < innerHeight;
    tip.style.left = left + scrollX + "px";
    tip.style.top = (below ? r.bottom + 6 : r.top - tip.offsetHeight - 6) + scrollY + "px";
  };
  if (matchMedia("(hover: hover)").matches && location.protocol !== "file:") {
    document.addEventListener("mouseover", ev => {
      const a = ev.target.closest && ev.target.closest("main a, header a, details a, nav.pn a");
      if (!a || a.origin !== location.origin || !/\.html$/.test(a.pathname)
          || a.pathname === location.pathname || /\/index\.html$/.test(a.pathname)) return;
      clearTimeout(timer);
      timer = setTimeout(() => preview(a), 350);
      a.addEventListener("mouseleave", hidePreview, { once: true });
    });
  }
})();
