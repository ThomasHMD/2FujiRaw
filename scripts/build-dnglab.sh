#!/usr/bin/env bash
# Compile un dnglab patché qui supporte le Hasselblad X2D II 100C.
#
# Upstream dnglab 0.7.2 ne connaît que le X2D 100C original. Le X2D II 100C
# partage le même capteur Sony IMX461 : un simple alias dans la config
# `hasselblad/x2d_100c.toml` suffit à router les .3FR X2D II vers le même
# décodeur. On clone la v0.7.2, on patche, on compile en release arm64.
#
# Prérequis : rustup + cargo (`curl https://sh.rustup.rs -sSf | sh`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
BUILD_DIR="$ROOT/.build-dnglab"
DNGLAB_VERSION="0.7.2"

mkdir -p "$VENDOR"

# Sanity check : cargo doit être disponible. Source l'env rustup si besoin.
if ! command -v cargo >/dev/null; then
    if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.cargo/env"
    fi
fi
if ! command -v cargo >/dev/null; then
    echo "Erreur : cargo introuvable. Installe Rust via https://rustup.rs avant de relancer." >&2
    exit 1
fi

# 1. Clone v0.7.2 (shallow)
rm -rf "$BUILD_DIR"
echo "Cloning dnglab v${DNGLAB_VERSION}..."
git clone --depth 1 --branch "v${DNGLAB_VERSION}" \
    https://github.com/dnglab/dnglab.git "$BUILD_DIR" 2>&1 | tail -5

# 2. Patch : ajouter les alias X2D II 100C dans la config X2D 100C.
#    Idempotent — si le patch a déjà été appliqué, grep retombe et on skip.
CAM_TOML="$BUILD_DIR/rawler/data/cameras/hasselblad/x2d_100c.toml"
if ! grep -q "X2D II 100C" "$CAM_TOML"; then
    echo "Patch : ajout des alias X2D II 100C..."
    # Insère les 2 lignes d'alias après la ligne du X2D 100C original
    sed -i '' 's|\["Hasselblad X2D 100C", "X2D 100C"\],|\["Hasselblad X2D 100C", "X2D 100C"\],\
  \["Hasselblad X2D II 100C", "X2D 100C"\],\
  \["X2D II 100C", "X2D 100C"\],|' "$CAM_TOML"
else
    echo "Patch : déjà appliqué, skip."
fi

# 2b. Compat cargo : certains manifests du tag v0.7.2 demandent edition=2024,
#     mais le cargo installé sur cette machine est plus ancien. On downgrade
#     localement vers edition=2021 pour permettre le build.
echo "Patch : downgrade édition Cargo 2024 -> 2021..."
find "$BUILD_DIR" -name Cargo.toml -print0 | while IFS= read -r -d '' manifest; do
    if grep -q 'edition = "2024"' "$manifest"; then
        sed -i '' 's/edition = "2024"/edition = "2021"/g' "$manifest"
    fi
done

# 3. Build release
echo "Compilation dnglab (cargo release)..."
(cd "$BUILD_DIR" && cargo build --release --bin dnglab)

# 4. Copier le binaire dans vendor/
cp "$BUILD_DIR/target/release/dnglab" "$VENDOR/dnglab"
chmod +x "$VENDOR/dnglab"

echo "OK → $VENDOR/dnglab ($("$VENDOR/dnglab" --version))"
