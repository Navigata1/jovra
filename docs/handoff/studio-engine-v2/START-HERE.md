# JOVRA Studio: Claude continuation handoff

This package extends the JOVRA Tennis build already in progress. It contains product direction, 40 visual targets, six portable editing skills, planning contracts, examples and a small plan validator. It is not a deployed processing service.

1. Read `CLAUDE-STUDIO-BRIDGE-PROMPT.md` in this folder. Send that text as the next instruction to the existing Claude conversation.
2. Open `JOVRA-Studio-Complete-v2.html` at the archive root. It embeds all 40 screens, four logo candidates, the continuation prompt, the detailed expansion prompt, all six skills, examples, source assessment and research. It opens offline and offers downloads of the embedded text files. The earlier relative-image gallery is also retained.
3. Read `skills/jovra-studio-director/SKILL.md`; it routes the other five skills. Claude may read these ordinary files directly. If the harness supports project skill discovery, copy the six named skill folders into the existing repository’s `.claude/skills/` without replacing its Matt Pocock skills. This package has not installed them.
4. Read the original detailed expansion at `../CLAUDE-STUDIO-EXPANSION-PROMPT.md`, and the Studio briefs under `../../../design-reference/studio/brief/`.
5. Use the contract/example and validator only as an initial planning boundary. They do not render, validate actual media bytes, provide a trained tennis model, or authorize cloud spending.

The original uploaded ZIP and landing HTML are included unchanged in `source-attachments/` at the archive root, alongside the extracted source text and MIT notices. You do not need to attach them again. Their historical instructions are source material; the JOVRA bridge prompt and skill suite define the intended adaptation. A flat MP4 is a film; interactive camera switching remains a separate project-player feature.

Preserve the original app foundation, player-owned recordings and five-tab navigation. Studio can be richer on iPad and use focused sheets on iPhone. Native Android follows shared contracts. The paid cloud vision is staged behind measured costs and new ADRs; the existing free/local v1 is not silently paywalled.

For local helper verification run from this folder:

```sh
python3 scripts/validate_edit_plan.py examples/edit-plan.sample.json
python3 scripts/check_sample_plan.py
```

The sample is fictional, marked Sample, and binds illustrative source metadata. Passing it proves planning checks, not a rendered film or source authenticity. Real footage is still needed for the first complete media journey, and real multiple views are needed to verify synchronization.
