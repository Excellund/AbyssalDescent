# GitHub Actions storage

Keep the complete gameplay and release checks. Use short-lived Actions artifacts for investigation and direct GitHub Release assets for published versions. The local desktop playtest exporter does not consume Actions artifact storage.

## AbyssalDescent policy

- Passing regression logs: one day, downloaded promptly when checkpoint evidence is needed.
- Unsuccessful regression logs: seven days, subject to the repository retention limit.
- Log files use compression level 9; copied projects, saves and executables are excluded.
- Artifact upload is best-effort. Test failures still fail validation, while an upload quota or service failure cannot block an otherwise passing release.
- Branch checks, PR merge checks, full regression coverage and the release dependency remain in place.

These workflow changes take effect for runs using the updated commit. Older branches and tags keep their own workflow definitions. Retention changes do not shorten the lifetime of artifacts already uploaded.

## Account audit, September 14, 2026

The GitHub API inventory of all 20 repositories owned by `Excellund` found:

| Repository / artifact category | Count | Stored bytes |
| --- | ---: | ---: |
| AbyssalDescent gameplay logs | 27 | 4,631,333 |
| Project-Farhand Windows debug builds | 58 | 2,848,664,981 |
| Project-Farhand diagnostics and screenshots | 115 | 44,395,489 |
| Other owned repositories' artifacts | 0 | 0 |

Project-Farhand accounted for 99.84% of current artifact bytes across these repositories. It uploaded a roughly 45–54 MB Windows debug build after every successful CI run, with seven-day retention. AbyssalDescent had no Actions caches; Farhand had one 2,708,285-byte cache. This inventory is a current artifact snapshot, not the account billing meter. The authenticated CLI lacks permission to read the billing report, so the reported 90% usage was not independently verified.

The owner-approved Farhand policy keeps all existing validation and export steps but uploads executable builds only when explicitly requested through manual dispatch, with one-day retention. Diagnostics remain available for seven days and screenshots for three. That workflow is maintained in Farhand; changes to this repository do not update other repositories' workflows.

## Immediate recovery and prevention

Following explicit owner approval, 55 older Farhand executable bundles were deleted on September 14, freeing 2,687,955,782 bytes (about 2.69 GB). A fresh inventory verified all 118 protected artifacts remained: the three newest successful debug builds (two main checkpoints and the newest branch build), plus all 115 diagnostic bundles and screenshots. Farhand's current artifact storage fell to 205,104,688 bytes. AbyssalDescent artifacts were preserved. Retained existing builds keep their original September 17 expiration dates. Artifact deletion is permanent; obtain owner confirmation for any future manual cleanup.

For future development, request downloadable executable artifacts only when needed and download them within their retention window. Keep published versions in GitHub Releases. Continue normal local playtesting and all CI validation. Review the account's Actions storage usage in Billing, including other private repositories and Packages, before raising a paid budget.

GitHub distinguishes current stored bytes from accrued monthly storage usage: deleting artifacts stops their future storage accumulation but does not remove usage already recorded for the month. Usage reporting may take 6–12 hours to update. Actions artifacts and Packages share an allowance; Actions caches use a separate allowance, so clearing a small dependency cache does not address the executable backlog.

Sources: [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [artifact retention settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-repository), and [upload-artifact inputs](https://github.com/actions/upload-artifact#inputs).
