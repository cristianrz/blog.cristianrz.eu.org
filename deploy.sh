#!/bin/sh

set -eu

DEST="${HOME}/public_html"

rm "$DEST"/*

cp -v ./*.html  ./*.xml "$DEST"

chmod 0640 "$DEST"/*
