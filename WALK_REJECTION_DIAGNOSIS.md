# Real-walk rejection: 56 raw, 0 verified

Evidence read directly from the RMX3990 debug ledger after the user's reported 50-step walk.

| Bucket start UTC milliseconds | Raw | Credited | Reason | Walking hop fraction |
|---|---:|---:|---|---:|
|1794679070000|20|0|NOT_GAIT|0.2|
|1794679080000|15|0|NOT_GAIT|0.4|
|1794679090000|13|0|NOT_GAIT|0.2|
|1794679100000|8|0|NOT_GAIT|0.2|

Independent IMU peak counts sum to 55 across these 20 hops. Manual count reported: 50. Eight hops have asymmetry below 0.10, the impact gate. Six have periodicity r0 below 0.20 (including the end-of-walk transition). Carry estimate changes HAND_HELD -> BAG -> POCKET. Exact attribution of each UNKNOWN hop additionally requires the classifier score/context, so these gate counts are not mutually exclusive causal totals.

The UI's live VEHICLE label is not the reason these buckets were rejected. Every bucket above is NOT_GAIT. Activity Recognition after the walk reports STILL. Each bucket needs at least half its hops classified WALK/RUN; none qualified.

Conclusion: a real-world false rejection of reported genuine walking. This disproves any claim that the current Flutter demo reliably verifies normal walking across carrying positions. The hotspot and sync do not fix classifier accuracy.

No thresholds were changed and no rejected historical steps were converted to reward-eligible steps. Lowering/removing the impact gate based on this one walk could also allow rhythmic shaking; any candidate correction needs replay against both genuine and fake evidence. Preserve the existing counter/IMU cap and server downgrade-only rule.

Raw diagnostic copies are in diagnostics-local/ (gitignored). They are private device evidence, not fixtures for public publishing. The older prototype validation remains in GENUINE_STEP_ENGINE.md; its in-sample results must not be presented as this walk's accuracy.
