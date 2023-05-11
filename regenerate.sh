#!/bin/sh
#
# regenerate.sh
# =============
# 
# Replaces all pages headers and footers by header.html and footer.html.
# It will also set the page title by replacing %a%b%c in the header.html with
# whatever is in <h2> (there should only be one). It will then create a  .bak
# file and replace the html for the new one.
#

set -eu

_log_info(){
	printf '\e[34m[*] %s\e[0m\n' "$*"
}

find index.html page/ article/ -type f -name "*.html"| while read -r file; do
	_log_info "Generating $file"
	_log_info "- Grabbing title"
	title="$(awk '/h2/ { gsub(/.*<h2>/,""); gsub(/<\/h2>/,""); print  }' "$file")"

	_log_info "- Adding headers"
	{
		sed "s/%a%b%c/$title/g" header.html 
		awk '
		BEGIN { content = 0; }
		/<!-- BEGIN MAIN CONTENT -->/ { content=1; next; }
		/<!-- END MAIN CONTENT -->/ { content=0; next; }
		content == 1 { print; }
		' "$file"
		cat footer.html
	} > "$file.new"

	_log_info "- Creating backup and overwriting file"
	mv "$file" "$file.bak"
	mv "$file.new" "$file"
done
