# Adversarial Fault Injection Report (2026-06-29)

Purpose: intentionally inject impossible/out-of-order state faults and classify failure types plus downstream consequences.

Harness:
- tools/2.0testsuites/test_editbox_pipeline_adversarial_fault_injection.lua

## Key Finding

A latent policy weakness was discovered and fixed during this run:
- Whisper resolution could carry stale channelName metadata if upstream state was corrupted.
- Fix applied in Src/Policies/ChannelPolicy.lua: whisper selections now always clear channelName.

Targeted repro (before fix):
- pendingTabSwitch chatType=WHISPER, target=Alice, channelName=Trade
- result: WHISPER target=Alice channelName=Trade

After fix:
- WHISPER channelName is always nil.

## Campaign Configuration

1. adversarial-extreme-1fps
- iterations=12000
- faultIntensity=78

2. adversarial-extreme-2fps
- iterations=12000
- faultIntensity=82

3. adversarial-extreme-4fps
- iterations=12000
- faultIntensity=86

Fault classes injected:
- lastused-poison-whisper-nil
- pending-frame-crosswire
- blizz-target-blank
- malformed-affinity-empty-target
- stale-affinity-wrong-type
- forced-frame-target-dropout
- pre-open-ui-state-corruption
- stale-target-injection
- post-resolve-target-flip
- post-resolve-whisper-collapse
- post-resolve-channel-target-drop

## Results After Fix

1. adversarial-extreme-1fps
- faultsInjected=9637
- divergenceCount=987
- divergenceByType: chatType=417, target=987, channelName=0
- maxRecoverySteps=4
- unrecoveredAtEnd=false
- whisperCollapseVsControl=417
- stickyDriftEvents=2805
- hardFailureTotal=578
- hardFailureTypes:
  - faulted:channel-without-target=174
  - faulted:non-target-with-target=404

2. adversarial-extreme-2fps
- faultsInjected=10086
- divergenceCount=1021
- divergenceByType: chatType=435, target=1021, channelName=0
- maxRecoverySteps=5
- unrecoveredAtEnd=true (activeDivergenceSpan=1)
- whisperCollapseVsControl=435
- stickyDriftEvents=2928
- hardFailureTotal=589
- hardFailureTypes:
  - faulted:channel-without-target=172
  - faulted:non-target-with-target=417

3. adversarial-extreme-4fps
- faultsInjected=10660
- divergenceCount=1126
- divergenceByType: chatType=439, target=1126, channelName=0
- maxRecoverySteps=4
- unrecoveredAtEnd=false
- whisperCollapseVsControl=439
- stickyDriftEvents=3051
- hardFailureTotal=685
- hardFailureTypes:
  - faulted:channel-without-target=207
  - faulted:non-target-with-target=478

## Failure Type Interpretation

Observed hard failures are dominated by deliberately injected post-resolve corruption:
- post-resolve-target-flip drives non-target-with-target failures.
- post-resolve-channel-target-drop drives channel-without-target failures.

This indicates:
- Core policy resolution is resilient under adversarial pre-open noise.
- The most dangerous downstream consequences come from state corruption after resolve.

## Downstream Consequences to Prioritize

1. Whisper-to-SAY collapse under post-resolve corruption
- Present as divergence chatType mismatch and whisperCollapseVsControl counts.

2. Sticky state drift
- stickyDriftEvents are high; corrupted post-resolve writes pollute future opens.

3. Short-lived but frequent divergence
- maxRecoverySteps remained low (4-5), but divergence frequency is non-trivial.

## Recommendation Focus

1. Guard post-resolve writes before commit/send
- Enforce type-target invariants immediately before persisting LastUsed.

2. Add a commit-time sanitizer
- If chatType is non-target, force target/channelName=nil.
- If chatType is CHANNEL with nil target, demote to SAY before commit.
- If chatType is WHISPER/BN_WHISPER with nil target, demote to SAY before commit.

3. Add a self-heal on next open
- If persisted LastUsed is invalid, sanitize it in place once and continue.
