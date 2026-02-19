# AWS Web Application Terraform Stack

A cost-optimized Terraform Stack for deploying a simple web application on AWS with separate dev and prod environments using OIDC authentication.

## Architecture

- **Dev Environment**: EC2 t3.nano instance (~$3.80/month) in us-east-1
- **Prod Environment**: EC2 t3.small instance (~$15/month) in us-west-2
- **Web Server**: Nginx serving a custom HTML page
- **Authentication**: OIDC (OpenID Connect) - no static AWS credentials
- **Infrastructure**: Uses default VPC to minimize costs

## Prerequisites

1. **Terraform CLI v1.13+** (with Stacks support)
2. **HCP Terraform Account** (free tier works)
3. **AWS Account** with permissions to:
   - Create IAM roles and OIDC providers
   - Launch EC2 instances
   - Create security groups

## Setup Instructions

### Step 1: Configure AWS OIDC Provider

First, you need to set up an IAM OIDC identity provider and role in AWS that trusts HCP Terraform.

#### 1.1 Create OIDC Provider in AWS

```bash
# Replace with your HCP Terraform organization name
export TFC_ORG_NAME="your-org-name"

aws iam create-open-id-connect-provider \
  --url "https://app.terraform.io" \
  --client-id-list "aws.workload.identity" \
  --thumbprint-list "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
```

#### 1.2 Create IAM Role for Terraform Stacks

Create a file `trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/app.terraform.io"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.terraform.io:aud": "aws.workload.identity"
        },
        "StringLike": {
          "app.terraform.io:sub": "organization:YOUR_ORG_NAME:project:*:stack:*:deployment:*"
        }
      }
    }
  ]
}
```

Create the role:

```bash
aws iam create-role \
  --role-name hcp-terraform-stacks-role \
  --assume-role-policy-document file://trust-policy.json

# Attach permissions policy (adjust as needed for your security requirements)
aws iam attach-role-policy \
  --role-name hcp-terraform-stacks-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
```

#### 1.3 Update the Role ARN

Edit [deployments.tfdeploy.hcl](deployments.tfdeploy.hcl) and replace `YOUR_ACCOUNT_ID` with your actual AWS account ID:

```hcl
locals {
  role_arn = "arn:aws:iam::123456789012:role/hcp-terraform-stacks-role"
}
```

### Step 2: Create Stack in HCP Terraform

#### 2.1 Login to HCP Terraform

```bash
terraform login
```

#### 2.2 Initialize the Stack

```bash
cd terraform-web-stack
terraform stacks init
```

This will:
- Download required providers
- Validate your configuration
- Generate `.terraform.lock.hcl`

#### 2.3 Validate Configuration

```bash
terraform stacks validate
```

### Step 3: Deploy the Stack

#### 3.1 Upload Configuration

```bash
terraform stacks configuration upload
```

This automatically triggers deployment runs for both dev and prod environments.

#### 3.2 Monitor Deployment

Watch the deployment progress:

```bash
# Watch specific deployment
terraform stacks deployment-group watch -deployment-group=dev_default

# Or list all deployment runs
terraform stacks deployment-run list
```

#### 3.3 Approve Deployments (if needed)

If auto-approve is not configured, approve the plans:

```bash
# Get the deployment run ID from the list command
terraform stacks deployment-run approve-all-plans -deployment-run-id=sdr-xxxxx
```

### Step 4: Access Your Web Application

After successful deployment, get the outputs:

```bash
# Use HCP Terraform API to get outputs
TOKEN=$(jq -r '.credentials["app.terraform.io"].token' ~/.terraform.d/credentials.tfrc.json)

# Get deployment step ID from previous commands, then:
curl -L -s -H "Authorization: Bearer $TOKEN" \
  "https://app.terraform.io/api/v2/stack-deployment-steps/{step-id}/artifacts?name=apply-description" | \
  jq -r '.outputs | to_entries | .[] | "\(.key): \(.value.change.after)"'
```

You should see outputs like:
```
web_url: http://54.123.45.67
instance_id: i-0123456789abcdef0
public_ip: 54.123.45.67
```

Open the `web_url` in your browser to see your deployed web application!

## File Structure

