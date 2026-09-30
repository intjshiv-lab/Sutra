#!/usr/bin/env bash
# build-android.sh — Cross-compile SutraCore for Android + generate Kotlin UniFFI bindings
# Usage: bash scripts/build-android.sh
# Requires: cargo-ndk (cargo install cargo-ndk), Android NDK in $ANDROID_NDK_HOME

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "📦 Cross-compiling sutra-core for Android (arm64-v8a, x86_64)..."
cargo ndk \
  -t arm64-v8a \
  -t x86_64 \
  -o "$ROOT/apps/sutra-android/app/src/main/jniLibs" \
  build --manifest-path "$ROOT/Cargo.toml" --release

echo "🔧 Generating UniFFI Kotlin bindings..."
cargo run --manifest-path "$ROOT/Cargo.toml" --bin uniffi-bindgen generate \
  "$ROOT/crates/sutra-core/src/sutra_core.udl" \
  --language kotlin \
  --out-dir "$ROOT/apps/sutra-android/app/src/main/java/com/sutra/generated/"

echo "✅ Android JNI libs at apps/sutra-android/app/src/main/jniLibs/"
echo "✅ Kotlin bindings at apps/sutra-android/app/src/main/java/com/sutra/generated/"
