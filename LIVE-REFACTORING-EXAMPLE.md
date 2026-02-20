# Live Refactoring Example: Using moved, removed, and import

This guide walks through a real example using all three refactoring blocks in your Terraform Stack.

## Scenario

We'll demonstrate:
1. **Import** an existing Elastic IP into Terraform management
2. **Move** (rename) the security group from `web` to `web_server`
3. **Remove** an old test tag from state without destroying it

## Prerequisites

- Deployments are currently destroyed (`destroy = true`)
- We'll modify the stack to do the refactoring

---

## Part 1: Setup - Create Test Resource to Import

First, let's manually create an Elastic IP in AWS that we'll import.

### Step 1: Create Elastic IP manually

```bash
# Create an EIP in us-east-1 (for dev deployment)
aws ec2 allocate-address \
  --domain vpc \
  --region us-east-1 \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=web-app-dev-manual-eip},{Key=Environment,Value=dev},{Key=Purpose,Value=terraform-import-demo}]'

# Save the allocation ID from the output
# Example output:
# {
#     "PublicIp": "54.123.45.67",
#     "AllocationId": "eipalloc-0abc123def456789",
#     ...
# }
```

**Save the `AllocationId`** - we'll use it for the import block.

### Step 2: Create another EIP for prod

```bash
# Create an EIP in us-west-2 (for prod deployment)
aws ec2 allocate-address \
  --domain vpc \
  --region us-west-2 \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=web-app-prod-manual-eip},{Key=Environment,Value=prod},{Key=Purpose,Value=terraform-import-demo}]'

# Save this allocation ID too
```

---

## Part 2: Prepare the Module for Refactoring

### Step 1: Remove `destroy = true` from deployments

Edit `deployments.tfdeploy.hcl`:

```hcl
# Remove or comment out destroy = true from both deployments
deployment "dev" {
  inputs = {
    aws_region     = "us-east-1"
    environment    = "dev"
    instance_type  = "t3.nano"
    role_arn       = local.role_arn
    identity_token = identity_token.aws.jwt
    project_name   = local.project_name
  }
  # destroy = true  # ← Comment this out
}

deployment "prod" {
  inputs = {
    aws_region     = "us-west-2"
    environment    = "prod"
    instance_type  = "t3.small"
    role_arn       = local.role_arn
    identity_token = identity_token.aws.jwt
    project_name   = local.project_name
  }
  # destroy = true  # ← Comment this out
}
```

### Step 2: Add variable for EIP allocation IDs

Edit `modules/web-server/variables.tf` and add:

```hcl
variable "eip_allocation_id" {
  description = "Elastic IP allocation ID to import (empty to skip)"
  type        = string
  default     = ""
}
```

### Step 3: Update deployments to pass EIP IDs

Edit `deployments.tfdeploy.hcl`:

```hcl
deployment "dev" {
  inputs = {
    aws_region         = "us-east-1"
    environment        = "dev"
    instance_type      = "t3.nano"
    role_arn           = local.role_arn
    identity_token     = identity_token.aws.jwt
    project_name       = local.project_name
    eip_allocation_id  = "eipalloc-DEV_ID_HERE"  # ← Replace with your dev EIP
  }
}

deployment "prod" {
  inputs = {
    aws_region         = "us-west-2"
    environment        = "prod"
    instance_type      = "t3.small"
    role_arn           = local.role_arn
    identity_token     = identity_token.aws.jwt
    project_name       = local.project_name
    eip_allocation_id  = "eipalloc-PROD_ID_HERE"  # ← Replace with your prod EIP
  }
}
```

---

## Part 3: Add Refactoring Blocks

Create `modules/web-server/refactoring.tf`:

