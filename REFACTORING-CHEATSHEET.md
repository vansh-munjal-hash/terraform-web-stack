# Terraform Stacks Refactoring Quick Reference

## Where Do Blocks Go?

```
✅ modules/web-server/main.tf        (or refactoring.tf)
❌ components.tfcomponent.hcl        (stack config - wrong place)
❌ deployments.tfdeploy.hcl          (stack config - wrong place)
```

## Three Block Types

| Block | Purpose | State | Infrastructure |
|-------|---------|-------|----------------|
| `moved` | Rename/restructure | ✅ Kept (new address) | ✅ Untouched |
| `removed` | Stop managing | ❌ Removed | ✅ Keeps running |
| `import` | Start managing | ✅ Added | ✅ Already exists |

## Syntax Quick Reference

### moved
```hcl
moved {
  from = aws_instance.old_name
  to   = aws_instance.new_name
}

resource "aws_instance" "new_name" {
  # ... config
}
```

### removed
```hcl
removed {
  from = aws_security_group.legacy
  lifecycle {
    destroy = false  # ⚠️ Required!
  }
}

# Remove resource block
```

### import
```hcl
import {
  to = aws_instance.existing
  id = "i-1234567890abcdef0"
}

resource "aws_instance" "existing" {
  # Config must match existing resource
}
```

## Workflow

1. **Add block** to module (main.tf or refactoring.tf)
2. **Update resource** definitions as needed
3. **Upload config**: `terraform stacks configuration upload -organization-name=X -project-name=Y -stack-name=Z`
4. **Review plan** in HCP Terraform UI
5. **Apply** changes
6. **Remove block** after success
7. **Upload again** to clean up

## Common Use Cases

### Rename a Resource
```hcl
# Step 1: Add moved block
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}

# Step 2: Rename resource
resource "aws_instance" "web_server" {
  # existing config
}
```

### Import Existing EC2
```hcl
# Step 1: Find instance ID
# aws ec2 describe-instances

# Step 2: Add import block
import {
  to = aws_instance.imported
  id = "i-0abc123def456789"
}

# Step 3: Add matching config
resource "aws_instance" "imported" {
  ami           = "ami-12345"
  instance_type = "t3.nano"
  # must match existing!
}
```

### Stop Managing (Keep Running)
```hcl
# Step 1: Add removed block
removed {
  from = aws_instance.legacy
  lifecycle {
    destroy = false
  }
}

# Step 2: Delete resource block
# resource "aws_instance" "legacy" { ... }
```

## AWS CLI Helpers

```bash
# List EC2 instances
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# List security groups
aws ec2 describe-security-groups \
  --query 'SecurityGroups[].[GroupId,GroupName]' \
  --output table

# Get instance details
aws ec2 describe-instances --instance-ids i-XXXXX

# Get security group details
aws ec2 describe-security-groups --group-ids sg-XXXXX
```

## Safety Checklist

Before refactoring:
- [ ] Code committed to git
- [ ] Tested in dev first
- [ ] Reviewed resource addresses
- [ ] Know how to rollback
- [ ] Have backups of critical data

## Common Errors

**Resource not found in state**
→ Check addresses with `terraform state list` or in HCP UI

**Resource already exists**
→ Moved block might have already run, remove it

**Config doesn't match imported resource**
→ Use AWS CLI to inspect and match exactly

## Multiple Deployments Warning

⚠️ Blocks affect **ALL deployments** (dev, prod, etc.)

Test strategy:
1. Test with dev only first
2. Then apply to prod
3. Or use deployment-specific variables

## Pro Tips

- Place blocks in separate `refactoring.tf` file for visibility
- One refactoring operation at a time
- Always remove blocks after successful apply
- Test with `terraform stacks validate` before uploading
- Keep blocks temporary - they're not meant to stay

## Example Files in This Stack

- `REFACTORING-GUIDE.md` - Complete documentation
- `modules/web-server/refactoring.tf.example` - Practical examples

## Quick Command Reference

```bash
# Validate locally
terraform stacks validate

# Upload configuration
terraform stacks configuration upload \
  -organization-name=vansh-org \
  -project-name=Claude-Test \
  -stack-name=claude-stack-1

# View in HCP Terraform
# Check the returned URL for plan details
```

## Need Help?

See `REFACTORING-GUIDE.md` for:
- Detailed explanations
- Step-by-step examples
- Troubleshooting guide
- Stack-specific considerations
