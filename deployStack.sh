#!/bin/bash

# Configuration
STACK_NAME="eventbridge-demo"
TEMPLATE_FILE="eventbridge-stack.yaml"
REGION="us-east-1"  # Change this to your desired region

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if command was successful
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: $1${NC}"
        exit 1
    fi
}

# Function to display status message
status_message() {
    echo -e "${YELLOW}$1...${NC}"
}

# Check if AWS CLI is installed
status_message "Checking AWS CLI installation"
if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Validate template
status_message "Validating CloudFormation template"
aws cloudformation validate-template \
    --template-body file://${TEMPLATE_FILE} \
    --region ${REGION}

check_error "Template validation failed"
echo -e "${GREEN}Template validation successful${NC}"

# Check if stack exists
status_message "Checking if stack exists"
STACK_EXISTS=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${REGION} 2>&1)
STACK_STATUS=$?

if [ $STACK_STATUS -eq 0 ]; then
    # Update existing stack
    status_message "Updating existing stack: ${STACK_NAME}"
    UPDATE_OUTPUT=$(aws cloudformation update-stack \
        --stack-name ${STACK_NAME} \
        --template-body file://${TEMPLATE_FILE} \
        --capabilities CAPABILITY_IAM \
        --region ${REGION} 2>&1)
    UPDATE_STATUS=$?

    if [ $UPDATE_STATUS -eq 0 ]; then
        status_message "Waiting for stack update to complete"
        aws cloudformation wait stack-update-complete \
            --stack-name ${STACK_NAME} \
            --region ${REGION}
        check_error "Stack update failed"
        echo -e "${GREEN}Stack update completed successfully${NC}"
    else
        if echo "$UPDATE_OUTPUT" | grep -q "No updates are to be performed"; then
            echo -e "${GREEN}No updates are necessary${NC}"
        else
            echo -e "${RED}Error: Stack update failed - $UPDATE_OUTPUT${NC}"
            exit 1
        fi
    fi
else
    # Create new stack
    status_message "Creating new stack: ${STACK_NAME}"
    aws cloudformation create-stack \
        --stack-name ${STACK_NAME} \
        --template-body file://${TEMPLATE_FILE} \
        --capabilities CAPABILITY_IAM \
        --region ${REGION}

    check_error "Stack creation failed"

    status_message "Waiting for stack creation to complete"
    aws cloudformation wait stack-create-complete \
        --stack-name ${STACK_NAME} \
        --region ${REGION}

    check_error "Stack creation failed during wait"
    echo -e "${GREEN}Stack creation completed successfully${NC}"
fi

# Display stack outputs
status_message "Retrieving stack outputs"
aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${REGION} \
    --query 'Stacks[0].Outputs' \
    --output table

echo -e "${GREEN}Deployment script completed successfully${NC}"
