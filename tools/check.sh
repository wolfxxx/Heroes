#!/bin/sh
# Re-import (registers new class_names) then compile-check all scripts. Prints only errors + summary.
G=/c/Users/PC/Documents/Godot/Godot_v4.7.2-stable_win64_console.exe
cd "$(dirname "$0")/.."
timeout 180 $G --headless --path . --import >/dev/null 2>&1
timeout 120 $G --headless --path . res://tools/check_scripts.tscn 2>&1 | grep -E -A1 "SCRIPT ERROR|FAILED|CHECK DONE|Parse Error" | grep -v "GDScript backtrace" | grep -v "^--$"