```hcl
# ============================================================================
# PART 1: IMPORT BLOCK - Import existing Elastic IPs
# ============================================================================

# Import the manually created Elastic IP
# This will run for both dev and prod deployments
# Each deployment imports its own EIP based on the variable
import {
  to = aws_eip.web[0]
  id = var.eip_allocation_id
}

# ============================================================================
# PART 2: MOVED BLOCK - Rename security group
# ============================================================================

# Rename aws_security_group.web to aws_security_group.web_server
# This demonstrates renaming a resource without recreating it
moved {
  from = aws_security_group.web
  to   = aws_security_group.web_server
}

# ============================================================================
# PART 3: REMOVED BLOCK - Remove old test instance from state
# ============================================================================

# This would be used if we had a test instance we wanted to orphan
# For this demo, we'll add this conceptually
# (commented out since we don't have a test instance)

# removed {
#   from = aws_instance.test_instance
#   lifecycle {
#     destroy = false
#   }
# }
```

---

## Part 4: Update Module Resources

Edit `modules/web-server/main.tf`:

### Change 1: Rename security group resource

Find the `aws_security_group.web` resource and rename it:

```hcl
# BEFORE:
# resource "aws_security_group" "web" {

# AFTER:
resource "aws_security_group" "web_server" {
  name_prefix = "${var.project_name}-${var.environment}-"
  description = "Security group for ${var.environment} web server"
  vpc_id      = data.aws_vpc.default.id

  # ... rest of configuration stays the same
}
```

### Change 2: Update security group reference in instance

Find where `aws_security_group.web` is referenced:

```hcl
# BEFORE:
# vpc_security_group_ids = [aws_security_group.web.id]

# AFTER:
vpc_security_group_ids = [aws_security_group.web_server.id]
```

### Change 3: Add Elastic IP resource

Add the EIP resource definition (after the aws_instance resource):

```hcl
# Elastic IP for the web server
# Imported from existing manually-created EIP
resource "aws_eip" "web" {
  count = var.eip_allocation_id != "" ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.web_server.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-eip"
    Environment = var.environment
    ManagedBy   = "Terraform Stacks"
  }

  lifecycle {
    # Prevent Terraform from trying to modify allocation
    # since we're importing an existing one
    ignore_changes = [
      tags["Purpose"],  # Keep the import demo tag
    ]
  }
}
```

### Change 4: Update instance resource name

While we're refactoring, let's also rename the instance to match:

Add this to `refactoring.tf`:

```hcl
# Rename instance to match security group naming
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}
```

Then in `main.tf`, rename the resource:

```hcl
# BEFORE:
# resource "aws_instance" "web" {

# AFTER:
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.web_server.id]
  # ... rest of configuration
}
```

---

## Part 5: Update Outputs

Edit `modules/web-server/outputs.tf`:

```hcl
# Update output names to match renamed resources
output "instance_id" {
  description = "ID of the web server instance"
  value       = aws_instance.web_server.id
}

output "public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web_server.public_ip
}

output "web_url" {
  description = "URL to access the web application"
  value       = "http://${aws_instance.web_server.public_ip}"
}

output "security_group_id" {
  description = "ID of the web server security group"
  value       = aws_security_group.web_server.id
}

# Add new output for EIP
output "elastic_ip" {
  description = "Elastic IP address (if imported)"
  value       = length(aws_eip.web) > 0 ? aws_eip.web[0].public_ip : null
}

output "elastic_ip_allocation_id" {
  description = "Elastic IP allocation ID (if imported)"
  value       = length(aws_eip.web) > 0 ? aws_eip.web[0].allocation_id : null
}
```

---

## Part 6: Summary of Changes

Here's what we're doing in one place:

### refactoring.tf (NEW FILE)
```hcl
# Import existing Elastic IPs (one per deployment)
import {
  to = aws_eip.web[0]
  id = var.eip_allocation_id
}

# Rename security group: web → web_server
moved {
  from = aws_security_group.web
  to   = aws_security_group.web_server
}

# Rename instance: web → web_server
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}
```

### main.tf Changes
- Renamed `aws_security_group.web` → `aws_security_group.web_server`
- Renamed `aws_instance.web` → `aws_instance.web_server`
- Added `aws_eip.web` resource (conditional)
- Updated all references

