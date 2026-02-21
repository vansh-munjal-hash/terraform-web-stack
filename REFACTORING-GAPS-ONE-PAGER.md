# Terraform Stacks Refactoring Gaps - Engineering Brief

**Audience:** Engineers working on Stacks improvements
**Purpose:** Actionable gap analysis
**Date:** February 2026

---

## TL;DR

`moved`, `removed`, and `import` blocks work **within modules** but fail across Stacks boundaries. Need declarative state management for cross-deployment/component/stack operations.

**Critical Gaps:** Cross-deployment moves, incremental testing, cross-component moves, ownership model

---

## What Works Today ✅

| Capability | Status | Block |
|------------|--------|-------|
| Rename resource in module | ✅ | `moved` |
| Import existing resource | ✅ | `import` |
| Stop managing (keep running) | ✅ | `removed` |
| Convert count → for_each | ✅ | `moved` |

---

## Gap 1: Cross-Deployment Movement 🔥 P0

**Problem:** Cannot move resources between deployments declaratively

```hcl
# Doesn't work
moved {
  from = deployment.dev.component.web.aws_instance.test
  to   = deployment.prod.component.web.aws_instance.promoted
}
```

**Impact:** Must manually coordinate `removed` + `import` (error-prone, time window where unmanaged)

**Proposed Solution:**
```hcl
refactoring {
  moved {
    from       = deployment.dev.component.web.aws_instance.test
    to         = deployment.prod.component.web.aws_instance.promoted
    migrate_id = true
  }
}
```

**Tech Requirements:**
- Atomic cross-state operations
- Preserve resource ID
- Rollback on failure

---

## Gap 2: Incremental Refactoring 🔥 P0

**Problem:** Refactoring hits ALL deployments simultaneously - cannot test dev before prod

```hcl
# This affects dev, staging, prod ALL AT ONCE
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}
```

**Impact:** High risk, no validation path, hesitant to refactor production

**Proposed Solution:**
```hcl
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

**Alternative:** Phase-based rollout (`phase = "preview" | "test" | "apply"`)

**Tech Requirements:**
- Deployment-scoped refactoring blocks
- Conditional execution based on deployment

---

## Gap 3: Cross-Component Movement 🟡 P1

**Problem:** Cannot reorganize component boundaries without recreation

```hcl
# Doesn't work
moved {
  from = component.web_server.aws_security_group.shared
  to   = component.networking.aws_security_group.shared
}
```

**Impact:** Component structure becomes rigid, difficult to extract shared resources

**Proposed Solution:**
```hcl
refactoring {
  moved {
    from       = component.web_server.aws_security_group.shared
    to         = component.networking.aws_security_group.shared
    deployments = "*"
  }
}
```

---

## Gap 4: Resource Ownership Model 🟡 P1

**Problem:** No way to declare which deployment manages shared resources

**Conflict Example:**
```
Dev:  aws_s3_bucket.shared (bucket: "my-bucket")
Prod: aws_s3_bucket.shared (bucket: "my-bucket")
# Both manage same bucket → conflict!
```

**Proposed Solution:**
```hcl
resource_ownership {
  resource "aws_s3_bucket.shared" {
    owner = deployment.prod

    access {
      deployment = deployment.dev
      mode       = "data_source"  # Read-only
    }
  }
}
```

---

## Additional Gaps (Lower Priority)

| Gap | Priority | Impact |
|-----|----------|--------|
| Cross-stack movement | P2 | Must recreate when reorganizing stacks |
| Refactoring preview | P2 | Can't see state changes before apply |
| State rollback | P2 | No undo for failed refactoring |

---

## Implementation Priority

### Phase 1 (P0 - Must Have)
1. Cross-deployment movement
2. Incremental refactoring

### Phase 2 (P1 - Should Have)
3. Cross-component movement
4. Resource ownership model

### Phase 3 (P2 - Nice to Have)
5. Refactoring preview command
6. State rollback capability
7. Cross-stack transfers

---

## Real-World Impact

**Today (Manual):**
1. Remove from dev: `removed { from = aws_instance.test }`
2. Upload dev → Apply
3. Import to prod: `import { to = aws_instance.promoted, id = "i-xxx" }`
4. Upload prod → Apply
5. Clean up blocks
6. Upload again

**Desired (Declarative):**
```hcl
refactoring {
  moved {
    from = deployment.dev.component.web.aws_instance.test
    to   = deployment.prod.component.web.aws_instance.promoted
  }
}
```

---

## Success Metrics

**Engineering:**
- Zero manual state surgery for cross-deployment moves
- 100% declarative refactoring operations
- Test-in-dev capability for all refactoring

**User:**
- Hours → minutes refactoring time
- Increased production refactoring confidence
- Fewer state-related support tickets

---

## Technical Considerations

**State Architecture:**
- Deployments use separate state files
- Need transaction-like semantics for cross-state operations
- Atomic remove + add across boundaries

**Scope Hierarchy:**
```
Stack
├── Deployment (dev/prod/staging)
│   └── Component (web/db/network)
│       └── Module (resources)
```

`moved`/`removed`/`import` work at **module level** → Need **stack/deployment/component level** operations

---

## Open Questions

1. How to handle partial failures in cross-state operations?
2. Provider implications for cross-boundary moves?
3. Automatic dependency updates for cross-component refs?
4. API surface: Stack-level HCL or API-driven?
5. Backwards compatibility strategy?

---

## Summary Table

| Gap | Priority | Effort | User Impact |
|-----|----------|--------|-------------|
| Cross-deployment moves | P0 | High | 🔥 Can't promote dev→prod |
| Incremental refactoring | P0 | Medium | 🔥 Can't test before prod |
| Cross-component moves | P1 | High | 🟡 Rigid architecture |
| Resource ownership | P1 | Medium | 🟡 Silent conflicts |
| Cross-stack moves | P2 | High | 🔵 Recreate required |
| Refactoring preview | P2 | Low | 🔵 Blind changes |
| State rollback | P2 | Medium | 🔵 No undo |

---

**Full Reference:** TERRAFORM-STACKS-REFACTORING-SUMMARY.md
**Repository:** https://github.com/vansh-munjal-hash/terraform-web-stack
