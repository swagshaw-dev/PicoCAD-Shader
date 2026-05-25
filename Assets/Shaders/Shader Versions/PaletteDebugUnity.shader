Shader "Hidden/PaletteDebugUnity"
{
    Properties
    {
        _IndexTex("Index Texture", 2D) = "white" {}
        _PaletteTex("Palette Texture", 2D) = "white" {}
        _LightDir("Light Direction", Vector) = (0.0, 0.0, 1.0, 0)
        _Ambient("Ambient", Float) = 0.15
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Overlay" }
        Pass
        {
            ZTest Always Cull Off ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _IndexTex;
            sampler2D _PaletteTex;
            float4 _LightDir;
            float _Ambient;

            struct appdata
            {
                float2 pos : POSITION; // full-screen triangle positions (-1..1)
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv  : TEXCOORD0; // 0..1
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = float4(v.pos.xy, 0.0, 1.0);
                o.uv  = v.pos * 0.5 + 0.5;
                return o;
            }

            // Helper: sample palette (idx 0..15, row 0..2)
            float3 SamplePalette(float idx, int paletteRow)
            {
                float u = (idx + 0.5) / 16.0;
                float v = (paletteRow + 0.5) / 3.0;
                return tex2D(_PaletteTex, float2(u, v)).rgb;
            }

            float4 frag(v2f i) : SV_Target
            {
                // --- index sampling (0..15)
                float texSample = tex2D(_IndexTex, i.uv).r;
                float colorIdx = floor(texSample * 255.0 + 0.5);
                colorIdx = clamp(colorIdx, 0.0, 15.0);

                // --- lighting (flat normal facing +Z for consistent band math)
                float3 n = float3(0.0, 0.0, 1.0);
                float3 L = normalize(_LightDir.xyz);
                float rawDot = -dot(n, L);
                float lightFactor = 1.0 - (1.0 - rawDot) * (1.0 - rawDot);
                lightFactor = clamp(lightFactor, _Ambient, 1.0);

                // --- checker using SV_POSITION (pixel coords)
                float2 fragCoord = i.pos.xy; // SV_POSITION is in pixel space in fragment
                float checker = fmod(floor(fragCoord.x) + floor(fragCoord.y), 2.0);

                // --- paletteRow selection (0=bright,1=mid,2=dark) with checker only in mid band
                int paletteRow = 0;
                if (lightFactor < 0.4)
                {
                    paletteRow = 2;
                }
                else if (lightFactor < 0.56)
                {
                    paletteRow = 1;
                }
                else if (lightFactor < 0.75)
                {
                    paletteRow = (checker < 0.5) ? 1 : 0;
                }
                else
                {
                    paletteRow = 0;
                }

                // --- final palette color
                float3 finalColor = SamplePalette(colorIdx, paletteRow);

                // --- split screen into three panels by uv.x
                if (i.uv.x < 0.3333333)
                {
                    // left: show index as grayscale
                    float debugIdx = colorIdx / 15.0;
                    return float4(debugIdx, debugIdx, debugIdx, 1.0);
                }
                else if (i.uv.x < 0.6666666)
                {
                    // middle: show checker and highlight mid-band pixels
                    float3 c = float3(checker, checker, checker);
                    if (paletteRow == 1) c = lerp(c, float3(0.0, 1.0, 0.0), 0.6);
                    return float4(c, 1.0);
                }
                else
                {
                    // right: show final palette result
                    return float4(finalColor, 1.0);
                }
            }

            ENDHLSL
        }
    }
}
