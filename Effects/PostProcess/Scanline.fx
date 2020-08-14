#include "Helper_PP.fx"

SamplerState samPoint_Border
{
    Filter = MIN_MAG_MIP_POINT;
    AddressU = BORDER;
    AddressV = BORDER;
    BorderColor = float4(0.f, 0.f, 0.f, 1.f);
};

float gTotalTime;

float gBend;
float gBendInfluence;

float gVigRounding;

float gHorOffsetMult;

float gScanlineSpeed;
float gScanlineScale;


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

float2 GetBentCoords(float2 uv)
{
    //Move to -1,1 range
    uv -= 0.5f;
    uv *= 2.f;
    
    //Bend happens according to the other axis
    uv.x *= 1.f + pow(abs(uv.y) / gBend, gBendInfluence);
    uv.y *= 1.f + pow(abs(uv.x) / gBend, gBendInfluence);

    //Back to 0,1 range
    uv *= 0.5f;
    return uv + 0.5f;
}

float GetAmountVignette(float2 uv)
{
    //Move to -1,1 range
    uv -= 0.5f;
    uv *= 2.f; //If you multiply by more, the distance increases -> vignette covers more of the screen
    
    //Get distance from center
    float amount = sqrt(pow(abs(uv.x), gVigRounding) + pow(abs(uv.y), gVigRounding));
    
    //The gradient should be the other way around
    amount = 1.f - amount;
    
    //Smooth interpolation
    return smoothstep(0.f, 0.8f, amount);
}

//PIXEL SHADER
//------------
float4 PS(PS_INPUT input) : SV_Target
{
    //Get texture dimensions
    float w;
    float h;
    gTexture.GetDimensions(w, h);
    
    //UV y coordinate is transformed according to time/screen height
    //From there, you can determine if the line the UV coordinate is in should be darkened or not
    float scanlinePos = (input.TexCoord.y + (gTotalTime * gScanlineSpeed)) * h;
    float amount = scanlinePos * gScanlineScale;
    
    //The darkening factor, pixel's either fully visible or darkened
    float value = clamp(fmod(floor(amount), 2.f), 0.7f, 1.f);
    
    //Offset of the horizontal UV depending on darkening
    float uvHor = (input.TexCoord - 0.5f) * 2.f;
    float horOffset = (1.f - value) * gHorOffsetMult;
    uvHor *= horOffset;
    
    float2 finalCoords = GetBentCoords(input.TexCoord + float2(uvHor, 0.f));
    
    //Final colour sample from render target
    float4 colour = gTexture.Sample(samPoint_Border, finalCoords) * value * GetAmountVignette(finalCoords);
    colour.w = 1.f;
    return colour;
}


//TECHNIQUE
//---------
technique11 Scanline
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