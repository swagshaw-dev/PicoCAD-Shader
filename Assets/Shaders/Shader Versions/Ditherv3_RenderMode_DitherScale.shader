Shader "Custom/Ditherv3_RenderMode_DitherScale"
{
    Properties
    {
        _IndexTex("Index Texture", 2D) = "white" {}
        _PaletteTex("Palette Texture", 2D) = "white" {}
        _Ambient("Ambient", Float) = 0.2
        _LightDir("Light Direction", Vector) = (0.3, 0.6, 0.8, 0)
        _RenderMode("Render Mode", Int) = 0   // 0 = texture, 1 = vertex index
        _DitherScale("Dither Scale (px)", Float) = 1.0
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
            int _RenderMode;
            float _DitherScale;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv     : TEXCOORD0;
                float  colorIndex : TEXCOORD1;   // vertex index
            };

            struct v2f
            {
                float4 pos       : SV_POSITION;
                float3 normal    : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
                float2 uv        : TEXCOORD2;
                float  colorIndex : TEXCOORD3;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.pos       = UnityObjectToClipPos(v.vertex);
                o.normal    = UnityObjectToWorldNormal(v.normal);
                o.screenPos = ComputeScreenPos(o.pos);
                o.uv        = v.uv;
                o.colorIndex = v.colorIndex;
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                // --- renderMode switching ---
                float idx;
                if (_RenderMode == 0)
                {
                    float texSample = tex2D(_IndexTex, i.uv).r;
                    idx = floor(texSample * 255.0 + 0.5);
                }
                else
                {
                    idx = i.colorIndex;
                }
                idx = clamp(idx, 0.0, 15.0);

                // --- lighting ---
                float3 n = normalize(i.normal);
                float3 L = normalize(_LightDir.xyz);
                float rawDot      = -dot(n, L);
                float lightFactor = 1.0 - (1.0 - rawDot) * (1.0 - rawDot);
                lightFactor       = clamp(lightFactor, _Ambient, 1.0);

                // --- screen-space checker with adjustable scale ---
                // Reconstruct pixel coords (Unity ComputeScreenPos -> divide by w)
                float2 fragCoord = i.screenPos.xy / i.screenPos.w;

                // Protect against zero/negative scale
                float scale = max(0.0001, _DitherScale);

                // Use floor(fragCoord/scale) to control checker size in pixels
                float checker = fmod(floor(fragCoord.x / scale) + floor(fragCoord.y / scale), 2.0);

                // --- shading bands ---
                int paletteRow = 0; // bright
                if (lightFactor < 0.4)
                    paletteRow = 2; // dark
                else if (lightFactor < 0.56)
                    paletteRow = 1; // mid
                else if (lightFactor < 0.75)
                    paletteRow = (checker < 0.5) ? 1 : 0;
                else
                    paletteRow = 0;

                // --- palette lookup ---
                float u = (idx + 0.5) / 16.0;
                float v = (paletteRow + 0.5) / 3.0;
                float3 finalColor = tex2D(_PaletteTex, float2(u, v)).rgb;

                return float4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }
}
