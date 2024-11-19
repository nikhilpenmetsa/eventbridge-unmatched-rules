#!/bin/bash

# Configuration
REGION="us-east-1"
STACK_NAME="eventbridge-demo"

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

# Function to purge a queue
purge_queue() {
    local queue_url=$1
    local queue_name=$2
    
    echo -e "\n${YELLOW}Purging $queue_name...${NC}"
    aws sqs purge-queue \
        --queue-url "$queue_url" \
        --region $REGION
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully purged $queue_name${NC}"
    else
        echo -e "${RED}Failed to purge $queue_name${NC}"
    fi
}

# Get queue URLs from CloudFormation stack outputs
status_message "Getting queue URLs from stack outputs"

# Get Process Order Queue URL
PROCESS_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`ProcessOrderQueueUrl`].OutputValue' \
    --output text \
    --region $REGION)

if [[ -z "$PROCESS_QUEUE_URL" || "$PROCESS_QUEUE_URL" == "None" ]]; then
    echo -e "${RED}Failed to get Process Order Queue URL from stack outputs${NC}"
    exit 1
fi

# Get Inverse Match Queue URL
INVERSE_MATCH_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`InverseMatchQueueUrl`].OutputValue' \
    --output text \
    --region $REGION)

if [[ -z "$INVERSE_MATCH_QUEUE_URL" || "$INVERSE_MATCH_QUEUE_URL" == "None" ]]; then
    echo -e "${RED}Failed to get Process Order Queue URL from stack outputs${NC}"
    exit 1
fi

# Get Catch All Queue URL
CATCH_ALL_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`CatchAllQueueUrl`].OutputValue' \
    --output text \
    --region $REGION)

if [[ -z "$CATCH_ALL_QUEUE_URL" || "$CATCH_ALL_QUEUE_URL" == "None" ]]; then
    echo -e "${RED}Failed to get Catch All Queue URL from stack outputs${NC}"
    exit 1
fi


# Display retrieved queue URLs
echo -e "${GREEN}Retrieved queue URLs:${NC}"
echo -e "${BLUE}Process Order Queue:${NC} $PROCESS_QUEUE_URL"
echo -e "${BLUE}Unmatched Events Queue:${NC} $UNMATCHED_QUEUE_URL"

# Purge both queues
purge_queue "$PROCESS_QUEUE_URL" "Process Order Queue"
purge_queue "$INVERSE_MATCH_QUEUE_URL" "Inverse Match Queue"
purge_queue "$CATCH_ALL_QUEUE_URL" "Catch All Queue"


echo -e "\n${GREEN}Queue purge operations completed${NC}"
echo -e "${YELLOW}Note: It may take up to 60 seconds for the purge to complete${NC}"
