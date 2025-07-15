#!/bin/bash

# Script to query chatbot usage logs and analytics
set -e

echo "🔍 Resume Bot Analytics Query Tool"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Get log group name from CloudFormation outputs
LOG_GROUP=$(aws cloudformation describe-stacks --stack-name ResumeBotBackendStack --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' --output text)

if [ -z "$LOG_GROUP" ]; then
    print_error "Could not find log group name from CloudFormation outputs"
    print_warning "Make sure the backend stack has been deployed successfully"
    exit 1
fi

print_status "Using log group: $LOG_GROUP"

# Function to run CloudWatch Logs Insights query
run_query() {
    local query_name="$1"
    local query="$2"
    local start_time="$3"
    
    print_header "$query_name"
    
    # Start the query
    query_id=$(aws logs start-query \
        --log-group-name "$LOG_GROUP" \
        --start-time "$start_time" \
        --end-time $(date +%s) \
        --query-string "$query" \
        --query 'queryId' \
        --output text)
    
    if [ -z "$query_id" ]; then
        print_error "Failed to start query: $query_name"
        return 1
    fi
    
    print_status "Query started with ID: $query_id"
    print_status "Waiting for results..."
    
    # Wait for query to complete
    while true; do
        status=$(aws logs get-query-results --query-id "$query_id" --query 'status' --output text)
        if [ "$status" = "Complete" ]; then
            break
        elif [ "$status" = "Failed" ]; then
            print_error "Query failed: $query_name"
            return 1
        fi
        sleep 2
    done
    
    # Get and display results
    aws logs get-query-results --query-id "$query_id" --query 'results' --output table
    echo ""
}

# Default to last 24 hours
START_TIME=$(($(date +%s) - 86400))

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --hours)
            HOURS="$2"
            START_TIME=$(($(date +%s) - $HOURS * 3600))
            shift 2
            ;;
        --days)
            DAYS="$2"
            START_TIME=$(($(date +%s) - $DAYS * 86400))
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--hours N] [--days N]"
            echo "  --hours N    Show data for last N hours (default: 24)"
            echo "  --days N     Show data for last N days"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_status "Analyzing chatbot usage for the last $(( ($(date +%s) - START_TIME) / 3600 )) hours"
echo ""

# Query 1: Total interactions count
run_query "Total Chatbot Interactions" \
'fields @timestamp
| filter @message like /CHATBOT_INTERACTION/
| stats count() as total_interactions' \
"$START_TIME"

# Query 2: Top questions asked
run_query "Top 10 Questions Asked" \
'fields @timestamp, question
| filter @message like /chatbot_interactions/
| parse @message /.*"question": ?"([^"]*)".*/ as question
| stats count() as frequency by question
| sort frequency desc
| limit 10' \
"$START_TIME"

# Query 3: Average response times
run_query "Response Time Statistics" \
'fields @timestamp, response_time_ms
| filter @message like /chatbot_interactions/
| parse @message /.*"response_time_ms": ?([0-9]+).*/ as response_time_ms
| stats avg(response_time_ms) as avg_response_time, min(response_time_ms) as min_response_time, max(response_time_ms) as max_response_time, count() as total_requests' \
"$START_TIME"

# Query 4: Success rate
run_query "Success Rate Analysis" \
'fields @timestamp, success
| filter @message like /chatbot_interactions/
| parse @message /.*"success": ?(true|false).*/ as success
| stats count() as total by success' \
"$START_TIME"

# Query 5: Errors if any
run_query "Recent Errors" \
'fields @timestamp, error, question
| filter @message like /chatbot_interactions/
| parse @message /.*"success": ?false.*"error": ?"([^"]*)".*/ as error
| parse @message /.*"question": ?"([^"]*)".*/ as question
| filter ispresent(error)
| sort @timestamp desc
| limit 10' \
"$START_TIME"

# Query 6: Usage patterns by hour
run_query "Usage Patterns by Hour" \
'fields @timestamp
| filter @message like /CHATBOT_INTERACTION/
| stats count() as interactions by bin(5m)
| sort @timestamp desc
| limit 20' \
"$START_TIME"

print_header "Analytics Summary"
print_status "Dashboard URL available in CloudFormation outputs"
print_status "Log group: $LOG_GROUP"
print_status "Time range: Last $(( ($(date +%s) - START_TIME) / 3600 )) hours"

echo ""
print_status "To view real-time logs, run:"
echo "aws logs tail $LOG_GROUP --follow"
echo ""
print_status "To view the CloudWatch dashboard:"
aws cloudformation describe-stacks --stack-name ResumeBotBackendStack --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' --output text