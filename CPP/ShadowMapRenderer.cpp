#include "stdafx.h"
#include "ShadowMapRenderer.h"
#include "ContentManager.h"
#include "ShadowMapMaterial.h"
#include "RenderTarget.h"
#include "MeshFilter.h"
#include "SceneManager.h"
#include "OverlordGame.h"

#include "ModelComponent.h"

ShadowMapRenderer::~ShadowMapRenderer()
{
	//Watch out for memory leaks
	delete m_pShadowMat;
	delete m_pShadowRT;
}

void ShadowMapRenderer::Initialize(const GameContext& gameContext)
{
	//Early out
	if (m_IsInitialized)
	{
		return;
	}

	//Creating shadow generator material + initialize it
	m_pShadowMat = new ShadowMapMaterial();
	m_pShadowMat->Initialize(gameContext);

	//We need a new render target (shadow mapping)
	m_pShadowRT = new RenderTarget(gameContext.pDevice);

	//Create descriptor (depth ONLY)
	const GameSettings::WindowSettings windowSettings = OverlordGame::GetGameSettings().Window;
	RENDERTARGET_DESC rt_Desc{};
	rt_Desc.EnableDepthBuffer = true;
	rt_Desc.EnableDepthSRV = true;
	rt_Desc.EnableColorBuffer = false;
	rt_Desc.EnableColorSRV = false;
	rt_Desc.Width = (int)m_Dimensions.x;
	rt_Desc.Height = (int)m_Dimensions.y;

	//Create it
	m_pShadowRT->Create(rt_Desc);

	//Finished
	m_IsInitialized = true;
}

void ShadowMapRenderer::SetLight(DirectX::XMFLOAT3 position, DirectX::XMFLOAT3 direction)
{
	//XMFLOAT3 to XMVector
	m_LightPosition = position;
	DirectX::XMStoreFloat3(&m_LightDirection, DirectX::XMVector3Normalize(DirectX::XMLoadFloat3(&direction)));

	//We are making a directional light -> need an orthographic view-projection matrix
	const DirectX::XMMATRIX view = DirectX::XMMatrixLookAtLH(
		DirectX::XMLoadFloat3(&m_LightPosition),
		DirectX::XMVectorAdd(DirectX::XMLoadFloat3(&m_LightPosition), DirectX::XMLoadFloat3(&m_LightDirection)),
		DirectX::XMVectorSet(0.f, 1.0f, 0.f, 1.f) );

	const DirectX::XMMATRIX projection = DirectX::XMMatrixOrthographicLH(m_Size * /*windowSettings.AspectRatio*/ m_Dimensions.x / m_Dimensions.y, m_Size, 50.f, 500.f);

	//Saved in the appropriate data-member
	DirectX::XMStoreFloat4x4(&m_LightVP, view * projection);
}

void ShadowMapRenderer::Begin(const GameContext& gameContext) const
{
	//Reset Texture Register 5 (Unbind)
	ID3D11ShaderResourceView *const pSRV[] = { nullptr };
	gameContext.pDeviceContext->PSSetShaderResources(1, 1, pSRV);

	//We're going to write to the special shadow map Render Target
	SceneManager::GetInstance()->GetGame()->SetRenderTarget(m_pShadowRT);

	//Clear this RT first
	m_pShadowRT->Clear(gameContext, reinterpret_cast<const float*>(&DirectX::Colors::Black));

	//ViewProjection needs to be up to date
	m_pShadowMat->SetLightVP(m_LightVP);

	//Set viewport
	D3D11_VIEWPORT viewport{};
	viewport.Width = static_cast<FLOAT>(m_Dimensions.x);
	viewport.Height = static_cast<FLOAT>(m_Dimensions.y);
	viewport.TopLeftX = 0.f;
	viewport.TopLeftY = 0.f;
	viewport.MinDepth = 0.0f;
	viewport.MaxDepth = 1.0f;
	SceneManager::GetInstance()->GetGame()->SetViewport(&viewport);
}

void ShadowMapRenderer::End(const GameContext& gameContext) const
{
	UNREFERENCED_PARAMETER(gameContext);
	
	//Shadow pass is finished, reset RT
	SceneManager::GetInstance()->GetGame()->SetRenderTarget(nullptr);

	//Reet viewport
	SceneManager::GetInstance()->GetGame()->SetViewport(nullptr);
}

