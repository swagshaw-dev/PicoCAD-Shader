Shader "Custom/v9"
{
    Properties
    {
        _IndexTex("Index Texture", 2D) = "white" {}
        _PaletteTex("Palette Texture", 2D) = "white" {}
        _DitherMode("Dither Mode 0=px 1=relative", Int) = 1
        _DitherScaleA("Plaid Scale A", Float) = 0.02
        _DitherScaleB("Plaid Scale B", Float) = 0.04
        _PlaidAngle("Plaid Angle (deg)", Float) = 45.0
        _PlaidBlend("Plaid Blend", Range(0,1)) = 1.0
        [Toggle] _InvertLight("Invert Lighting", Float) = 0
        _Ambient("Ambient", Range(0,1)) = 0.15
        _ThreshDark("Threshold Dark", Range(0,1)) = 0.4
        _ThreshMid("Threshold Mid", Range(0,1)) = 0.56
        _ThreshDither("Threshold Dither", Range(0,1)) = 0.75
        _LightScale("Light Scale", Range(0, 4)) = 1.0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        LOD 200

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_IndexTex);   SAMPLER(sampler_IndexTex);
            TEXTURE2D(_PaletteTex); SAMPLER(sampler_PaletteTex);

            CBUFFER_START(UnityPerMaterial)
                float _InvertLight;
                float4 _IndexTex_ST;
                float  _Ambient;
                int    _DitherMode;
                float  _DitherScaleA;
                float  _DitherScaleB;
                float  _PlaidAngle;
                float  _PlaidBlend;
                float _ThreshDark;
                float _ThreshMid;
                float _ThreshDither;
                float _LightScale;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 positionWS  : TEXCOORD2;
            };

            float2 Rotate2(float2 p, float a)
            {
                float ca = cos(a), sa = sin(a);
                return float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);
            }

            float3 SamplePalette(float idx, int row)
            {
                float u = (idx + 0.5) / 16.0;
                float v = (row  + 0.5) / 3.0;
                return SAMPLE_TEXTURE2D(_PaletteTex, sampler_PaletteTex, float2(u, v)).rgb;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = posInputs.positionCS;
                OUT.positionWS = posInputs.positionWS;
                OUT.normalWS   = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv         = TRANSFORM_TEX(IN.uv, _IndexTex);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // --- Index lookup
                float texSample = SAMPLE_TEXTURE2D(_IndexTex, sampler_IndexTex, IN.uv).r;
                float colorIdx  = clamp(floor(texSample * 255.0 + 0.5), 0.0, 15.0);

                // --- Screen-space plaid
                float2 screenSize = float2(_ScreenParams.x, _ScreenParams.y);
                float2 fragCoord  = IN.positionCS.xy;

                float shortSide = min(screenSize.x, screenSize.y);
                float scaleA = (_DitherMode == 1) ? max(0.0001, _DitherScaleA * shortSide) : max(0.0001, _DitherScaleA);
                float scaleB = (_DitherMode == 1) ? max(0.0001, _DitherScaleB * shortSide) : max(0.0001, _DitherScaleB);

                float2 cellA    = floor(fragCoord / scaleA);
                float  checkerA = fmod(cellA.x + cellA.y, 2.0);

                float  angleRad = radians(_PlaidAngle);
                float2 rotated  = Rotate2(fragCoord, angleRad);
                float2 cellB    = floor(rotated / scaleB);
                float  checkerB = fmod(cellB.x + cellB.y, 2.0);

                float plaidRaw = checkerA * checkerB;
                float plaid    = lerp(checkerA, plaidRaw, saturate(_PlaidBlend));

                // --- Lighting (URP main light)
                float3 normalWS    = normalize(IN.normalWS);
                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light  mainLight   = GetMainLight(shadowCoord);

                float lightSign = _InvertLight > 0.5 ? -1.0 : 1.0;
                float lambert   = saturate(dot(normalWS, mainLight.direction) * lightSign);
                float lightFactor = lambert * mainLight.shadowAttenuation * mainLight.distanceAttenuation;

                // Additional lights
                int additionalCount = GetAdditionalLightsCount();
                for (int i = 0; i < additionalCount; i++)
                {
                    Light addLight   = GetAdditionalLight(i, IN.positionWS);
                    float addLambert = saturate(dot(normalWS, addLight.direction));
                    lightFactor      = saturate(lightFactor + addLambert * addLight.shadowAttenuation * addLight.distanceAttenuation);
                }

                // Shape and apply ambient floor
                float shaped    = 1.0 - (1.0 - lightFactor) * (1.0 - lightFactor);
                shaped          = clamp(shaped * _LightScale, _Ambient, 1.0);


                // Palette row selection — light picks the row, does NOT tint the color
                int paletteRow;
                if (shaped < _ThreshDark)
                    paletteRow = 2;
                else if (shaped < _ThreshMid)
                    paletteRow = 1;
                else if (shaped < _ThreshDither)
                    paletteRow = (plaid < 0.5) ? 1 : 0;
                else
                    paletteRow = 0;


                float3 color = SamplePalette(colorIdx, paletteRow);
                return half4(color, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _IndexTex_ST;
                float  _Ambient;
                int    _DitherMode;
                float  _DitherScaleA;
                float  _DitherScaleB;
                float  _PlaidAngle;
                float  _PlaidBlend;
            CBUFFER_END
            ENDHLSL
        }

    }

    FallBack Off
}
