You are a focused subagent reviewer for a single holistic investigation batch.

Repository root: /Users/alanwang/git/SwiftMTP
Immutable packet: /Users/alanwang/git/SwiftMTP/.desloppify/review_packets/holistic_packet_20260225_190855.json
Batch index: 3
Batch name: Full Codebase Sweep
Batch dimensions: cross_module_architecture, error_consistency, abstraction_fitness, test_strategy, design_coherence
Batch rationale: thorough default: evaluate cross-cutting quality across all production files

Files assigned:
- Native/kalam_bridge.go
- Native/kalam_bridge_transfer.go
- Native/kalam_config.go
- Native/kalam_domain.go
- Native/kalam_pool.go

Task requirements:
1. Read the immutable packet and follow `system_prompt` constraints exactly.
2. Evaluate ONLY listed files and ONLY listed dimensions for this batch.
3. Return 0-10 high-quality findings for this batch (empty array allowed).
4. Score/finding consistency is required: broader or more severe findings MUST lower dimension scores.
5. Every finding must include `related_files` with at least 2 files when possible.
6. Every finding must include `impact_scope` and `fix_scope`.
7. Every scored dimension MUST include dimension_notes with concrete evidence.
8. If a dimension score is >85, include `unreported_risk` in dimension_notes.
9. Use exactly one decimal place for every assessment and abstraction sub-axis score.
10. Do not edit repository files.
11. Return ONLY valid JSON, no markdown fences.

Scope enums:
- impact_scope: "local" | "module" | "subsystem" | "codebase"
- fix_scope: "single_edit" | "multi_file_refactor" | "architectural_change"

Output schema:
{
  "batch": "Full Codebase Sweep",
  "batch_index": 3,
  "assessments": {"<dimension>": <0-100 with one decimal place>},
  "dimension_notes": {
    "<dimension>": {
      "evidence": ["specific code observations"],
      "impact_scope": "local|module|subsystem|codebase",
      "fix_scope": "single_edit|multi_file_refactor|architectural_change",
      "confidence": "high|medium|low",
      "unreported_risk": "required when score >85",
      "sub_axes": {"abstraction_leverage": 0-100 with one decimal place, "indirection_cost": 0-100 with one decimal place, "interface_honesty": 0-100 with one decimal place}  // required for abstraction_fitness when evidence supports it
    }
  },
  "findings": []
}
