// AgentGraph Unreal Engine 5 Template — GameCore.h
// Agent: unreal-developer
// Consumes: GDD from game-designer
// Produces: core-gameplay-framework
// Handoff_to: game-qa-engineer

// NOTE: This is a plain C++ scaffold. When a real UE5 C++ project is created,
// unreal-developer moves this into a proper module (Source/<Module>/*.Build.cs).

#pragma once

#include <cstdint>

namespace AgentGraph
{
    /** Gameplay state machine — mirrors the Unity GameManager state set. */
    enum class EGameState : std::uint8_t
    {
        Bootstrap,
        Loading,
        Running,
        Paused,
        GameOver,
        Victory
    };

    /** Core game core — singleton-style entry point for AgentGraph agents. */
    class GameCore
    {
    public:
        GameCore() = default;
        virtual ~GameCore() = default;

        /** Called once at game start. Replace with game-specific bootstrap. */
        void Bootstrap();

        EGameState GetState() const { return CurrentState; }
        void SetState(EGameState NewState) { CurrentState = NewState; }

    private:
        EGameState CurrentState = EGameState::Bootstrap;
    };
} // namespace AgentGraph
