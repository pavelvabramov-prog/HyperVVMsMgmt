# Changelog

## v1.1.2 (2026-11-18)

Changes compared with the original v1.1.0 release:

- **Shared VM selection:** introduced reusable selection context, candidate ordering and batch selection helpers, with VM GUID tracking and current-invocation exclusion of overlapping candidates.
- **hv-remove:** improved ambiguous-name selection and reporting, supports multiple selected candidates, preserves explicit final confirmation, and refines AD cleanup safety and `-KeepADAccount` behavior for list-file workflows.
- **hv-tags:** shared interactive multi-selection; CSV Hyper-V target preflight before writes; tags from each originating CSV row apply to its selected targets. Physical rows remain ordered. No transactional rollback is guaranteed for partial batch write failures.
- **hv-config:** earlier duplicate short-name rejection and selected VM identity safeguards.
- **hv-creds:** `-Help` and `/?` usage paths without prompting for credentials.
- **Diagnostics:** clearer selected/excluded candidate and overlapping-entry reporting.
- **Tests:** added focused regression scripts for shared selection, candidate ordering, reporting, AD safety and interactive tagging.

### Integration test evidence (test cluster)

- `hv-tags`: Add/Get/Remove with final tag-state restoration.
- `hv-config`: ValidateOnly and Apply, including guest rename, network configuration, domain join and reconnect.
- `hv-remove`: ValidateOnly and Apply, including verified cluster role, VM, VHDX and folder removal with `-KeepADAccount`.
- `hv-create`: duplicate-name rejection, successful ValidateOnly, then three VM creations with disk copies, network adapters, cluster roles and tag assignment; resulting VM objects and paths checked.
- `hv-inventory`: clustered VM inventory.

### Notes

- No new public parameters for shared candidate selection.
- Use `-KeepADAccount` for initial multi-VM removal tests. AD delete/reset with multi-selection has not been established by the above integration results.
- v1.1.2 release packaging was reviewed. Integration tests were performed against the test cluster; the packaged ZIP was not independently retested in the packaging environment
