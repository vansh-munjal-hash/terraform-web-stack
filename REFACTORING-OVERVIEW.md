# Terraform Stacks Refactoring: Complete Overview

Quick navigation for all refactoring documentation in this stack.

---

## 📚 Documentation Index

### For Daily Use
1. **[REFACTORING-CHEATSHEET.md](REFACTORING-CHEATSHEET.md)** - Quick syntax reference
2. **[REFACTORING-GUIDE.md](REFACTORING-GUIDE.md)** - Complete how-to guide
3. **[modules/web-server/refactoring.tf.example](modules/web-server/refactoring.tf.example)** - Copy-paste examples

### For Understanding Capabilities
4. **[LIVE-REFACTORING-EXAMPLE.md](LIVE-REFACTORING-EXAMPLE.md)** - Hands-on walkthrough
5. **[STATE-SURGERY-ANALYSIS.md](STATE-SURGERY-ANALYSIS.md)** - What works, what doesn't, gaps

---

## 🎯 Quick Start

### I want to...

**Rename a resource**
```hcl
# modules/web-server/refactoring.tf
moved {
  from = aws_instance.web
  to   = aws_instance.web_server
}
```
📖 See: [REFACTORING-CHEATSHEET.md](REFACTORING-CHEATSHEET.md#rename-a-resource)

**Import existing AWS resource**
```hcl
# modules/web-server/refactoring.tf
import {
  to = aws_instance.existing
  id = "i-1234567890abcdef0"
}
```
📖 See: [REFACTORING-CHEATSHEET.md](REFACTORING-CHEATSHEET.md#import-existing-ec2)

**Stop managing a resource (keep it running)**
```hcl
# modules/web-server/refactoring.tf
removed {
  from = aws_instance.legacy
  lifecycle { destroy = false }
}
```
📖 See: [REFACTORING-CHEATSHEET.md](REFACTORING-CHEATSHEET.md#stop-managing-keep-running)

---

## 📊 Capability Matrix

| Task | Supported | Where | Doc Link |
|------|-----------|-------|----------|
| Rename resource in module | ✅ | Module | [Guide](REFACTORING-GUIDE.md#using-moved-blocks) |
| Move resource between modules | ✅ | Module | [Guide](REFACTORING-GUIDE.md#example-moving-resource-into-a-module) |
| Import existing AWS resource | ✅ | Module | [Guide](REFACTORING-GUIDE.md#using-import-blocks) |
| Stop managing resource | ✅ | Module | [Guide](REFACTORING-GUIDE.md#using-removed-blocks) |
| Convert count to for_each | ✅ | Module | [Guide](REFACTORING-GUIDE.md#example-refactoring-with-for_each) |
| Move between deployments | ❌ | N/A | [Analysis](STATE-SURGERY-ANALYSIS.md#scenario-4-move-resource-between-deployments-dev--prod-) |
| Move between components | ❌ | N/A | [Analysis](STATE-SURGERY-ANALYSIS.md#scenario-5-move-resource-between-components-) |
| Move between stacks | ❌ | N/A | [Analysis](STATE-SURGERY-ANALYSIS.md#scenario-6-move-resource-between-stacks-) |
| Test refactoring in dev only | ❌ | N/A | [Analysis](STATE-SURGERY-ANALYSIS.md#scenario-7-bulk-refactoring-across-deployments-) |

---

## 🔥 Common Scenarios

### Scenario 1: Adopting Existing Infrastructure

**Goal:** Your team manually created EC2 instances. You want Terraform to manage them.

**Solution:** Use `import` blocks

**Steps:**
1. Find instance IDs: `aws ec2 describe-instances`
2. Add import block with instance ID
3. Add resource definition matching existing config
4. Upload and apply

📖 **Full Example:** [LIVE-REFACTORING-EXAMPLE.md - Part 1](LIVE-REFACTORING-EXAMPLE.md#part-1-setup---create-test-resource-to-import)

---

### Scenario 2: Cleaning Up Naming

**Goal:** Rename `aws_instance.web` to `aws_instance.web_server` for consistency

**Solution:** Use `moved` blocks

**Steps:**
1. Add moved block: `from = aws_instance.web`, `to = aws_instance.web_server`
2. Rename resource in code
3. Update all references
4. Upload and apply
5. Remove moved block

📖 **Full Example:** [LIVE-REFACTORING-EXAMPLE.md - Part 3](LIVE-REFACTORING-EXAMPLE.md#part-3-add-refactoring-blocks)

---

### Scenario 3: Handing Off Resources

**Goal:** Another team will manage a security group. Keep it running but stop Terraform management.

**Solution:** Use `removed` blocks

**Steps:**
1. Add removed block with `destroy = false`
2. Remove resource definition from code
3. Upload and apply
4. Resource stays in AWS, removed from state

📖 **Full Example:** [LIVE-REFACTORING-EXAMPLE.md - Part 9](LIVE-REFACTORING-EXAMPLE.md#part-9-demonstrating-removed-block)

---

### Scenario 4: Moving Between Deployments ⚠️

**Goal:** Move a resource from dev deployment to prod deployment

**Status:** ❌ **Not Supported**

**Workaround:**
1. Use `removed` block in dev (keep resource running)
2. Use `import` block in prod (same resource ID)
3. Coordinate timing carefully

📖 **Analysis:** [STATE-SURGERY-ANALYSIS.md - Gap 1](STATE-SURGERY-ANALYSIS.md#gap-1-cross-deployment-movement-)

---

## 🚨 Critical Limitations

### ❌ What DOESN'T Work

1. **Cross-deployment movement**
   - Can't move resources from dev → prod declaratively
   - Workaround: `removed` + `import` manually coordinated

2. **Cross-component movement**
   - Can't reorganize components without recreating resources
   - Must destroy and recreate

3. **Incremental testing**
   - Refactoring applies to ALL deployments at once
   - Can't test in dev before prod

4. **Cross-stack transfers**
   - Stacks are isolated
   - Must recreate resources or manual state surgery

📖 **Full Gap Analysis:** [STATE-SURGERY-ANALYSIS.md](STATE-SURGERY-ANALYSIS.md#critical-gaps)

---

## 💡 Best Practices

### ✅ Do This

- **Always commit to git** before refactoring
- **Test syntax locally** with `terraform stacks validate`
- **Review plans carefully** in HCP Terraform UI
- **Remove refactoring blocks** after successful apply
- **Document why** you're refactoring (comments or commit message)

### ❌ Avoid This

- **Don't leave refactoring blocks** permanently in code
- **Don't combine multiple refactorings** in one upload
- **Don't refactor without backups** (git + state backups)
- **Don't skip reviewing** the plan before applying
- **Don't edit state files manually** unless absolutely necessary

📖 **Full Best Practices:** [REFACTORING-GUIDE.md - Best Practices](REFACTORING-GUIDE.md#best-practices)

---

## 📋 Workflow Checklist

When doing any refactoring:

- [ ] **Commit current code** to git
- [ ] **Add refactoring blocks** to module
- [ ] **Update resource definitions** as needed
- [ ] **Validate locally**: `terraform stacks validate`
- [ ] **Upload config**: `terraform stacks configuration upload ...`
- [ ] **Review plan** in HCP Terraform UI
- [ ] **Check all deployments** will behave correctly
- [ ] **Apply changes** (through UI or auto-apply)
- [ ] **Verify success** (check AWS resources)
- [ ] **Remove refactoring blocks**
- [ ] **Upload again** to clean up
- [ ] **Commit final code** to git

📖 **Detailed Workflow:** [REFACTORING-GUIDE.md - Workflow](REFACTORING-GUIDE.md#workflow)

---

## 🛠️ Useful Commands

### Validation
```bash
# Validate stack configuration
terraform stacks validate
```

### Upload
```bash
# Upload configuration to HCP Terraform
terraform stacks configuration upload \
  -organization-name=vansh-org \
  -project-name=Claude-Test \
  -stack-name=claude-stack-1
```

### AWS CLI Helpers
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
```

📖 **More Commands:** [REFACTORING-CHEATSHEET.md - AWS CLI Helpers](REFACTORING-CHEATSHEET.md#aws-cli-helpers)

---

## 📖 Reading Guide

### If you're new to refactoring blocks:
1. Start with **[REFACTORING-CHEATSHEET.md](REFACTORING-CHEATSHEET.md)** - get the basics
2. Read **[REFACTORING-GUIDE.md](REFACTORING-GUIDE.md)** - understand details
3. Try **[LIVE-REFACTORING-EXAMPLE.md](LIVE-REFACTORING-EXAMPLE.md)** - hands-on practice

### If you need to refactor NOW:
1. **[REFACTORING-CHEATSHEET.md](REFACTORING-CHEATSHEET.md)** - copy syntax
2. **[modules/web-server/refactoring.tf.example](modules/web-server/refactoring.tf.example)** - copy examples
3. Modify and go!

### If you're hitting limitations:
1. **[STATE-SURGERY-ANALYSIS.md](STATE-SURGERY-ANALYSIS.md)** - understand gaps
2. Check if your scenario is listed
3. See proposed workarounds or alternatives

### If you want to understand what's possible:
1. **[STATE-SURGERY-ANALYSIS.md](STATE-SURGERY-ANALYSIS.md)** - comprehensive analysis
2. See what works vs what doesn't
3. Review proposed stack-level features

---

## 🎓 Learning Path

### Beginner
- [ ] Read [REFACTORING-CHEATSHEET.md](REFACTORING-CHEATSHEET.md)
- [ ] Understand `moved`, `removed`, `import` syntax
- [ ] Try renaming a resource in a test module

### Intermediate
- [ ] Read [REFACTORING-GUIDE.md](REFACTORING-GUIDE.md)
- [ ] Complete [LIVE-REFACTORING-EXAMPLE.md](LIVE-REFACTORING-EXAMPLE.md)
- [ ] Import an existing AWS resource
- [ ] Practice with all three block types

### Advanced
- [ ] Read [STATE-SURGERY-ANALYSIS.md](STATE-SURGERY-ANALYSIS.md)
- [ ] Understand deployment/component/stack boundaries
- [ ] Learn workarounds for cross-deployment scenarios
- [ ] Contribute to gap analysis or proposals

---

## 🐛 Troubleshooting

### Common Errors

**"Resource not found in state"**
- The `from` address doesn't exist
- Check with `terraform state list` or HCP UI
- Verify exact resource address

**"Resource already exists"**
- The `to` address already exists
- Might have already been moved
- Remove the moved block

**"Configuration doesn't match"**
- Import block config doesn't match AWS resource
- Use `aws ec2 describe-*` to inspect
- Match configuration exactly

📖 **Full Troubleshooting:** [REFACTORING-GUIDE.md - Troubleshooting](REFACTORING-GUIDE.md#troubleshooting)

---

## 📞 Getting Help

### Internal Resources
- **[REFACTORING-GUIDE.md](REFACTORING-GUIDE.md)** - comprehensive guide
- **[STATE-SURGERY-ANALYSIS.md](STATE-SURGERY-ANALYSIS.md)** - gap analysis
- **[LIVE-REFACTORING-EXAMPLE.md](LIVE-REFACTORING-EXAMPLE.md)** - working example

### External Resources
- [Terraform moved Block Docs](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring)
- [Terraform import Block Docs](https://developer.hashicorp.com/terraform/language/import)
- [Terraform removed Block Docs](https://developer.hashicorp.com/terraform/language/resources/syntax#removing-resources)
- [Terraform Stacks Docs](https://developer.hashicorp.com/terraform/language/stacks)

---

## 🔮 Future Enhancements

See [STATE-SURGERY-ANALYSIS.md - Stack-Level Support Proposals](STATE-SURGERY-ANALYSIS.md#stack-level-support-proposals) for detailed proposals including:

- Stack-scoped refactoring blocks
- Resource ownership declarations
- Refactoring phases (preview/test/apply)
- Cross-deployment/component/stack movement
- State rollback capabilities

---

## 📝 Quick Reference Card

```
┌─────────────────────────────────────────────────────────────┐
│                    Refactoring Quick Card                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  RENAME:           moved { from = X, to = Y }              │
│  IMPORT:           import { to = X, id = "aws-id" }        │
│  ORPHAN:           removed { from = X, destroy = false }   │
│                                                             │
│  WHERE:            modules/web-server/refactoring.tf       │
│  VALIDATE:         terraform stacks validate               │
│  UPLOAD:           terraform stacks configuration upload   │
│  CLEANUP:          rm refactoring.tf && upload again       │
│                                                             │
│  ✅ Works:         Within module/deployment                 │
│  ❌ Doesn't work:  Cross-deployment/component/stack         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Summary

This repository contains complete documentation for using `moved`, `removed`, and `import` blocks with Terraform Stacks:

- **What works:** Module-level refactoring, importing resources, orphaning resources
- **What doesn't:** Cross-deployment/component/stack movement, incremental testing
- **Workarounds:** Manual coordination of `removed` + `import` for cross-boundary scenarios
- **Proposals:** Stack-level features to address gaps

All documentation is in this directory. Start with the [REFACTORING-CHEATSHEET.md](REFACTORING-CHEATSHEET.md) for quick reference.
