# ShowRunner documentation

These are living documents. Update the relevant topic rather than adding dated
migration plans or test-session reports. Historical versions remain in Git.

- [Architecture](architecture.md): runtime boundaries and strict graph persistence.
- [Product status](product-parity.md): supported surfaces, deliberate exclusions and open work.
- [Testing](testing.md): local/CI checks, native fixtures, screenshots and benchmarks.
- [Live service testing](testing/live-services.md): demonstrated coverage, limits and isolation.
- [Connection setup and node testing](testing/live-nodes.md): local YAML and provider requirements.
- [Release and versioning policy](versioning-policy.md): manual preview, publish and asset rebuilds.
- [Release checklist](release-checklist.md): operator checks before publication.
- [Streamer.bot comparison](streamerbot-comparison.md): current capability gaps and priorities.
- [Chat and commands](chat-and-commands.md): managed command behavior, unified chat and OBS dock setup.
- [Heart rate](heart-rate.md): BLE devices, simulation and automation.
- [Dependency provenance](dependency-provenance.md): license and attribution boundaries.

Machine-readable evidence is maintained in [contract parity](parity.json),
[product surfaces](product-surface.json) and [node catalog](testing/node-catalog.json).
Those inventories describe coverage/contracts, not proof that every third-party
service has been exercised live.

Architecture decisions: [Remote boundary](architecture/adr-001-remote-agent.md),
[graph-only automations](architecture/adr-002-timeline.md),
[external plugins](architecture/adr-003-external-plugins.md),
[workspace tabs](architecture/adr-004-workspace-docking.md).
