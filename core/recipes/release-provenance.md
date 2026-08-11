---
recipe_id: release-provenance
recipe_name: "Release provenance envelope — source, license, authority, and evidence"
applies_when: "A release includes third-party data/assets, regulated claims, external artifacts, affiliate relationships, privacy-sensitive behavior, or other policy-bound material"
severity: STRONG (when installed)
linked_rules:
  - quality-gates
  - operations
---

# Recipe — Release Provenance

> Opt-in evidence envelope, not a legal-compliance certification. Laws, contracts,
> licenses, and regulator expectations differ by product, jurisdiction, distribution
> channel, and date. The adopter owns the applicable policy and qualified approval;
> CONDUCTOR only makes missing or stale evidence visible.

## 1. Inventory policy-bound material

Record each third-party asset, dataset, model/output, external binary, disclosure,
claim, privacy-sensitive flow, payment/health/financial surface, and distribution
artifact that the project's policy identifies. Each entry includes:

- stable item ID and release snapshot;
- source/provenance and retrieval or generation method;
- owner/licensor/provider and asserted license or contractual basis;
- permitted use, redistribution/hosting constraints, attribution/disclosure duty;
- applicable project policy, jurisdiction/scope, policy version, and review date;
- approving authority, expiration/re-review condition, and fallback/removal plan;
- bounded evidence references without credentials or private source material.

Public availability, an API response, a logo provider, model output, or a search result
does not by itself establish permission to copy, rehost, endorse, or redistribute.

## 2. Fail closed on unknown authority

Unknown source, missing license, expired approval, changed content digest, absent
required disclosure, or an unreviewed policy scope is `verification-required` or
`blocked`. Do not infer legal permission, transfer user authority through an agent or
external message, or label a release compliant because technical tests passed.

## 3. Keep domain profiles separate

Projects may layer counsel- or policy-owner-approved profiles for brand/affiliate,
privacy, payments, health, financial, accessibility, export, or marketplace rules.
Those profiles name their jurisdiction, authority, version, effective date, required
evidence, and exceptions. One domain profile never becomes a universal rule for all
projects or all countries.

## 4. Release gate

Compare the current inventory with the previously approved release. New, removed,
changed, or expired entries require review. Bind the final decision and artifact
digests to the release snapshot. Technical provenance can be `passed`; legal or policy
scope not reviewed by the authorized owner remains `verification-required`.
