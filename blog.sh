#!/bin/sh
#
# blog.sh
# =============
#
# Replaces all pages headers and footers by header.html and footer.html.
# It will also set the page title by replacing %a%b%c in the header.html with
# whatever is in <h2> (there should only be one). It will then create a  .bak
# file and replace the html for the new one.
#

set -eu

_log_info() {
	printf '\e[34m[*] %s\e[0m\n' "$*" >&2
}

_log_err() {
	printf '\e[31m[-] %s\e[0m\n' "$*" >&2
}

_log_fatal() {
	printf '\e[31m[-] %s\e[0m\n' "$*" >&2
	exit 1
}

new() {
	file="$1/$2.html"
	if [ -f "$file" ]; then
		_log_err "$file already exists"
	fi

	cat <<EOF >"$file"
<!-- BEGIN MAIN CONTENT -->/
<h2>Page title</h2>
<p>Page content</p>
<!-- END MAIN CONTENT -->/
EOF

	_log_info "Created $file, remember to:"
	_log_info "- run \`./build.sh\` before publishing"
	_log_info "- add the page to index.html"

}

usage() {
	cat <<EOF
Usage: $0 <command> [options]

Commands:
  new <category> <pagename>  Create a new item with the specified name in the
    specified category

Options:
  -h, --help     output usage information
  -v, --version  output the version number
EOF
}

if [ "$#" -eq 0 ]; then
	usage
	exit 1
fi

cmd="$1"
shift

case "$cmd" in
new)
	if [ "$#" -ne 2 ]; then
		usage
		exit 1
	fi
	new "$@"
	;;
--help)
	usage
	exit 0
	;;
esac
