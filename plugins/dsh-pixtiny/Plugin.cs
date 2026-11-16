using System;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.Unity.IL2CPP;
using HarmonyLib;
using UnityEngine;

namespace Dsh.PixTiny;

/// <summary>
/// dsh-PixTiny: 把「像素化马赛克」相关材质参数统一压到极小的通用补丁。
/// 适用于使用 _Pix / _PixelSize / _BlockSize / _Divisor / _Mosa_On 这类属性的 Unity 游戏。
/// 在 Material.SetFloat 的赋值前改写数值，不依赖具体游戏的类名。
/// </summary>
[BepInPlugin(Guid, "dsh-PixTiny", Version)]
public class Plugin : BasePlugin
{
    public const string Guid = "io.github.qiliu233.pixtiny";
    public const string Version = "1.1.0";

    internal static ManualLogSource L;
    internal static ConfigEntry<float> PixelScale;
    internal static ConfigEntry<float> DivisorBoost;
    internal static ConfigEntry<bool> DisableMosaicSwitch;

    public override void Load()
    {
        L = Log;
        PixelScale = Config.Bind("General", "PixelScale", 0.001f,
            "写入 _Pix/_PixelSize/_BlockSize 的值。越小越接近原图（1 = 原始尺寸）。");
        DivisorBoost = Config.Bind("General", "DivisorBoost", 1000000f,
            "写入 _Divisor 的值。该值越大，马赛克块越小。");
        DisableMosaicSwitch = Config.Bind("General", "DisableMosaicSwitch", true,
            "是否把 _Mosa_On 置 0（关闭马赛克总开关）。");

        var harmony = new Harmony(Guid);
        try
        {
            harmony.PatchAll(typeof(Plugin).Assembly);
            L.LogInfo($"[dsh-PixTiny] v{Version} 已加载");
        }
        catch (Exception e)
        {
            L.LogError("[dsh-PixTiny] 补丁失败: " + e);
        }
    }
}

[HarmonyPatch(typeof(Material), "SetFloat", new Type[] { typeof(string), typeof(float) })]
static class PatchSetFloatString
{
    static bool Prefix(string name, ref float value)
    {
        if (name == null) return true;
        var p = Plugin.PixelScale.Value;
        switch (name)
        {
            case "_Pix":
            case "_PixelSize":
            case "_BlockSize":
                value = p;
                break;
            case "_Divisor":
                value = Plugin.DivisorBoost.Value;
                break;
            case "_Mosa_On":
                if (Plugin.DisableMosaicSwitch.Value) value = 0f;
                break;
        }
        return true;
    }
}

[HarmonyPatch(typeof(Material), "SetFloat", new Type[] { typeof(int), typeof(float) })]
static class PatchSetFloatId
{
    static readonly int IdPix = Shader.PropertyToID("_Pix");
    static readonly int IdPixelSize = Shader.PropertyToID("_PixelSize");
    static readonly int IdBlockSize = Shader.PropertyToID("_BlockSize");
    static readonly int IdDivisor = Shader.PropertyToID("_Divisor");
    static readonly int IdMosaOn = Shader.PropertyToID("_Mosa_On");

    static bool Prefix(int nameID, ref float value)
    {
        var p = Plugin.PixelScale.Value;
        if (nameID == IdPix || nameID == IdPixelSize || nameID == IdBlockSize) value = p;
        else if (nameID == IdDivisor) value = Plugin.DivisorBoost.Value;
        else if (nameID == IdMosaOn && Plugin.DisableMosaicSwitch.Value) value = 0f;
        return true;
    }
}
