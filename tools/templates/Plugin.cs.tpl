using System;
using BepInEx;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using HarmonyLib;
using UnityEngine;

namespace @NAME@;

[BepInPlugin("@GUID@", "@NAME@", "1.0.0")]
public class Plugin : BasePlugin
{
    internal static ManualLogSource L;

    public override void Load()
    {
        L = Log;
        var harmony = new Harmony("@GUID@");
        try
        {
            harmony.PatchAll(typeof(Plugin).Assembly);
            L.LogInfo("[@NAME@] 补丁已全部应用");
        }
        catch (Exception e)
        {
            L.LogError("[@NAME@] 补丁失败: " + e);
        }
    }
}

// 示例: 按需修改要 hook 的方法
// [HarmonyPatch(typeof(SomeGameClass), "SomeMethod")]
// static class SomePatch { static bool Prefix() => false; }
