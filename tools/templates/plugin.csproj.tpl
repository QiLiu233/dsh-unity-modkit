<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net6.0</TargetFramework>
    <AssemblyName>@NAME@</AssemblyName>
    <RootNamespace>@NAME@</RootNamespace>
    <LangVersion>latest</LangVersion>
    <Nullable>disable</Nullable>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="BepInEx.Unity.IL2CPP"><HintPath>@GAMEROOT@\BepInEx\core\BepInEx.Unity.IL2CPP.dll</HintPath><Private>false</Private></Reference>
    <Reference Include="BepInEx.Core"><HintPath>@GAMEROOT@\BepInEx\core\BepInEx.Core.dll</HintPath><Private>false</Private></Reference>
    <Reference Include="0Harmony"><HintPath>@GAMEROOT@\BepInEx\core\0Harmony.dll</HintPath><Private>false</Private></Reference>
    <Reference Include="Il2CppInterop.Runtime"><HintPath>@GAMEROOT@\BepInEx\core\Il2CppInterop.Runtime.dll</HintPath><Private>false</Private></Reference>
    <Reference Include="UnityEngine.CoreModule"><HintPath>@GAMEROOT@\BepInEx\interop\UnityEngine.CoreModule.dll</HintPath><Private>false</Private></Reference>
    <Reference Include="UnityEngine"><HintPath>@GAMEROOT@\BepInEx\interop\UnityEngine.dll</HintPath><Private>false</Private></Reference>
    <Reference Include="Assembly-CSharp"><HintPath>@GAMEROOT@\BepInEx\interop\Assembly-CSharp.dll</HintPath><Private>false</Private></Reference>
    <Reference Include="Il2Cppmscorlib"><HintPath>@GAMEROOT@\BepInEx\interop\Il2Cppmscorlib.dll</HintPath><Private>false</Private></Reference>
  </ItemGroup>
</Project>