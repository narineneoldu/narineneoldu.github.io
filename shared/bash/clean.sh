#!/usr/bin/env bash

# Hem en hem tr temp tsv dosyalarını siler
find . -type f \( -name ".qrender-time.tmp-en.tsv" -o -name ".qrender-time.tmp-tr.tsv" \) -delete
find . -type f \( -name "reading-time-debug.log" -o -name "reading-time-debug.log" \) -delete
find . -type f -name '*_reading_stats.yml' -delete
