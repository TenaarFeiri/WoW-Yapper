# Pipeline Breakpoint Sweep (2026-06-29)

Purpose: aggressively increase environment noise and throttle FPS to find the first profile that violates chat-selection invariants.

Harness:
- tools/2.0testsuites/test_editbox_pipeline_breakpoint_sweep.lua

Command:
- lua tools/2.0testsuites/test_editbox_pipeline_breakpoint_sweep.lua

Profile Grid:
- Noise levels: 0, 20, 40, 60, 75, 85, 92, 97, 100
- FPS levels: 240, 120, 60, 30, 15, 8, 4, 2, 1
- Total profiles: 81

Per Profile Workload:
- Rapid-switch iterations: 3200
- Whisper-spam iterations: 3600

Invariant Gates:
- WHISPER/BN_WHISPER must always resolve with target.
- CHANNEL must always resolve with target.
- Non-target chat types must not carry target/channelName.

Result:
- No invariant break found across 81/81 profiles.
- Stability held at the most extreme tested profile: noise=100, fps=1.

Extreme Profile Metrics (noise=100, fps=1):
1. Rapid-switch
- opens=3200
- sends=1680
- receives=2562
- captures=155
- consumes=34
- expires=121
- whisperPreserves=0
- sayFallbacks=72
- leaksPrevented=764

2. Whisper-spam
- opens=3600
- sends=3252
- receives=3600
- captures=3167
- consumes=2061
- expires=1106
- whisperPreserves=2847
- sayFallbacks=0
- leaksPrevented=0

Interpretation:
- Under this simulator, policy invariants are robust even under severe jitter and noisy event pressure.
- Expired affinity rises at low FPS/high noise as expected, but target-safety invariants remain intact.

Next Deepening Option:
- Introduce adversarial fault-injection (e.g., malformed chatType/target combos or forced out-of-order state writes) to probe beyond plausible runtime noise.
