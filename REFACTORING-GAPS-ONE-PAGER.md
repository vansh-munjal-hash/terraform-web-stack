# Terraform Stacks Refactoring Gaps - Engineering Brief

**Target Audience:** Engineers working on Terraform Stacks improvements
**Document Purpose:** Actionable gap analysis for feature development
**Status:** Production findings from real-world usage
**Date:** February 2026

---

## TL;DR

`moved`, `removed`, and `import` blocks work **within modules** but fail across Terraform Stacks boundaries (deployments, components, stacks). Users need declarative state management for cross-boundary operations.

**Priority Gaps:**
1. 🔥 **High:** Cross-deployment resource movement
2. 🔥 **High:** Incremental refactoring (test dev before prod)
3. 🟡 **Medium:** Cross-component movement
4. 🟡 **Medium:** Resource ownership model

---

## What Works Today ✅

| Feature | Status | Notes |
|---------|--------|-------|
| Rename resource in module | ✅ Works | `moved` block |
| Import existing resource | ✅ Works | `import` block, per-deployment via variables |
| Stop managing resource | ✅ Works | `removed` block with `destroy = false` |
| Convert count to for_each | ✅ Works | Multiple `moved` blocks |

---

## Critical Gaps ❌

### Gap 1: Cross-Deployment Movement 🔥 Priority: HIGH

**Problem:** Cannot move resources between deployments (dev → prod) declaratively

**Current Reality:**
```hcl
# This doesn't work
moved {
  from = deployment.dev.component.web.aws_instance.test
  to   = deployment.prod.component.web.aws_instance.promoted
}
```

**Why It Matters:**
- Each deployment has separate state
- `moved` blocks are state-scoped
- No mechanism to transfer across state boundaries

**User Impact:**
- Must manually coordinate `removed` + `import` (error-prone)
- Risk of time window where resource is unmanaged
- Cannot promote infrastructure from dev to prod without recreation

**Workaround (Manual):**
```hcl
# In dev module
removed {
  from = aws_instance.test
  lifecycle { destroy = false }
}

# In prod module
import {
  to = aws_instance.promoted
  id = "i-same-instance-id"
}
```

**Proposed Solution:**
```hcl
# Hypothetical stack-level syntax
refactoring {
  moved {
    from       = deployment.dev.component.web.aws_instance.test
    to         = deployment.prod.component.web.aws_instance.promoted
    migrate_id = true  # Keep AWS resource ID
  }
}
```

**Technical Requirements:**
- Stack orchestrator needs to coordinate state operations
- Atomic operation: remove from source state, add to target state
- Handle rollback if either operation fails
- Preserve resource ID and attributes

---

### Gap 2: Incremental Refactoring 🔥 Priority: HIGH

**Problem:** Refactoring applies to ALL deployments simultaneously, cannot test in dev first

**Current Reality:**
```hcl
# modules/web-server/refactoring.tf
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}

# Executes for dev, staging, prod ALL AT ONCE
```

**Why It Matters:**
- High risk: prod refactored without testing
- No rollback if prod fails
- Cannot validate approach incrementally

**User Impact:**
- Must accept all-or-nothing deployment of refactoring
- Hesitant to refactor production stacks
- Testing in isolated environments doesn't reflect actual behavior

**Proposed Solution:**
```hcl
# Deployment-scoped refactoring control
deployment "dev" {
  refactoring {
    enabled = true

    moved {
      from = aws_instance.web
      to   = aws_instance.web_server
    }
  }
}

deployment "prod" {
  refactoring {
    enabled = false  # Don't apply yet
  }
}
```

**Alternative Solution:**
```hcl
# Phase-based rollout
refactoring {
  phase = "preview"  # Options: preview, test, apply

  moved {
    from = aws_instance.web
    to   = aws_instance.web_server
  }
}

deployment "dev" {
  refactoring_phase = "apply"
}

deployment "prod" {
  refactoring_phase = "preview"  # Just show plan
}
```

**Technical Requirements:**
- Refactoring blocks need deployment-level scope
- Plan mode should show which deployments will execute
- State changes should be deployment-conditional

---

### Gap 3: Cross-Component Movement 🟡 Priority: MEDIUM

**Problem:** Cannot reorganize component boundaries without recreation

**Current Reality:**
```hcl
# This doesn't work
moved {
  from = component.web_server.aws_security_group.shared
  to   = component.networking.aws_security_group.shared
}
```

**Why It Matters:**
- Components are logical boundaries
- Refactoring architecture requires recreation
- Cannot separate concerns without downtime

**User Impact:**
- Component structure becomes rigid
- Difficult to extract shared resources
- Must use data sources as workaround

**Proposed Solution:**
```hcl
# Stack-level component refactoring
refactoring {
  moved {
    from       = component.web_server.aws_security_group.shared
    to         = component.networking.aws_security_group.shared
    deployments = "*"  # Apply to all deployments
  }
}
```

**Technical Requirements:**
- Component-aware state operations
- Handle provider differences between components
- Update component dependencies automatically

---

### Gap 4: Resource Ownership Model 🟡 Priority: MEDIUM

**Problem:** No way to declare which deployment should manage shared resources

**Current Reality:**
```
Dev deployment:  aws_s3_bucket.shared (bucket: "my-bucket")
Prod deployment: aws_s3_bucket.shared (bucket: "my-bucket")

# Both manage same bucket → conflict!
```

**Why It Matters:**
- Silent conflicts when multiple deployments manage same resource
- State drift
- Unpredictable applies

**User Impact:**
- Must manually track resource ownership
- Duplicate management causes conflicts
- No declarative way to express "prod owns this"

