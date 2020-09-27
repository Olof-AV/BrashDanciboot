#include "Helper_PP.fx"

SamplerState samLinear
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

float gFadeValue;

Texture2D gFadeTex;
float gNoiseScale;

//VERTEX SHADER
//-------------
PS_INPUT VS(VS_INPUT input)
{
    PS_INPUT output = (PS_INPUT)0;
    
    // Set the Position
    output.Position = float4(input.Position, 1.f);
    
    // Set the TexCoord
    output.TexCoord = input.TexCoord;
    
    return output;
}

//PIXEL SHADER
//------------
float4 PS(PS_INPUT input) : SV_Target
{
    //Get dimensions + aspect ratio
    float screenW, screenH;
    gTexture.GetDimensions(screenW, screenH);
    float aspectRatio = screenW / screenH;
    
    float2 uv = float2(input.TexCoord.x * aspectRatio, input.TexCoord.y) * gNoiseScale;
    float sampledValue = gFadeTex.Sample(samLinear, uv).x;

    //Black
    if(sampledValue > gFadeValue)
    {
        return float4(0.f, 0.f, 0.f, 1.f);
    }
    
    //Otherwise, normal
    return float4(gTexture.Sample(samPoint, input.TexCoord).xyz, 1.f);
}


//TECHNIQUE
//---------
technique11 Fade
{
    pass P0
    {
        // Set states...
        SetRasterizerState(BackCulling);
        SetDepthStencilState(Depth, 0);
        
        SetVertexShader( CompileShader( vs_4_0, VS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PS() ) );
    }
}