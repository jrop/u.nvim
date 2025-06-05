{
  pkgs ?
    import
      # nixpkgs-unstable (neovim@0.11.2):
      (fetchTarball {
        url = "https://github.com/nixos/nixpkgs/archive/e4b09e47ace7d87de083786b404bf232eb6c89d8.tar.gz";
        sha256 = "1a2qvp2yz8j1jcggl1yvqmdxicbdqq58nv7hihmw3bzg9cjyqm26";
      })
      { },
}:
pkgs.mkShell {
  packages = [
    pkgs.git
    pkgs.gnumake
    pkgs.lua-language-server
    pkgs.lua51Packages.busted
    pkgs.lua51Packages.luacov
    pkgs.lua51Packages.luarocks
    pkgs.lua51Packages.nlua
    pkgs.neovim
    pkgs.stylua
  ];
}
