Shader "Custom/v28" 
{
    Properties
    {
        _IndexTex("Index Texture", 2D) = "white" {}
        _PaletteTex("Palette (16 x 4)", 2D) = "white" {}
        [HideInInspector] _DitherMode("Dither Mode", Int) = 1
        [Toggle] _FlatShading("Flat Shading (Off for Round Objects)", Float) = 1
        _Ambient("Ambient", Range(0,1)) = 0.15
        _ThreshBlack("Threshold Black", Range(0,1)) = 0.2
        _ThreshDark("Threshold Dark", Range(0,1)) = 0.16
        _ThreshMid("Threshold Mid", Range(0,1)) = 0
        _ThreshDither("Threshold Dither", Range(0,1)) = 1
        _LightSteps("Light Steps (quantize)", Range(2, 8)) = 8
        _ThreshBand("Dither Band Min", Range(0, 1)) = 0.0
        _DitherScaleA("Threshold Plaid (#not dynamic to camera)", Float) = 0.02
        [HideInInspector] _BandScale("Band Gradient Scale", Float) = 0.0
        [HideInInspector] _BandCap("Band Gradient Cap", Float) = 0.0
        [HideInInspector] _ShadowCutoff("Shadow Cutoff", Range(0,1)) = 0.0
        _LightScale("Light Scale", Range(0, 4)) = 1.65
        [Enum(Front,2,Back,1,Both,0)] _Cull("Show Faces", Float) = 2
        [Enum(Flat Light,0,Flat Dark,1,Light Scale,2)] _BackFaceMode("Back Face Shading", Float) = 1
        [Enum(None,0,Stipple,1,Blend,2)] _AlphaMode("Alpha Mode (None)", Float) = 0
        _Cutoff("Alpha Cutoff", Range(0,1)) = 1
        [Toggle] _InvertLight("Invert Lighting", Float) = 0
        [Toggle] _InvertLightBack("Invert Back Face Lighting", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }
        LOD 200

        // ================================================================== //
        // Two-pass rendering for double-sided geometry (all alpha modes).
        //
        // A single Cull-Off pass renders triangles in index-buffer order.
        // Front faces can land before their matching back faces, causing
        // incorrect compositing that shifts with view angle.
        //
        // Solution (when Cull = Both or Back):
        //   Pass 1 (BackFaces)  — Cull Front, renders back faces only.
        //   Pass 2 (ForwardLit) — clips back faces already drawn in Pass 1.
        //
        // When Cull = Front (front faces only), Pass 1 is a no-op.
        // ================================================================== //

        // ------------------------------------------------------------------ //
        // Pass 1 — Back faces (all alpha modes)
        // ------------------------------------------------------------------ //
        Pass
        {
            Name "BackFaces"
            Tags { "LightMode"="SRPDefaultUnlit" }

            Cull   Front
            Blend  SrcAlpha OneMinusSrcAlpha
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragBackFaces
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_IndexTex);   SAMPLER(sampler_IndexTex);
            TEXTURE2D(_PaletteTex); SAMPLER(sampler_PaletteTex);
            SamplerState sampler_point_clamp;

            CBUFFER_START(UnityPerMaterial)
                float  _InvertLight;
                float  _InvertLightBack;
                float  _FlatShading;
                float  _BackFaceMode;
                float  _AlphaMode;
                float4 _IndexTex_ST;
                float4 _IndexTex_TexelSize;
                float  _Ambient;
                int    _DitherMode;
                float  _DitherScaleA;
                float  _ThreshBlack;
                float  _ThreshDark;
                float  _ThreshMid;
                float  _ThreshDither;
                float  _LightSteps;
                float  _ThreshBand;
                float  _BandScale;
                float  _BandCap;
                float  _LightScale;
                float  _ShadowCutoff;
                float  _Cutoff;
                float  _Cull;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                float4 shadowCoord : TEXCOORD3;
                #endif
            };

            float3 SamplePalette(int idx, int row)
            {
                float u = (idx + 0.5) / 16.0;
                float v = 1.0 - (row + 0.5) / 4.0;
                return SAMPLE_TEXTURE2D_LOD(_PaletteTex, sampler_PaletteTex, float2(u, v), 0).rgb;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = posInputs.positionCS;
                OUT.positionWS = posInputs.positionWS;
                OUT.normalWS   = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv         = TRANSFORM_TEX(IN.uv, _IndexTex);
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                OUT.shadowCoord = GetShadowCoord(posInputs);
                #endif
                return OUT;
            }

            half4 fragBackFaces(Varyings IN, half facing : VFACE) : SV_Target
            {
                // _Cull: 0 = Both, 1 = Back only, 2 = Front only.
                // Skip entirely when showing front faces only.
                if (_Cull > 1.5) clip(-1.0);

                // --- Sample index texture
                float2 snappedUV   = (floor(IN.uv * _IndexTex_TexelSize.zw) + 0.5) * _IndexTex_TexelSize.xy;
                float4 inputSample = SAMPLE_TEXTURE2D_LOD(_IndexTex, sampler_point_clamp, snappedUV, 0);
                float  alpha       = inputSample.a;
                float3 inputColor  = inputSample.rgb;

                // --- Screen-space checker
                float2 screenCell = floor(IN.positionCS.xy / max(0.0001, _DitherScaleA * min(_ScreenParams.x, _ScreenParams.y)));
                float  plaid      = fmod(screenCell.x + screenCell.y, 2.0);

                // --- Alpha mode
                if (_AlphaMode < 0.5)
                    clip(alpha - _Cutoff);
                else if (_AlphaMode < 1.5)
                {
                    clip(alpha - 1.0 / 255.0);
                    clip(alpha - plaid);
                }

                float outAlpha = (_AlphaMode > 1.5) ? alpha : 1.0;

                // --- Snap to nearest palette color
                int   colorIdx = 0;
                float minDist  = 1e9;
                for (int p = 0; p < 16; p++)
                {
                    float3 palColor = SamplePalette(p, 0);
                    float3 diff     = inputColor - palColor;
                    float  dist     = dot(diff, diff);
                    if (dist < minDist)
                    {
                        minDist  = dist;
                        colorIdx = p;
                    }
                }

                // --- Back face shading: Light pins row 0, Dark pins row 3.
                if (_BackFaceMode < 0.5)
                    return half4(SamplePalette(colorIdx, 0), outAlpha);
                if (_BackFaceMode > 0.5 && _BackFaceMode < 1.5)
                    return half4(SamplePalette(colorIdx, 3), outAlpha);

                // --- Dithered back face mode — full lighting path
                float3 vertexNormalWS = normalize(IN.normalWS) * -1.0;
                float3 normalWS       = vertexNormalWS;
                if (_FlatShading > 0.5)
                {
                    float3 geoNormal = normalize(cross(ddy(IN.positionWS), ddx(IN.positionWS)));
                    float  agreement = dot(geoNormal, vertexNormalWS);
                    if (abs(agreement) > 0.5)
                        normalWS = agreement >= 0.0 ? geoNormal : -geoNormal;
                }

                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    float4 shadowCoord = IN.shadowCoord;
                #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                    float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                #else
                    float4 shadowCoord = float4(0, 0, 0, 0);
                #endif

                Light mainLight = GetMainLight(shadowCoord);

                float lightSign   = (_InvertLight > 0.5) != (_InvertLightBack > 0.5) ? -1.0 : 1.0;
                float lambert     = saturate(dot(normalWS, mainLight.direction) * lightSign);
                float mainShadow  = step(_ShadowCutoff, mainLight.shadowAttenuation);
                float lightFactor = lambert * mainShadow * mainLight.distanceAttenuation;

                InputData inputData = (InputData)0;
                inputData.positionWS              = IN.positionWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);

                LIGHT_LOOP_BEGIN((uint)GetAdditionalLightsCount())
                    Light addLight   = GetAdditionalLight(lightIndex, IN.positionWS);
                    float addLambert = saturate(dot(normalWS, addLight.direction) * lightSign);
                    float addShadow  = step(_ShadowCutoff, addLight.shadowAttenuation);
                    lightFactor      = saturate(lightFactor + addLambert * addShadow * addLight.distanceAttenuation);
                LIGHT_LOOP_END

                float shaped = 1.0 - (1.0 - lightFactor) * (1.0 - lightFactor);
                shaped = clamp(shaped * _LightScale, _Ambient, 1.0);
                shaped = floor(shaped * _LightSteps + 0.5) / _LightSteps;

                float shapedGrad   = max(abs(ddx(shaped)), abs(ddy(shaped)));
                float adaptiveBand = max(_ThreshBand, min(shapedGrad * _BandScale, _BandCap));

                float tBlack  = _ThreshBlack;
                float tDark   = max(_ThreshDark,   tBlack + adaptiveBand);
                float tMid    = max(_ThreshMid,    tDark  + adaptiveBand);
                float tDither = max(_ThreshDither, tMid);

                bool dithBit = (plaid < 0.5);

                int paletteRow;
                if (shaped < tBlack)
                    paletteRow = 3;
                else if (shaped < tDark)
                    paletteRow = dithBit ? 3 : 2;
                else if (shaped < tMid)
                    paletteRow = dithBit ? 2 : 1;
                else if (shaped < tDither)
                    paletteRow = dithBit ? 1 : 0;
                else
                    paletteRow = 0;

                return half4(SamplePalette(colorIdx, paletteRow), outAlpha);
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------ //
        // Pass 2 — Main ForwardLit
        // Clips back faces when they were already rendered in Pass 1.
        // ------------------------------------------------------------------ //
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            Cull   [_Cull]
            Blend  SrcAlpha OneMinusSrcAlpha
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_IndexTex);   SAMPLER(sampler_IndexTex);
            TEXTURE2D(_PaletteTex); SAMPLER(sampler_PaletteTex);
            SamplerState sampler_point_clamp;

            CBUFFER_START(UnityPerMaterial)
                float  _InvertLight;
                float  _InvertLightBack;
                float  _FlatShading;
                float  _BackFaceMode;
                float  _AlphaMode;
                float4 _IndexTex_ST;
                float4 _IndexTex_TexelSize;
                float  _Ambient;
                int    _DitherMode;
                float  _DitherScaleA;
                float  _ThreshBlack;
                float  _ThreshDark;
                float  _ThreshMid;
                float  _ThreshDither;
                float  _LightSteps;
                float  _ThreshBand;
                float  _BandScale;
                float  _BandCap;
                float  _LightScale;
                float  _ShadowCutoff;
                float  _Cutoff;
                float  _Cull;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                float4 shadowCoord : TEXCOORD3;
                #endif
            };

            float3 SamplePalette(int idx, int row)
            {
                float u = (idx + 0.5) / 16.0;
                float v = 1.0 - (row + 0.5) / 4.0;
                return SAMPLE_TEXTURE2D_LOD(_PaletteTex, sampler_PaletteTex, float2(u, v), 0).rgb;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = posInputs.positionCS;
                OUT.positionWS = posInputs.positionWS;
                OUT.normalWS   = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv         = TRANSFORM_TEX(IN.uv, _IndexTex);
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                OUT.shadowCoord = GetShadowCoord(posInputs);
                #endif
                return OUT;
            }

            half4 frag(Varyings IN, half facing : VFACE) : SV_Target
            {
                bool isBackFace = (facing < 0.0);

                // --- Guard: back faces were already rendered in Pass 1.
                // _Cull: 0 = Both, 1 = Back only, 2 = Front only.
                // Both: back faces already drawn, clip them here.
                if (_Cull < 0.5 && isBackFace) clip(-1.0);
                // Back only: everything was drawn in Pass 1.
                if (_Cull > 0.5 && _Cull < 1.5) clip(-1.0);

                // --- Sample index texture
                float2 snappedUV   = (floor(IN.uv * _IndexTex_TexelSize.zw) + 0.5) * _IndexTex_TexelSize.xy;
                float4 inputSample = SAMPLE_TEXTURE2D_LOD(_IndexTex, sampler_point_clamp, snappedUV, 0);
                float  alpha       = inputSample.a;
                float3 inputColor  = inputSample.rgb;

                // --- Screen-space checker
                float2 fragCoord = IN.positionCS.xy;
                float  shortSide = min(_ScreenParams.x, _ScreenParams.y);
                float  scale     = max(0.0001, _DitherScaleA * shortSide);
                float2 cell      = floor(fragCoord / scale);
                float  plaid     = fmod(cell.x + cell.y, 2.0);

                // --- Alpha mode
                if (_AlphaMode < 0.5)
                    clip(alpha - _Cutoff);
                else if (_AlphaMode < 1.5)
                {
                    clip(alpha - 1.0 / 255.0);
                    clip(alpha - plaid);
                }

                float outAlpha = (_AlphaMode > 1.5) ? alpha : 1.0;

                // --- Snap input color to nearest base palette color (row 0)
                int   colorIdx = 0;
                float minDist  = 1e9;
                for (int p = 0; p < 16; p++)
                {
                    float3 palColor = SamplePalette(p, 0);
                    float3 diff     = inputColor - palColor;
                    float  dist     = dot(diff, diff);
                    if (dist < minDist)
                    {
                        minDist  = dist;
                        colorIdx = p;
                    }
                }

                // --- Back face early exits: Light pins to row 0, Dark pins to row 3.
                if (isBackFace && _BackFaceMode < 0.5)
                    return half4(SamplePalette(colorIdx, 0), outAlpha);
                if (isBackFace && _BackFaceMode > 0.5 && _BackFaceMode < 1.5)
                    return half4(SamplePalette(colorIdx, 3), outAlpha);

                // --- Normal resolution
                float3 vertexNormalWS = normalize(IN.normalWS) * (isBackFace ? -1.0 : 1.0);
                float3 normalWS       = vertexNormalWS;
                if (_FlatShading > 0.5)
                {
                    float3 geoNormal = normalize(cross(ddy(IN.positionWS), ddx(IN.positionWS)));
                    float  agreement = dot(geoNormal, vertexNormalWS);
                    if (abs(agreement) > 0.5)
                        normalWS = agreement >= 0.0 ? geoNormal : -geoNormal;
                }

                // --- Shadow coordinate
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    float4 shadowCoord = IN.shadowCoord;
                #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                    float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                #else
                    float4 shadowCoord = float4(0, 0, 0, 0);
                #endif

                Light mainLight = GetMainLight(shadowCoord);

                float lightSign   = (_InvertLight > 0.5) != (isBackFace && _InvertLightBack > 0.5) ? -1.0 : 1.0;
                float lambert     = saturate(dot(normalWS, mainLight.direction) * lightSign);
                float mainShadow  = step(_ShadowCutoff, mainLight.shadowAttenuation);
                float lightFactor = lambert * mainShadow * mainLight.distanceAttenuation;

                // --- Additional lights
                InputData inputData = (InputData)0;
                inputData.positionWS              = IN.positionWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);

                LIGHT_LOOP_BEGIN((uint)GetAdditionalLightsCount())
                    Light addLight   = GetAdditionalLight(lightIndex, IN.positionWS);
                    float addLambert = saturate(dot(normalWS, addLight.direction) * lightSign);
                    float addShadow  = step(_ShadowCutoff, addLight.shadowAttenuation);
                    lightFactor      = saturate(lightFactor + addLambert * addShadow * addLight.distanceAttenuation);
                LIGHT_LOOP_END

                float shaped = 1.0 - (1.0 - lightFactor) * (1.0 - lightFactor);
                shaped = clamp(shaped * _LightScale, _Ambient, 1.0);
                shaped = floor(shaped * _LightSteps + 0.5) / _LightSteps;

                // --- Palette row selection
                float shapedGrad   = max(abs(ddx(shaped)), abs(ddy(shaped)));
                float adaptiveBand = max(_ThreshBand, min(shapedGrad * _BandScale, _BandCap));

                float tBlack  = _ThreshBlack;
                float tDark   = max(_ThreshDark,   tBlack + adaptiveBand);
                float tMid    = max(_ThreshMid,    tDark  + adaptiveBand);
                float tDither = max(_ThreshDither, tMid);

                bool dithBit = (plaid < 0.5);

                int paletteRow;
                if (shaped < tBlack)
                    paletteRow = 3;
                else if (shaped < tDark)
                    paletteRow = dithBit ? 3 : 2;
                else if (shaped < tMid)
                    paletteRow = dithBit ? 2 : 1;
                else if (shaped < tDither)
                    paletteRow = dithBit ? 1 : 0;
                else
                    paletteRow = 0;

                float3 color = SamplePalette(colorIdx, paletteRow);
                return half4(color, outAlpha);
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------ //
        // DepthOnly
        // ------------------------------------------------------------------ //
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }

            ZWrite On
            ColorMask R
            Cull    [_Cull]

            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_IndexTex); SAMPLER(sampler_IndexTex);

            CBUFFER_START(UnityPerMaterial)
                float  _InvertLight;
                float  _InvertLightBack;
                float  _FlatShading;
                float  _BackFaceMode;
                float  _AlphaMode;
                float4 _IndexTex_ST;
                float4 _IndexTex_TexelSize;
                float  _Ambient;
                int    _DitherMode;
                float  _DitherScaleA;
                float  _ThreshBlack;
                float  _ThreshDark;
                float  _ThreshMid;
                float  _ThreshDither;
                float  _LightSteps;
                float  _ThreshBand;
                float  _BandScale;
                float  _BandCap;
                float  _LightScale;
                float  _ShadowCutoff;
                float  _Cutoff;
                float  _Cull;
            CBUFFER_END

            struct DepthAttributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct DepthVaryings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            DepthVaryings DepthVert(DepthAttributes IN)
            {
                DepthVaryings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv         = TRANSFORM_TEX(IN.uv, _IndexTex);
                return OUT;
            }

            half DepthFrag(DepthVaryings IN) : SV_Target
            {
                // Blend mode must not write depth at all.
                clip(_AlphaMode > 1.5 ? -1.0 : 1.0);

                float alpha = SAMPLE_TEXTURE2D(_IndexTex, sampler_IndexTex, IN.uv).a;
                clip(alpha - _Cutoff);
                return 0;
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------ //
        // ShadowCaster
        // ------------------------------------------------------------------ //
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_IndexTex); SAMPLER(sampler_IndexTex);

            CBUFFER_START(UnityPerMaterial)
                float  _InvertLight;
                float  _InvertLightBack;
                float  _FlatShading;
                float  _BackFaceMode;
                float  _AlphaMode;
                float4 _IndexTex_ST;
                float4 _IndexTex_TexelSize;
                float  _Ambient;
                int    _DitherMode;
                float  _DitherScaleA;
                float  _ThreshBlack;
                float  _ThreshDark;
                float  _ThreshMid;
                float  _ThreshDither;
                float  _LightSteps;
                float  _ThreshBand;
                float  _BandScale;
                float  _BandCap;
                float  _LightScale;
                float  _ShadowCutoff;
                float  _Cutoff;
                float  _Cull;
            CBUFFER_END

            float3 _LightDirection;
            float3 _LightPosition;

            struct ShadowAttributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct ShadowVaryings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            float4 GetShadowClipPos(ShadowAttributes IN)
            {
                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(IN.normalOS);
                #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                    float3 lightDir = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDir = _LightDirection;
                #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir));
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return positionCS;
            }

            ShadowVaryings ShadowVert(ShadowAttributes IN)
            {
                ShadowVaryings OUT;
                OUT.positionCS = GetShadowClipPos(IN);
                OUT.uv         = TRANSFORM_TEX(IN.uv, _IndexTex);
                return OUT;
            }

            half4 ShadowFrag(ShadowVaryings IN) : SV_Target
            {
                float alpha = SAMPLE_TEXTURE2D(_IndexTex, sampler_IndexTex, IN.uv).a;
                clip(alpha - _Cutoff);
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
