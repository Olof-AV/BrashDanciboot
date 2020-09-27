//Base
float4x4 gWorld : WORLD;
float4x4 gWorldViewProj : WORLDVIEWPROJECTION;
float4x4 gMatrixViewInverse : VIEWINVERSE;

//To fix warning
float4x4 gMatrixView : VIEW;
float4x4 gMatrixViewProj : VIEWPROJECTION;

//Diffuse
TextureCube gSkySphere;

SamplerState samLinear
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Wrap;// or Mirror or Clamp or Border
    AddressV = Wrap;// or Mirror or Clamp or Border
};
RasterizerState Solid
{
    FillMode = SOLID;
    CullMode = NONE;
    //CullMode = FRONT;
};


struct VS_INPUT
{
    float3 pos : POSITION;
};

struct VS_OUTPUT
{
    float4 pos : SV_POSITION;
    float4 worldPos : COLOR0;
};

//--------------------------------------------------------------------------------------
// Vertex Shader
//--------------------------------------------------------------------------------------
VS_OUTPUT VS(VS_INPUT input)
{
    //Initialise
    VS_OUTPUT output = (VS_OUTPUT) 0;
    
    float3 newPos = input.pos + gMatrixViewInverse[3].xyz;
    
    //Transform
    output.pos = mul(float4(newPos, 1.f), gWorldViewProj);
    output.worldPos = float4(newPos, 1.f);
    
    return output;
}

//--------------------------------------------------------------------------------------
// Pixel Shader
//--------------------------------------------------------------------------------------
float4 PS(VS_OUTPUT input) : SV_TARGET
{
    //Get a pos on the skysphere texture cube
    float3 viewDirection = normalize(input.worldPos.xyz - gMatrixViewInverse[3].xyz);
    
    //Return it
    return gSkySphere.Sample(samLinear, viewDirection);
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