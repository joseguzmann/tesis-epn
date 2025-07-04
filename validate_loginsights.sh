#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== LOGINSIGHTS VALIDATION SCRIPT ===${NC}"
echo "Timestamp: $(date)"
echo

# Variables
TOTAL_TESTS=0
PASSED_TESTS=0
WARNINGS=0

# Helper functions
check_pass() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "${GREEN}✓ $1${NC}"
}

check_fail() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${RED}✗ $1${NC}"
}

check_warn() {
    WARNINGS=$((WARNINGS + 1))
    echo -e "${YELLOW}⚠ $1${NC}"
}

# 1. Check container status
echo -e "${BLUE}1. CHECKING CONTAINER STATUS${NC}"
for container in loginsights moodle-app moodle-db ollama; do
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        check_pass "$container is running"
    else
        check_fail "$container is NOT running"
    fi
done
echo

# 2. Check report generation
echo -e "${BLUE}2. CHECKING REPORT GENERATION${NC}"
REPORT_COUNT=$(docker exec loginsights find /reports -name "summary_*.txt" -type f 2>/dev/null | wc -l)
if [ "$REPORT_COUNT" -gt 0 ]; then
    check_pass "Found $REPORT_COUNT reports"
else
    check_fail "No reports found"
fi

# Check if reports are being generated for all containers
for container in moodle-app moodle-db ollama; do
    CONTAINER_REPORTS=$(docker exec loginsights find /reports -name "summary_${container}_*.txt" -type f 2>/dev/null | wc -l)
    if [ "$CONTAINER_REPORTS" -gt 0 ]; then
        check_pass "Found $CONTAINER_REPORTS reports for $container"
    else
        check_fail "No reports found for $container"
    fi
done
echo

# 3. Check report freshness
echo -e "${BLUE}3. CHECKING REPORT FRESHNESS${NC}"
LATEST_REPORT=$(docker exec loginsights find /reports -name "summary_*.txt" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | awk '{print $2}')
if [ -n "$LATEST_REPORT" ]; then
    REPORT_AGE=$(docker exec loginsights bash -c "echo \$((\$(date +%s) - \$(stat -c %Y '$LATEST_REPORT')))")
    if [ "$REPORT_AGE" -lt 180 ]; then
        check_pass "Latest report is $REPORT_AGE seconds old (fresh)"
    elif [ "$REPORT_AGE" -lt 300 ]; then
        check_warn "Latest report is $REPORT_AGE seconds old (slightly old)"
    else
        check_fail "Latest report is $REPORT_AGE seconds old (stale)"
    fi
fi
echo

# 4. Check report content quality
echo -e "${BLUE}4. CHECKING REPORT CONTENT QUALITY${NC}"
# Get the most recent report for each container
for container in moodle-app moodle-db ollama; do
    LATEST=$(docker exec loginsights find /reports -name "summary_${container}_*.txt" -type f 2>/dev/null | sort | tail -1)
    if [ -n "$LATEST" ]; then
        echo -e "\n${YELLOW}Checking $container report: $(basename $LATEST)${NC}"
        
        # Check file size
        SIZE=$(docker exec loginsights stat -c%s "$LATEST" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 1000 ]; then
            check_pass "Report size is adequate ($SIZE bytes)"
        else
            check_warn "Report might be too small ($SIZE bytes)"
        fi
        
        # Check for key sections
        if docker exec loginsights grep -q "=== ANÁLISIS ===" "$LATEST" 2>/dev/null; then
            check_pass "Contains analysis section"
        else
            check_fail "Missing analysis section"
        fi
        
        if docker exec loginsights grep -q "=== LOGS ORIGINALES" "$LATEST" 2>/dev/null; then
            check_pass "Contains original logs section"
        else
            check_fail "Missing original logs section"
        fi
        
        # Check if analysis was successful or timed out
        if docker exec loginsights grep -q "timeout" "$LATEST" 2>/dev/null; then
            check_warn "Report indicates timeout occurred"
        fi
        
        # Check for actual log content - fixed pattern
        LOG_LINES=$(docker exec loginsights grep -E "^[0-9]{4}-|^[A-Za-z]{3} [0-9]{2}" "$LATEST" 2>/dev/null | wc -l || echo 0)
        if [ "$LOG_LINES" -gt 10 ]; then
            check_pass "Contains $LOG_LINES log lines"
        elif [ "$LOG_LINES" -gt 0 ]; then
            check_warn "Only contains $LOG_LINES log lines"
        else
            check_fail "No log lines found"
        fi
    fi
