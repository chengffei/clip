check:
	bash scripts/compile-check.sh

verify:
	bash scripts/rebuild-and-open.sh

release-check:
	CONFIG=release UNIVERSAL=1 bash scripts/bundle.sh
