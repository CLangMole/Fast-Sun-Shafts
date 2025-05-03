Shader "CMole/SunShafts"
{
    Properties
    {
        [HideInInspector] _SunScreenX ("SunScreenX", Float) = 0
        [HideInInspector] _SunScreenY ("SunScreenY", Float) = 0
        _ShaftsOffset ("Shafts Offset", Float) = 0
        _Tint ("Tint", Color) = (255, 255, 255, 255)
        [HideInInspector] _Alpha ("Alpha", Range( 0 , 1)) = 1
        _BlurOffset ("Blur Offset", Float) = 5
    }
    SubShader
    {
        ZWrite Off Cull Off

        Tags
        {
            "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "SunShaftsEffect"
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment frag
            #pragma multi_compile QUALITY_LOW QUALITY_HIGH

            half _SunScreenX;
            half _SunScreenY;
            half _ShaftsOffset;
            half4 _Tint;
            half _Alpha;

            static const half dither_4_thresholds[16] =
            {
                1.0 / 17.0, 9.0 / 17.0, 3.0 / 17.0, 11.0 / 17.0,
                13.0 / 17.0, 5.0 / 17.0, 15.0 / 17.0, 7.0 / 17.0,
                4.0 / 17.0, 12.0 / 17.0, 2.0 / 17.0, 10.0 / 17.0,
                16.0 / 17.0, 8.0 / 17.0, 14.0 / 17.0, 6.0 / 17.0
            };

            static const half dither_8_thresholds[64] =
            {
                1.0 / 65.0, 49.0 / 65.0, 13.0 / 65.0, 61.0 / 65.0, 4.0 / 65.0, 52.0 / 65.0, 16.0 / 65.0, 64.0 / 65.0,
                33.0 / 65.0, 17.0 / 65.0, 45.0 / 65.0, 29.0 / 65.0, 36.0 / 65.0, 20.0 / 65.0, 48.0 / 65.0, 32.0 / 65.0,
                9.0 / 65.0, 57.0 / 65.0, 5.0 / 65.0, 53.0 / 65.0, 12.0 / 65.0, 60.0 / 65.0, 8.0 / 65.0, 56.0 / 65.0,
                41.0 / 65.0, 25.0 / 65.0, 37.0 / 65.0, 21.0 / 65.0, 44.0 / 65.0, 28.0 / 65.0, 40.0 / 65.0, 24.0 / 65.0,
                3.0 / 65.0, 51.0 / 65.0, 15.0 / 65.0, 63.0 / 65.0, 2.0 / 65.0, 50.0 / 65.0, 14.0 / 65.0, 62.0 / 65.0,
                35.0 / 65.0, 19.0 / 65.0, 47.0 / 65.0, 31.0 / 65.0, 34.0 / 65.0, 18.0 / 65.0, 46.0 / 65.0, 30.0 / 65.0,
                11.0 / 65.0, 59.0 / 65.0, 7.0 / 65.0, 55.0 / 65.0, 10.0 / 65.0, 58.0 / 65.0, 6.0 / 65.0, 54.0 / 65.0,
                43.0 / 65.0, 27.0 / 65.0, 39.0 / 65.0, 23.0 / 65.0, 42.0 / 65.0, 26.0 / 65.0, 38.0 / 65.0, 22.0 / 65.0
            };

            half dither4(const half2 screen_pos)
            {
                uint2 pixel_pos = uint2(floor(screen_pos * _ScreenParams.xy)) % 4;
                uint index = pixel_pos.y * 4 + pixel_pos.x;

                return -dither_4_thresholds[index];
            }

            half dither8(const half2 screen_pos)
            {
                uint2 pixel_pos = uint2(floor(screen_pos * _ScreenParams.xy)) % 8;
                uint index = pixel_pos.y * 8 + pixel_pos.x;

                return -dither_8_thresholds[index];
            }

            half disperse(const half2 screen_pos, const half screen_c, const half sun_c)
            {
                half dither = 0;

                #ifdef QUALITY_LOW
                dither = dither4(screen_pos);
                #else
                dither = dither8(screen_pos);
                #endif

                return (screen_c + sun_c) * _ShaftsOffset * dither + screen_c;
            }

            half4 frag(const Varyings i) : SV_Target
            {
                half2 uv = i.texcoord;

                const half u = uv.x;
                const half v = uv.y;

                const half2 dispersed_uv = half2(disperse(uv, u, _SunScreenX),
                                                 disperse(uv, v, _SunScreenY));
                
                const half dispersed_alpha = 1 - SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, dispersed_uv).a;

                half4 result = smoothstep(0, 1, dispersed_alpha * _Tint) * _Alpha;

                return result;
            }
            ENDHLSL
        }
        Pass
        {
            Name "DualBlurDownsample"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment downsample

            half _BlurOffset;

            half4 downsample(const Varyings i) : SV_Target
            {
                const half2 uv = i.texcoord;

                const half2 half_pixel = (_BlitTexture_TexelSize.xy * 0.5).xy;
                const half2 offset = half2(1.0 + _BlurOffset, 1.0 + _BlurOffset);

                half4 uv1;
                uv1.xy = uv - half_pixel * offset;
                uv1.zw = uv + half_pixel * offset;

                half4 uv2;
                uv2.xy = uv - half2(half_pixel.x, -half_pixel.y) * offset;
                uv2.zw = uv + half2(half_pixel.x, -half_pixel.y) * offset;

                half4 o = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv) * 4;

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv1.xy);

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv1.zw);

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv2.xy);

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv2.zw);

                return o * 0.125;
            }
            ENDHLSL
        }
        Pass
        {
            Name "DualBlurUpsample"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment upsample

            half _BlurOffset;

            half4 upsample(const Varyings i) : SV_Target
            {
                const half2 uv = i.texcoord;

                const half2 half_pixel = (_BlitTexture_TexelSize * 0.5).xy;
                const half2 offset = float2(1.0 + _BlurOffset, 1.0 + _BlurOffset);

                half4 uv1;
                uv1.xy = uv + half2(-half_pixel.x * 2.0, 0.0) * offset;
                uv1.zw = uv + half2(-half_pixel.x, half_pixel.y) * offset;

                half4 uv2;
                uv2.xy = uv + half2(0.0, half_pixel.y * 2.0) * offset;
                uv2.zw = uv + half_pixel * offset;

                half4 uv3;
                uv3.xy = uv + half2(half_pixel.x * 2.0, 0.0) * offset;
                uv3.zw = uv + half2(half_pixel.x, -half_pixel.y) * offset;

                half4 uv4;
                uv4.xy = uv + half2(0.0, -half_pixel.y * 2.0) * offset;
                uv4.zw = uv - half_pixel * offset;

                half4 o = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv1.xy);

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv1.zw) * 2;

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv2.xy);

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv2.zw) * 2;

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv3.xy);

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv3.zw) * 2;

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv4.xy);

                o += SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv4.zw) * 2;

                return o * 0.0833;
            }
            ENDHLSL
        }
        Pass
        {
            Name "ShaftsBlurSum"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment frag

            TEXTURE2D(_DispersedTex);

            half4 frag(const Varyings i) : SV_Target
            {
                const half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord);
                const half4 shafts = SAMPLE_TEXTURE2D(_DispersedTex, sampler_LinearClamp, i.texcoord);
                return color + shafts;
            }
            ENDHLSL
        }
        Pass
        {
            Name "PreDownsample"
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment frag

            half4 frag(const Varyings i) : SV_Target
            {
                return SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, i.texcoord);
            }
            ENDHLSL
        }
    }
}