// AgentGraph Unity Template — GameManager.cs
// Agent: unity-developer
// Consumes: GDD from game-designer
// Produces: core-gameplay-framework
// Handoff_to: game-qa-engineer

using UnityEngine;

/// <summary>
/// Core game manager — singleton entry point.
/// AgentGraph agents extend this skeleton to implement game-specific logic.
/// </summary>
public class GameManager : MonoBehaviour
{
    public static GameManager Instance { get; private set; }

    [Header("Game State")]
    public GameState CurrentState = GameState.Bootstrap;

    [Header("Agent Hooks — implement these per GDD")]
    public bool EnableAnalytics = true;
    public bool EnableIAP = false;
    public bool EnableAds = false;
    public bool EnableLeaderboard = false;

    private void Awake()
    {
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }
        Instance = this;
        DontDestroyOnLoad(gameObject);
    }

    private void Start()
    {
        // AgentGraph: replace with game-specific bootstrap
        BootstrapGame();
    }

    private void BootstrapGame()
    {
        // AgentGraph: initialize subsystems
        // - SaveSystem.Load()
        // - AudioManager.Init()
        // - Analytics.Track("game_start")
        // - Tutorial.Show() if first run

        CurrentState = GameState.Running;
        Debug.Log("[AgentGraph] GameManager bootstrapped. Ready for game-specific logic.");
    }

    public void SetState(GameState newState)
    {
        CurrentState = newState;
        Debug.Log($"[AgentGraph] GameState → {newState}");
    }
}

public enum GameState
{
    Bootstrap,
    Loading,
    Running,
    Paused,
    GameOver,
    Victory
}
