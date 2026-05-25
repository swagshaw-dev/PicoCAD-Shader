Shader "Custom/Ditherv3"
{
    Properties
    {
        _IndexTex("Index Texture", 2D) = "white" {}
        _PaletteTex("Palette Texture", 2D) = "white" {}
        _Ambient("Ambient", Float) = 0.2
        _LightDir("Light Direction", Vector) = (0.3, 0.6, 0.8, 0)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _IndexTex;
            sampler2D _PaletteTex;
            float _Ambient;
            float4 _LightDir;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv     : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos       : SV_POSITION;
                float3 normal    : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
                float2 uv        : TEXCOORD2;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos       = UnityObjectToClipPos(v.vertex);
                o.normal    = UnityObjectToWorldNormal(v.normal);
                o.screenPos = ComputeScreenPos(o.pos);
                o.uv        = v.uv;
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                // 1) Sample index texture (0–255 → 0–15)
                float texSample = tex2D(_IndexTex, i.uv).r;
                float colorIdx  = floor(texSample * 255.0 + 0.5);
                colorIdx        = clamp(colorIdx, 0.0, 15.0);

                // 2) Lighting from normals (GLSL-style shaping)
                float3 n = normalize(i.normal);
                float3 L = normalize(_LightDir.xyz);

                float rawDot     = -dot(n, L);
                float lightFactor = 1.0 - (1.0 - rawDot) * (1.0 - rawDot);
                lightFactor       = clamp(lightFactor, _Ambient, 1.0);

                // 3) Screen-space checker (Unity equivalent of gl_FragCoord)
                float2 fragCoord = i.screenPos.xy / i.screenPos.w;
                float checker    = fmod(floor(fragCoord.x) + floor(fragCoord.y), 2.0);

                // 4) Choose palette row (0=bright, 1=mid, 2=dark)
                int paletteRow = 0; // bright by default

                if (lightFactor < 0.4)
                {
                    paletteRow = 2; // dark
                }
                else if (lightFactor < 0.56)
                {
                    paletteRow = 1; // mid
                }
                else if (lightFactor < 0.75)
                {
                    // dither between mid and bright
                    paletteRow = (checker < 0.5) ? 1 : 0;
                }

                // 5) Palette lookup (16×3 texture)
                float u = (colorIdx + 0.5) / 16.0;
                float v = (paletteRow + 0.5) / 3.0;

                float3 finalColor = tex2D(_PaletteTex, float2(u, v)).rgb;

                return float4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }
}