```
terraform-web-stack/
├── modules/
│   └── web-server/          # Web server module
│       ├── main.tf          # EC2 instance, security group, user data
│       ├── variables.tf     # Module input variables
│       └── outputs.tf       # Module outputs
├── variables.tfcomponent.hcl   # Stack variable declarations
├── providers.tfcomponent.hcl   # AWS provider with OIDC config
├── components.tfcomponent.hcl  # Component definitions
├── outputs.tfcomponent.hcl     # Stack outputs
├── deployments.tfdeploy.hcl    # Dev and prod deployments
└── README.md                   # This file
```

## Cost Breakdown

### Development Environment
- EC2 t3.nano: ~$3.80/month (730 hours × $0.0052/hour)
- Data transfer: ~$0.50/month (assuming minimal traffic)
- **Total: ~$4.30/month** ✅ Under $10/month target!

### Production Environment
- EC2 t3.small: ~$15/month (730 hours × $0.0208/hour)
- Data transfer: Variable based on traffic

## Customization

### Change Instance Types

Edit [deployments.tfdeploy.hcl](deployments.tfdeploy.hcl):

```hcl
deployment "dev" {
  inputs = {
    instance_type = "t3.micro"  # Change to t3.micro for more resources
    # ...
  }
}
```

### Change Regions

Update the `aws_region` input in the deployment:

```hcl
deployment "dev" {
  inputs = {
    aws_region = "eu-west-1"  # Deploy to Europe
    # ...
  }
}
```

### Add More Environments

Add a new deployment block in [deployments.tfdeploy.hcl](deployments.tfdeploy.hcl):

```hcl
deployment "staging" {
  inputs = {
    aws_region     = "us-west-1"
    environment    = "staging"
    instance_type  = "t3.micro"
    role_arn       = local.role_arn
    identity_token = identity_token.aws.jwt
    project_name   = local.project_name
  }
}
```

## Updating the Stack

Make changes to your configuration files and upload:

```bash
terraform stacks configuration upload
```

HCP Terraform will automatically plan and show you what changes will be made.

## Destroying Resources

To destroy a deployment, edit [deployments.tfdeploy.hcl](deployments.tfdeploy.hcl) and add `destroy = true`:

```hcl
deployment "dev" {
  inputs = {
    # ... existing inputs
  }
  destroy = true
}
```

Then upload the configuration:

```bash
terraform stacks configuration upload
```

After the resources are destroyed, remove the deployment block from the file.

## Troubleshooting

### OIDC Authentication Fails

**Error**: `Error assuming role: AccessDenied`

**Solution**:
1. Verify the IAM role ARN is correct in [deployments.tfdeploy.hcl](deployments.tfdeploy.hcl)
2. Check the trust policy includes your HCP Terraform organization name
3. Ensure the OIDC provider thumbprint is correct

### Instance Not Accessible

**Error**: Cannot access web application via public IP

**Solution**:
1. Check security group rules allow HTTP (port 80) from your IP
2. Wait 2-3 minutes after deployment for user data script to complete
3. Check instance is in "running" state in AWS console

### Provider Lock File Issues

**Error**: Provider version mismatch

**Solution**:
```bash
terraform stacks providers-lock
```

## Security Considerations

1. **OIDC Authentication**: Uses temporary credentials instead of static access keys
2. **Security Groups**: Configured to allow HTTP/HTTPS from anywhere (adjust for production)
3. **Default VPC**: Uses default VPC for simplicity (create custom VPC for production)
4. **IAM Permissions**: Role has EC2FullAccess (use least-privilege permissions for production)

## Next Steps

- Add HTTPS with Let's Encrypt certificates
- Set up Application Load Balancer for high availability
- Implement Auto Scaling for production
- Add CloudWatch monitoring and alarms
- Set up custom VPC with private subnets
- Implement proper logging and auditing

## Resources

- [Terraform Stacks Documentation](https://developer.hashicorp.com/terraform/language/stacks)
- [AWS OIDC Setup Guide](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration)
- [EC2 Pricing Calculator](https://aws.amazon.com/ec2/pricing/on-demand/)

## License

This stack is provided as-is for educational and demonstration purposes.
