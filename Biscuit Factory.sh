#!/bin/sh
printf '\033c\033]0;%s\a' Biscuit Factory
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Biscuit Factory.x86_64" "$@"
