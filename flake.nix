{
  description = "cerebro: read-only hub of the knowledge bases (math, thesis, courses)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # The reader, shared with the projects whose bases it opens.  The makefile builds
    # against the sibling checkout (../knowledge-base) when it is there.
    knowledge-base = {
      url = "git+ssh://git@github.com/4137314/knowledge-base";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, knowledge-base }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      # Command `cerebro`, server and state "cerebro" (~/.local/state/cerebro-emacs);
      # the bases are in bases.el.
      hub = knowledge-base.lib.mkHub pkgs {
        name = "cerebro";
        registry = "bases.el";
        rootVar = "CEREBRO_ROOT";
      };
      # `cerebro-site REGISTRY HUB-ROOT OUT [--base NAME]... [--pdf] [--no-index|--index-only]`:
      # the static site and PDF manuals of the bases marked :publish t (tools/site.el,
      # tools/manual.el), with the reader's engine and LaTeX pipeline;
      # `cerebro-site --test` runs their tests.
      siteApp = name: inputs: pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = inputs;
        text = ''
          reader="${knowledge-base}/emacs"
          tools="${./tools}"
          if [ "''${1:-}" = --test ]; then
            exec emacs --batch -Q -L "$reader" -L "$tools" -l "$tools/test-manual.el" \
              -f ert-run-tests-batch-and-exit
          fi
          exec emacs --batch -Q -L "$reader" -l "$tools/site.el" -f site-main "$@"
        '';
      };
      site = siteApp "cerebro-site" [ pkgs.emacs-nox pkgs.texliveFull pkgs.qpdf ];
      # The same without TeX, for --index-only (home, search index, sitemap).
      site-index = siteApp "cerebro-site-index" [ pkgs.emacs-nox ];
    in {
      packages.x86_64-linux = { default = hub; inherit site site-index; };
      apps.x86_64-linux = {
        default = { type = "app"; program = "${hub}/bin/cerebro"; };
        site = { type = "app"; program = "${site}/bin/cerebro-site"; };
        site-index = { type = "app"; program = "${site-index}/bin/cerebro-site-index"; };
      };
    };
}
