# Prepare a website hostname

Use the manual **Prepare website domain** GitHub workflow on main to attach a
configured hostname to the existing `curfew-landing` Pages project. Supply the
reviewed configuration source commit and manifest hash used by the native and
backend releases. The workflow installs that source's exact cf package and
validates its generated configuration artifact before operating on Pages.

Run `status`, then `preview`, then `attach`. The hostname comes from the
production website origin in the artifact. Preview uses cf's deployment-free
dry-run. Attachment preserves all existing domains; rerunning reads an existing
attachment instead of creating another. A successful attachment can remain
pending until DNS and certificate validation finish. Run status again and
verify public DNS and HTTPS before treating the hostname as active.

The existing website token operates on Pages. DNS for a new zone may require
the separately approved zone credential. Do not expand either token merely to
combine those operations. The workflow does not publish assets, modify DNS,
redirect the old website, deploy account services, or revoke authorization.
Those actions belong to the coordinated migration after its readiness gates.

Validate changes with `node --test scripts/pages-domain.test.mjs` and actionlint.
Failure to inspect the project or verify the artifact stops attachment. If
attachment itself fails, inspect status before retrying; a provider may have
accepted the request before the client lost its response. Rollback before
cutover consists of leaving the existing public domain active and removing only
the newly added attachment if necessary. Never remove the old public redirect
hostname as part of migration cleanup.
