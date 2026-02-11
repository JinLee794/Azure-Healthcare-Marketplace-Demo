SHELL := /bin/bash

LOG_DIR := .local-logs

.PHONY: local-start local-stop local-logs local-start-npi local-start-icd10 local-start-cms local-start-fhir local-start-pubmed local-start-clinical setup-mcp-config eval-contracts eval-latency-local eval-native-local eval-all

local-start: local-start-npi local-start-icd10 local-start-cms local-start-fhir local-start-pubmed local-start-clinical
	@echo "All MCP servers started. Logs: $(LOG_DIR)/<server>.log"

local-start-npi:
	@bash -c 'mkdir -p "$(LOG_DIR)"; ./scripts/local-test.sh npi-lookup 7071 > "$(LOG_DIR)/npi-lookup.log" 2>&1 & echo $$! > "$(LOG_DIR)/npi-lookup.pid"'

local-start-icd10:
	@bash -c 'mkdir -p "$(LOG_DIR)"; ./scripts/local-test.sh icd10-validation 7072 > "$(LOG_DIR)/icd10-validation.log" 2>&1 & echo $$! > "$(LOG_DIR)/icd10-validation.pid"'

local-start-cms:
	@bash -c 'mkdir -p "$(LOG_DIR)"; ./scripts/local-test.sh cms-coverage 7073 > "$(LOG_DIR)/cms-coverage.log" 2>&1 & echo $$! > "$(LOG_DIR)/cms-coverage.pid"'

local-start-fhir:
	@bash -c 'mkdir -p "$(LOG_DIR)"; ./scripts/local-test.sh fhir-operations 7074 > "$(LOG_DIR)/fhir-operations.log" 2>&1 & echo $$! > "$(LOG_DIR)/fhir-operations.pid"'

local-start-pubmed:
	@bash -c 'mkdir -p "$(LOG_DIR)"; ./scripts/local-test.sh pubmed 7075 > "$(LOG_DIR)/pubmed.log" 2>&1 & echo $$! > "$(LOG_DIR)/pubmed.pid"'

local-start-clinical:
	@bash -c 'mkdir -p "$(LOG_DIR)"; ./scripts/local-test.sh clinical-trials 7076 > "$(LOG_DIR)/clinical-trials.log" 2>&1 & echo $$! > "$(LOG_DIR)/clinical-trials.pid"'

local-stop:
	@bash -c 'if [ -d "$(LOG_DIR)" ]; then \
	  for pidfile in "$(LOG_DIR)"/*.pid; do \
	    if [ -f "$$pidfile" ]; then \
	      name=$$(basename "$$pidfile" .pid); \
	      pid=$$(cat "$$pidfile"); \
	      if kill -0 $$pid >/dev/null 2>&1; then \
	        echo "Stopping $$name (pid $$pid)"; \
	        kill $$pid; \
	      else \
	        echo "Process not running for $$name (pid $$pid)"; \
	      fi; \
	      rm -f "$$pidfile"; \
	    fi; \
	  done; \
	else \
	  echo "No $(LOG_DIR) directory found. Nothing to stop."; \
	fi; \
	for port in 7071 7072 7073 7074 7075 7076; do \
	  pids=$$(lsof -ti tcp:$$port 2>/dev/null || true); \
	  if [ -n "$$pids" ]; then \
	    echo "Stopping listener(s) on port $$port: $$pids"; \
	    kill $$pids 2>/dev/null || true; \
	  fi; \
	done'

local-logs:
	@bash -c 'ls -1 "$(LOG_DIR)"/*.log 2>/dev/null || echo "No logs found in $(LOG_DIR)"'

# Generate .vscode/mcp.json from template using azd environment values
setup-mcp-config:
	@bash ./scripts/postdeploy.sh

eval-contracts:
	@python3 ./scripts/eval_contracts.py

eval-latency-local:
	@python3 ./scripts/eval_latency.py --config ./scripts/evals/mcp-latency.local.json

eval-native-local:
	@src/agents/.venv/bin/python ./scripts/eval_native_agent_framework.py --config ./scripts/evals/native-agent-framework.local.json

eval-all: eval-contracts eval-latency-local eval-native-local
