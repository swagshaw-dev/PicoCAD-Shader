Shader "Custom/v28_Optimized" 
{
    Properties
    {
        _IndexTex("Index Texture", 2D) = "white" {}
        _PaletteTex("Palette (16 x 4)", 2D) = "white" {}
        _DitherScaleA("Dither Scale", Float) = 0.02
        _Ambient("Ambient", Range(0,1)) = 0.15
        _LightScale("Light Scale", Range(0, 4)) = 1.65
        _LightSteps("Light Steps", Range(2, 8)) = 8
        _ThreshBlack("Thresh Black", Range(0,1)) = 0.2
        _ThreshDark("Thresh Dark", Range(0,1)) = 0.16
        _ThreshMid("Thresh Mid", Range(0,1)) = 0.4
        _ThreshDither("Thresh Dither", Range(0,1)) = 0.8
        [Toggle] _FlatShading("Flat Shading", Float) = 1
        [Enum(Front,2,Back,1,Both,0)] _Cull("Show Faces", Float) = 0
        _Cutoff("Alpha Cutoff", Range(0,1)) = 0.1
    }

    SubShader
    {
        // Changed Queue to AlphaTest to ensure it renders in the correct order for cutouts
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        TEXTURE2D(_IndexTex); SAMPLER(sampler_IndexTex);
        TEXTURE2D(_PaletteTex); SAMPLER(sampler_PaletteTex);
        SamplerState sampler_point_clamp;

        CBUFFER_START(UnityPerMaterial)
            float4 _IndexTex_ST;
            float4 _IndexTex_TexelSize;
            half _Ambient, _LightScale, _LightSteps, _Cutoff;
            half _ThreshBlack, _ThreshDark, _ThreshMid, _ThreshDither;
            half _DitherScaleA, _FlatShading, _Cull;
        CBUFFER_END

        struct Attributes {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
            float2 uv : TEXCOORD0;
        };

        struct Varyings {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            half3 normalWS : TEXCOORD1;
            float3 positionWS : TEXCOORD2;
            float4 shadowCoord : TEXCOORD3;
        };

        half3 SamplePal(int idx, int row) {
            // Ensure UVs stay within the 16x4 grid exactly
            float2 uv = float2((idx + 0.5) / 16.0, 1.0 - (row + 0.5) / 4.0);
            return SAMPLE_TEXTURE2D_LOD(_PaletteTex, sampler_point_clamp, uv, 0).rgb;
        }

        Varyings vert(Attributes IN) {
            Varyings OUT;
            VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
            OUT.positionCS = pos.positionCS;
            OUT.positionWS = pos.positionWS;
            OUT.uv = TRANSFORM_TEX(IN.uv, _IndexTex);
            OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
            OUT.shadowCoord = GetShadowCoord(pos);
            return OUT;
        }

        half4 CommonFrag(Varyings IN, half facing) {
            // 1. Sample Index Texture with Snapping [cite: 31, 94]
            float2 snappedUV = (floor(IN.uv * _IndexTex_TexelSize.zw) + 0.5) * _IndexTex_TexelSize.xy;
            half4 tex = SAMPLE_TEXTURE2D_LOD(_IndexTex, sampler_point_clamp, snappedUV, 0);
            
            // 2. Immediate Alpha Check
            clip(tex.a - _Cutoff);

            // 3. Screen-space Dither Calculation [cite: 33-34, 96-99]
            half shortSide = min(_ScreenParams.x, _ScreenParams.y);
            half scale = max(0.001, _DitherScaleA * shortSide);
            half2 screenCell = floor(IN.positionCS.xy / scale);
            half plaid = fmod(screenCell.x + screenCell.y, 2.0);

            // 4. Normals [cite: 46-48, 111-113]
            half3 normalWS = normalize(IN.normalWS);
            if (facing < 0) normalWS *= -1.0; 
            
            if(_FlatShading > 0.5) {
                normalWS = normalize(cross(ddy(IN.positionWS), ddx(IN.positionWS)));
                if (facing < 0) normalWS *= -1.0;
            }

            // 5. Lighting Path [cite: 51-54, 116-119]
            Light mainLight = GetMainLight(IN.shadowCoord);
            half ndl = saturate(dot(normalWS, mainLight.direction));
            half lightFactor = saturate(ndl * mainLight.shadowAttenuation * mainLight.distanceAttenuation);
            
            // 6. Quantize Lighting [cite: 60, 125]
            half shaped = floor(saturate(lightFactor * _LightScale + _Ambient) * _LightSteps + 0.5) / _LightSteps;
            
            // 7. Palette Row Selection [cite: 65-68, 131-134]
            int row = 0;
            bool ditherBit = (plaid < 0.5);
            if (shaped < _ThreshBlack) row = 3;
            else if (shaped < _ThreshDark) row = ditherBit ? 3 : 2;
            else if (shaped < _ThreshMid) row = ditherBit ? 2 : 1;
            else if (shaped < _ThreshDither) row = ditherBit ? 1 : 0;
            else row = 0;

            // 8. Find closest color in Palette Row 0 [cite: 39-42, 104-107]
            int colorIdx = 0;
            half minDist = 100.0;
            for(int i=0; i<16; i++) {
                half3 pCol = SamplePal(i, 0);
                half3 diff = tex.rgb - pCol;
                half d = dot(diff, diff); 
                if(d < minDist) { 
                    minDist = d; 
                    colorIdx = i; 
                }
            }

            return half4(SamplePal(colorIdx, row), 1.0);
        }
        ENDHLSL

        Pass
        {
            Name "ForwardPass"
            Cull [_Cull] // Using the enum directly
            ZWrite On    // Enabled ZWrite to prevent invisibility in some depth settings
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE

            half4 frag(Varyings IN, half facing : VFACE) : SV_Target { 
                return CommonFrag(IN, facing); 
            }
            ENDHLSL
        }
    }
}