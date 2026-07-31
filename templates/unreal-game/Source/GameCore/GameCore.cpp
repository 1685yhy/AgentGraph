// AgentGraph Unreal Engine 5 Template — GameCore.cpp
// Agent: unreal-developer
// Consumes: GDD from game-designer
// Produces: core-gameplay-framework
// Handoff_to: game-qa-engineer

#include "GameCore.h"

namespace AgentGraph
{
    void GameCore::Bootstrap()
    {
        // AgentGraph: replace with game-specific bootstrap
        // - SaveSystem::Get().Load()
        // - AudioManager::Get().Init()
        // - Analytics::Track("game_start")
        // - Tutorial::Show() on first run

        SetState(EGameState::Running);
    }
} // namespace AgentGraph
