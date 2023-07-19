#!/bin/sh

set -eu

DEST="${HOME}/public_html"

rm "$DEST"/*

for i in . article page; do
	mkdir -p "${DEST}/${i}"

	cp -v ./"$i"/*.html "${DEST}/${i}"
	cp -v ./"$i"*.xml "${DEST}/${i}"
done

find "$DEST" -type f -exec chmod 0640 {} +
find "$DEST" -type d -exec chmod 0750 {} +

