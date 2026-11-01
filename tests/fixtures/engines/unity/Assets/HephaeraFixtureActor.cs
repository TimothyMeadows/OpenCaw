using UnityEngine;

public sealed class HephaeraFixtureActor : MonoBehaviour
{
    public static int Awakes;
    public static int Enables;
    public static int Disables;
    public static int Destructions;
    public int Value;
    private void Awake() { Awakes++; }
    private void OnEnable() { Enables++; }
    private void OnDisable() { Disables++; }
    private void OnDestroy() { Destructions++; }
}
