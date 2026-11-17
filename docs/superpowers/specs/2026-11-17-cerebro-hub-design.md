# Cerebro: hub delle knowledge base (design)

## Perché

I launcher di Tesi, Remote Sensing e Computer Science non partono più: i `.desktop` in
`~/.local/share/applications/` puntano a `~/dev/dev/...` e `~/dev/git/...`, percorsi spariti
col riordino di `~/dev` (14/11). L'utente vuole un'unica porta d'ingresso, **Cerebro**, che
apra tutte le basi di appunti in **sola lettura**, con le note di matematica di cerebro
trattate come una base fra le altre. La scrittura in cerebro (org-roam, Guix) non la usa.

## Obiettivi

- Una voce "Cerebro" nel launcher → una finestra Emacs con la **pagina delle basi**
  (Matematica, Tesi, Remote Sensing, Computer Science); si entra in una e si torna alla
  pagina delle basi senza chiudere la finestra (scelta B).
- Tutte le basi lette con il lettore `knowledge-base` esistente: stessi tasti, formule,
  grafo, segnalibro di lettura.
- Le 210 note di matematica (oggi nel branch `feature/emacs-ui`) diventano la base `math`
  nel formato del lettore.
- Robusto ai traslochi: niente percorsi assoluti scritti a mano.

## Non-obiettivi

- Modificare o scrivere note dal lettore.
- Cambiare il contenuto delle basi di tesi, remote-sensing, computer-science.
- Toccare la sessione di studio in corso (server `remote-sensing`, stato
  `~/.local/state/remote-sensing-emacs`).

## Anti-obiettivi

- Perdere note di matematica (testo, dimostrazioni, link fra note).
- Rompere `make study` nei singoli progetti.

## Approcci considerati

- **A. Menu rofi + lettori separati**: poco lavoro, riusa tutto; una finestra per base.
- **B. Una finestra Emacs con pagina delle basi** — *scelta dall'utente*. Più integrato;
  richiede che il lettore sappia cambiare base a caldo (oggi lo stato è globale, una base
  per processo).

## Design

### 1. Lettore (`personal/knowledge-base`)

- `kb-open-base`: cambia base nello stesso processo. Chiude i buffer delle note della base
  precedente, rimette ai valori di default `kb-domains`, `kb-areas`, `kb-forbidden`,
  `kb-latex-preamble` (le config li modificano con `setq` / `kb-preamble-add`), imposta
  `kb-dir` e `kb-state-dir`, carica il `kb-config.el` della base, poi `kb-reload`,
  `kb--load-meta`, rendering in idle e `kb-home`.
- **Pagina delle basi** (`kb-bases`): attiva quando c'è `KB_BASES` (file di registro).
  Una riga per base: titolo, numero di note, nota al segnalibro. `RET` entra; un tasto
  libero (proposta: `H`) torna alla pagina da qualunque vista; anche nel pannello `?`.
- **Blocchi speciali**: rendere `#+begin_theorem` / `definition` / `lemma` /
  `proposition` / `corollary` / `remark` / `axiom` / `proof` come intestazione colorata
  ("Theorem", "Proof", …) con il corpo; righe `#+NAME:` / `#+DEPENDS:` nascoste.
  Generico: vale per qualunque base.
- `lib.mkHub pkgs { name, registry, rootVar }`: come `mkReader` ma senza base fissa;
  esporta `KB_BASES`. Stato per base in `~/.local/state/<name>-emacs/bases/<base>/`
  (cache SVG e segnalibro separati per base). Il primo ingresso in una base rende tutte
  le formule (come al primo avvio dei lettori singoli), poi è cache.
- I lettori singoli (`mkReader`) restano invariati nel comportamento.

### 2. Cerebro (`personal/cerebro`, branch `main`)

