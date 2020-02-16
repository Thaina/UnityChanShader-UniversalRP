# UnityChanShader-UniversalRP
Fix UnityChanShader for working with UniversalRP

For correct ambient light, need to be used in conjunction with https://gist.github.com/Thaina/79fd5bd25f47344aac04865b42a568fd/revisions

Use above file to override `Library\PackageCache\com.unity.render-pipelines.universal@7.2.0\Runtime\ForwardLights.cs`
