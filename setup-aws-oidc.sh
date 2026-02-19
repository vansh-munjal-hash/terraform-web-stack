#!/bin/bash
set -e

echo "================================================"
echo "AWS OIDC Setup for Terraform Stacks"
echo "================================================"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Prompt for required information
read -p "Enter your AWS Account ID: " AWS_ACCOUNT_ID
read -p "Enter your HCP Terraform Organization Name: " TFC_ORG_NAME

if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$TFC_ORG_NAME" ]; then
    echo "Error: AWS Account ID and Organization Name are required."
    exit 1
fi

echo ""
echo "Step 1: Creating OIDC Provider in AWS..."
echo "----------------------------------------------"

# Check if OIDC provider already exists
OIDC_EXISTS=$(aws iam list-open-id-connect-providers --output text | grep "app.terraform.io" || echo "")

if [ -n "$OIDC_EXISTS" ]; then
    echo "OIDC provider already exists, skipping creation."
else
    aws iam create-open-id-connect-provider \
        --url "https://app.terraform.io" \
        --client-id-list "aws.workload.identity" \
        --thumbprint-list "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"

    echo "✓ OIDC provider created successfully"
fi

echo ""
echo "Step 2: Creating IAM Trust Policy..."
echo "----------------------------------------------"

# Create trust policy JSON
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/app.terraform.io"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:${TFC_ORG_NAME}:project:*:stack:*:deployment:*"
        }
      }
    }
  ]
}
EOF

echo "✓ Trust policy created: trust-policy.json"

echo ""
echo "Step 3: Creating IAM Role..."
echo "----------------------------------------------"

# Check if role already exists
ROLE_EXISTS=$(aws iam get-role --role-name hcp-terraform-stacks-role 2>/dev/null || echo "")

if [ -n "$ROLE_EXISTS" ]; then
    echo "IAM role already exists, updating trust policy..."
    aws iam update-assume-role-policy \
        --role-name hcp-terraform-stacks-role \
        --policy-document file://trust-policy.json
else
    aws iam create-role \
        --role-name hcp-terraform-stacks-role \
        --assume-role-policy-document file://trust-policy.json \
        --description "Role for HCP Terraform Stacks with OIDC authentication"

    echo "✓ IAM role created: hcp-terraform-stacks-role"
fi

echo ""
echo "Step 4: Attaching IAM Policies..."
echo "----------------------------------------------"

# Attach EC2 Full Access (you may want to restrict this in production)
aws iam attach-role-policy \
    --role-name hcp-terraform-stacks-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

echo "✓ Attached AmazonEC2FullAccess policy"

# Get the role ARN
ROLE_ARN=$(aws iam get-role --role-name hcp-terraform-stacks-role --query 'Role.Arn' --output text)

echo ""
echo "================================================"
echo "Setup Complete!"
echo "================================================"
echo ""
echo "Your IAM Role ARN:"
echo "$ROLE_ARN"
echo ""
echo "Next Steps:"
echo "1. Update deployments.tfdeploy.hcl with the role ARN above"
echo "2. Run: terraform stacks init"
echo "3. Run: terraform stacks validate"
echo "4. Run: terraform stacks configuration upload"
echo ""
echo "Command to update deployments.tfdeploy.hcl:"
echo "sed -i.bak 's|arn:aws:iam::YOUR_ACCOUNT_ID:role/hcp-terraform-stacks-role|$ROLE_ARN|g' deployments.tfdeploy.hcl"
echo ""
