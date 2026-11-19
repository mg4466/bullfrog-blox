# Godot's CLI is the build system here: there is no compile step, only an
# import pass and the game itself.
GODOT ?= godot
PROJECT := --path .

.PHONY: import run test screenshots clean

# Godot resolves class_name types via a cache written by the editor or this
# import pass. A fresh clone needs it once; every other target depends on it.
import:
	$(GODOT) --headless --import $(PROJECT)

run: import
	$(GODOT) $(PROJECT)

test: import
	$(GODOT) --headless $(PROJECT) --script res://tests/test_logic.gd
	$(GODOT) --headless $(PROJECT) res://tests/controls.tscn
	$(GODOT) --headless $(PROJECT) res://tests/playthrough.tscn --fixed-fps 60 --quit-after 9000

screenshots: import
	$(GODOT) $(PROJECT) res://tests/capture.tscn

clean:
	rm -rf .godot
