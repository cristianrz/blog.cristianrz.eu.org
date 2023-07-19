#!/bin/sh

set -eu

DEST="${HOME}/public_html"

git reset HEAD --hard

rm -r "$DEST"/*

for i in . article page; do
	mkdir -p "${DEST}/${i}"

	cp ./"$i"/*.html "${DEST}/${i}" || true
	cp ./"$i"/*.xml "${DEST}/${i}" ||  true
done

find "$DEST"/ -type f -exec chmod 0640 {} + 
find "$DEST"/ -type d -exec chmod 0750 {} + 

printf '[*] Deployed successfully\n'

