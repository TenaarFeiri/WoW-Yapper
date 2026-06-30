# Pipeline Stress Baseline (2026-06-29)

Purpose: establish a first-pass, non-optimized baseline for chat pipeline stability before optimization work.

Harness:
- tools/2.0testsuites/test_editbox_pipeline_stress_sim.lua

Command:
- lua tools/2.0testsuites/test_editbox_pipeline_stress_sim.lua

Result:
- 58798/58798 passed

Scenario Metrics

1. pipeline-rapid-switch/optimal/low
- opens=3500
- sends=1922
- receives=0
- captures=0
- consumes=0
- expired=0
- whisperFallbackPreserved=0
- sayFallbacks=83
- leakPreventions=908

2. pipeline-rapid-switch/optimal/high
- opens=3500
- sends=1918
- receives=0
- captures=0
- consumes=0
- expired=0
- whisperFallbackPreserved=0
- sayFallbacks=83
- leakPreventions=924

3. pipeline-rapid-switch/noisy/low
- opens=3500
- sends=1940
- receives=1033
- captures=42
- consumes=26
- expired=16
- whisperFallbackPreserved=0
- sayFallbacks=69
- leakPreventions=907

4. pipeline-rapid-switch/noisy/high
- opens=3500
- sends=1889
- receives=1061
- captures=52
- consumes=24
- expired=28
- whisperFallbackPreserved=0
- sayFallbacks=79
- leakPreventions=921

5. pipeline-whisper-spam/optimal/low
- opens=4200
- sends=2504
- receives=4200
- captures=3298
- consumes=2158
- expired=1140
- whisperFallbackPreserved=2755
- sayFallbacks=0
- leakPreventions=0

6. pipeline-whisper-spam/optimal/high
- opens=4200
- sends=2548
- receives=4200
- captures=3230
- consumes=2119
- expired=1111
- whisperFallbackPreserved=2724
- sayFallbacks=0
- leakPreventions=0

7. pipeline-whisper-spam/noisy/low
- opens=4200
- sends=2557
- receives=4200
- captures=3247
- consumes=2114
- expired=1133
- whisperFallbackPreserved=2670
- sayFallbacks=0
- leakPreventions=0

8. pipeline-whisper-spam/noisy/high
- opens=4200
- sends=2524
- receives=4200
- captures=3278
- consumes=2078
- expired=1200
- whisperFallbackPreserved=2783
- sayFallbacks=0
- leakPreventions=0

Notes
- This baseline intentionally favors observability over optimization.
- Seeds are deterministic per scenario name for reproducible comparisons.
