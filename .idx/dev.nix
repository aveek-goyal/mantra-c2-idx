{ pkgs, ... }: {
  channel = "stable-24.05";

  # Keep this minimal like the template
  packages = [
    # Core packages from template
    pkgs.cargo
    pkgs.rustc
    pkgs.rustup
    pkgs.rustfmt
    pkgs.stdenv.cc
    pkgs.llvmPackages.bintools  # Add this for LLD
    pkgs.llvmPackages.clang     # More complete LLVM toolchain
    pkgs.llvmPackages.lld       # Adding explicit LLD linker

    # Other necessary tools
    pkgs.go
    pkgs.docker
    pkgs.git
    pkgs.gh
    pkgs.cargo-generate
    pkgs.jq
    pkgs.wget
    pkgs.python3
    pkgs.python3Packages.colorama
    pkgs.python3Packages.gitpython
    pkgs.sudo
  ];

  env = {
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
    RUST_BACKTRACE = "1";
    CC = "clang";
    # Update RUSTFLAGS to remove -fuse-ld=lld for WASM builds
    RUSTFLAGS = "";

    # MANTRA Chain environment variables
    CHAIN_ID = "mantra-dukong-1";
    TESTNET_NAME = "mantra-dukong";
    DENOM = "uom";
    BECH32_HRP = "wasm";
    WASMD_VERSION = "v0.53.0";
    CONFIG_DIR = ".mantrachaind";
    BINARY = "mantrachaind";
    COSMJS_VERSION = "v0.28.1";
    RPC = "https://rpc.dukong.mantrachain.io:443";
    FAUCET = "https://faucet.dukong.mantrachain.io";
    NODE = "--node $RPC";
    TXFLAG = "--node https://rpc.dukong.mantrachain.io:443 --chain-id $CHAIN_ID --gas-prices 0.01$DENOM --gas auto --gas-adjustment 1.5";
  };
  services.docker.enable = true;

  idx = {
    extensions = [
      "rust-lang.rust-analyzer"
      "tamasfe.even-better-toml"
      "serayuzgur.crates"
      "vadimcn.vscode-lldb"
      "ms-python.python"
    ];

  workspace = {
  onStart = {
    setup-mantra = ''
      echo "=== Setting up MANTRA Chain environment ==="
      
      if [ ! -d "$HOME/MANTRA" ]; then
        mkdir -p ~/MANTRA && cd ~/MANTRA
        VERSION="v1.0.0"
        curl -LO https://github.com/MANTRA-Chain/mantrachain/releases/download/$VERSION/mantrachaind-1.0.0-linux-amd64.tar.gz
        tar -xzvf mantrachaind-1.0.0-linux-amd64.tar.gz
        chmod +x mantrachaind
        
        echo 'export LD_LIBRARY_PATH=~/MANTRA:$LD_LIBRARY_PATH' >> "$HOME/.bashrc"
        echo 'export PATH=~/MANTRA:$PATH' >> "$HOME/.bashrc"
        source "$HOME/.bashrc"
        echo "✓ MANTRA Chain setup complete"
      fi

      echo "=== Setting up Cargo configuration ==="
      # Create .cargo directory if it doesn't exist
      mkdir -p .cargo
      
      # Create or update config.toml
      cat > .cargo/config.toml << 'EOF'
[target.wasm32-unknown-unknown]
linker = "rust-lld"
rustflags = [
  "-C", "link-arg=-fuse-ld=lld",
  "-C", "target-feature=+atomics,+bulk-memory,+mutable-globals",
]

[build]
target = "wasm32-unknown-unknown"

[profile.release]
opt-level = 3
debug = false
rpath = false
lto = true
debug-assertions = false
codegen-units = 1
panic = 'abort'
incremental = false
overflow-checks = true
EOF
      echo "✓ Cargo configuration created"

      # Add WASM target
      echo "=== Setting up WASM target ==="
      rustup target add wasm32-unknown-unknown
      
      # Add build helper function
      if ! grep -q "build_wasm()" "$HOME/.bashrc"; then
        echo '
build_wasm() {
  cargo build --release
}' >> "$HOME/.bashrc"
        source "$HOME/.bashrc"
        echo "✓ Build helper function added. You can now use 'build_wasm' command"
      fi
      
      echo "=== Verifying installations ==="
      rustc --version && echo "✓ Rust is properly configured"
      cargo --version && echo "✓ Cargo is properly configured"
    '';
  };
};


  };
}
