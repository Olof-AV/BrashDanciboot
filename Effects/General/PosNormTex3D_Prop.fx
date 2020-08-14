#include "Helper_Shadows.fx"

//Base
float4x4 gWorld : WORLD;
float4x4 gWorldViewProj : WORLDVIEWPROJECTION;
float4x4 gMatrixViewInverse : VIEWINVERSE;

//To fix warning
float4x4 gMatrixView : VIEW;
float4x4 gMatrixViewProj : VIEWPROJECTION;

//Diffuse
Texture2D gDiffuseMap;

//Specular
float3 gSpecularColour;
float gShininess;
float gSpecularFresnelPower;
float gSpecularFresnelMult;

//Normal
Texture2D gNormalMap;
bool gUseNormalMap;
bool gFlipNormalGreenChannel;

//Light warp
Texture2D gLightWarpMap;

//Ambient
float3 gAmbientColour;

SamplerState samLinear
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Wrap;// or Mirror or Clamp or Border
    AddressV = Wrap;// or Mirror or Clamp or Border
};

SamplerState samWarp
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Clamp; // or Mirror or Clamp or Border
    AddressV = Clamp; // or Mirror or Clamp or Border
};

RasterizerState Solid
{
	FillMode = SOLID;
	CullMode = FRONT;
};


struct VS_INPUT
{
	float3 pos : POSITION;
    float3 normal : NORMAL;
    float3 tangent : TANGENT;
    float3 binormal : BINORMAL;
	float2 texCoord : TEXCOORD;
};

struct VS_OUTPUT
{
	float4 pos : SV_POSITION;
	float4 worldPos : COLOR0;
    float3 normal : NORMAL;
    float3 tangent : TANGENT;
    float3 binormal : BINORMAL;
    float2 texCoord : TEXCOORD;
    float4 lPos : TEXCOORD1;
};

//NORMAL MAPPING FUNCTION
float3 CalculateNormal(float3 tangent, float3 binormal, float3 normal, float2 texCoord)
{
    float3 newNormal = normal;
	
	//Only modify if using normal map
	if(gUseNormalMap)
    {
		if(gFlipNormalGreenChannel)
        {
            binormal = -binormal;
        }
		
		//Get local axis
        float3x3 localAxis = float3x3(tangent, binormal, normal);
		
		//Transform sampled normal from texture according to calculated axis
        float3 sampledNormal = gNormalMap.Sample(samLinear, texCoord);
        newNormal = 2.f * sampledNormal - 1.f;
        newNormal = mul(newNormal, localAxis);
        newNormal = normalize(newNormal);
    }
	
    return newNormal;
}

//SPECULAR FUNCTION (PHONG)
float3 CalculateSpecularPhong(float3 viewDirection, float3 normal)
{
	//Specular Specular Logic
    float3 reflectedVector = normalize(reflect(gLightDirection, normal));
	
	//Get observedArea of the vectors
    float observedArea = saturate(dot(reflectedVector, viewDirection));
	
	//Return result
    return gSpecularColour * pow(observedArea, gShininess);
}

//--------------------------------------------------------------------------------------
// Vertex Shader
//--------------------------------------------------------------------------------------
VS_OUTPUT VS(VS_INPUT input)
{
	//Initialise
    VS_OUTPUT output = (VS_OUTPUT) 0;
	
    //Transform
    output.pos = mul(float4(input.pos, 1.f), gWorldViewProj);
    output.worldPos = mul(float4(input.pos, 1.f), gWorld);
    output.normal = normalize(mul(input.normal, (float3x3) gWorld));
    output.tangent = normalize(mul(input.tangent, (float3x3) gWorld));
    output.binormal = normalize(mul(input.binormal, (float3x3) gWorld));
	
	//Light pos
    output.lPos = mul(float4(input.pos, 1.f), gWorldViewProj_Light);
	
    output.texCoord = input.texCoord;
    return output;
}

//--------------------------------------------------------------------------------------
// Pixel Shader
//--------------------------------------------------------------------------------------
float4 PS(VS_OUTPUT input) : SV_TARGET
{
	//Value of this current pixel, is it in shadow or nah
    float shadowValue = EvaluateShadowMap(input.lPos);
	
	//Get view dir
    float3 viewDirection = normalize(input.worldPos.xyz - gMatrixViewInverse[3].xyz);
    input.normal = CalculateNormal(input.tangent, input.binormal, input.normal, input.texCoord); //normal map
	
	//Get albedo colour
	float4 albedoColor = gDiffuseMap.Sample(samLinear,input.texCoord);
    float3 color_rgb = albedoColor.rgb;
    float color_a = albedoColor.a;
	
	//Apply half lambert (non squared)
	float diffuseStrength = dot(input.normal, -gLightDirection);
	diffuseStrength = (diffuseStrength * 0.5f) + 0.5f;
    diffuseStrength = saturate(diffuseStrength) * shadowValue;
	
	//Get light warp according to halflambert
    float3 lightWarp = gLightWarpMap.Sample(samWarp, float2(diffuseStrength, diffuseStrength));
	
	//Diffuse
    float3 diffuse = gAmbientColour + lightWarp;
	
	//Phong specular
    float specFresnel = saturate(pow(((1.f - saturate(abs(dot(input.normal, viewDirection))))), gSpecularFresnelPower) * gSpecularFresnelMult);
    float3 phong = specFresnel * CalculateSpecularPhong(-viewDirection, input.normal);
	
	//Obtain final colour
    color_rgb = saturate(diffuse * color_rgb + phong * shadowValue);

	//Return it
    return float4(color_rgb, color_a);
}

//--------------------------------------------------------------------------------------
// Technique
//--------------------------------------------------------------------------------------
technique11 Default
{
    pass P0
    {
		SetRasterizerState(Solid);
		SetVertexShader( CompileShader( vs_4_0, VS() ) );
		SetGeometryShader( NULL );
		SetPixelShader( CompileShader( ps_4_0, PS() ) );
    }
}

