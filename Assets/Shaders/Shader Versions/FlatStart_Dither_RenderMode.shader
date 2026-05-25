Shader "Custom/FlatStart_Dither_RenderMode"
{
    Properties
    {
        _Color("Color", Color) = (1,1,1,1)
        _IndexTex("Index Texture", 2D) = "white" {}
        _RenderMode("Render Mode", Int) = 0   // 0 = texture, 1 = vertex index
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

            float4 _Color;
            sampler2D _IndexTex;
            int _RenderMode;

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
                    // sample from texture
                    idx = tex2D(_IndexTex, i.uv).r;
                }
                else
                {
                    // use vertex-provided index
                    idx = i.colorIndex;
                }

                // Basic lighting
                float3 n = normalize(i.normal);
                float light = saturate(dot(n, normalize(float3(0.3, 0.6, 0.8))));

                // Reconstruct pixel coordinates
                float2 fragCoord = i.screenPos.xy / i.screenPos.w;

                // Checker pattern
                float checker = fmod(floor(fragCoord.x) + floor(fragCoord.y), 2.0);
                float dither = checker < 0.5 ? 0.0 : 1.0;

                // Mix light with dither (just for demonstration)
                float final = lerp(light, light * 0.5, dither);

                // Multiply by index (so you can see it doing something)
                return float4(_Color.rgb * final * idx, 1.0);
            }

            ENDHLSL
        }
    }
}
