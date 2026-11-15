# Editor performance and memory baseline — 2026-11-15

This is an observed baseline, not a release budget. Future optimization claims
must compare the same workload, resolution, machine, runtime, and measurement
method or clearly explain the difference.

## Reference environment

- Windows 11 Pro build 26300 x64
- Intel Core i7-12700K, 20 logical processors
- NVIDIA GeForce RTX 3080, driver 32.0.16.2114
- 1440×900 configured editor window, vsync enabled
- Pinned Haxe/HashLink/Heaps/DX12 toolchain from `docs/TOOLCHAIN_VERSIONS.md`
- Development HashLink build (`bin/boltspark.hl`)

## Method

Executed:

```powershell
.\tests\native\Measure-EditorPerformance.ps1 -DurationMinutes 15 -SampleSeconds 5
```

The first minute remained idle at the baseline window size. From minute 1
through minute 15, the script alternated the window between 1280×800 and
1440×900 every sample to exercise swap-chain resize, layout, render-zone, font,
and retained-resource paths. It sampled process CPU, Windows GPU Engine
counters, working set, private bytes, and handle count. Opt-in in-application
telemetry accumulated frame deltas in allocation-free 60-second windows.

Raw local evidence was generated at
`bin/test-results/performance/20261115-054745/` (`samples.csv`, `summary.json`,
stdout, and stderr). Generated evidence remains ignored; the probe source and
this result record are tracked.

## Results

| Measurement | 1-minute idle snapshot | 15-minute final snapshot | Change |
|---|---:|---:|---:|
| Working set | 148,578,304 B (141.70 MiB) | 149,708,800 B (142.77 MiB) | +1,130,496 B (+1.08 MiB) |
| Private bytes | 174,755,840 B (166.66 MiB) | 172,351,488 B (164.37 MiB) | -2,404,352 B (-2.29 MiB) |
| Handles | 484 | 476 | -8 |
| Sample CPU | 3.666% | 3.804% | observational |
| Sample GPU Engine aggregate | 0.616% | 10.897% | resize workload active at final sample |

- Idle average CPU across the first-minute samples: **4.529%** normalized over
  20 logical processors.
- Resize-phase average CPU: **3.780%**.
- Idle GPU Engine samples averaged **10.130%** (range 0.616–32.659%); Windows'
  per-engine aggregate is noisy and is recorded as an observation, not a budget.
- Resize-phase GPU Engine samples averaged **10.756%**.
- The first 60-second frame window averaged **16.807 ms / 59.498 FPS**. It
  included startup and one 497.608 ms maximum outlier.
- Subsequent resize windows averaged approximately **16.7–16.9 ms** and
  **59.1–59.85 FPS**. Most maximum samples were about 53–68 ms, with two
  resize outliers at 116.672 ms and 143.418 ms.
- Resize-phase working set remained within 148,586,496–149,938,176 bytes;
  private bytes remained within 170,917,888–180,543,488 bytes.
- stderr was empty and shutdown completed normally.

## Conclusion

This 15-minute run shows **no unbounded process memory or handle growth** while
idle and repeatedly resizing. Working set ended 1.08 MiB above the one-minute
snapshot, private bytes ended 2.29 MiB lower, and handles decreased. This does
not replace longer soak tests, GPU-memory instrumentation, or representative
project workloads once asset and scene systems are integrated.
