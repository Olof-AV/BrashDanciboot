#include "Helper_PP.fx"

SamplerState samLUT
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

//The lookup table texture to use
Texture2D gTextureLUT;

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
//DESIGNED FOR HALD10 LUTs
//------------
float4 PS(PS_INPUT input) : SV_Target
{   
    //Get texture size
    float w;
    float h;
    gTextureLUT.GetDimensions(w, h);
    
    //Get Red and Green channel values
    //Then limit them exclusively to the first top left square
    float3 colour = saturate(gTexture.Sample(samPoint, input.TexCoord).rgb);
    colour.rg /= 8.f;
    colour.r = clamp(colour.r, 0.f, 1.f / 8.f - 1.f / w);
    colour.g = clamp(colour.g, 0.f, 1.f / 8.f - 1.f / h);
    
    //Get index for blue values
    int blueSquare = int(floor(colour.b * (8.f * 8.f - 1.f)));
    
    //Calculate offset from that index
    float2 offset;
    offset.x = blueSquare % 8 / 8.f;
    offset.y = blueSquare / 8 / 8.f;
    
    //Apply offset to final coordinate
    colour.rg += offset;
	
    //Get looked up colour
    return gTextureLUT.Sample(samLUT, colour.rg);
}

//TECHNIQUE
//---------
technique11 ColourGrade
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

