#include "Helper_PP.fx"

SamplerState samAniso
{
    Filter = ANISOTROPIC;
    MaxAnisotropy = 16;
    AddressU = Mirror;
    AddressV = Mirror;
};

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

float LuminanceFromLinearRGB(float3 LinearRBG)
{
    return dot(LinearRBG, float3(0.2126729f, 0.7151522f, 0.0721750f));
}

float SampleLuminanceFromLinearRGB(float2 uv, float2 offset)
{
    return LuminanceFromLinearRGB(gTexture.Sample(samPoint, uv + offset).xyz);
}

//Reference:
//https://catlikecoding.com/unity/tutorials/advanced-rendering/fxaa/
//http://developer.download.nvidia.com/assets/gamedev/files/sdk/11/FXAA_WhitePaper.pdf

//PIXEL SHADER
//------------
float4 PS(PS_INPUT input) : SV_Target
{
    //Get texture dimensions
    float w, h;
    gTexture.GetDimensions(w, h);
    
    //Size of pixel relative to uv
    float2 pixelSize = float2(1.f / w, 1.f / h);
    
    //Obtain luminance data -- FXAA only uses the middle pixel and non-diagonal neighbours
    float lumMiddle = SampleLuminanceFromLinearRGB(input.TexCoord, float2(0.f, 0.f));
    float lumLeft = SampleLuminanceFromLinearRGB(input.TexCoord, float2(-pixelSize.x, 0.f));
    float lumRight = SampleLuminanceFromLinearRGB(input.TexCoord, float2(pixelSize.x, 0.f));
    float lumTop = SampleLuminanceFromLinearRGB(input.TexCoord, float2(0.f, -pixelSize.y));
    float lumBottom = SampleLuminanceFromLinearRGB(input.TexCoord, float2(0.f, pixelSize.y));
    
    //To calculate local contrast, you then have to find out the highest and lowest contrast
    float contrastHigh = max(max(max(max(lumBottom, lumTop), lumRight), lumLeft), lumMiddle);
    float contrastLow = min(min(min(min(lumBottom, lumTop), lumRight), lumLeft), lumMiddle);
    float contrast = contrastHigh - contrastLow;
    
    //The visible contrast limit (slow setting) as defined in the original algorithm
    //   0.0833 - upper limit (default, the start of visible unfiltered edges)
	//   0.0625 - high quality (faster)
	//   0.0312 - visible limit (slower)
    if (contrast < 0.0312f)
    {
        return float4(gTexture.Sample(samPoint, input.TexCoord).xyz, 1.f);
    }
    
    //The relative contrast threshold (slow setting) as seen in the original algorithm
    //   0.333 - too little (faster)
	//   0.250 - low quality
	//   0.166 - default
	//   0.125 - high quality 
	//   0.063 - overkill (slower)
    if(contrast < 0.063f * contrastHigh)
    {
        return float4(gTexture.Sample(samPoint, input.TexCoord).xyz, 1.f);
    }
    
    //Calculate blend factor
    //We also need the diagonal neighbours for this one, so get em
    float lumTopLeft = SampleLuminanceFromLinearRGB(input.TexCoord, -pixelSize);
    float lumTopRight = SampleLuminanceFromLinearRGB(input.TexCoord, float2(pixelSize.x, -pixelSize.y));
    float lumBottomLeft = SampleLuminanceFromLinearRGB(input.TexCoord, float2(-pixelSize.x, pixelSize.y));
    float lumBottomRight = SampleLuminanceFromLinearRGB(input.TexCoord, pixelSize);
    
    //Pixel blend factor
    float filter = 2.f * (lumTop + lumBottom + lumLeft + lumRight);
    filter += lumTopLeft + lumTopRight + lumBottomLeft + lumBottomRight;
    filter /= 12.f;
    filter = abs(filter - lumMiddle); //Contrast between middle and average, via absolute difference
    filter = saturate(filter / contrast); //Filter is normalised relative to the contrast of the non-diagonal luminance values
    
    float blendFactor = smoothstep(0.f, 1.f, filter);
    blendFactor *= blendFactor;
    
    //Determine if the blend direction is horizontal or not
    float horizontal = abs(lumTop + lumBottom - 2.f * lumMiddle) * 2.f +
                       abs(lumTopLeft + lumBottomLeft - 2.f * lumLeft) +
                       abs(lumTopRight + lumBottomRight - 2.f * lumRight);
    float vertical = abs(lumLeft + lumRight - 2.f * lumMiddle) * 2.f +
                     abs(lumTopLeft + lumTopRight - 2.f * lumTop) +
                     abs(lumBottomLeft + lumBottomRight - 2.f * lumBottom);
    bool isHorizontal = horizontal >= vertical;
    
    //Should we blend in positive or negative direction?
    float lumPos = ((isHorizontal) ? lumBottom : lumRight);
    float lumNeg = ((isHorizontal) ? lumTop : lumLeft);
    
    //Determine pixel step according to previously found direction
    float pixelStep = ((isHorizontal) ? pixelSize.y : pixelSize.x);
    
    //Compare gradients
    float oppositeLuminance;
    float gradient;
    float gradientPos = abs(lumPos - lumMiddle);
    float gradientNeg = abs(lumNeg - lumMiddle);
    if (gradientPos < gradientNeg)
    {
        pixelStep = -pixelStep;
        oppositeLuminance = lumNeg;
        gradient = gradientNeg;
    }
    else
    {
        oppositeLuminance = lumPos;
        gradient = gradientPos;
    }
    
    //Edge blend factor
    float edgeBlendFactor;
    {
        float2 uvEdge = input.TexCoord;
        float2 edgeStep;
        if(isHorizontal)
        {
            uvEdge.y += pixelStep * 0.5f;
            edgeStep = float2(pixelSize.x, 0.f);
        }
        else
        {
            uvEdge.x += pixelStep * 0.5f;
            edgeStep = float2(0.f, pixelSize.y);
        }
        
        float edgeLuminance = (lumMiddle + oppositeLuminance) * 0.5f;
        float gradientThreshold = gradient * 0.25f;
        
        float2 pUV = uvEdge + edgeStep;
        float pLuminanceDelta = SampleLuminanceFromLinearRGB(pUV, float2(0.f, 0.f)) - edgeLuminance;
        bool pAtEnd = abs(pLuminanceDelta) >= gradientThreshold;
        
        for (int i = 0; i < 9 && !pAtEnd; ++i)
        {
            pUV += edgeStep;
            pLuminanceDelta = SampleLuminanceFromLinearRGB(pUV, float2(0.f, 0.f)) - edgeLuminance;
            pAtEnd = abs(pLuminanceDelta) >= gradientThreshold;
        }
        if(!pAtEnd)
        {
            pUV += edgeStep;
        }
        
        float2 nUV = uvEdge - edgeStep;
        float nLuminanceDelta = SampleLuminanceFromLinearRGB(nUV, float2(0.f, 0.f)) - edgeLuminance;
        bool nAtEnd = abs(nLuminanceDelta) >= gradientThreshold;
        
        for (int j = 0; j < 9 && !nAtEnd; ++j)
        {
            nUV -= edgeStep;
            nLuminanceDelta = SampleLuminanceFromLinearRGB(pUV, float2(0.f, 0.f)) - edgeLuminance;
            pAtEnd = abs(nLuminanceDelta) >= gradientThreshold;
        }
        if(!nAtEnd)
        {
            nUV -= edgeStep;
        }
        
        float pDistance, nDistance;
        if(isHorizontal)
        {
            pDistance = pUV.x - input.TexCoord.x;
            nDistance = input.TexCoord.x - nUV.x;
        }
        else
        {
            pDistance = pUV.y - input.TexCoord.y;
            nDistance = input.TexCoord.y - nUV.y;
        }
        
        float shortestDistance;
        bool deltaSign;
        if(pDistance <= nDistance)
        {
            shortestDistance = pDistance;
            deltaSign = pLuminanceDelta >= 0.f;
        }
        else
        {
            shortestDistance = nDistance;
            deltaSign = nLuminanceDelta >= 0.f;
        }
        
        if (deltaSign == (lumMiddle - edgeLuminance >= 0.f))
        {
            edgeBlendFactor = 0.f;
        }
        
        edgeBlendFactor = 0.5f - shortestDistance / (pDistance + nDistance);
    }
    
    //The final blend factor of FXAA is the max of these two
    float finalBlend = max(blendFactor, edgeBlendFactor);
    
    //Blending
    float2 finalUv = input.TexCoord;
    float subPixelBlending = 1.f;
    if(isHorizontal)
    {
        finalUv.y += pixelStep * finalBlend * subPixelBlending;
    }
    else
    {
        finalUv.x += pixelStep * finalBlend * subPixelBlending;
    }
    
    //Result
    return float4(gTexture.SampleLevel(samAniso, finalUv, 0).xyz, 1.f);
}


//TECHNIQUE
//---------
technique11 FXAA
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

