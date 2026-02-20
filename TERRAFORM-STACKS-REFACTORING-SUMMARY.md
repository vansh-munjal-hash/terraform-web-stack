# Terraform Stacks: Refactoring Blocks (moved, removed, import)
## What Works & What Doesn't - Internal Reference Guide

**Document Version:** 1.0
**Last Updated:** February 2026
**Status:** Production-Ready Findings
**Audience:** Engineering Teams Using Terraform Stacks

---

## Executive Summary

Terraform 1.5+ introduced three declarative refactoring blocks (`moved`, `removed`, `import`) that work within Terraform Stacks with **important limitations**. This document provides a practical guide for when to use these blocks and where manual state management is still required.

### TL;DR

✅ **Use these blocks for:** Renaming resources, importing existing infrastructure, orphaning resources
⚠️ **Limitations:** Cannot move resources between deployments, components, or stacks
📋 **Recommendation:** Great for module-level refactoring, but cross-boundary moves still need workarounds

---

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [What Works Today](#what-works-today)
3. [Known Limitations](#known-limitations)
4. [Decision Tree](#decision-tree)
5. [Code Examples](#code-examples)
6. [Workarounds](#workarounds)
7. [Best Practices](#best-practices)

---

## Quick Reference

### The Three Blocks

| Block | Purpose | Example | Destroys Resources? |
|-------|---------|---------|---------------------|
| `moved` | Rename/restructure | `aws_instance.web` → `aws_instance.web_server` | ❌ No |
| `removed` | Stop managing | Hand off to another team | ❌ No (with `destroy = false`) |
| `import` | Adopt existing | Bring manually created EC2 into Terraform | ❌ No |

### Compatibility Matrix

| Scenario | Works? | Block Type | Notes |
|----------|--------|-----------|-------|
| Rename resource in module | ✅ Yes | `moved` | Standard use case |
| Import existing AWS resource | ✅ Yes | `import` | One per deployment |
| Stop managing resource | ✅ Yes | `removed` | Resource keeps running |
| Convert count to for_each | ✅ Yes | `moved` | Multiple moves needed |
| Move between deployments | ❌ No | N/A | Manual workaround required |
| Move between components | ❌ No | N/A | Must recreate |
| Move between stacks | ❌ No | N/A | Must recreate |
| Test in dev before prod | ❌ No | N/A | All deployments affected |

---

## What Works Today

### ✅ 1. Rename Resources

**Use Case:** Better naming conventions, code cleanup

```hcl
# modules/web-server/refactoring.tf
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}

# Then update the resource definition
resource "aws_instance" "web_server" {
  # existing configuration
}
```

**Result:** Resource renamed in state, no downtime

---

### ✅ 2. Import Existing Infrastructure

**Use Case:** Adopt manually created resources

```hcl
# modules/web-server/refactoring.tf
import {
  to = aws_instance.existing
  id = "i-1234567890abcdef0"
}

resource "aws_instance" "existing" {
  # Configuration must match existing resource
  ami           = "ami-12345678"
  instance_type = "t3.nano"
}
```

**Result:** Existing resource now managed by Terraform

**Deployment-Specific Imports:**
```hcl
# Use variables for different resources per deployment
import {
  to = aws_eip.imported[0]
  id = var.import_eip_id
}

# In deployments.tfdeploy.hcl
deployment "dev" {
  inputs = {
    import_eip_id = "eipalloc-dev123"
  }
}

deployment "prod" {
  inputs = {
    import_eip_id = "eipalloc-prod456"
  }
}
```

---

### ✅ 3. Stop Managing Resources

**Use Case:** Hand off to another team, keep running

```hcl
# modules/web-server/refactoring.tf
removed {
  from = aws_security_group.legacy

  lifecycle {
    destroy = false  # CRITICAL: Keeps resource alive
  }
}

# Remove or comment out the resource block
```

**Result:** Resource removed from state but continues running

---

### ✅ 4. Refactor count to for_each

**Use Case:** More flexible resource indexing

```hcl
# modules/network/refactoring.tf
moved {
  from = aws_subnet.private[0]
  to   = aws_subnet.private["us-east-1a"]
}

moved {
  from = aws_subnet.private[1]
  to   = aws_subnet.private["us-east-1b"]
}

# Update resource to use for_each
resource "aws_subnet" "private" {
  for_each = toset(["us-east-1a", "us-east-1b"])
  # ...
}
```

**Result:** Flexible indexing without recreation

---

## Known Limitations

### ❌ 1. Cross-Deployment Movement

**Problem:** Cannot move resources between deployments (dev → prod)

**Why It Matters:**
```
❌ Cannot do this:
moved {
  from = deployment.dev.aws_instance.test
  to   = deployment.prod.aws_instance.promoted
}
```

Each deployment has separate state, and `moved` blocks only work within a single state.

**Impact:** Must manually coordinate `removed` + `import` or recreate resources

---

### ❌ 2. Cross-Component Movement

**Problem:** Cannot reorganize components without recreation

**Example:**
```
❌ Cannot do this:
moved {
  from = component.web_server.aws_security_group.shared
  to   = component.networking.aws_security_group.shared
}
```

Components are separate logical units, blocks don't cross boundaries.

**Impact:** Restructuring requires careful planning or downtime

---

### ❌ 3. Cross-Stack Movement

**Problem:** Stacks are completely isolated

**Impact:** Consolidating or splitting stacks requires recreation

---

### ⚠️ 4. All Deployments Affected Simultaneously

**Problem:** Cannot test refactoring in dev before prod

**What Happens:**
```hcl
# modules/web-server/refactoring.tf
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}

# This executes for ALL deployments (dev, prod, staging) at once
```

**Impact:** Higher risk, no incremental rollout

---

### ⚠️ 5. Blocks Must Be Removed

**Problem:** Refactoring blocks are one-time operations

**Workflow:**
1. Add block
2. Upload and apply
3. **Must remove block** after success
4. Upload again

**Impact:** Manual cleanup required, blocks can't stay in code

---

## Decision Tree

```
Need to refactor Terraform resources?
│
├─ Within a single deployment's module?
│  └─ ✅ Use moved/removed/import blocks
│
├─ Between deployments (dev → prod)?
│  └─ ⚠️ Use workaround (removed + import)
│
├─ Between components?
│  └─ ❌ Must recreate or use data sources
│
├─ Between stacks?
│  └─ ❌ Must recreate resources
│
└─ Need to test in dev first?
   └─ ⚠️ Not possible, all deployments affected
```

---

## Code Examples

### Example 1: Complete Refactoring Workflow

```hcl
# Step 1: Add blocks to modules/web-server/refactoring.tf
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}

moved {
  from = aws_security_group.web
  to   = aws_security_group.web_server
}

# Step 2: Update resource definitions in main.tf
resource "aws_instance" "web_server" {
  vpc_security_group_ids = [aws_security_group.web_server.id]
  # ... rest of config
}

resource "aws_security_group" "web_server" {
  # ... config
}

# Step 3: Validate and upload
terraform stacks validate
terraform stacks configuration upload -organization-name=X -project-name=Y -stack-name=Z

# Step 4: After successful apply, remove refactoring.tf
rm modules/web-server/refactoring.tf

# Step 5: Upload again
terraform stacks configuration upload -organization-name=X -project-name=Y -stack-name=Z
```

### Example 2: Import with Variables

```hcl
# modules/database/variables.tf
variable "import_db_instance_id" {
  type    = string
  default = ""
}

# modules/database/refactoring.tf
import {
  to = aws_db_instance.imported[0]
  id = var.import_db_instance_id
}

resource "aws_db_instance" "imported" {
  count = var.import_db_instance_id != "" ? 1 : 0
  # ... configuration matching existing DB
}

# deployments.tfdeploy.hcl
deployment "dev" {
  inputs = {
    import_db_instance_id = "mydb-dev-instance"
  }
}

deployment "prod" {
  inputs = {
    import_db_instance_id = "mydb-prod-instance"
  }
}
```

---

## Workarounds

### Workaround 1: Move Between Deployments

**Scenario:** Move resource from dev to prod without destroying it

**Steps:**
1. In dev deployment, add `removed` block with `destroy = false`
2. Upload dev changes
3. In prod deployment, add `import` block with same resource ID
4. Upload prod changes
5. **Timing is critical** - coordinate carefully

**Code:**
```hcl
# Dev deployment module
removed {
  from = aws_eip.test
  lifecycle { destroy = false }
}

# Prod deployment module
import {
  to = aws_eip.promoted
  id = "eipalloc-abc123"  # Same EIP from dev
}
```

**Risk:** Time window where resource isn't managed by either deployment

---

### Workaround 2: Move Between Components

**Scenario:** Reorganize component boundaries

**Options:**
- **Option A:** Use data sources to reference across components
- **Option B:** Recreate resources (if acceptable downtime)
- **Option C:** Manual state surgery via HCP Terraform API

**Recommendation:** Use data sources for shared resources instead:
```hcl
# component.networking manages the VPC
resource "aws_vpc" "main" { ... }

# component.web_server references it
data "aws_vpc" "main" {
  id = var.vpc_id  # Pass from networking component
}
```

---

### Workaround 3: Test Refactoring Safely

**Scenario:** Want to test in dev before prod

**Current Reality:** Not possible with blocks (all deployments execute simultaneously)

**Best Practices:**
1. **Validate locally** before uploading: `terraform stacks validate`
2. **Review plan carefully** in HCP Terraform UI before applying
3. **Use git** to enable quick rollback
4. **Backup state** before major refactoring (via HCP Terraform)
5. **Consider maintenance window** for production

---

## Best Practices

### ✅ Do This

1. **Always use version control** - commit before refactoring
2. **Validate locally** - `terraform stacks validate` before upload
3. **Review plans in HCP UI** - check what will change
4. **Remove blocks after success** - don't leave them permanently
5. **Document why** - add comments explaining refactoring reason
6. **One refactoring at a time** - don't combine multiple changes
7. **Use deployment-specific variables** - for imports that differ per environment

### ❌ Avoid This

1. **Don't skip validation** - always validate before uploading
2. **Don't leave blocks in code** - they're one-time operations
3. **Don't combine with other changes** - refactor separately
4. **Don't forget to clean up** - remove blocks after execution
5. **Don't skip plan review** - always check HCP UI before applying
6. **Don't guess resource IDs** - use AWS CLI to verify
7. **Don't use in production first** - test refactoring pattern in dev

### 🔒 Safety Checklist

Before refactoring:
- [ ] Code committed to git
- [ ] Validated locally
- [ ] Reviewed resource addresses (correct `from` and `to`)
- [ ] Understand impact (all deployments affected)
- [ ] Have rollback plan (git revert)
- [ ] Have backup of critical data
- [ ] Team aware (if prod changes)

---

## Common Errors & Solutions

### Error: "Resource not found in state"

**Cause:** The `from` address doesn't exist in state

**Solution:**
- Check resource address with HCP Terraform state viewer
- Verify exact resource name and type
- Ensure resource exists in state before moving

### Error: "Resource already exists"

**Cause:** The `to` address already exists in state

**Solution:**
- Block might have already executed
- Remove the `moved` block and upload again

### Error: "Configuration doesn't match imported resource"

**Cause:** Import block config doesn't match actual AWS resource

**Solution:**
- Use AWS CLI to inspect resource: `aws ec2 describe-instances --instance-ids i-XXX`
- Match configuration exactly (AMI, instance type, tags, etc.)
- Use `lifecycle { ignore_changes = [...] }` for attributes that differ

### Error: "Resource instance keys not allowed"

**Cause:** `removed` block doesn't support `[0]` or `[key]` syntax

**Solution:**
- Use `removed { from = aws_eip.web }` not `aws_eip.web[0]`
- Remove entire resource, not specific instances

---

## AWS CLI Helpers

```bash
# Find EC2 instance ID and details
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=my-app" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' \
  --output table

# Find security group ID
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=my-sg" \
  --query 'SecurityGroups[].[GroupId,GroupName]' \
  --output table

# Find EIP allocation ID
aws ec2 describe-addresses \
  --filters "Name=tag:Name,Values=my-eip" \
  --query 'Addresses[].[AllocationId,PublicIp,InstanceId]' \
  --output table

# Get complete instance details (for import)
aws ec2 describe-instances --instance-ids i-1234567890abcdef0

# Get complete security group details (for import)
aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0
```

---

## When to Use Manual State Management

Despite these refactoring blocks, some scenarios **still require manual state management**:

| Scenario | Use Blocks? | Alternative |
|----------|------------|-------------|
| Rename within module | ✅ Yes | `moved` block |
| Import existing resource | ✅ Yes | `import` block |
| Move between deployments | ❌ No | `removed` + `import` workaround |
| Move between components | ❌ No | HCP Terraform state API |
| Move between stacks | ❌ No | Recreate or HCP API |
| Fix state corruption | ❌ No | HCP Terraform state management |
| Bulk state operations | ❌ No | HCP Terraform API + scripting |

---

## Feature Gaps & Future Needs

Based on real-world usage, these capabilities would significantly improve Terraform Stacks refactoring:

### Priority 1: High Impact

1. **Stack-scoped `moved` blocks** - Move resources between deployments/components
   ```hcl
   # Hypothetical syntax
   moved {
     from = deployment.dev.component.web.aws_instance.test
     to   = deployment.prod.component.web.aws_instance.promoted
   }
   ```

2. **Deployment-scoped refactoring** - Test in dev before prod
   ```hcl
   # Hypothetical syntax
   deployment "dev" {
     refactoring_enabled = true
   }
   deployment "prod" {
     refactoring_enabled = false  # Skip for now
   }
   ```

3. **Refactoring preview** - See state changes before apply
   ```bash
   # Hypothetical command
   terraform stacks refactoring plan
   # Shows: mv, rm, import operations per deployment
   ```

### Priority 2: Medium Impact

4. **Resource ownership model** - Declare which deployment owns shared resources
5. **Cross-stack transfers** - Move resources between stacks declaratively
6. **State rollback** - Undo failed refactoring operations

---

## Additional Resources

### Internal Documentation
- **Complete Guide:** `REFACTORING-GUIDE.md` in repository
- **Quick Reference:** `REFACTORING-CHEATSHEET.md` in repository
- **Live Example:** `LIVE-REFACTORING-EXAMPLE.md` - real execution walkthrough
- **Gap Analysis:** `STATE-SURGERY-ANALYSIS.md` - detailed findings

### External Resources
- [Terraform moved Block Docs](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring)
- [Terraform import Block Docs](https://developer.hashicorp.com/terraform/language/import)
- [Terraform removed Block Docs](https://developer.hashicorp.com/terraform/language/resources/syntax#removing-resources)
- [Terraform Stacks Docs](https://developer.hashicorp.com/terraform/language/stacks)

---

## Summary

### ✅ What Works
- Rename resources within modules
- Import existing infrastructure
- Stop managing resources without destroying
- Convert count to for_each

### ❌ What Doesn't Work
- Move resources between deployments
- Move resources between components or stacks
- Test refactoring in dev before prod
- Permanent refactoring blocks in code

### 📋 Recommendation
**Use these blocks for module-level refactoring.** For cross-boundary moves (between deployments/components/stacks), plan for workarounds or recreation. Always test the refactoring pattern in a safe environment first.

---

## Questions?

For questions or issues with these blocks:
1. Check the detailed guides in repository
2. Review HCP Terraform state viewer for resource addresses
3. Contact DevOps team for complex state management needs

**Document Maintainer:** [Your Team/Name]
**Last Review:** February 2026
**Next Review:** August 2026
