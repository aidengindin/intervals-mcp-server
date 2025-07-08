{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-system = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, uv2nix, pyproject-nix, pyproject-build-system, ... }:
   let
    inherit (nixpkgs) lib;

    workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

    overlay = workspace.mkPyprojectOverlay {
      sourcePreference = "wheel";
    };

    pyprojectOverrides = _final: _prev: {
    };

    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    python = pkgs.python312;

    pythonSet =
      (pkgs.callPackage pyproject-nix.build.packages {
        inherit python;
      }).overrideScope
        (
          lib.composeManyExtensions [
            pyproject-build-system.overlays.default
            overlay
            pyprojectOverrides
          ]
        );
    
    # Function to create the server package with optional credentials
    mkServerPackage = { apiKey ? null, athleteId ? null }: 
      pkgs.writeShellApplication {
        name = "intervals-mcp-server";
        runtimeInputs = [
          (pythonSet.mkVirtualEnv "intervals-mcp-server-env" workspace.deps.default)
        ];
        text = ''
          ${lib.optionalString (apiKey != null) ''export INTERVALS_API_KEY="${apiKey}"''}
          ${lib.optionalString (athleteId != null) ''export INTERVALS_ATHLETE_ID="${athleteId}"''}
          exec python -m intervals_mcp_server.server "$@"
        '';
      };
   in {
     # Default package that expects env vars to be set externally
     packages.x86_64-linux.default = mkServerPackage {};
     
     # Function to create a configured server package
     packages.x86_64-linux.mkConfiguredServer = mkServerPackage;

    apps.x86_64-linux = {
      default = {
        type = "app";
        program = "${self.packages.x86_64-linux.default}/bin/intervals-mcp-server";
      };
    };
    
    # Overlay for using this flake as an input
    overlays.default = final: prev: {
      intervals-mcp-server = mkServerPackage {};
      mkIntervalsServer = mkServerPackage;
    };
    
    devShells.x86_64-linux.default = let
      virtualenv = pythonSet.mkVirtualEnv "intervals-mcp-server-dev-env" workspace.deps.all;

    in pkgs.mkShell {
      packages = [
        pkgs.uv
      ];
      buildInputs = [
        virtualenv
      ];
      env = {
        UV_NO_SYNC = "1";
        UV_PYTHON = "${virtualenv}/bin/python";
        UV_PYTHON_DOWNLOADS = "never";
      };
      shellHook = ''
        unset PYTHONPATH
        
        # Activate the virtualenv
        export PATH="${virtualenv}/bin:$PATH"
        export VIRTUAL_ENV="${virtualenv}"
        
        # Show which python is being used
        echo "🐍 $(python --version)"

        if [ -f .env ]; then
          source .env
          echo "Loaded envionment variables from .env"
        fi
      '';
    };
  };
}

