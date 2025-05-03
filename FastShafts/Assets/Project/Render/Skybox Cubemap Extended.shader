Shader "Skybox/Cubemap Extended"
{
    Properties
    {
        [NoScaleOffset][StyledTextureSingleLine]_Tex("Cubemap (HDR)", CUBE) = "black" {}
        [Space(10)]_Exposure("Cubemap Exposure", Range( 0 , 8)) = 1
        [Gamma]_TintColor("Cubemap Tint Color", Color) = (0.5,0.5,0.5,1)
        [Space(10)]_FogIntensity("Fog Intensity", Range( 0 , 1)) = 1
        _FogSmoothness("Fog Smoothness", Range( 0.01 , 1)) = 0.01
        _FogFill("Fog Fill", Range(0, 1)) = 0.5
        _Alpha("Alpha", Range(0, 1)) = 0
        _AlphaStep ("Alpha Step", Range(0.1, 1)) = 0.1
        [HideInInspector]_Tex_HDR("DecodeInstructions", Vector) = (0,0,0,0)
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Background" "Queue"="Background" "PreviewType"="Skybox"
        }

        CGINCLUDE
        #pragma target 2.0
        ENDCG
        Blend Off
        AlphaToMask Off
        Cull Off
        ColorMask RGBA
        ZWrite Off
        ZTest LEqual

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "UnityShaderVariables.cginc"

            struct attributes
            {
                float4 vertex : POSITION;
                float4 color : COLOR;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct varyings
            {
                float4 vertex : SV_POSITION;
                float4 interpolated_uv : TEXCOORD1;
                float4 uv : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            uniform half4 _Tex_HDR;
            uniform samplerCUBE _Tex;
            uniform half4 _TintColor;
            uniform half _Exposure;
            uniform float _FogPosition;
            uniform half _FogSmoothness;
            uniform half _FogDensity;
            uniform half _FogIntensity;
            uniform half _AlphaStep;

            varyings vert(attributes v)
            {
                varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                const float interpolated_ortho = lerp(1.0, unity_OrthoParams.y / unity_OrthoParams.x,
                                          unity_OrthoParams.w);
                o.interpolated_uv = float4(v.vertex.x, v.vertex.y * interpolated_ortho, v.vertex.z, 0.0);
                o.uv = v.vertex;
                o.vertex = UnityObjectToClipPos(v.vertex);
                return o;
            }

            fixed4 frag(varyings i) : SV_Target
            {
                const float3 uv = i.interpolated_uv.xyz;
                const half4 tex = texCUBE(_Tex, uv);
                half3 c = DecodeHDR(tex, _Tex_HDR);
                c = c * unity_ColorSpaceDouble * _TintColor;
                c *= _Exposure;

                const float density = lerp(saturate(pow(abs(i.uv.y - _FogPosition), 1.0 - _FogSmoothness)), 0.0,
                           _FogDensity);

                fixed3 result = lerp(unity_FogColor, half4(c, 1.0), lerp(1.0, density, _FogIntensity));

                fixed3 color = result;
                const fixed grayscale = dot(color.rgb, float3(0.3, 0.59, 0.11));
                color.r = grayscale;
                color.g = grayscale;
                color.b = grayscale;

                fixed alpha = step(color, _AlphaStep);

                return fixed4(result, alpha);
            }
            ENDCG
        }
    }

    Fallback "Skybox/Cubemap"
}