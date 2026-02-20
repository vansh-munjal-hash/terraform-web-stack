# Terraform Stacks Refactoring Guide

A comprehensive guide to using `moved`, `removed`, and `import` blocks with Terraform Stacks and local modules.

## Table of Contents
- [Overview](#overview)
- [Where to Place Refactoring Blocks](#where-to-place-refactoring-blocks)
- [Using moved Blocks](#using-moved-blocks)
- [Using removed Blocks](#using-removed-blocks)
- [Using import Blocks](#using-import-blocks)
- [Stack-Specific Considerations](#stack-specific-considerations)
- [Examples](#examples)

## Overview

Refactoring blocks (`moved`, `removed`, `import`) allow you to manage Terraform state changes without destroying infrastructure. In Terraform Stacks, these blocks are placed in **local modules** where your resources are defined.

### Key Principles

1. **Blocks go in modules**, not in stack configuration files (.tfcomponent.hcl or .tfdeploy.hcl)
2. **Each deployment maintains its own state**, so refactoring affects all deployments using that module
3. **Blocks are temporary** - remove them after successful state migration

## Where to Place Refactoring Blocks

```
terraform-web-stack/
├── modules/
│   └── web-server/
│       ├── main.tf              ← Place moved/removed/import blocks here
│       ├── variables.tf
│       └── outputs.tf
├── components.tfcomponent.hcl   ← References the module
└── deployments.tfdeploy.hcl     ← Deployments use the component
```

### Important Notes

- Place blocks in `main.tf` (or create `refactoring.tf` for organization)
- Blocks affect **all deployments** (dev, prod, etc.) using that module
- Test with one deployment first if possible

## Using moved Blocks

### Purpose
Rename or restructure resources without destroying them.

### Syntax in Local Module

```hcl
# modules/web-server/main.tf

moved {
  from = aws_instance.old_name
  to   = aws_instance.new_name
}

resource "aws_instance" "new_name" {
  # ... existing configuration
}
```

### Example: Renaming a Resource

**Scenario:** Rename `aws_instance.web` to `aws_instance.web_server`

```hcl
# modules/web-server/main.tf

moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}

resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  # ... rest of configuration
}
```

### Example: Moving Resource into a Module

**Scenario:** You have a resource at root level and want to move it into a module

```hcl
# In the module where you're moving the resource TO
moved {
  from = aws_security_group.web
  to   = module.web_server.aws_security_group.web
}
```

### Example: Refactoring with for_each

**Scenario:** Converting from `count` to `for_each`

```hcl
# Old configuration
# resource "aws_instance" "web" {
#   count = 2
#   ...
# }

# New configuration with moved blocks
moved {
  from = aws_instance.web[0]
  to   = aws_instance.web["primary"]
}

moved {
  from = aws_instance.web[1]
  to   = aws_instance.web["secondary"]
}

resource "aws_instance" "web" {
  for_each = toset(["primary", "secondary"])

  # ... configuration
}
```

### Workflow

1. Add `moved` block to module
2. Upload stack configuration: `terraform stacks configuration upload ...`
3. HCP Terraform will show the state migration in the plan
4. After successful apply, remove the `moved` block
5. Upload configuration again to clean up

## Using removed Blocks

### Purpose
Remove resources from Terraform state without destroying the actual infrastructure.

### Syntax in Local Module

```hcl
# modules/web-server/main.tf

removed {
  from = aws_instance.legacy

  lifecycle {
    destroy = false  # Critical: prevents destruction
  }
}

# Note: Remove the resource block as well, or comment it out
```

### Example: Orphaning a Resource

**Scenario:** You want to keep an EC2 instance running but stop managing it with Terraform

```hcl
# modules/web-server/main.tf

removed {
  from = aws_instance.legacy_server

  lifecycle {
    destroy = false
  }
}

# Remove or comment out the resource block:
# resource "aws_instance" "legacy_server" {
#   ...
# }
```

### Example: Handing Off to Another Stack

**Scenario:** Moving resource management to a different Terraform configuration

```hcl
removed {
  from = aws_security_group.shared

  lifecycle {
    destroy = false
  }
}

# The resource will continue running
# You can import it into another Terraform config using import blocks
```

### Workflow

1. Add `removed` block with `destroy = false`
2. Comment out or remove the resource block
3. Upload stack configuration
4. HCP Terraform will remove from state without destroying
5. After successful apply, remove the `removed` block
6. Upload configuration again

## Using import Blocks

### Purpose
Declaratively bring existing AWS resources under Terraform management.

### Syntax in Local Module

```hcl
# modules/web-server/main.tf

import {
  to = aws_instance.existing
  id = "i-1234567890abcdef0"  # AWS resource ID
}

resource "aws_instance" "existing" {
  # Configuration must match the existing resource
  ami           = "ami-12345678"
  instance_type = "t3.nano"

  # ... rest of configuration
}
```

### Example: Import Existing EC2 Instance

**Scenario:** You manually created an EC2 instance and want Terraform to manage it

```hcl
# modules/web-server/main.tf

import {
  to = aws_instance.imported_web
  id = "i-0abc123def456789"
}

resource "aws_instance" "imported_web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.web.id]
  subnet_id              = data.aws_subnets.default.ids[0]

  tags = {
    Name        = "${var.project_name}-${var.environment}-imported"
    Environment = var.environment
    ManagedBy   = "Terraform Stacks"
  }
}
```

### Example: Import Security Group

**Scenario:** Import an existing security group

```hcl
# modules/web-server/main.tf

import {
  to = aws_security_group.existing
  id = "sg-0123456789abcdef0"
}

resource "aws_security_group" "existing" {
  name_prefix = "${var.project_name}-${var.environment}-"
  description = "Existing security group now managed by Terraform"
  vpc_id      = data.aws_vpc.default.id

  # Configuration must match existing security group rules
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### Workflow

1. Find the AWS resource ID (e.g., instance ID, security group ID)
2. Add `import` block with the resource ID
3. Define the `resource` block with configuration matching the existing resource
4. Upload stack configuration
5. HCP Terraform will import the resource into state
6. After successful import, remove the `import` block
7. Upload configuration again
8. The resource is now fully managed by Terraform

### Pro Tips for import

- Use AWS CLI or Console to inspect existing resources
- Match the configuration exactly (use `terraform show` after import to verify)
- For complex resources, import first then adjust configuration
- Test import in dev environment before prod

```bash
# Get EC2 instance details
aws ec2 describe-instances --instance-ids i-1234567890abcdef0

# Get security group details
aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0
```

## Stack-Specific Considerations

### Multiple Deployments

When you have multiple deployments (dev, prod), refactoring blocks affect **all of them**:

```hcl
# deployments.tfdeploy.hcl
deployment "dev" {
  # Uses modules/web-server
}

deployment "prod" {
  # Uses modules/web-server
}
```

**Both deployments** will execute the moved/removed/import blocks when you upload the configuration.

### Testing Strategy

1. **Test with one deployment first**
   - Temporarily remove other deployments or set them to `destroy = true`
   - Test refactoring with dev only
   - Once verified, apply to prod

2. **Use separate configurations if needed**
   - Create environment-specific modules if refactoring differs
   - Or use conditional logic in modules

### Deployment-Specific Imports

If you need to import different resources per deployment:

```hcl
# modules/web-server/main.tf

# Use variables to make imports conditional
import {
  to = aws_instance.imported
  id = var.import_instance_id  # Pass from deployment
}

resource "aws_instance" "imported" {
  count = var.import_instance_id != "" ? 1 : 0
  # ... configuration
}
```

```hcl
# deployments.tfdeploy.hcl
deployment "dev" {
  inputs = {
    import_instance_id = "i-dev123456"  # Dev instance
    # ...
  }
}

deployment "prod" {
  inputs = {
    import_instance_id = "i-prod789012"  # Prod instance
    # ...
  }
}
```

## Examples

### Complete Example: Refactoring the Web Server Module

Let's say we want to:
1. Rename `aws_instance.web` to `aws_instance.web_server`
2. Import an existing elastic IP
3. Remove an old security group rule

#### Step 1: Create refactoring.tf in the module

```hcl
# modules/web-server/refactoring.tf

# Rename the EC2 instance
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}

# Import an existing Elastic IP
import {
  to = aws_eip.web
  id = "eipalloc-12345678"
}

# Remove old security group from management (but keep it running)
removed {
  from = aws_security_group.old_rules

  lifecycle {
    destroy = false
  }
}
```

#### Step 2: Update main.tf

```hcl
# modules/web-server/main.tf

# Renamed resource (was aws_instance.web)
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  # ... rest of configuration
}

# New resource for imported EIP
resource "aws_eip" "web" {
  domain   = "vpc"
  instance = aws_instance.web_server.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-eip"
    Environment = var.environment
  }
}

# Old security group resource removed (commented out)
# resource "aws_security_group" "old_rules" {
#   ...
# }
```

#### Step 3: Upload and apply

```bash
terraform stacks configuration upload \
  -organization-name=vansh-org \
  -project-name=Claude-Test \
  -stack-name=claude-stack-1
```

#### Step 4: Clean up after successful apply

Remove the refactoring blocks from `refactoring.tf` and upload again.

## Best Practices

### General Guidelines

1. **Always use version control** - commit before refactoring
2. **Test in non-production first** - verify with dev environment
3. **One refactoring at a time** - don't combine multiple changes
4. **Review plans carefully** - HCP Terraform shows what will change
5. **Remove blocks after success** - don't leave them permanently
6. **Document your changes** - add comments explaining why you refactored

### Safety Checklist

Before refactoring:
- [ ] Code is committed to git
- [ ] You understand what resources will be affected
- [ ] You've tested the syntax locally (`terraform stacks validate`)
- [ ] You've reviewed the state addresses you're moving from/to
- [ ] You have backups of any critical data
- [ ] You know how to rollback if needed

### Rollback Strategy

If something goes wrong:

1. **Revert git changes** to previous working state
2. **Upload previous configuration** to HCP Terraform
3. **Manually fix state** if needed using HCP Terraform state management
4. **Contact HashiCorp support** for complex state issues

## Troubleshooting

### Common Errors

**Error: Resource not found in state**
```
The resource you're moving from doesn't exist in state.
```
**Solution:** Check resource addresses with `terraform state list` or in HCP Terraform UI.

**Error: Resource already exists**
```
The resource you're moving to already exists in state.
```
**Solution:** The resource might have already been moved. Remove the moved block.

**Error: Configuration doesn't match imported resource**
```
The configuration doesn't match the actual resource attributes.
```
**Solution:** Use AWS CLI to inspect the resource and match configuration exactly.

### Getting Resource Addresses

To see current state addresses:
1. Go to HCP Terraform UI
2. Navigate to your deployment
3. View the state file
4. Look for resource addresses (e.g., `aws_instance.web`)

Or use AWS CLI to find resource IDs:
```bash
# List EC2 instances
aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]' --output table

# List security groups
aws ec2 describe-security-groups --query 'SecurityGroups[].[GroupId,GroupName]' --output table
```

## Additional Resources

- [Terraform moved Block Documentation](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring)
- [Terraform import Block Documentation](https://developer.hashicorp.com/terraform/language/import)
- [Terraform removed Block Documentation](https://developer.hashicorp.com/terraform/language/resources/syntax#removing-resources)
- [Terraform Stacks Documentation](https://developer.hashicorp.com/terraform/language/stacks)

## Summary

| Block | Purpose | Goes in State | Resource Survives |
|-------|---------|--------------|-------------------|
| `moved` | Rename/restructure | Yes (new address) | Yes |
| `removed` | Stop managing | No | Yes |
| `import` | Start managing | Yes | Yes (already exists) |

All three blocks help you manage infrastructure changes safely without destroying resources. Use them in your local modules, test thoroughly, and always remove them after successful application.
