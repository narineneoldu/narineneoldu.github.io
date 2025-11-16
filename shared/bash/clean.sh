#!/usr/bin/env bash

# Hem en hem tr temp tsv dosyalarını siler
find . -type f \( -name ".qrender-time.tmp-en.tsv" -o -name ".qrender-time.tmp-tr.tsv" \) -delete
