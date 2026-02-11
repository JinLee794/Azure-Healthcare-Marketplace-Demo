SHELL := /bin/bash

LOG_DIR := .local-logs

.PHONY: local-start local-stop local-logs local-start-npi local-start-icd10 local-start-cms local-start-fhir local-start-pubmed local-start-clinical setup-mcp-config eval-contracts eval-latency-local eval-native-local eval-all

define START_SERVER
	@bash -c 'mkdir -p "$(LOG_DIR)"; \
	  pids=$$(lsof -ti tcp:$(3) -sTCP:LISTEN 2>/dev/null || true); \
	  if [ -n "$$pids" ]; then \
	    echo "Port $(3) already has listener(s): $$pids. Restarting $(1)..."; \
	    kill $$pids 2>/dev/null || true; \
	    for _ in $$(seq 1 10); do \
	      if ! lsof -ti tcp:$(3) -sTCP:LISTEN >/dev/null 2>&1; then break; fi; \
	      sleep 0.1; \
	    done; \
	    pids=$$(lsof -ti tcp:$(3) -sTCP:LISTEN 2>/dev/null || true); \
	    if [ -n "$$pids" ]; then \
	      echo "Port $(3) still busy after SIGTERM. Force stopping: $$pids"; \
	      kill -9 $$pids 2>/dev/null || true; \
	    fi; \
	    for _ in $$(seq 1 10); do \
	      if ! lsof -ti tcp:$(3) -sTCP:LISTEN >/dev/null 2>&1; then break; fi; \
	      sleep 0.1; \
	    done; \
	  fi; \
	  if lsof -ti tcp:$(3) -sTCP:LISTEN >/dev/null 2>&1; then \
	    echo "ERROR: Port $(3) is still in use. Could not start $(1)."; \
	    exit 1; \
	  fi; \
	  ./scripts/local-test.sh $(1) $(3) > "$(LOG_DIR)/$(2).log" 2>&1 & echo $$! > "$(LOG_DIR)/$(2).pid"'
endef

local-start: local-stop local-start-npi local-start-icd10 local-start-cms local-start-fhir local-start-pubmed local-start-clinical
	@echo "All MCP servers started. Logs: $(LOG_DIR)/<server>.log"

local-start-npi:
	$(call START_SERVER,npi-lookup,npi-lookup,7071)

local-start-icd10:
	$(call START_SERVER,icd10-validation,icd10-validation,7072)

local-start-cms:
	$(call START_SERVER,cms-coverage,cms-coverage,7073)

local-start-fhir:
	$(call START_SERVER,fhir-operations,fhir-operations,7074)

local-start-pubmed:
	$(call START_SERVER,pubmed,pubmed,7075)

local-start-clinical:
	$(call START_SERVER,clinical-trials,clinical-trials,7076)

local-stop:
	@bash -c 'if [ -d "$(LOG_DIR)" ]; then \
	  for pidfile in "$(LOG_DIR)"/*.pid; do \
	    if [ -f "$$pidfile" ]; then \
	      name=$$(basename "$$pidfile" .pid); \
	      pid=$$(cat "$$pidfile"); \
	      if kill -0 $$pid >/dev/null 2>&1; then \
	        echo "Stopping $$name (pid $$pid)"; \
	        kill $$pid; \
	        sleep 0.2; \
	        if kill -0 $$pid >/dev/null 2>&1; then \
	          echo "Force stopping $$name (pid $$pid)"; \
	          kill -9 $$pid 2>/dev/null || true; \
	        fi; \
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
	    sleep 0.2; \
	    pids=$$(lsof -ti tcp:$$port 2>/dev/null || true); \
	    if [ -n "$$pids" ]; then \
	      echo "Force stopping listener(s) on port $$port: $$pids"; \
	      kill -9 $$pids 2>/dev/null || true; \
	    fi; \
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
	@src/agents/.venv/bin/python ./scripts/eval_native_agent_framework.py --config ./scripts/evals/native-agent-framework.local.json --wait-for-servers-seconds 30

eval-all: eval-contracts eval-latency-local eval-native-local
