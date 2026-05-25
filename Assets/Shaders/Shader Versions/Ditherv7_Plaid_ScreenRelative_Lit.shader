Shader "Custom/Ditherv7_Plaid_ScreenRelative_Lit"
{
    Properties
    {
        _IndexTex("Index Texture", 2D) = "white" {}
        _PaletteTex("Palette Texture", 2D) = "white" {}
        _Ambient("Ambient", Float) = 0.2
        _RenderMode("Render Mode", Int) = 0

        // Plaid controls
        _DitherMode("Dither Mode 0=px 1=relative", Int) = 1
        _DitherScaleA("Plaid Scale A", Float) = 0.02
        _DitherScaleB("Plaid Scale B", Float) = 0.04
        _PlaidAngle("Plaid Angle (deg)", Float) = 45.0
        _PlaidBlend("Plaid Blend", Range(0,1)) = 1.0

        // Material light color fallback (can be driven from script to match scene light)
        _LightColor("Light Color", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Pass
        {
            ZWrite On
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _IndexTex;
            sampler2D _PaletteTex;
            float _Ambient;
            int _RenderMode;

            int _DitherMode;
            float _DitherScaleA;
            float _DitherScaleB;
            float _PlaidAngle;
            float _PlaidBlend;

            float4 _LightColor; // material-provided light color fallback

            // Unity provides _WorldSpaceLightPos0 and _ScreenParams automatically

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv     : TEXCOORD0;
                float  colorIndex : TEXCOORD1;
            };

            struct v2f
            {
                float4 pos       : SV_POSITION; // pixel coords available in frag as i.pos.xy
                float3 normal    : TEXCOORD0;   // world normal
                float3 worldPos  : TEXCOORD1;   // world position
                float4 screenPos : TEXCOORD2;
                float2 uv        : TEXCOORD3;
                float  colorIndex : TEXCOORD4;
            };

            v2f vert(appdata v)
            {
                v2f o;
                float4 worldPos4 = mul(unity_ObjectToWorld, v.vertex);
                o.worldPos = worldPos4.xyz;
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
                // --- index selection
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

                // --- compute light direction from Unity main light
                // _WorldSpaceLightPos0: if w==0 => directional light (direction = xyz)
                // if w!=0 => positional light (position = xyz)
                float3 L;
                float4 wLight = _WorldSpaceLightPos0; // built-in
                if (abs(wLight.w) < 0.5) // directional light
                {
                    // Unity stores directional light direction in _WorldSpaceLightPos0.xyz
                    // Use it directly (normalize to be safe)
                    L = normalize(wLight.xyz);
                }
                else
                {
                    // point light: direction from surface to light position
                    L = normalize(wLight.xyz - i.worldPos);
                }

                // --- light color / intensity
                // Use material-provided _LightColor as a fallback; script can update it to match scene light.
                float3 lightCol = _LightColor.rgb;
                // compute luminance of the light color to scale the dot
                float lightIntensity = dot(lightCol, float3(0.2126, 0.7152, 0.0722));

                // --- lighting shaping (GLSL-style shaping)
                float3 n = normalize(i.normal);
                float rawDot = -dot(n, L);
                rawDot *= lightIntensity;
                float lightFactor = 1.0 - (1.0 - rawDot) * (1.0 - rawDot);
                lightFactor = clamp(lightFactor, _Ambient, 1.0);

                // --- screen pixel coords
                float2 fragCoord = i.pos.xy; // pixel coordinates

                // --- compute effective scales (screen-relative or pixel)
                float screenW = _ScreenParams.x;
                float screenH = _ScreenParams.y;
                float shortSide = min(screenW, screenH);

                float scaleA = _DitherScaleA;
                float scaleB = _DitherScaleB;

                if (_DitherMode == 1)
                {
                    scaleA = max(0.0001, _DitherScaleA * shortSide);
                    scaleB = max(0.0001, _DitherScaleB * shortSide);
                }
                else
                {
                    scaleA = max(0.0001, scaleA);
                    scaleB = max(0.0001, scaleB);
                }

                // --- Plaid computation
                float2 cellA = floor(fragCoord / scaleA);
                float checkerA = fmod(cellA.x + cellA.y, 2.0);

                float angleRad = radians(_PlaidAngle);
                // rotate around screen center for nicer symmetry
                float2 center = float2(screenW, screenH) * 0.5;
                float2 rel = fragCoord - center;
                float2 rotated = rotate2(rel, angleRad) + center;
                float2 cellB = floor(rotated / scaleB);
                float checkerB = fmod(cellB.x + cellB.y, 2.0);

                float plaidRaw = checkerA * checkerB;
                float plaid = lerp(checkerA, plaidRaw, saturate(_PlaidBlend));

                // --- shading bands (plaid only in mid band)
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
                    paletteRow = (plaid < 0.5) ? 1 : 0;
                }
                else
                {
                    paletteRow = 0;
                }

                // --- palette lookup
                float u = (idx + 0.5) / 16.0;
                float v = (paletteRow + 0.5) / 3.0;
                float3 finalColor = tex2D(_PaletteTex, float2(u, v)).rgb;

                // Optional: tint by light color (uncomment to enable)
                // finalColor *= lightCol;

                return float4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }
}