void ShadowMapRenderer::DrawFoliage(const GameContext& gameContext, MeshFilter* pMeshFilter, DirectX::XMFLOAT4X4 world, ModelComponent* const pModelComp) const
{
	//Updating shader variables in material
	m_pShadowMat->SetLightVP(m_LightVP);
	m_pShadowMat->SetWorld(world);

	m_pShadowMat->SetFoliageTexture(pModelComp->GetFoliageTexture());
	m_pShadowMat->SetFoliageSwayDir(pModelComp->GetFoliageSwayDir());
	m_pShadowMat->SetFoliageSwaySpeed(pModelComp->GetFoliageSwaySpeed());
	m_pShadowMat->SetFoliageSwayStrength(pModelComp->GetFoliageSwayStrength());
	m_pShadowMat->SetFoliagePosMult(pModelComp->GetFoliagePosMult());
	m_pShadowMat->SetTotalTime(gameContext.pGameTime->GetTotal());

	//Setting the correct inputlayout, buffers, topology
	const UINT index = (UINT)m_pShadowMat->Foliage;

	//Set buffers
	const UINT offset = 0;
	const VertexBufferData data = pMeshFilter->GetVertexBufferData(gameContext, m_pShadowMat->m_InputLayoutIds[index]);
	gameContext.pDeviceContext->IASetVertexBuffers(0, 1, &data.pVertexBuffer, &data.VertexStride, &offset);
	gameContext.pDeviceContext->IASetIndexBuffer(pMeshFilter->m_pIndexBuffer, DXGI_FORMAT_R32_UINT, 0);

	//Set topology+layouts
	gameContext.pDeviceContext->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY::D3D10_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
	gameContext.pDeviceContext->IASetInputLayout(m_pShadowMat->m_pInputLayouts[index]);

	//Draw
	D3DX11_TECHNIQUE_DESC techDesc;
	m_pShadowMat->m_pShadowTechs[index]->GetDesc(&techDesc);
	for (UINT p = 0; p < techDesc.Passes; ++p)
	{
		m_pShadowMat->m_pShadowTechs[index]->GetPassByIndex(p)->Apply(0, gameContext.pDeviceContext);
		gameContext.pDeviceContext->DrawIndexed(data.IndexCount, 0, 0);
	}
}

void ShadowMapRenderer::Draw(const GameContext& gameContext, MeshFilter* pMeshFilter, DirectX::XMFLOAT4X4 world, const std::vector<DirectX::XMFLOAT4X4>& bones) const
{
	//Updating shader variables in material
	m_pShadowMat->SetBones(*bones.data()->m, bones.size());
	m_pShadowMat->SetLightVP(m_LightVP);
	m_pShadowMat->SetWorld(world);

	m_pShadowMat->SetTotalTime(gameContext.pGameTime->GetTotal());

	//Setting the correct inputlayout, buffers, topology
	//(some variables are set based on the generation type Skinned or Static)
	const UINT index = (pMeshFilter->m_HasAnimations) ? (UINT)m_pShadowMat->Skinned : (UINT)m_pShadowMat->Static;

	//Set buffers
	const UINT offset = 0;
	const VertexBufferData data = pMeshFilter->GetVertexBufferData(gameContext, m_pShadowMat->m_InputLayoutIds[index]);
	gameContext.pDeviceContext->IASetVertexBuffers(0, 1, &data.pVertexBuffer, &data.VertexStride, &offset);
	gameContext.pDeviceContext->IASetIndexBuffer(pMeshFilter->m_pIndexBuffer, DXGI_FORMAT_R32_UINT, 0);

	//Set topology+layouts
	gameContext.pDeviceContext->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY::D3D10_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
	gameContext.pDeviceContext->IASetInputLayout(m_pShadowMat->m_pInputLayouts[index]);

	//Draw
	D3DX11_TECHNIQUE_DESC techDesc;
	m_pShadowMat->m_pShadowTechs[index]->GetDesc(&techDesc);
	for (UINT p = 0; p < techDesc.Passes; ++p)
	{
		m_pShadowMat->m_pShadowTechs[index]->GetPassByIndex(p)->Apply(0, gameContext.pDeviceContext);
		gameContext.pDeviceContext->DrawIndexed(data.IndexCount, 0, 0);
	}
}

void ShadowMapRenderer::UpdateMeshFilter(const GameContext& gameContext, MeshFilter* pMeshFilter, bool isFoliage)
{
	//Use different index based on the type of mesh
	const UINT index = (isFoliage) ? (UINT)m_pShadowMat->Foliage : ((pMeshFilter->m_HasAnimations) ? (UINT)m_pShadowMat->Skinned : (UINT)m_pShadowMat->Static);

	pMeshFilter->BuildVertexBuffer(gameContext, m_pShadowMat->m_InputLayoutIds[index], m_pShadowMat->m_InputLayoutSizes[index], m_pShadowMat->m_InputLayoutDescriptions[index] );
	pMeshFilter->BuildIndexBuffer(gameContext);
}

ID3D11ShaderResourceView* ShadowMapRenderer::GetShadowMap() const
{
	//Returns the depth shader resource view of the shadow generator render target
	return m_pShadowRT->GetDepthShaderResourceView();
}
