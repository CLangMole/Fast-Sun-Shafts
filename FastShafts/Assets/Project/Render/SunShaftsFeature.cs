using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

namespace Project.Render
{
    public class SunShaftsFeature : ScriptableRendererFeature
    {
        private enum ShaftsQuality
        {
            Low,
            High
        }

        private class SunShaftsPass : ScriptableRenderPass
        {
            private const string DispersionPassName = "SunShaftsEffect";
            private const string BlurDownSamplePassName = "DualBlurDownsample";
            private const string BlurUpsamplePassName = "DualBlurUpsample";
            private const string PreDownSamplePassName = "PreDownsample";
            private const string SumPassName = "ShaftsBlurSum";
            private const string LowQualityName = "QUALITY_LOW";
            private const string HighQualityName = "QUALITY_HIGH";

            private Material _material;
            private ShaftsQuality _quality;
            private bool _downSample;

            public void Init(Material material, ShaftsQuality quality, bool downSample)
            {
                _material = material;
                _quality = quality;
                _downSample = downSample;
            }

            private class SumPassData
            {
                public TextureHandle Source;
                public TextureBindInfo Additive;
                public Material Material;
                public int ShaderPass;
            }

            private struct TextureBindInfo
            {
                public readonly TextureHandle Texture;
                public readonly int Id;

                public TextureBindInfo(TextureHandle texture, int id)
                {
                    Texture = texture;
                    Id = id;
                }
            }

            public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
            {
                var resourceData = frameData.Get<UniversalResourceData>();
                var camera = frameData.Get<UniversalCameraData>().camera;
                var cameraTransform = camera.transform;
                var cameraDirection = cameraTransform.forward;
                var cameraPosition = cameraTransform.position;

                var sun = RenderSettings.sun.transform;
                var sunDirection = sun.forward;

                switch (_quality)
                {
                    case ShaftsQuality.Low:
                        _material.EnableKeyword(LowQualityName);
                        _material.DisableKeyword(HighQualityName);
                        break;
                    case ShaftsQuality.High:
                        _material.EnableKeyword(HighQualityName);
                        _material.DisableKeyword(LowQualityName);
                        break;
                    default:
                        throw new ArgumentOutOfRangeException();
                }

                var angle = Vector3.Dot((sun.position - cameraPosition).normalized, cameraDirection);

                _material.SetFloat(AlphaProperty, Mathf.Max(angle, 0));

                var sunProj = camera.WorldToViewportPoint(sun.position + sunDirection * 10000f);

                _material.SetFloat(SunProjXProperty, -sunProj.x);
                _material.SetFloat(SunProjYProperty, -sunProj.y);

                if (resourceData.isActiveTargetBackBuffer)
                {
                    return;
                }

                var source = resourceData.activeColorTexture;

                var dispersionTexDesc = renderGraph.GetTextureDesc(source);
                dispersionTexDesc.name = $"CameraColor-{DispersionPassName}";
                dispersionTexDesc.clearBuffer = false;
                var dispersionTex = renderGraph.CreateTexture(dispersionTexDesc);
                var dispersionParameters =
                    new RenderGraphUtils.BlitMaterialParameters(source, dispersionTex, _material, 0);
                renderGraph.AddBlitPass(dispersionParameters, DispersionPassName);

                var downSampleTexDesc = dispersionTexDesc;
                downSampleTexDesc.name = $"DispersionTex-{PreDownSamplePassName}";
                downSampleTexDesc.width /= 2;
                downSampleTexDesc.height /= 2;
                TextureHandle downSampleTex = default;

                if (_downSample)
                {
                    downSampleTex = renderGraph.CreateTexture(downSampleTexDesc);
                    var downSampleParameters =
                        new RenderGraphUtils.BlitMaterialParameters(dispersionTex, downSampleTex, _material, 4);
                    renderGraph.AddBlitPass(downSampleParameters, PreDownSamplePassName);
                }

                var blurDownSampleTexDesc = dispersionTexDesc;
                blurDownSampleTexDesc.name = $"DispersionTex-{BlurDownSamplePassName}";
                var blurDownSampleTex = renderGraph.CreateTexture(blurDownSampleTexDesc);
                var blurDownSampleParameters =
                    new RenderGraphUtils.BlitMaterialParameters(_downSample ? downSampleTex : dispersionTex,
                        blurDownSampleTex, _material, 1);
                renderGraph.AddBlitPass(blurDownSampleParameters, BlurDownSamplePassName);

                var blurUpSampleTexDesc = blurDownSampleTexDesc;
                blurUpSampleTexDesc.name = $"BlurDownSampleTex-{BlurUpsamplePassName}";
                var blurUpSampleTex = renderGraph.CreateTexture(blurUpSampleTexDesc);
                var blurUpSampleParameters =
                    new RenderGraphUtils.BlitMaterialParameters(blurDownSampleTex, blurUpSampleTex, _material, 2);
                renderGraph.AddBlitPass(blurUpSampleParameters, BlurUpsamplePassName);

                var resultTexDesc = blurUpSampleTexDesc;
                resultTexDesc.name = $"BlurUpSampleTex-{SumPassName}";
                var resultTex = renderGraph.CreateTexture(resultTexDesc);

                using var builder = renderGraph.AddRasterRenderPass<SumPassData>(SumPassName, out var passData);

                passData.Source = source;
                passData.Additive = new TextureBindInfo(blurUpSampleTex, DispersedTexProperty);
                passData.ShaderPass = 3;
                passData.Material = _material;

                builder.UseTexture(passData.Additive.Texture);
                builder.UseTexture(source);

                builder.SetRenderAttachment(resultTex, 0);
                builder.SetRenderFunc(
                    (SumPassData data, RasterGraphContext context) => ExecuteRenderFunc(data, context));

                resourceData.cameraColor = resultTex;
            }

            private static void ExecuteRenderFunc(SumPassData data, RasterGraphContext context)
            {
                data.Material.SetTexture(data.Additive.Id, data.Additive.Texture);
                Blitter.BlitTexture(context.cmd, data.Source, new Vector4(1, 1, 0, 0), data.Material, data.ShaderPass);
            }
        }

        private static readonly int AlphaProperty = Shader.PropertyToID("_Alpha");
        private static readonly int SunProjXProperty = Shader.PropertyToID("_SunScreenX");
        private static readonly int SunProjYProperty = Shader.PropertyToID("_SunScreenY");
        private static readonly int DispersedTexProperty = Shader.PropertyToID("_DispersedTex");

        private SunShaftsPass _shaftsPass;

        [SerializeField] private RenderPassEvent injectionPoint = RenderPassEvent.BeforeRenderingTransparents;
        [SerializeField] private Material material;
        [SerializeField] private ShaftsQuality quality;
        [SerializeField] private bool downSample;

        public override void Create()
        {
            _shaftsPass = new SunShaftsPass
            {
                renderPassEvent = injectionPoint
            };
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (material == null)
            {
                Debug.LogWarning("no material");
                return;
            }

            _shaftsPass.Init(material, quality, downSample);
            renderer.EnqueuePass(_shaftsPass);
        }
    }
}