### variables.tf Addition
- Added `eip_allocation_id` variable

### deployments.tfdeploy.hcl Changes
- Removed `destroy = true` from both deployments
- Added `eip_allocation_id` input to both deployments

---

## Part 7: Execute the Refactoring

### Step 1: Validate locally

```bash
terraform stacks validate
```

Expected output:
```
Success! Terraform Stacks configuration is valid and ready for use within HCP Terraform.
```

### Step 2: Upload configuration

```bash
terraform stacks configuration upload \
  -organization-name=vansh-org \
  -project-name=Claude-Test \
  -stack-name=claude-stack-1
```

### Step 3: Review the plan in HCP Terraform UI

Go to the URL provided in the output. You should see:

**For dev deployment:**
- ✅ Import: `aws_eip.web[0]` (importing eipalloc-xxx)
- ✅ Move: `aws_security_group.web` → `aws_security_group.web_server`
- ✅ Move: `aws_instance.web` → `aws_instance.web_server`
- 🆕 Create: `aws_instance.web_server` (new instance)
- 🆕 Create: `aws_security_group.web_server` (new SG)
- 🔄 Update: EIP association

**Same for prod deployment.**

### Step 4: Apply

If the plan looks good, apply the changes through the HCP Terraform UI or CLI.

### Step 5: Verify the changes

```bash
# Check that EIPs are still there (not destroyed)
aws ec2 describe-addresses \
  --allocation-ids eipalloc-DEV_ID eipalloc-PROD_ID

# Verify EC2 instances are running
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=web-app" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==`Environment`].Value|[0]]' \
  --output table
```

---

## Part 8: Cleanup - Remove Refactoring Blocks

After successful apply, remove the `refactoring.tf` file:

```bash
# Delete the refactoring file
rm modules/web-server/refactoring.tf
```

Then upload again:

```bash
terraform stacks configuration upload \
  -organization-name=vansh-org \
  -project-name=Claude-Test \
  -stack-name=claude-stack-1
```

This upload should show no changes - the refactoring is complete!

---

## Part 9: Demonstrating `removed` Block

To demonstrate the `removed` block, let's orphan the Elastic IPs:

### Step 1: Create removed block

Create `modules/web-server/refactoring.tf` again:

```hcl
# Stop managing the Elastic IPs (but keep them allocated)
removed {
  from = aws_eip.web[0]

  lifecycle {
    destroy = false
  }
}
```

### Step 2: Comment out or remove the aws_eip resource

In `main.tf`, comment out the `aws_eip.web` resource:

```hcl
# Elastic IP for the web server
# REMOVED from management - keeping it allocated in AWS
# resource "aws_eip" "web" {
#   count = var.eip_allocation_id != "" ? 1 : 0
#   ...
# }
```

### Step 3: Upload configuration

```bash
terraform stacks configuration upload \
  -organization-name=vansh-org \
  -project-name=Claude-Test \
  -stack-name=claude-stack-1
```

### Step 4: Verify EIPs are removed from state but still exist

After apply:

```bash
# EIPs should still exist in AWS
aws ec2 describe-addresses \
  --allocation-ids eipalloc-DEV_ID eipalloc-PROD_ID

# Output: Shows both EIPs still allocated
```

The EIPs are now orphaned - they exist in AWS but Terraform is no longer managing them.

### Step 5: Cleanup refactoring block

```bash
rm modules/web-server/refactoring.tf

terraform stacks configuration upload \
  -organization-name=vansh-org \
  -project-name=Claude-Test \
  -stack-name=claude-stack-1
```

---

## Part 10: Final Cleanup

### Option 1: Destroy the stack

```hcl
# deployments.tfdeploy.hcl
deployment "dev" {
  inputs = { ... }
  destroy = true
}

deployment "prod" {
  inputs = { ... }
  destroy = true
}
```

