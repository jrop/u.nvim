{
  pkgs ?
    import
      # neovim@0.11.1: https://history.nix-packages.com/package/neovim/0.11.1
      (fetchTarball "https://github.com/nixos/nixpkgs/tarball/e73c3bf29132da092f9c819b97b6e214367eb71f")
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
