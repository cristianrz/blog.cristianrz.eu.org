#!/bin/sh

set -eu

_log_info() {
    printf '\e[34m[*] %s\e[0m\n' "$*" >&2
}

find index.html page/ article/ -type f -name "*.html" | while read -r file; do
    _log_info "Generating $file"
    _log_info "- Grabbing title"
    title="$(awk '/<h2>/ { gsub(/.*<h2>/, ""); gsub(/<\/.*/, "");  print  }' "$file")"

    _log_info "- Adding headers"
    {
        sed "s/%a%b%c/$title/g" header.html
        printf '\n'
        awk '
				BEGIN { content = 0; }
				/<!-- BEGIN MAIN CONTENT -->/ { content=1; next; }
				/<!-- END MAIN CONTENT -->/ { content=0; next; }
				content == 1 && $0 !~ /^$/ { print; }
			' "$file"
        printf '\n'
        cat footer.html
    } >"$file.new"

    sed -i.bak 's/..\/index.html/#/g' index.html
    rm index.html.bak

    _log_info "- Creating backup and overwriting file"
    mv "$file" "$file.bak"
    mv "$file.new" "$file"
done
