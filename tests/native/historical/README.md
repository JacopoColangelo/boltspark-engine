# Historical native interaction probes

These are the exact PowerShell probe sources cited by the 2026-11-12 through
2026-11-14 transform/window acceptance evidence. They were recovered from the
previously ignored `bin/` evidence workspace so the source is no longer lost.
They preserve historical inputs—including the superseded 1/2/3 shortcuts—and
are primarily provenance for those results. Run them against the corresponding
historical revision when exact reproduction is required; use the maintained
top-level probes for current acceptance.

Run a standalone probe through the staging wrapper, for example:

```powershell
.\tests\native\Invoke-HistoricalProbe.ps1 verify-transform-gizmo
```

The wrapper copies the tracked source to ignored `bin/` before execution because
these historical scripts derive their runtime and evidence paths from
`PSScriptRoot`. New probes should instead follow the self-contained pattern in
the parent `tests/native/` directory and write to `bin/test-results/` directly.

`verify-gizmo-drag` expects an already running probe-mode development editor;
the other tracked scripts start the process they need. These probes use
window-addressed Win32 messages, not global input injection.
