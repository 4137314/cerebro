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
    in {
      packages.x86_64-linux.default = hub;
      apps.x86_64-linux.default = { type = "app"; program = "${hub}/bin/cerebro"; };
    };
}
