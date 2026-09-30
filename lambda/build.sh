#!/usr/bin/env bash
# Empaqueta la Lambda (codigo + dependencias) en function.zip
set -e
cd "$(dirname "$0")"
npm install --omit=dev
rm -f function.zip
zip -rq function.zip index.mjs node_modules package.json package-lock.json
echo "lambda/function.zip listo ($(du -h function.zip | cut -f1))"
