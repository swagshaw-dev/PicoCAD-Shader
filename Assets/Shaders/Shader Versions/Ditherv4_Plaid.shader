Shader "Custom/Ditherv4_Plaid"
{
    Properties
    {
        _IndexTex("Index Texture", 2D) = "white" {}
        _PaletteTex("Palette Texture", 2D) = "white" {}
        _Ambient("Ambient", Float) = 0.2
        _LightDir("Light Direction", Vector) = (0.3, 0.6, 0.8, 0)
        _RenderMode("Render Mode", Int) = 0   // 0 = texture, 1 = vertex index

        // Plaid controls
        _DitherScaleA("Plaid Scale A (px)", Float) = 4.0
        _DitherScaleB("Plaid Scale B (px)", Float) = 8.0
        _PlaidAngle("Plaid Angle (deg)", Float) = 45.0
        _PlaidBlend("Plaid Blend (A*B -> 0..1)", Range(0,1)) = 1.0
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

            float _DitherScaleA;
            float _DitherScaleB;
            float _PlaidAngle;
            float _PlaidBlend;

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv     : TEXCOORD0;
                float  colorIndex : TEXCOORD1;   // vertex index
            };

            struct v2f
            {
                float4 pos       : SV_POSITION; // pixel coords available in frag as i.pos.xy
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

            // rotate a 2D point by angle (radians)
            float2 rotate2(float2 p, float a)
            {
                float ca = cos(a);
                float sa = sin(a);
                return float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);
            }

            float4 frag(v2f i) : SV_Target
            {
                // --- renderMode switching: get integer index 0..15
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

                // --- lighting (GLSL-style shaping)
                float3 n = normalize(i.normal);
                float3 L = normalize(_LightDir.xyz);
                float rawDot      = -dot(n, L);
                float lightFactor = 1.0 - (1.0 - rawDot) * (1.0 - rawDot);
                lightFactor       = clamp(lightFactor, _Ambient, 1.0);

                // --- pixel coords (SV_POSITION is in pixel space in fragment)
                float2 fragCoord = i.pos.xy;

                // --- Plaid / checker computation (pixel-space)
                // Protect scales
                float scaleA = max(0.0001, _DitherScaleA);
                float scaleB = max(0.0001, _DitherScaleB);

                // Checker A: axis-aligned
                float2 cellA = floor(fragCoord / scaleA);
                float checkerA = fmod(cellA.x + cellA.y, 2.0);

                // Checker B: rotated grid
                // rotate around origin; you can add an offset if you want to shift the plaid
                float angleRad = radians(_PlaidAngle);
                float2 rotated = rotate2(fragCoord, angleRad);
                float2 cellB = floor(rotated / scaleB);
                float checkerB = fmod(cellB.x + cellB.y, 2.0);

                // Combine into a plaid. Use product for woven look, then optionally blend toward A*B.
                float plaidRaw = checkerA * checkerB; // 1 when both are 1, 0 otherwise
                // To allow softer control, mix between simple checkerA and product
                float plaid = lerp(checkerA, plaidRaw, saturate(_PlaidBlend));

                // --- shading bands (use plaid only in mid band)
                int paletteRow = 0; // bright
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
                    // use plaid to choose between mid and bright
                    paletteRow = (plaid < 0.5) ? 1 : 0;
                }
                else
                {
                    paletteRow = 0; // bright
                }

                // --- palette lookup (16x3)
                float u = (idx + 0.5) / 16.0;
                float v = (paletteRow + 0.5) / 3.0;
                float3 finalColor = tex2D(_PaletteTex, float2(u, v)).rgb;

                return float4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }
}
