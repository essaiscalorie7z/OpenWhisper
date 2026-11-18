#!/usr/bin/env bash
set -euo pipefail
mkdir -p vendor
archive=vendor/whisper-v1.8.2.zip
if [[ ! -f "$archive" ]]; then
  curl -fL --retry 3 -o "$archive.part" https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.2/whisper-v1.8.2-xcframework.zip
  mv "$archive.part" "$archive"
fi
echo "3ffeec1df254d908f01ee3d87bf0aedb8fbc8f29cbf50dc8702741bb85381385  $archive" | shasum -a 256 -c -
unzip -oq "$archive" 'build-apple/whisper.xcframework/*' -d vendor
if [[ "${1:-}" != "--device" ]]; then
  model=Tests/Fixtures/ggml-base-q5_1.bin
  if [[ ! -f "$model" ]]; then
    curl -fL --retry 3 -o "$model.part" https://huggingface.co/ggerganov/whisper.cpp/resolve/c521a4b02f422512d734391fdf08bb08c0862f68/ggml-base-q5_1.bin
    mv "$model.part" "$model"
  fi
  echo "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898  $model" | shasum -a 256 -c -
fi
curl -fL --retry 3 -o vendor/fr_50k.txt https://raw.githubusercontent.com/hermitdave/FrequencyWords/525f9b560de45753a5ea01069454e72e9aa541c6/content/2018/fr/fr_50k.txt
python3 scripts/lexicon.py vendor/fr_50k.txt
xcodegen generate
