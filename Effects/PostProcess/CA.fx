#include "Helper_PP.fx"

//Intensity of chromatic aberration effect
float gMult;

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
    //Compare pixel to center
    float2 dir = float2(0.5f, 0.5f) - input.TexCoord;
    
    //Distortion intensity comes into play here
    float blue = gTexture.Sample(samPoint, input.TexCoord).b;
    float green = gTexture.Sample(samPoint, input.TexCoord + dir * 0.01f * gMult).g;
    float red = gTexture.Sample(samPoint, input.TexCoord + dir * 0.02f * gMult).r;
    
    //Return result
    return float4(red, green, blue, 1.f);
}


//TECHNIQUE
//---------
technique11 CA
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