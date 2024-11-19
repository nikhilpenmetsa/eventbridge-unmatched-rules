#!/bin/bash

# Configuration
EVENT_BUS_NAME="order-processing-bus"
REGION="us-east-1"  # Change this to your desired region
EVENTS_DIR="./events"  # Directory containing JSON event files

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display status message
status_message() {
    echo -e "${YELLOW}$1...${NC}"
}

# Function to check if command was successful
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: $1${NC}"
        return 1
    fi
    return 0
}

# Check if AWS CLI is installed
status_message "Checking AWS CLI installation"
if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if jq is installed
status_message "Checking jq installation"
if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq is not installed. Please install it first:${NC}"
    echo -e "${YELLOW}For Windows (Git Bash):${NC} curl -L -o /usr/bin/jq.exe https://github.com/stedolan/jq/releases/latest/download/jq-win64.exe"
    exit 1
fi

# Check if events directory exists
if [ ! -d "$EVENTS_DIR" ]; then
    echo -e "${RED}Events directory '$EVENTS_DIR' not found${NC}"
    exit 1
fi

# Create a temporary directory that works in Git Bash
TEMP_DIR="./temp_events"
mkdir -p "$TEMP_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Function to format event for EventBridge
format_event() {
    local event_file=$1
    local temp_file=$2
    
    # Convert the event to EventBridge entry format
    jq -c '{
        EventBusName: $busName,
        Time: .time,
        Source: .source,
        DetailType: ."detail-type",
        Detail: (.detail | tostring)
    }' --arg busName "$EVENT_BUS_NAME" "$event_file" > "$temp_file"
}

# Function to send event and check result
send_event() {
    local event_file=$1
    local file_name=$(basename "$event_file")
    local temp_file="$TEMP_DIR/${file_name}.tmp"
    
    echo -e "\n${BLUE}Processing event file: $file_name${NC}"
    echo -e "${YELLOW}Original event content:${NC}"
    cat "$event_file"
    echo

    # Format the event for EventBridge
    format_event "$event_file" "$temp_file"
    
    echo -e "${YELLOW}Formatted event content:${NC}"
    cat "$temp_file"
    echo

    echo -e "${YELLOW}Sending event to EventBridge...${NC}"
    aws events put-events --entries "[$(<"$temp_file")]" --region $REGION
    
    if check_error "Failed to send event"; then
        echo -e "${GREEN}Successfully sent event${NC}"
    fi
}

# Function to check SQS queue for messages
check_queue() {
    local queue_url=$1
    local queue_name=$2
    
    echo -e "\n${YELLOW}Checking $queue_name for messages...${NC}"
    aws sqs receive-message \
        --queue-url "$queue_url" \
        --region $REGION \
        --max-number-of-messages 10 \
        --wait-time-seconds 5 \
        --output json
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully checked $queue_name${NC}"
    else
        echo -e "${RED}Failed to check $queue_name${NC}"
    fi
}

# Get queue URLs from CloudFormation stack outputs
status_message "Getting queue URLs from stack outputs"
STACK_NAME="eventbridge-demo"

PROCESS_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`ProcessOrderQueueUrl`].OutputValue' \
    --output text \
    --region $REGION)

CATCH_ALL_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`CatchAllQueueUrl`].OutputValue' \
    --output text \
    --region $REGION)

# Main execution
echo -e "\n${YELLOW}Starting event processing sequence${NC}"
echo -e "${YELLOW}Looking for event files in: $EVENTS_DIR${NC}"

# Count JSON files
json_files=($(find "$EVENTS_DIR" -type f -name "*.json"))
file_count=${#json_files[@]}

if [ $file_count -eq 0 ]; then
    echo -e "${RED}No JSON files found in $EVENTS_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}Found $file_count JSON event files${NC}"

# Process each event file
for event_file in "${json_files[@]}"; do
    send_event "$event_file"
    sleep 2  # Brief pause between events
    
    # Check both queues after each event
    check_queue "$PROCESS_QUEUE_URL" "Process Order Queue"
    check_queue "$CATCH_ALL_QUEUE_URL" "Catch All Queue"
    
    echo -e "${BLUE}----------------------------------------${NC}"
done

echo -e "\n${GREEN}Test sequence completed${NC}"
echo -e "${YELLOW}Note: If you don't see messages in the queues, they might have been processed already or there might be a delay${NC}"
echo -e "${YELLOW}You can also check the CloudWatch logs and metrics for more details${NC}"