- `flake.nix`: `packages.default = knowledge-base.lib.mkHub …` con `name = "cerebro"`.
- `bases.el`: registro, percorsi **relativi alla radice di `~/dev`** (trovata a runtime
  con `git rev-parse --show-superproject-working-tree` dalla radice di cerebro):

  | base | titolo | radice | note | config |
  |---|---|---|---|---|
  | math | Matematica | `personal/cerebro` | `kb` | `kb-config.el` |
  | thesis | Tesi | `uni/bachelor-thesis` | `study/kb` | `study/kb-config.el` |
  | remote-sensing | Remote Sensing | `uni/remote-sensing` | `study/kb` | `study/kb-config.el` |
  | computer-science | Computer Science | `uni/computer-science` | `study/kb` | `study/kb-config.el` |

- `kb/` con le note di matematica convertite, `kb-config.el` (domini e aree).
- `makefile`: `install` (profilo in `~/.local/state/cerebro-emacs/profile` + `.desktop`
  "Cerebro" generato da template), `run`, `check` (`--check` su ogni base),
  `uninstall`.
- Il vecchio editor (Guix, org-roam, export LaTeX, tracker, hook Taskwarrior) **esce da
  `main`** ma resta intatto nei branch `feature/emacs-ui` / `legacy/*` e nella copia
  `misc/_synced/cerebro` (a cui puntano gli hook Taskwarrior: non la si tocca).

### 3. Conversione delle note di matematica

Script una tantum (`tools/convert-roam.py`, tenuto nel repo per riproducibilità) da
`feature/emacs-ui:notes/math/*.org` a `kb/<dominio>/<slug>.org`:

- `:ID:` = slug dal titolo (`abelian-group`); tutti i `[[id:UUID]]` riscritti agli slug.
- `DOMAIN` e `AREA` dai `FILETAGS` (tag di stato `growing`/`evergreen`/`easy`… scartati):
  foundations (logic, set/model/proof theory, computability), algebra (group, ring,
  field, commutative, linear algebra), analysis (real, complex, functional, measure,
  harmonic, ODE/PDE, calculus of variations, approximation), topology (general,
  algebraic, differential), geometry (convex, differential, symplectic, algebraic),
  probability (probability theory, statistics), physics (mathematical physics, classical
  mechanics, dynamics, quantum). Area = tag più specifico.
- `KIND` dal primo blocco: definition/axiom → `definition`; theorem/proposition/lemma/
  corollary → `theorem`.
- `#+summary:` = primo paragrafo prima del primo blocco.
- `REQUIRES` = note che possiedono le etichette citate in `#+DEPENDS` (escluse le proprie);
  eventuali cicli spezzati togliendo l'arco all'indietro, e l'arco rimosso va in `SEE`
  (lo script stampa l'elenco).
- `MSC`, `DATE` conservati come proprietà; corpo della nota invariato.
- Le 11 note di `courses/` e `conjectures/` non sono concetti: restano nel branch storico,
  fuori dalla base.
- Accettazione: `--check` della base `math` passa (metadati, link, DAG, formule rese);
  numero di note 210, nessun link perso (confronto conteggi prima/dopo).

### 4. Launcher

- `make install` in cerebro crea `cerebro.desktop`.
- I tre `.desktop` rotti (thesis, remote-sensing, computer-science) vengono rimossi: si
  entra da Cerebro; `make study` nei progetti continua a funzionare.

## Vincoli

- Test isolati: nome istanza `cerebro-test`, `XDG_STATE_HOME` nella scratchpad, lettore
  da worktree (`--override-input knowledge-base path:…`). Mai il server/stato
  `remote-sensing` finché l'utente studia.
- Pacchetti solo via Nix; push e `nix profile` li fa l'utente.
- Commit solo su richiesta.

## Lasciato a chi implementa

- Disposizione grafica della pagina delle basi (nello stile del lettore).
- Tasto esatto per tornare alle basi se `H` risultasse occupato.
- Aree precise e ordine di studio in `kb-config.el` di math.
