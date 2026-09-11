PYTHON ?= python3
QT6_BIN ?= /usr/lib/qt6/bin

.PHONY: test test-safety test-offscreen test-native test-full smoke lint bench render preview

# SAFE DEFAULT: pure Python guard/static tests only, NOT regression acceptance.
test: test-safety

test-safety:
	@printf '%s\n' 'SAFE DEFAULT: pure-Python guard checks only; NOT full acceptance.'
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m unittest discover -s tests -p 'test_spawn_safety.py' -v

# Real owned subprocesses + Qt offscreen; does not prove native behavior.
test-offscreen:
	$(PYTHON) tests/run_tests.py offscreen

# Fresh scoped consent required; hidden-backend is NOT visible/action consent.
test-native:
	$(PYTHON) tests/run_tests.py native

# Refuses before discovery without native consent; skips are NOT acceptance.
test-full:
	$(PYTHON) tests/run_tests.py full

smoke:
	$(PYTHON) tests/smoke.py

lint:
	$(QT6_BIN)/qmllint -I /usr/lib/qt6/qml Dock.qml DockSurface.qml shell.qml ui/*.qml services/*.qml

bench:
	$(PYTHON) tests/run_tests.py bench

render:
	$(PYTHON) tests/run_tests.py render

# Daily-use standalone dock; no host plugin changes.
# Set OMADOCKED_SCREENS=all or a comma-separated output list.
preview:
	OMADOCKED_VISIBLE=1 $(PYTHON) tools/preview.py -- -n -p "$(CURDIR)/shell.qml"
