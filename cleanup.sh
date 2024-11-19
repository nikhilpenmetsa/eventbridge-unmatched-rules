#!/bin/bash

# Configuration
STACK_NAME="eventbridge-demo"
REGION="us-east-1"

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

# Function to check if stack exists
check_stack() {
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION &>/dev/null
    
    return $?
}

# Check if stack exists
status_message "Checking if stack '$STACK_NAME' exists"
if ! check_stack; then
    echo -e "${RED}Stack '$STACK_NAME' does not exist in region '$REGION'${NC}"
    exit 1
fi

# Get current stack status
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].StackStatus' \
    --output text \
    --region $REGION)

echo -e "${BLUE}Current stack status: $STACK_STATUS${NC}"

# Check if stack is already being deleted
if [[ $STACK_STATUS == *"DELETE_IN_PROGRESS"* ]]; then
    echo -e "${YELLOW}Stack deletion is already in progress${NC}"
    exit 0
fi

if [[ $STACK_STATUS == *"DELETE_FAILED"* ]]; then
    echo -e "${RED}Previous deletion failed. You may need to remove some resources manually${NC}"
    exit 1
fi

# Confirm deletion
echo -e "${RED}WARNING: This will delete the entire stack '$STACK_NAME' and all its resources${NC}"
read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Stack deletion cancelled${NC}"
    exit 0
fi

# Delete the stack
status_message "Deleting stack '$STACK_NAME'"
aws cloudformation delete-stack \
    --stack-name $STACK_NAME \
    --region $REGION

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to initiate stack deletion${NC}"
    exit 1
fi

echo -e "${GREEN}Stack deletion initiated${NC}"

# Wait for stack deletion to complete
echo -e "${YELLOW}Waiting for stack deletion to complete...${NC}"
if aws cloudformation wait stack-delete-complete \
    --stack-name $STACK_NAME \
    --region $REGION; then
    echo -e "${GREEN}Stack '$STACK_NAME' has been successfully deleted${NC}"
else
    echo -e "${RED}Stack deletion failed or timed out${NC}"
    echo -e "${YELLOW}Check the AWS Console for more details${NC}"
    exit 1
fi
