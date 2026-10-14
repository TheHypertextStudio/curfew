# Curfew privacy reference

The public [Privacy Policy](https://curfew.hypertext.studio/privacy) and
[Data Retention Policy](https://curfew.hypertext.studio/retention) are authored in
`landing/src/content/privacy.html` and `landing/src/content/retention.html`.
Their native Astro routes and `/legal/history` preserve stable policy links and
prior documents. Maintain these sources together when information flows change;
do not treat uninstalling as deletion of hosted accounts or shared containers.

Curfew supports accountless local use. Optional encrypted account sync still
processes identity, device, billing, authorization, routing, and audit metadata.
Connecting an assistant or enabling task review can disclose information to that
service, independently of encrypted sync. Account deletion does not remove
assistant, Docket/Athena, iCloud, payment-provider, or local copies.

Implementation references:

- [Audit log](Documentation/audit-log.md): decision metadata, rotation, and storage.
- [Presence detection](Documentation/presence-detection.md): optional camera frames
  stay in memory, with no identification, storage, or upload.
- [Coordinator status](Documentation/curfew-sync-status.md): optional reporting to
  a user-chosen HTTPS server, without reflections or camera frames.
- [Curfew Sync](Documentation/curfew-sync.md): hosted sync, recovery, and remote
  control; coordinator implementation lives in the separate `curfew-sync` repo.

Official legal and privacy contact: legal@hypertext.studio. Ordinary support:
hello@hypertext.studio.
