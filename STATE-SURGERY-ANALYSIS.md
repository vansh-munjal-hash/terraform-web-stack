# Terraform Stacks State Surgery Analysis

## What Works Today vs What Needs Stack-Level Support

This document analyzes state management capabilities in Terraform Stacks, identifies gaps, and proposes where stack-level support would be beneficial.

---

## Table of Contents
1. [Current Capabilities](#current-capabilities)
2. [State Surgery Scenarios](#state-surgery-scenarios)
3. [What Works Today](#what-works-today)
4. [Critical Gaps](#critical-gaps)
5. [Stack-Level Support Proposals](#stack-level-support-proposals)
6. [Comparison with Traditional Terraform](#comparison-with-traditional-terraform)

---

## Current Capabilities

### Available Refactoring Blocks (Terraform 1.5+)

| Block | Scope | Cross-Deployment | Cross-Stack | State Surgery Alternative |
|-------|-------|------------------|-------------|---------------------------|
| `moved` | Within module/deployment | ❌ | ❌ | `terraform state mv` |
| `removed` | Within module/deployment | ❌ | ❌ | `terraform state rm` |
| `import` | Within module/deployment | ❌ | ❌ | `terraform import` CLI |

### Key Limitation
**All three blocks operate within a single deployment's state.** They cannot move resources between:
- Different deployments (dev → prod)
- Different stacks
- Different components within a stack

---

## State Surgery Scenarios

### Scenario 1: Rename Resource Within Module ✅
**Use Case:** You want to rename `aws_instance.web` to `aws_instance.web_server`

**Status:** ✅ **Works with `moved` block**

```hcl
# modules/web-server/main.tf
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}
```

**Why it works:**
- Single deployment state
- No cross-boundary movement
- Block handles address change automatically

---

### Scenario 2: Stop Managing Resource (Keep Running) ✅
**Use Case:** Hand off resource to another team, keep it running

**Status:** ✅ **Works with `removed` block**

```hcl
# modules/web-server/main.tf
removed {
  from = aws_security_group.legacy
  lifecycle {
    destroy = false
  }
}
```

**Why it works:**
- Removes from current deployment state
- Resource continues running in AWS
- Another team can import it elsewhere

---

### Scenario 3: Import Existing AWS Resource ✅
**Use Case:** Adopt manually created infrastructure

**Status:** ✅ **Works with `import` block**

```hcl
# modules/web-server/main.tf
import {
  to = aws_instance.existing
  id = "i-1234567890abcdef0"
}

resource "aws_instance" "existing" {
  # Config matching existing resource
}
```

**Why it works:**
- Brings external resource into deployment state
- One-time operation per deployment
- Declarative vs CLI command

---

### Scenario 4: Move Resource Between Deployments (dev → prod) ❌
**Use Case:** You created something in dev, want to move it to prod without recreating

**Status:** ❌ **DOES NOT WORK** - Critical Gap

**Current Reality:**
- Each deployment has **separate state**
- `moved` block only works within a deployment
- No way to transfer resources between deployments

**Why this matters:**
```
Deployment: dev (state file: dev.tfstate)
├── aws_instance.web
└── aws_security_group.web

Deployment: prod (state file: prod.tfstate)
├── ??? (can't move from dev)
└── ??? (must recreate or manual state surgery)
```

**Workaround Required:**
1. Export dev state manually
2. Remove from dev state using `removed` block
3. Import into prod using `import` block
4. Resource ID stays the same, but requires coordination

**Gap:** No declarative way to say "move this resource from deployment A to deployment B"

---

### Scenario 5: Move Resource Between Components ❌
**Use Case:** Restructure stack by moving resources between components

**Status:** ❌ **DOES NOT WORK** - Critical Gap

**Example:**
```
component "networking" { ... }
component "web_server" { ... }

# Want to move security group from web_server to networking
# moved block can't cross component boundaries
```

**Why it fails:**
- Components may have different providers
- Components are separate abstraction layers
- `moved` blocks are module-scoped

**What you need:**
```hcl
# Hypothetical stack-level syntax (doesn't exist)
stack_moved {
  from = component.web_server.aws_security_group.web
  to   = component.networking.aws_security_group.web
}
```

---

### Scenario 6: Move Resource Between Stacks ❌
**Use Case:** Reorganize infrastructure across multiple stacks

**Status:** ❌ **DOES NOT WORK** - Critical Gap

**Example:**
```
Stack 1: networking-stack
Stack 2: application-stack

# Want to move VPC from networking to application
# No way to do this declaratively
```

**Current Reality:**
- Stacks are completely isolated
- Separate organizations, projects, or state backends
- Must recreate resources or use manual state surgery

**Gap:** No mechanism for cross-stack resource transfers

---

### Scenario 7: Bulk Refactoring Across Deployments ⚠️
**Use Case:** Rename resource in module used by 10 deployments

**Status:** ⚠️ **Partially Works** - Usability Gap

**What happens:**
```hcl
# modules/web-server/main.tf
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}
```

When you upload configuration:
- **All deployments** (dev, prod, staging, etc.) execute the `moved` block
- No way to test with one deployment first
- All-or-nothing operation

**Risks:**
- Can't test incrementally
- If one deployment fails, others may have already applied
- No rollback mechanism

**What would help:**
```hcl
# Hypothetical deployment-scoped moved block
deployment "dev" {
  refactoring {
    moved {
      from = component.web_server.aws_instance.web
      to   = component.web_server.aws_instance.web_server
    }
  }
}
```

---

### Scenario 8: Fix Duplicate Resources Across Deployments ❌
**Use Case:** You accidentally created the same resource in multiple deployments

**Status:** ❌ **DOES NOT WORK** - Critical Gap

**Problem:**
```
Dev deployment:  aws_s3_bucket.shared (bucket: "my-shared-bucket")
Prod deployment: aws_s3_bucket.shared (bucket: "my-shared-bucket")

# Conflict! Same S3 bucket managed by two states
```

**What you need:**
1. Remove from one deployment's state
2. Keep in the other
3. Ensure both deployments can reference it

**Current workaround:**
```hcl
# In dev deployment
removed {
  from = aws_s3_bucket.shared
  lifecycle { destroy = false }
}

# Prod keeps managing it
# Dev references via data source
data "aws_s3_bucket" "shared" {
  bucket = "my-shared-bucket"
}
```

**Gap:** No way to declare "this resource should only be in one deployment's state"

---

## What Works Today

### ✅ 1. Module-Level Refactoring

**Scenario:** Rename, restructure, or reorganize resources within a module

```hcl
# modules/web-server/main.tf

# Rename resource
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}

# Move into/out of sub-module
moved {
  from = aws_security_group.web
  to   = module.networking.aws_security_group.web
}

# Convert count to for_each
moved {
  from = aws_instance.web[0]
  to   = aws_instance.web["primary"]
}
```

**Applies to:** All deployments using the module

---

### ✅ 2. Importing External Resources

**Scenario:** Bring manually created resources under Terraform management

```hcl
# modules/web-server/main.tf

import {
  to = aws_instance.imported
  id = "i-1234567890abcdef0"
}

resource "aws_instance" "imported" {
  # Configuration matching existing
}
```

**Works for:**
- Manually created AWS resources
- Resources from other IaC tools
- Existing infrastructure adoption

**Per-deployment import:**
```hcl
# Use variables for deployment-specific imports
import {
  to = aws_instance.imported[0]
  id = var.import_instance_id
}

resource "aws_instance" "imported" {
  count = var.import_instance_id != "" ? 1 : 0
  # ...
}
```

```hcl
# deployments.tfdeploy.hcl
deployment "dev" {
  inputs = {
    import_instance_id = "i-dev123"
  }
}

deployment "prod" {
  inputs = {
    import_instance_id = "i-prod456"
  }
}
```

---

### ✅ 3. Orphaning Resources

**Scenario:** Stop managing resources without destroying them

```hcl
# modules/web-server/main.tf

removed {
  from = aws_instance.legacy
  lifecycle {
    destroy = false
  }
}
```

**Use cases:**
- Handing off to another team
- Migrating to different IaC tool
- Keeping resources for manual management

---

### ✅ 4. Traditional State Surgery (Manual)

**When blocks don't work, you can use HCP Terraform API or CLI:**

```bash
# Traditional Terraform commands (non-Stacks)
terraform state list
terraform state show aws_instance.web
terraform state mv aws_instance.web aws_instance.web_server
terraform state rm aws_instance.legacy
```

**In Stacks Context:**
- Access state via HCP Terraform UI
- Use HCP Terraform API for state manipulation
- Download state, modify, re-upload (dangerous!)

**Limitations:**
- No declarative syntax
- Error-prone
- Requires API tokens and permissions
- Not tracked in code/git

---

## Critical Gaps

### Gap 1: Cross-Deployment Movement ⛔

**Problem:** Cannot move resources between deployments declaratively

**Impact:**
- Can't reorganize resources across environments
- Must recreate resources or use manual state editing
- No way to promote resources from dev to prod

**Example Need:**
```hcl
# Doesn't exist - hypothetical syntax
stack_moved {
  from = deployment.dev.component.web_server.aws_instance.test
  to   = deployment.prod.component.web_server.aws_instance.test
}
```

**Workaround:**
```hcl
# Manual process:
# 1. In dev: removed block (keep resource)
# 2. In prod: import block (same resource ID)
# 3. Coordinate uploads carefully
```

**Risk:** Time window where resource isn't managed by either deployment

---

### Gap 2: Cross-Component Movement ⛔

**Problem:** Cannot move resources between components in the same deployment

**Impact:**
- Stack refactoring is difficult
- Must recreate resources when reorganizing
- Can't separate concerns without downtime

**Example Need:**
```hcl
# Doesn't exist - hypothetical syntax
component_moved {
  from = component.web_server.aws_security_group.shared
  to   = component.networking.aws_security_group.shared
  deployment = "*"  # Apply to all deployments
}
```

---

### Gap 3: Cross-Stack Movement ⛔

**Problem:** Stacks are completely isolated, no resource transfer mechanism

**Impact:**
- Can't reorganize stack boundaries
- Must destroy and recreate when splitting/merging stacks
- No way to consolidate infrastructure

**Example Need:**
```hcl
# Doesn't exist - hypothetical syntax
cross_stack_moved {
  from = stack.networking.deployment.prod.aws_vpc.main
  to   = stack.application.deployment.prod.aws_vpc.main
}
```

---

### Gap 4: Conditional Refactoring ⛔

**Problem:** Blocks apply to ALL deployments, no way to test incrementally

**Impact:**
- Can't test refactoring with dev before prod
- All-or-nothing across deployments
- Risky for production environments

**Example Need:**
```hcl
# Doesn't exist - hypothetical syntax
deployment "dev" {
  refactoring {
    enabled = true  # Test refactoring in dev first
  }
}

deployment "prod" {
  refactoring {
    enabled = false  # Don't apply yet
  }
}
```

---

### Gap 5: Duplicate Resource Detection ⛔

**Problem:** No way to detect/resolve resources managed by multiple deployments

**Impact:**
- Silent conflicts
- State drift
- Unpredictable behavior

**Example Need:**
```hcl
# Doesn't exist - hypothetical syntax
resource_ownership {
  resource = aws_s3_bucket.shared
  owner    = deployment.prod  # Only prod manages this

  # Other deployments get read-only access
  access {
    deployment = deployment.dev
    mode       = "data_source"
  }
}
```

---

### Gap 6: State Rollback ⛔

**Problem:** No way to rollback state after failed refactoring

**Impact:**
- Can't undo bad state changes
- Must manually fix state issues
- No safety net

**Example Need:**
```hcl
# Doesn't exist - hypothetical syntax
terraform stacks state rollback \
  -deployment=dev \
  -to-version=previous
```

---

### Gap 7: State Diff/Preview ⛔

**Problem:** Can't preview state changes before applying refactoring blocks

**Impact:**
- Don't know what state operations will occur
- Surprises during apply
- Hard to validate correctness

**Example Need:**
```bash
# Doesn't exist - hypothetical command
terraform stacks refactoring plan

# Output:
# State Changes:
# - deployment.dev:
#   - mv: aws_instance.web → aws_instance.web_server
#   - rm: aws_security_group.legacy
#   - import: aws_eip.web (id: eipalloc-123)
```

---

## Stack-Level Support Proposals

### Proposal 1: Stack-Scoped Refactoring Block

Add refactoring capabilities at the stack level (.tfdeploy.hcl):

```hcl
# deployments.tfdeploy.hcl

# Cross-deployment movement
refactoring {
  moved {
    from       = deployment.dev.component.web_server.aws_instance.test
    to         = deployment.prod.component.web_server.aws_instance.promoted
    migrate_id = true  # Keep AWS resource ID
  }
}

# Cross-component movement
refactoring {
  moved {
    from       = component.web_server.aws_security_group.shared
    to         = component.networking.aws_security_group.shared
    deployments = ["dev", "prod"]  # Apply to specific deployments
  }
}

# Deployment-specific refactoring
deployment "dev" {
  refactoring {
    moved {
      from = component.web_server.aws_instance.web
      to   = component.web_server.aws_instance.web_server
    }
  }
}
```

**Benefits:**
- Declarative cross-boundary movement
- Version controlled
- Reviewable in PRs

---

### Proposal 2: Resource Ownership Declaration

Declare which deployment owns shared resources:

```hcl
# deployments.tfdeploy.hcl

resource_ownership {
  # S3 bucket managed by prod only
  resource "aws_s3_bucket.shared" {
    owner = deployment.prod

    # Dev references it as data source
    access {
      deployment = deployment.dev
      mode       = "data_source"
    }
  }

  # VPC managed by networking stack
  resource "aws_vpc.main" {
    owner = stack.networking.deployment.prod

    # Application stack references it
    access {
      stack      = stack.application
      deployment = "*"
      mode       = "data_source"
    }
  }
}
```

**Benefits:**
- Prevents duplicate management
- Clear ownership model
- Automatic data source generation

---

### Proposal 3: Refactoring Phases

Introduce phases to test refactoring incrementally:

```hcl
# deployments.tfdeploy.hcl

refactoring {
  phase = "preview"  # Options: preview, test, apply

  moved {
    from = aws_instance.web
    to   = aws_instance.web_server
  }
}

deployment "dev" {
  refactoring_phase = "apply"   # Dev applies refactoring
}

deployment "prod" {
  refactoring_phase = "preview"  # Prod only previews
}
```

**Benefits:**
- Test in dev before prod
- Preview state changes
- Gradual rollout

---

### Proposal 4: State Surgery Commands

Add stack-aware state management commands:

```bash
# Move between deployments
terraform stacks state mv \
  -from-deployment=dev \
  -to-deployment=prod \
  aws_instance.web

# Move between components
terraform stacks state mv \
  -deployment=prod \
  -from-component=web_server \
  -to-component=networking \
  aws_security_group.shared

# Preview state changes from refactoring blocks
terraform stacks refactoring plan

# Rollback state
terraform stacks state rollback \
  -deployment=dev \
  -to-configuration=stc-abc123

# Detect duplicate resources
terraform stacks state detect-conflicts
```

**Benefits:**
- Purpose-built for stacks architecture
- Understand deployment/component boundaries
- Safer than manual state editing

---

### Proposal 5: Cross-Stack Resource Transfer

Enable declarative cross-stack movement:

```hcl
# In the TARGET stack
import {
  from_stack  = "networking-stack"
  deployment  = "prod"
  resource    = "aws_vpc.main"

  to = aws_vpc.imported

  lifecycle {
    remove_from_source = true  # Remove from source stack
  }
}

resource "aws_vpc" "imported" {
  # Configuration
}
```

**Benefits:**
- Reorganize stack boundaries
- Consolidate infrastructure
- Maintain continuity

---

## Comparison with Traditional Terraform

### Traditional Terraform (Workspaces/Modules)

| Capability | Traditional | Stacks | Gap |
|------------|------------|--------|-----|
| Rename resource | `moved` block | `moved` block | ✅ Same |
| Import resource | `import` block/CLI | `import` block | ✅ Same |
| Remove from state | `removed` block | `removed` block | ✅ Same |
| Move between workspaces | `state mv` CLI | ❌ No equivalent | ⛔ Gap |
| Move between modules | `moved` block | `moved` block | ✅ Same |
| Move between projects | Manual state surgery | ❌ No support | ⛔ Gap |
| State rollback | ❌ Manual backups | ❌ No support | ⛔ Both lack |
| Conditional refactoring | ❌ No support | ❌ No support | ⛔ Both lack |

**Key Insight:**
Stacks introduce new boundaries (deployments, components, stacks) but don't provide tools to move resources across them. Traditional Terraform has `state mv` CLI for workspace-level movement, but Stacks lack equivalent.

---

## Recommendations

### Short Term (What Users Can Do Today)

1. **Module-level refactoring:** Use `moved`, `removed`, `import` within modules
2. **Manual coordination:** For cross-deployment movement:
   - `removed` from source
   - `import` into target
   - Coordinate timing carefully
3. **Git tracking:** Always commit before refactoring
4. **Test in dev:** Accept that all deployments will execute blocks

### Medium Term (Feature Requests)

1. **Stack-scoped refactoring blocks** for cross-deployment/component movement
2. **Refactoring phases** to test incrementally
3. **State surgery commands** aware of stack structure
4. **Duplicate resource detection** across deployments

### Long Term (Architecture Improvements)

1. **Resource ownership model** for shared resources
2. **Cross-stack transfer mechanism**
3. **State versioning and rollback**
4. **Refactoring plan preview** before apply

---

## Summary Matrix

| Scenario | Status | Works Today | Gap | Priority |
|----------|--------|-------------|-----|----------|
| Rename resource in module | ✅ | `moved` block | None | N/A |
| Import external resource | ✅ | `import` block | None | N/A |
| Stop managing resource | ✅ | `removed` block | None | N/A |
| Move between deployments | ❌ | Manual workaround | No declarative syntax | 🔥 High |
| Move between components | ❌ | Must recreate | No stack-level `moved` | 🔥 High |
| Move between stacks | ❌ | Must recreate | No cross-stack support | Medium |
| Test refactoring incrementally | ❌ | All deployments at once | No conditional refactoring | 🔥 High |
| Detect duplicate management | ❌ | Manual detection | No ownership model | Medium |
| Rollback state | ❌ | Manual recovery | No state versioning | Low |
| Preview state changes | ❌ | Only in plan | No refactoring-specific preview | Low |

---

## Next Steps

See `LIVE-REFACTORING-EXAMPLE.md` for hands-on examples of what works today with all three block types.
