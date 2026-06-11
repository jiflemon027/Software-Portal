---
project: Software Portal
version: 1.0
created: 2026-06-11
last_updated: 2026-06-11
status: initialized
---

# Software Portal

## Overview

Software Portal is a BigFix platform dashboard suite for managing, maintaining, and dispatching role-aware fixlets. It enables BigFix administrators to rapidly copy installation fixlets from external sources, associate them with user roles, and deploy them to appropriate target groups with confidence in default deployment options.

## Purpose

Enable rapid copy-through-categorization-to-deploy workflow for software installation fixlets in BigFix.

## Primary Features

### 1. **Copier Dashboard**
Copy installation fixlets from external locations into the BigFix Custom site "Dereso Software Portal".

### 2. **Modifier Dashboard**
- Create associations between user roles and software access permissions
- Modify fixlet relevance rules to enforce role-based conditions
- Update fixlet descriptions to reflect role-specific context

### 3. **Dispatcher Dashboard**
- Deploy fixlets to appropriate target groups
- Auto-select default deployment options (installer, target group, expiration)
- Automatically create 'offer' style deployments with auto-derived category

## Technology Stack

- **BigFix Platform** — Core platform
- **BigFix API** — REST API integration
- **ActionScript** — BigFix fixlet scripting language
- **Relevance** — BigFix relevance language
- **JavaScript** — Client-side dashboard logic

## End Users

BigFix administrators managing software deployment and access control.

## Success Criteria

Enable rapid copy-through-categorization-to-deploy of software installers. Reduce manual workflow time by centralizing all three operations (copy, categorize, deploy) into unified dashboards.

## Timeline

1 month to MVP completion.

## Constraints & Dependencies

- Must integrate with existing BigFix instance (Dereso custom site)
- Requires BigFix admin access to create/modify fixlets
- Role-based access control must be enforced by relevance logic
- Default deployment options must be safe and well-tested before auto-selection

## Success Metrics

- ✅ All three dashboards functional and tested
- ✅ Copier can successfully import fixlets from external sources
- ✅ Modifier can create role-fixlet associations and update relevance rules
- ✅ Dispatcher can deploy fixlets and auto-create offers
- ✅ BigFix admins can execute full workflow in < 5 minutes per fixlet

---

## Team & Context

- **Version**: 1.0
- **Last Updated**: 2026-06-11
- **Created**: 2026-06-11
- **Current Phase**: Project Initialization