**Proposed Solution:**
```hcl
resource_ownership {
  resource "aws_s3_bucket.shared" {
    owner = deployment.prod

    # Dev gets read-only access
    access {
      deployment = deployment.dev
      mode       = "data_source"
    }
  }
}
```

**Technical Requirements:**
- Ownership declaration at stack level
- Automatic data source generation for non-owners
- Validation to prevent duplicate management
- Clear error messages for conflicts

---

### Gap 5: Cross-Stack Movement 🔵 Priority: LOW

**Problem:** Stacks are isolated, no resource transfer mechanism

**User Impact:** Must recreate resources when reorganizing stacks

**Proposed Solution:**
```hcl
# In target stack
import {
  from_stack  = "networking-stack"
  deployment  = "prod"
  resource    = "aws_vpc.main"

  to = aws_vpc.imported

  lifecycle {
    remove_from_source = true
  }
}
```

---

### Gap 6: Refactoring Preview/Diff 🔵 Priority: LOW

**Problem:** Cannot preview state changes before applying refactoring blocks

**Proposed Solution:**
```bash
terraform stacks refactoring plan

# Output:
# deployment.dev:
#   - moved: aws_instance.web → aws_instance.web_server
#   - removed: aws_security_group.old
#   - import: aws_eip.web (id: eipalloc-123)
#
# deployment.prod:
#   - moved: aws_instance.web → aws_instance.web_server
#   - removed: aws_security_group.old
#   - import: aws_eip.web (id: eipalloc-456)
```

---

### Gap 7: State Rollback 🔵 Priority: LOW

**Problem:** No way to undo failed refactoring

**Proposed Solution:**
```bash
terraform stacks state rollback \
  -deployment=dev \
  -to-configuration=stc-previous
```

---

## Implementation Priority

### Phase 1 (Must Have)
1. **Cross-deployment movement** - Enables dev-to-prod promotion
2. **Incremental refactoring** - Safe production refactoring

### Phase 2 (Should Have)
3. **Cross-component movement** - Architecture flexibility
4. **Resource ownership model** - Prevent conflicts

### Phase 3 (Nice to Have)
5. **Refactoring preview** - Better visibility
6. **State rollback** - Safety net
7. **Cross-stack movement** - Advanced use cases

---

## Technical Architecture Considerations

### State Management
- Deployments use separate state files
- Operations must be atomic across states
- Need transaction-like semantics for cross-state operations

### Scope Hierarchy
```
Stack
├── Deployment (dev, prod, staging)
│   └── Component (web, db, networking)
│       └── Module (resources)
```

- `moved`/`removed`/`import` work at **module level**
- Need stack-level operations for **deployment** and **component** levels

### Backward Compatibility
- New syntax should not break existing blocks
- Phased rollout with feature flags
- Clear migration path for users

---

## Real-World Example

**Scenario:** Promote tested instance from dev to prod

**Today (Manual, Error-Prone):**
1. Remove from dev state: `removed { from = aws_instance.test }`
2. Upload dev config
3. Apply dev changes
4. Import to prod: `import { to = aws_instance.promoted, id = "i-xxx" }`
5. Upload prod config
6. Apply prod changes
7. Clean up blocks
8. Upload again

**Desired (Declarative, Safe):**
```hcl
# Single operation
refactoring {
  moved {
    from = deployment.dev.component.web.aws_instance.test
    to   = deployment.prod.component.web.aws_instance.promoted
  }
}
```

---

## Success Metrics

**Engineering Metrics:**
- Zero manual state surgery for cross-deployment moves
- 100% of refactoring operations declarative
- Test-in-dev-first capability for all refactoring

**User Metrics:**
- Reduced time to refactor (from hours to minutes)
- Increased confidence in production refactoring
- Fewer state-related support tickets

---

## Open Questions for Implementation

1. **State transaction model:** How to handle partial failures in cross-state operations?
2. **Provider implications:** Do providers need to be aware of cross-boundary moves?
3. **Dependency tracking:** How to update cross-component references automatically?
4. **API design:** Should this be stack-level HCL or API-driven?
5. **Backwards compatibility:** Migration path for existing stacks?

---

## Testing Requirements

**Unit Tests:**
- Each refactoring operation type
- Error handling and rollback
- State validation

**Integration Tests:**
- Cross-deployment movement
- Cross-component movement
- Multi-deployment scenarios

**Real-World Validation:**
- Test with actual AWS resources
- Multi-region deployments
- Large state files (1000+ resources)

---

## References

**Full Documentation:** TERRAFORM-STACKS-REFACTORING-SUMMARY.md
**Live Example:** Executed with real AWS resources (dev/prod EC2, EIPs, SGs)
**Repository:** https://github.com/vansh-munjal-hash/terraform-web-stack

---

## Summary Table

| Gap | Impact | Priority | Effort | Proposed Solution |
|-----|--------|----------|--------|-------------------|
| Cross-deployment moves | 🔥 High | P0 | High | Stack-level `moved` block |
| Incremental refactoring | 🔥 High | P0 | Medium | Deployment-scoped refactoring |
| Cross-component moves | 🟡 Medium | P1 | High | Component-aware operations |
| Resource ownership | 🟡 Medium | P1 | Medium | Ownership declarations |
| Cross-stack moves | 🔵 Low | P2 | High | Cross-stack import |
| Refactoring preview | 🔵 Low | P2 | Low | `refactoring plan` command |
| State rollback | 🔵 Low | P2 | Medium | State versioning |

---

**For Questions:** Contact [team/maintainer]
**Next Steps:** Review proposed solutions, prioritize implementation
