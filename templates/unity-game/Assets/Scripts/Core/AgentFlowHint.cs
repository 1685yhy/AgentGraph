// AgentGraph Unity Template — AgentFlowHint.cs
// Purpose: Provides inline context for AI agents working on this project.
// Not compiled in release builds.

#if UNITY_EDITOR
using UnityEngine;

/// <summary>
/// Agent context hints — read by AgentGraph agents before starting work.
/// Each region maps to a specific agent's responsibility.
/// </summary>
public static class AgentFlowHint
{
    // ── game-designer ────────────────────────────────────────
    // INPUT:  User's game idea (natural language)
    // OUTPUT: GDD.md (game-design-doc.md in template root)
    // ACCEPTANCE:
    //   - Core loop defined (player action → system response → reward)
    //   - Win/lose conditions explicit
    //   - Target platform capabilities considered

    // ── technical-artist ─────────────────────────────────────
    // INPUT:  GDD.md, art style direction
    // OUTPUT: Materials, Shaders, Prefabs in Assets/Prefabs/
    // ACCEPTANCE:
    //   - Consistent art style across all assets
    //   - Draw calls within mobile/desktop budget
    //   - All materials use project-standard shader

    // ── game-ui-designer ─────────────────────────────────────
    // INPUT:  GDD.md, art style
    // OUTPUT: UI Prefabs, Canvas hierarchy
    // ACCEPTANCE:
    //   - All interactive elements ≥ 44x44px (touch target)
    //   - Color contrast meets WCAG AA

    // ── game-audio-engineer ───────────────────────────────────
    // INPUT:  GDD.md, mood direction
    // OUTPUT: AudioClips in Assets/Resources/Audio/
    // ACCEPTANCE:
    //   - BGM loops seamlessly
    //   - SFX < 200ms latency from trigger

    // ── monetization-designer ─────────────────────────────────
    // INPUT:  GDD.md, player flow
    // OUTPUT: Monetization design doc
    // ACCEPTANCE:
    //   - IAP placement does not break core loop enjoyment
    //   - Ad frequency ≤ 1 per 3 minutes

    // ── game-qa-engineer ──────────────────────────────────────
    // INPUT:  Playable build
    // OUTPUT: Bug report + test coverage report
    // ACCEPTANCE:
    //   - All scenes load without errors
    //   - Core loop completable from start to end
    //   - Edge cases tested (rapid input, low memory, background/foreground)

    // ── game-producer ─────────────────────────────────────────
    // INPUT:  QA-passed build
    // OUTPUT: Release build + store listing
    // ACCEPTANCE:
    //   - All 5 gates passed
    //   - Build size within store limits
}
#endif
