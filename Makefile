.PHONY: devlog-update devlog-pr-body doc-automation-test

devlog-update: ## Update generated weekly devlog blocks from the previous calendar week
	@PYTHONPATH=Scripts python3 -m doc_automation.devlog \
		--markdown docs/guides/devlog.md \
		--html docs/devlog.html \
		--repo-url https://github.com/dfakkeldy/MacroMark

devlog-pr-body: ## Generate the review checklist and AI-assisted draft for the weekly devlog PR
	@PYTHONPATH=Scripts python3 -m doc_automation.curate_devlog \
		--project-name MacroMark \
		--markdown docs/guides/devlog.md \
		--html docs/devlog.html \
		--repo-url https://github.com/dfakkeldy/MacroMark \
		--extra-guidance "MacroMark is an Apple Watch capture tool for Markdown daily notes. Avoid claiming public launch status, download counts, revenue, or active users unless present in the factual digest." \
		--extra-checklist "Verify any Apple Watch, Markdown automation, beta, or App Store claims against the linked commits before posting." \
		--out "$${DEVLOG_PR_BODY:-devlog-pr-body.md}"

doc-automation-test: ## Run the doc-automation Python unit tests
	@PYTHONPATH=Scripts python3 -m unittest discover -s Scripts/doc_automation/tests -t Scripts -v
