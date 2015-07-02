//
// KinoFog - Deferred fog effect
//
// Copyright (C) 2015 Keijiro Takahashi
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
// the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
Shader "Hidden/Kino/Fog"
{
    Properties
    {
        _MainTex ("-", 2D) = "" {}
        _FogColor ("-", Color) = (0, 0, 0, 0)
        _SkyTint ("-", Color) = (.5, .5, .5, .5)
        [Gamma] _SkyExposure ("-", Range(0, 8)) = 1.0
        [NoScaleOffset] _SkyCubemap ("-", Cube) = "" {}
    }
    CGINCLUDE

    #include "UnityCG.cginc"

    #pragma multi_compile FOG_LINEAR FOG_EXP FOG_EXP2
    #pragma multi_compile _ RADIAL_DIST
    #pragma multi_compile _ USE_SKYBOX

    sampler2D _MainTex;
    float4 _MainTex_TexelSize;

    sampler2D_float _CameraDepthTexture;

    float _DistanceOffset;
    float _Density;
    float _LinearGrad;
    float _LinearOffs;

    // Fog/skybox information
    half4 _FogColor;
    samplerCUBE _SkyCubemap;
    half4 _SkyCubemap_HDR;
    half4 _SkyTint;
    half _SkyExposure;
    float _SkyRotation;

    struct v2f
    {
        float4 pos : SV_POSITION;
        float2 uv : TEXCOORD0;
        float2 uv_depth : TEXCOORD1;
        float3 ray : TEXCOORD2;
    };

    float3 RotateAroundYAxis(float3 v, float deg)
    {
        float alpha = deg * UNITY_PI / 180.0;
        float sina, cosa;
        sincos(alpha, sina, cosa);
        float2x2 m = float2x2(cosa, -sina, sina, cosa);
        return float3(mul(m, v.xz), v.y).xzy;
    }

    v2f vert(appdata_full v)
    {
        v2f o;

        o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
        o.uv = v.texcoord.xy;
        o.uv_depth = v.texcoord.xy;
        o.ray = RotateAroundYAxis(v.texcoord1.xyz, -_SkyRotation);

    #if UNITY_UV_STARTS_AT_TOP
        if (_MainTex_TexelSize.y < 0.0) o.uv.y = 1.0 - o.uv.y;
    #endif

        return o;
    }

    // Applies one of standard fog formulas, given fog coordinate (i.e. distance)
    half ComputeFogFactor(float coord)
    {
        float fog = 0.0;
    #if FOG_LINEAR
        // factor = (end-z)/(end-start) = z * (-1/(end-start)) + (end/(end-start))
        fog = coord * _LinearGrad + _LinearOffs;
    #elif FOG_EXP
        // factor = exp(-density*z)
        fog = _Density * coord;
        fog = exp2(-fog);
    #else // FOG_EXP2
        // factor = exp(-(density*z)^2)
        fog = _Density * coord;
        fog = exp2(-fog * fog);
    #endif
        return saturate(fog);
    }

    // Distance-based fog
    float ComputeDistance(float3 ray, float depth)
    {
        float dist;
    #if RADIAL_DIST
        dist = length(ray * depth);
    #else
        dist = depth * _ProjectionParams.z;
    #endif
        // Built-in fog starts at near plane, so match that by
        // subtracting the near value. Not a perfect approximation
        // if near plane is very large, but good enough.
        dist -= _ProjectionParams.y;
        return dist;
    }

    half4 frag(v2f i) : SV_Target
    {
        half4 sceneColor = tex2D(_MainTex, i.uv);

        // Reconstruct world space position & direction towards this screen pixel.
        float zsample = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv_depth);
        float depth = Linear01Depth(zsample * (zsample < 1.0));

        // Compute fog amount.
        float g = ComputeDistance(i.ray, depth) - _DistanceOffset;
        half fog = ComputeFogFactor(max(0.0, g));

    #if USE_SKYBOX
        // Look up the skybox color.
        half3 skyColor = DecodeHDR(texCUBE(_SkyCubemap, i.ray), _SkyCubemap_HDR);
        skyColor *= _SkyTint.rgb * _SkyExposure * unity_ColorSpaceDouble;
        // Lerp between source color to skybox color with fog amount.
        return lerp(half4(skyColor, 1), sceneColor, fog);
    #else
        // Lerp between source color to fog color with the fog amount.
        return lerp(_FogColor, sceneColor, fog);
    #endif
    }

    ENDCG
    SubShader
    {
        ZTest Always Cull Off ZWrite Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            ENDCG
        }
    }
    Fallback off
}
