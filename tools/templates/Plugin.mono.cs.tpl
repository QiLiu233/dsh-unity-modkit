using System;
using BepInEx;
using BepInEx.Logging;
using HarmonyLib;
using UnityEngine;

namespace @NAME@;

[BepInPlugin("@GUID@", "@NAME@", "1.0.0")]
public class Plugin : BaseUnityPlugin
{
    internal static ManualLogSource L;

    private void Awake()
    {
        L = Logger;
        try
        {
            new Harmony("@GUID@").PatchAll(typeof(Plugin).Assembly);
            L.LogInfo("[@NAME@] 补丁已应用");
        }
        catch (Exception e)
        {
            L.LogError("[@NAME@] 补丁失败: " + e);
        }
    }
}

// [HarmonyPatch(typeof(SomeGameClass), "SomeMethod")]
// static class SomePatch { static bool Prefix() => false; }
