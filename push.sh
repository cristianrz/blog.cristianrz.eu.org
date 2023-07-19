#!/bin/sh

set -eu

_github(){
	git push origin2
}

_sdf(){
	git push sdf
}

_ctrl(){
	:
}

_github
_sdf
_ctrl