done
echo

# 5. Check Ollama connectivity
echo -e "${BLUE}5. CHECKING OLLAMA CONNECTIVITY${NC}"
if docker exec loginsights curl -s http://ollama:11434/api/tags >/dev/null 2>&1; then
    check_pass "Ollama API is accessible"
    
    MODEL_CHECK=$(docker exec loginsights curl -s http://ollama:11434/api/tags | grep -o '""' || echo "")
    if [ -n "$MODEL_CHECK" ]; then
        check_pass "tinyllama:1.1b model is available"
    else
        check_fail "tinyllama:1.1b model not found"
    fi
else
    check_fail "Cannot connect to Ollama API"
fi
echo

# 6. Check Docker socket permissions
echo -e "${BLUE}6. CHECKING DOCKER PERMISSIONS${NC}"
SOCKET_PERMS=$(docker exec loginsights stat -c "%a" /var/run/docker.sock 2>/dev/null || echo "")
if [ -n "$SOCKET_PERMS" ]; then
    check_pass "Docker socket is accessible"
    if [ "$SOCKET_PERMS" = "660" ] || [ "$SOCKET_PERMS" = "666" ]; then
        check_pass "Docker socket has correct permissions ($SOCKET_PERMS)"
    else
        check_warn "Docker socket has unusual permissions ($SOCKET_PERMS)"
    fi
else
    check_fail "Cannot access Docker socket"
fi
echo

# 7. Check for errors in LogInsights logs
echo -e "${BLUE}7. CHECKING FOR ERRORS${NC}"
ERROR_COUNT=$(docker logs loginsights 2>&1 | grep -iE "(error|exception|traceback)" | grep -v "NewConnectionError" | wc -l)
if [ "$ERROR_COUNT" -eq 0 ]; then
    check_pass "No errors found in LogInsights logs"
else
    check_warn "Found $ERROR_COUNT error messages in logs"
    echo "Recent errors:"
    docker logs loginsights 2>&1 | grep -iE "(error|exception|traceback)" | grep -v "NewConnectionError" | tail -5
fi
echo

# 8. Performance check
echo -e "${BLUE}8. CHECKING PERFORMANCE${NC}"
# Check memory usage
MEMORY_USAGE=$(docker stats --no-stream --format "{{.MemUsage}}" loginsights | awk '{print $1}')
echo "Memory usage: $MEMORY_USAGE"

# Check if reports are generated on schedule
REPORT_TIMES=$(docker exec loginsights find /reports -name "summary_*.txt" -type f -printf '%TY%Tm%Td_%TH%TM%TS\n' 2>/dev/null | sort | tail -5)
if [ -n "$REPORT_TIMES" ]; then
    check_pass "Recent report generation times:"
    echo "$REPORT_TIMES" | while read -r time; do
        echo "  - $time"
    done
fi
echo

# 9. Display sample analysis
echo -e "${BLUE}9. SAMPLE ANALYSIS OUTPUT${NC}"
SAMPLE_REPORT=$(docker exec loginsights find /reports -name "summary_*.txt" -type f 2>/dev/null | sort | tail -1)
if [ -n "$SAMPLE_REPORT" ]; then
    echo -e "${YELLOW}From: $(basename $SAMPLE_REPORT)${NC}"
    echo "---"
    docker exec loginsights bash -c "sed -n '/=== ANÁLISIS ===/,/=== LOGS ORIGINALES/{/=== LOGS ORIGINALES/!p}' '$SAMPLE_REPORT' | head -20" 2>/dev/null || echo "Could not extract analysis"
    echo "---"
fi
echo

# Final summary
echo -e "${BLUE}=== VALIDATION SUMMARY ===${NC}"
echo -e "Total tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$((TOTAL_TESTS - PASSED_TESTS))${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"

SUCCESS