Upload and apply to destroy all managed resources.

### Option 2: Clean up manual EIPs

```bash
# Release the Elastic IPs we manually created
aws ec2 release-address --allocation-id eipalloc-DEV_ID --region us-east-1
aws ec2 release-address --allocation-id eipalloc-PROD_ID --region us-west-2
```

---

## What We Demonstrated

### ✅ import Block
- Created Elastic IPs manually in AWS
- Imported them into Terraform state using `import` block
- Each deployment imported its own EIP using variables
- **Result:** Existing AWS resources now managed by Terraform

### ✅ moved Block
- Renamed `aws_security_group.web` → `aws_security_group.web_server`
- Renamed `aws_instance.web` → `aws_instance.web_server`
- **Result:** Resources renamed in state without destroying/recreating

### ✅ removed Block
- Removed Elastic IPs from Terraform state
- Used `lifecycle { destroy = false }` to keep them allocated
- **Result:** Resources continue running but Terraform no longer manages them

---

## Key Learnings

### What Worked

1. **Module-level refactoring:** All three blocks work within a module
2. **Deployment-specific imports:** Using variables, each deployment can import different resources
3. **Declarative:** All changes tracked in code, reviewable in PRs
4. **Safe:** Resources weren't destroyed during refactoring

### What Didn't Work / Limitations

1. **All deployments affected:** Both dev and prod executed the same refactoring blocks
2. **No incremental testing:** Can't test refactoring in dev before prod
3. **No cross-deployment movement:** Can't move resources from dev to prod state
4. **Manual coordination required:** Had to create EIPs beforehand with specific IDs

### What Would Help (Gaps)

1. **Deployment-scoped refactoring:** Test in dev, then apply to prod
2. **Cross-deployment moved:** Move resources between deployment states
3. **Refactoring preview:** See state changes before applying
4. **Resource discovery:** Auto-discover existing resources to import

---

## Appendix: Complete File Examples

### Complete refactoring.tf (All three blocks)

```hcl
# ============================================================================
# Live Refactoring Example
# Demonstrates: import, moved, and removed blocks
# ============================================================================

# 1. IMPORT: Bring existing Elastic IPs under management
import {
  to = aws_eip.web[0]
  id = var.eip_allocation_id
}

# 2. MOVED: Rename security group
moved {
  from = aws_security_group.web
  to   = aws_security_group.web_server
}

# 3. MOVED: Rename EC2 instance
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}

# 4. REMOVED: Stop managing EIP (for demonstration)
# Uncomment to orphan the EIP:
# removed {
#   from = aws_eip.web[0]
#   lifecycle {
#     destroy = false
#   }
# }
```

### AWS CLI Helper Commands

```bash
# List all EIPs in both regions
aws ec2 describe-addresses --region us-east-1 --output table
aws ec2 describe-addresses --region us-west-2 --output table

# Get specific EIP details
aws ec2 describe-addresses --allocation-ids eipalloc-xxx --region us-east-1

# List EC2 instances from the stack
aws ec2 describe-instances \
  --filters "Name=tag:ManagedBy,Values=Terraform Stacks" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress,Tags[?Key==`Environment`].Value|[0]]' \
  --output table

# List security groups from the stack
aws ec2 describe-security-groups \
  --filters "Name=tag:ManagedBy,Values=Terraform Stacks" \
  --query 'SecurityGroups[].[GroupId,GroupName,Tags[?Key==`Environment`].Value|[0]]' \
  --output table
```

---

## Conclusion

This live example demonstrates that `moved`, `removed`, and `import` blocks work well for module-level refactoring in Terraform Stacks. However, the analysis in `STATE-SURGERY-ANALYSIS.md` shows significant gaps when needing to:

- Move resources between deployments
- Move resources between components or stacks
- Test refactoring incrementally
- Detect and resolve duplicate resource management

See `STATE-SURGERY-ANALYSIS.md` for detailed gap analysis and proposals for stack-level support.
