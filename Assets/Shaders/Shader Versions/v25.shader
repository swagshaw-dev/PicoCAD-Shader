Shader "Custom/v25"
{
    Properties
    {
        _IndexTex("Add Object Texture Here", 2D) = "white" {}
        _PaletteTex("Add Palette Here (16 x 3)", 2D) = "white" {}
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
        _LightScale("Light Scale", Range(0, 4)) = 1.65
        [HideInInspector] _ShadowCutoff("Shadow Cutoff", Range(0,1)) = 0.0
        _Cutoff("Alpha Cutoff", Range(0,1)) = 1
        [Toggle] _InvertLight("Invert Lighting", Float) = 0
        [Toggle] _InvertLightBack("Invert Back Face Lighting", Float) = 1
        [Enum(Front,2,Back,1,Both,0)] _Cull("Show Faces", Float) = 2
        [Enum(Light,0,Dark,1,Dithered,2)] _BackFaceMode("Back Face Shading", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }
        LOD 200

        // ------------------------------------------------------------------ //
        // ForwardLit
        // ------------------------------------------------------------------ //
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            Cull [_Cull]

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

            // Point-clamp sampler: nearest-neighbour + clamp regardless of asset importer
            // settings. Unity resolves the sampler state from the identifier name.
            SamplerState sampler_point_clamp;

            CBUFFER_START(UnityPerMaterial)
                float  _InvertLight;
                float  _InvertLightBack;
                float  _FlatShading;
                float  _BackFaceMode;
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

            /// Sample a color from the palette by column index and row.
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
                // --- Sample index texture — snap UV to nearest texel center before
                // sampling to prevent perspective-correct interpolation drift from
                // reading a neighboring texel at triangle edges.
                float2 snappedUV   = (floor(IN.uv * _IndexTex_TexelSize.zw) + 0.5) * _IndexTex_TexelSize.xy;
                float4 inputSample = SAMPLE_TEXTURE2D_LOD(_IndexTex, sampler_point_clamp, snappedUV, 0);
                clip(inputSample.a - _Cutoff);
                float3 inputColor = inputSample.rgb;

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
                bool isBackFace = (facing < 0.0);
                if (isBackFace && _BackFaceMode < 0.5)
                    return half4(SamplePalette(colorIdx, 0), 1.0);
                if (isBackFace && _BackFaceMode > 0.5 && _BackFaceMode < 1.5)
                    return half4(SamplePalette(colorIdx, 3), 1.0);

                // --- Screen-space checker (threshold plaid)
                float2 fragCoord = IN.positionCS.xy;
                float  shortSide = min(_ScreenParams.x, _ScreenParams.y);
                float  scale     = max(0.0001, _DitherScaleA * shortSide);
                float2 cell      = floor(fragCoord / scale);
                float  plaid     = fmod(cell.x + cell.y, 2.0);

                // --- Normal resolution
                // Flat shading: derive geometric face normal from ddx/ddy of world position.
                // Guard: if the candidate normal disagrees strongly with the vertex normal
                // (dot < 0.5), the derivative crossed a triangle boundary — fall back to
                // the vertex normal to avoid a bad lambert value on edge pixels.
                // For back faces, flip the vertex normal so lambert is computed correctly
                // against the interior surface direction.
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

                // --- Additional lights (Forward and Forward+)
                // LIGHT_LOOP_BEGIN/END handles both rendering paths. In Forward+ it
                // iterates via the cluster structure (GetAdditionalLightsCount() returns 0
                // there, so a plain for-loop would always skip). InputData is the minimum
                // needed to feed the cluster lookup.
                InputData inputData = (InputData)0;
                inputData.positionWS              = IN.positionWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);

                LIGHT_LOOP_BEGIN((uint)GetAdditionalLightsCount())
                    Light addLight   = GetAdditionalLight(lightIndex, IN.positionWS);
                    float addLambert = saturate(dot(normalWS, addLight.direction) * lightSign);
                    float addShadow  = step(_ShadowCutoff, addLight.shadowAttenuation);
                    lightFactor      = saturate(lightFactor + addLambert * addShadow * addLight.distanceAttenuation);
                LIGHT_LOOP_END

                // Shape, scale, and apply ambient floor
                float shaped = 1.0 - (1.0 - lightFactor) * (1.0 - lightFactor);
                shaped = clamp(shaped * _LightScale, _Ambient, 1.0);

                // Quantize into discrete lighting steps
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

                // Dithered (_BackFaceMode >= 1.5): paletteRow already computed above.

                float3 color = SamplePalette(colorIdx, paletteRow);
                return half4(color, 1.0);
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
            Cull [_Cull]

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
