# Scripts

These scripts are historical bring-up helpers, not polished end-user installers.

Read each script before running it. Several scripts perform offline Windows servicing, BCD edits, driver staging, or partition formatting when explicitly configured for a mounted Windows volume.

Safe default rule:

- Dump/read-only scripts are for diagnostics.
- Stage/install/repair scripts can modify an offline Windows installation.
- Apply/fresh/reinstall scripts may format or rebuild Windows partitions and should not be used without adapting paths and verifying the target volume.

All local absolute paths in this public copy were replaced with placeholders such as `<PROJECT_ROOT>`, `<WORKSPACE>`, and `<ARTIFACT_DIR>`.
