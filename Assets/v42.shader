Shader "Custom/v42"
{
    Properties
    {
        _IndexTex("Index Texture", 2D) = "white" {}
        _PaletteTex("Palette (16 x 4)", 2D) = "white" {}

        [Header(Dither Settings)]
        [Toggle] _DynamicPlaid("Use Dynamic Camera Scaling", Float) = 0
        _DitherScaleStatic("Static Plaid Scale", Float) = 0.02
        _DitherNearScale("Near Plaid Scale", Float) = 0.01
        _DitherFarScale("Far Plaid Scale", Float) = 0.05
        _DistNear("Distance Near", Float) = 1.0
        _DistFar("Distance Far", Float) = 10.0

        [Header(Shading)]
        [Toggle] _FlatShading("Flat Shading", Float) = 1
        _Ambient("Ambient", Range(0,1)) = 0.15
        _ThreshBlack("Threshold Black", Range(0,1)) = 0.2
        _ThreshDark("Threshold Dark", Range(0,1)) = 0.16
        _ThreshMid("Threshold Mid", Range(0,1)) = 0
        _ThreshDither("Threshold Dither", Range(0,1)) = 1
        _LightSteps("Light Steps", Range(2, 8)) = 8
        _ThreshBand("Dither Band Min", Range(0, 1)) = 0.0
        _BandScale("Band Gradient Scale", Float) = 10.0
        _BandCap("Band Gradient Cap", Float) = 0.1

        [HideInInspector] _ShadowCutoff("Shadow Cutoff", Range(0,1)) = 0.0
        _LightScale("Light Scale", Range(0, 4)) = 1.65
        
        [Header(Rendering Options)]
        [Enum(Front,2,Back,1,Both,0)] _Cull("Show Faces", Float) = 2
        [Enum(Flat Light,0,Flat Dark,1,Light Scale,2)] _BackFaceMode("Back Face Shading", Float) = 1
        [Enum(None,0,Stipple,1,Blend,2)] _AlphaMode("Alpha Mode", Float) = 0
        _Cutoff("Alpha Cutoff", Range(0,1)) = 0.5
        [Enum(Off,0,On,1)] _ZWrite("Depth Write (ZWrite)", Float) = 1
        [Toggle] _InvertLight("Invert Lighting", Float) = 0
        [Toggle] _InvertLightBack("Invert Back Face Lighting", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }
        LOD 200

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        TEXTURE2D(_IndexTex); SAMPLER(sampler_IndexTex);
        TEXTURE2D(_PaletteTex); SAMPLER(sampler_PaletteTex);
        SamplerState sampler_point_clamp;

        CBUFFER_START(UnityPerMaterial)
            float _DynamicPlaid, _DitherScaleStatic, _DitherNearScale, _DitherFarScale, _DistNear, _DistFar;
            float _InvertLight, _InvertLightBack, _FlatShading, _BackFaceMode, _AlphaMode;
            float4 _IndexTex_ST, _IndexTex_TexelSize;
            float _Ambient, _ThreshBlack, _ThreshDark, _ThreshMid, _ThreshDither, _LightSteps;
            float _ThreshBand, _BandScale, _BandCap, _LightScale, _ShadowCutoff, _Cutoff, _Cull, _ZWrite;
        CBUFFER_END

        struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
        struct Varyings { 
            float4 positionCS : SV_POSITION; 
            float2 uv : TEXCOORD0; 
            float3 normalWS : TEXCOORD1; 
            float3 positionWS : TEXCOORD2; 
            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
            float4 shadowCoord : TEXCOORD3;
            #endif
        };

        float3 SamplePalette(int idx, int row) {
            float u = (idx + 0.5) / 16.0;
            float v = 1.0 - (row + 0.5) / 4.0;
            return SAMPLE_TEXTURE2D_LOD(_PaletteTex, sampler_PaletteTex, float2(u, v), 0).rgb;
        }

        float CalculatePlaid(float4 positionCS, float3 positionWS) {
            float finalScale = _DitherScaleStatic;
            if (_DynamicPlaid > 0.5) {
                float dist = distance(_WorldSpaceCameraPos, positionWS);
                float distFactor = saturate((dist - _DistNear) / max(0.0001, _DistFar - _DistNear));
                finalScale = lerp(_DitherNearScale, _DitherFarScale, distFactor);
            }
            float shortSide = min(_ScreenParams.x, _ScreenParams.y);
            float2 screenCell = floor(positionCS.xy / max(0.0001, finalScale * shortSide));
            return fmod(screenCell.x + screenCell.y, 2.0);
        }

        Varyings vert(Attributes IN) {
            Varyings OUT;
            VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
            OUT.positionCS = posInputs.positionCS;
            OUT.positionWS = posInputs.positionWS;
            OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
            OUT.uv = TRANSFORM_TEX(IN.uv, _IndexTex);
            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
            OUT.shadowCoord = GetShadowCoord(posInputs);
            #endif
            return OUT;
        }

        // Full Lighting Engine from v25/v31
        int GetShadedRow(float lightFactor, float plaid, float3 positionWS) {
            float shaped = 1.0 - (1.0 - lightFactor) * (1.0 - lightFactor);
            shaped = floor(clamp(shaped * _LightScale, _Ambient, 1.0) * _LightSteps + 0.5) / _LightSteps;
            
            float shapedGrad = max(abs(ddx(shaped)), abs(ddy(shaped)));
            float adaptiveBand = max(_ThreshBand, min(shapedGrad * _BandScale, _BandCap));

            float tBlack = _ThreshBlack;
            float tDark = max(_ThreshDark, tBlack + adaptiveBand);
            float tMid = max(_ThreshMid, tDark + adaptiveBand);
            float tDither = max(_ThreshDither, tMid);
            bool dithBit = (plaid < 0.5);

            if (shaped < tBlack) return 3;
            if (shaped < tDark) return dithBit ? 3 : 2;
            if (shaped < tMid) return dithBit ? 2 : 1;
            if (shaped < tDither) return dithBit ? 1 : 0;
            return 0;
        }
        ENDHLSL

        Pass
        {
            Name "BackFaces"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite [_ZWrite]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragBackFaces
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS

            half4 fragBackFaces(Varyings IN, half facing : VFACE) : SV_Target {
                if (_Cull > 1.5) clip(-1.0);
                float2 snappedUV = (floor(IN.uv * _IndexTex_TexelSize.zw) + 0.5) * _IndexTex_TexelSize.xy;
                float4 inputSample = SAMPLE_TEXTURE2D_LOD(_IndexTex, sampler_point_clamp, snappedUV, 0);
                float plaid = CalculatePlaid(IN.positionCS, IN.positionWS);
                clip(inputSample.a - _Cutoff);
                if (_AlphaMode > 0.5 && _AlphaMode < 1.5) clip(inputSample.a - plaid);

                int colorIdx = 0; float minDist = 1e9;
                for (int p = 0; p < 16; p++) {
                    float3 palColor = SamplePalette(p, 0);
                    float3 diff = inputSample.rgb - palColor;
                    float d = dot(diff, diff);
                    if (d < minDist) { minDist = d; colorIdx = p; }
                }

                if (_BackFaceMode < 0.5) return half4(SamplePalette(colorIdx, 0), 1.0);
                if (_BackFaceMode < 1.5) return half4(SamplePalette(colorIdx, 3), 1.0);

                float3 normalWS = normalize(IN.normalWS) * -1.0;
                if (_FlatShading > 0.5) normalWS = normalize(cross(ddy(IN.positionWS), ddx(IN.positionWS)));
                
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    float4 shadowCoord = IN.shadowCoord;
                #else
                    float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                #endif

                Light mainLight = GetMainLight(shadowCoord);
                float lightSign = (_InvertLight > 0.5) != (_InvertLightBack > 0.5) ? -1.0 : 1.0;
                float lightFactor = saturate(dot(normalWS, mainLight.direction) * lightSign) * step(_ShadowCutoff, mainLight.shadowAttenuation);

                for (int i = 0; i < GetAdditionalLightsCount(); i++) {
                    Light addLight = GetAdditionalLight(i, IN.positionWS);
                    lightFactor += saturate(dot(normalWS, addLight.direction) * lightSign) * addLight.distanceAttenuation;
                }

                return half4(SamplePalette(colorIdx, GetShadedRow(lightFactor, plaid, IN.positionWS)), 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull [_Cull]
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite [_ZWrite]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS

            half4 frag(Varyings IN, half facing : VFACE) : SV_Target {
                bool isBackFace = (facing < 0.0);
                if (_Cull < 0.5 && isBackFace) clip(-1.0);
                if (_Cull > 0.5 && _Cull < 1.5) clip(-1.0);

                float2 snappedUV = (floor(IN.uv * _IndexTex_TexelSize.zw) + 0.5) * _IndexTex_TexelSize.xy;
                float4 inputSample = SAMPLE_TEXTURE2D_LOD(_IndexTex, sampler_point_clamp, snappedUV, 0);
                float plaid = CalculatePlaid(IN.positionCS, IN.positionWS);
                clip(inputSample.a - _Cutoff);
                if (_AlphaMode > 0.5 && _AlphaMode < 1.5) clip(inputSample.a - plaid);

                int colorIdx = 0; float minDist = 1e9;
                for (int p = 0; p < 16; p++) {
                    float3 palColor = SamplePalette(p, 0);
                    float3 diff = inputSample.rgb - palColor;
                    float d = dot(diff, diff);
                    if (d < minDist) { minDist = d; colorIdx = p; }
                }

                float3 normalWS = normalize(IN.normalWS) * (isBackFace ? -1.0 : 1.0);
                if (_FlatShading > 0.5) normalWS = normalize(cross(ddy(IN.positionWS), ddx(IN.positionWS)));
                
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    float4 shadowCoord = IN.shadowCoord;
                #else
                    float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                #endif

                Light mainLight = GetMainLight(shadowCoord);
                float lightSign = (_InvertLight > 0.5) != (isBackFace && _InvertLightBack > 0.5) ? -1.0 : 1.0;
                float lightFactor = saturate(dot(normalWS, mainLight.direction) * lightSign) * step(_ShadowCutoff, mainLight.shadowAttenuation);

                for (int i = 0; i < GetAdditionalLightsCount(); i++) {
                    Light addLight = GetAdditionalLight(i, IN.positionWS);
                    lightFactor += saturate(dot(normalWS, addLight.direction) * lightSign) * addLight.distanceAttenuation;
                }
                
                int paletteRow = GetShadedRow(lightFactor, plaid, IN.positionWS);
                return half4(SamplePalette(colorIdx, paletteRow), (_AlphaMode > 1.5) ? inputSample.a : 1.0);
            }
            ENDHLSL
        }
    }
    FallBack Off
}