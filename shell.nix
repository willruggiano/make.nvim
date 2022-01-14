with import <nixpkgs> {};

mkShell {
  name = "make.nvim";
  nativeBuildInputs = [ nodejs ];
}
