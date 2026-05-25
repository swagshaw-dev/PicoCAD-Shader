Shader "Custom/v21"
{
    Properties
    {
        _IndexTex("Mesh Texture", 2D) = "white" {}
        _PaletteTex("Palette (16 x 3)", 2D) = "white" {}
        [HideInInspector] _DitherMode("Dither Mode", Int) = 1
        [Toggle] _InvertLight("Invert Lighting", Float) = 0
        [Toggle] _FlatShading("Flat Shading (Off for Round Objects)", Float) = 1
        _Ambient("Ambient", Range(0,1)) = 0.15
        _ThreshBlack("Threshold Black", Range(0,1)) = 0.04
        _ThreshDark("Threshold Dark", Range(0,1)) = 0.41
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
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull Mode (Back=Single / Off=Double)", Float) = 0
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
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_IndexTex);   SAMPLER(sampler_IndexTex);
            TEXTURE2D(_PaletteTex); SAMPLER(sampler_PaletteTex);

            CBUFFER_START(UnityPerMaterial)
                float  _InvertLight;
                float  _FlatShading;
                float4 _IndexTex_ST;
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
                // --- Sample input texture and clip transparent pixels early
                float4 inputSample = SAMPLE_TEXTURE2D(_IndexTex, sampler_IndexTex, IN.uv);
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

                // --- Back faces pin to row 3 (fully dark) and exit early.
                // When Cull is Front or Off, interior surfaces would otherwise be
                // inversely lit — the flipped normal makes the shadow side appear
                // bright and the lit side appear dark. There is no correct lighting
                // direction for an interior surface, so row 3 is both correct and
                // artistically consistent.
                if (facing < 0.0)
                {
                    float3 color = SamplePalette(colorIdx, 3);
                    return half4(color, 1.0);
                }

                // --- Screen-space checker (threshold plaid)
                // _DitherMode is locked to 1 (relative), so scale is expressed as a
                // fraction of the screen's short side. This keeps the checker size
                // visually consistent across resolutions.
                float2 fragCoord = IN.positionCS.xy;
                float  shortSide = min(_ScreenParams.x, _ScreenParams.y);
                float  scale     = max(0.0001, _DitherScaleA * shortSide);
                float2 cell      = floor(fragCoord / scale);
                float  plaid     = fmod(cell.x + cell.y, 2.0);

                // --- Normal resolution
                // Flat shading: derive the geometric face normal from screen-space
                // derivatives of world position. This gives every triangle one
                // uniform normal regardless of vertex normal smoothing, so the
                // lighting value is identical for every pixel on the face and the
                // palette row never changes mid-polygon. Without this, smooth-shaded
                // meshes produce continuous shading bands that "wrap" around the
                // object instead of snapping cleanly per-face.
                //
                // The geometric normal is aligned to the interpolated vertex normal
                // to guarantee it always faces outward (back faces already exited above).
                float3 normalWS = normalize(IN.normalWS);
                if (_FlatShading > 0.5)
                {
                    float3 geoNormal = normalize(cross(ddy(IN.positionWS), ddx(IN.positionWS)));
                    normalWS = dot(geoNormal, normalWS) >= 0.0 ? geoNormal : -geoNormal;
                }

                // Resolve shadow coordinate: vertex interpolator (low-end) or per-fragment
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    float4 shadowCoord = IN.shadowCoord;
                #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                    float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                #else
                    float4 shadowCoord = float4(0, 0, 0, 0);
                #endif

                Light mainLight = GetMainLight(shadowCoord);

                // Snap shadow attenuation to binary 0/1 at _ShadowCutoff.
                // Continuous shadow values (soft shadows, cascade transitions,
                // self-shadow penumbra) feed partial values into lightFactor
                // which then cross a palette threshold mid-face, producing the
                // diagonal band artifact. Hard-thresholding keeps each face
                // entirely in one palette row regardless of shadow map precision.
                // _ShadowCutoff is locked to 0, which passes all shadow values
                // through step() as 1 — i.e. full shadow contribution, no cutoff.
                float lightSign   = _InvertLight > 0.5 ? -1.0 : 1.0;
                float lambert     = saturate(dot(normalWS, mainLight.direction) * lightSign);
                float mainShadow  = step(_ShadowCutoff, mainLight.shadowAttenuation);
                float lightFactor = lambert * mainShadow * mainLight.distanceAttenuation;

                // Additional lights
                int additionalCount = GetAdditionalLightsCount();
                for (int i = 0; i < additionalCount; i++)
                {
                    Light addLight   = GetAdditionalLight(i, IN.positionWS);
                    float addLambert = saturate(dot(normalWS, addLight.direction) * lightSign);
                    float addShadow  = step(_ShadowCutoff, addLight.shadowAttenuation);
                    lightFactor      = saturate(lightFactor + addLambert * addShadow * addLight.distanceAttenuation);
                }

                // Shape, scale, and apply ambient floor
                float shaped = 1.0 - (1.0 - lightFactor) * (1.0 - lightFactor);
                shaped = clamp(shaped * _LightScale, _Ambient, 1.0);

                // Quantize shaped into discrete lighting steps before threshold evaluation.
                // This snaps the lighting value to a fixed grid so the face interior is always
                // a single flat level — ddx/ddy of the snapped value are exactly zero inside
                // a step and only spike at step boundaries (geometry edges whose two faces land
                // in different steps). The adaptive band below therefore only opens at actual
                // transitions, not continuously at every partial rotation angle.
                shaped = floor(shaped * _LightSteps + 0.5) / _LightSteps;

                // --- Palette row selection
                //
                // Uses all 4 palette rows:
                //   row 3 = fully dark / deep shadow
                //   row 2 = dark
                //   row 1 = mid
                //   row 0 = fully bright
                //
                // All four thresholds are enforced in ascending order:
                //   tBlack ≤ tDark ≤ tMid ≤ tDither
                //
                // The adaptive band (driven by ddx/ddy of the quantized shaped) only
                // opens at actual step boundaries — zero inside a flat face, nonzero
                // only at geometry edges and lighting transitions. _ThreshBand is a
                // user-tunable minimum applied everywhere. _BandScale and _BandCap are
                // locked to 0 for distribution, preserving the option to reopen them.
                //
                // Every transition dithers between ADJACENT rows only:
                //   [tBlack, tDark]   → dither row 3 ↔ row 2
                //   [tDark,  tMid]    → dither row 2 ↔ row 1
                //   [tMid,   tDither] → dither row 1 ↔ row 0
                //
                float shapedGrad   = max(abs(ddx(shaped)), abs(ddy(shaped)));
                float adaptiveBand = max(_ThreshBand, min(shapedGrad * _BandScale, _BandCap));

                float tBlack  = _ThreshBlack;
                float tDark   = max(_ThreshDark,   tBlack + adaptiveBand);
                float tMid    = max(_ThreshMid,    tDark  + adaptiveBand);
                float tDither = max(_ThreshDither, tMid);

                bool dithBit = (plaid < 0.5);

                int paletteRow;
                if (shaped < tBlack)
                    paletteRow = 3;                 // fully dark (row 3)
                else if (shaped < tDark)
                    paletteRow = dithBit ? 3 : 2;  // dither row 3 ↔ row 2
                else if (shaped < tMid)
                    paletteRow = dithBit ? 2 : 1;  // dither row 2 ↔ row 1
                else if (shaped < tDither)
                    paletteRow = dithBit ? 1 : 0;  // dither row 1 ↔ row 0
                else
                    paletteRow = 0;                 // fully bright (row 0)

                float3 color = SamplePalette(colorIdx, paletteRow);
                return half4(color, 1.0);
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------ //
        // DepthOnly — writes depth with correct alpha clip using _IndexTex.
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
                float  _FlatShading;
                float4 _IndexTex_ST;
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

            struct DepthAttributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct DepthVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

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
        // ShadowCaster — clips _IndexTex alpha so transparent regions don't
        // cast shadows.
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
                float  _FlatShading;
                float4 _IndexTex_ST;
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

            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
            };

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
