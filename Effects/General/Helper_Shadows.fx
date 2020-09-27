//Shadow mapping
float3 gLightDirection = float3(-0.577f, -0.577f, 0.577f);
float4x4 gWorldViewProj_Light;
float gShadowMapBias = 0.001f;
Texture2D gShadowMap;

SamplerComparisonState samCompare
{
   // sampler state
    Filter = COMPARISON_MIN_MAG_MIP_LINEAR;
    AddressU = MIRROR;
    AddressV = MIRROR;
 
   // sampler comparison state
    ComparisonFunc = LESS_EQUAL;
};

float2 texOffset(int u, int v)
{
    //Returns offseted value
    float w;
    float h;
    gShadowMap.GetDimensions(w, h);
    return float2(u * 1.f / w, v * 1.f / h);
}

float EvaluateShadowMap(float4 lpos)
{
    //Re-homogenise pos after interpolation (using w)
    lpos.xyz /= lpos.w;
    
    //If not visible to light, don't darken
    if (lpos.x < -1.f || lpos.x > 1.f ||
        lpos.y < -1.f || lpos.y > 1.f ||
        lpos.z < 0.f || lpos.z > 1.f)
    {
        return 1.f;
        //return 0.75f;
    }
    
    //Transform to valid UV coordinates
    float2 uv = float2(lpos.x * 0.5f + 0.5f, lpos.y * -0.5f + 0.5f);
    
    //Apply shadow bias
    lpos.z -= gShadowMapBias;
    
    //Get shadow map depth
    //Perform PCF filtering on 4x4 texel neighbourhood = 16-tap PCF
    float depth;
    for (float y = -1.5; y <= 1.5; y += 1.0)
    {
        for (float x = -1.5; x <= 1.5; x += 1.0)
        {
            //SampleCmpLevelZero ALREADY compares depth values for us, and also uses mipmap level 0
            depth += gShadowMap.SampleCmpLevelZero(samCompare, uv + texOffset(x, y), lpos.z).x;
        }
    }
    //16 taps so divide by that much
    depth /= 16.f;
    
    //Add a little to avoid pure black shadows, also saturate to have 0-1 range
    return saturate(depth + 0.65f);
}