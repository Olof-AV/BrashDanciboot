#include "stdafx.h"
#include "FruitItem.h"
#include "Components.h"

#include "../Materials/PropMaterial.h"
#include "ContentManager.h"
#include "PhysxManager.h"

#include "PlayerChar.h"
#include "GameScene.h"

#include "OverlordGame.h"

PropMaterial* FruitItem::m_pMaterial = nullptr;
UINT FruitItem::m_MaterialID = 6;
UINT FruitItem::m_InstanceCounter = 0;

FruitItem::FruitItem(PlayerChar* const pPlayer) : m_pPlayer{ pPlayer }
{
    m_InstanceCounter++;

    physx::PxPhysics* const pPhysX = PhysxManager::GetInstance()->GetPhysics();

    //Fruit components and so on
    {
        GetTransform()->Scale(0.1f, 0.1f, 0.1f);
        m_pModel = new ModelComponent(L"./Resources/Meshes/Fruit/Fruit.ovm");
        AddComponent(m_pModel);

        //Setup rigid body
        RigidBodyComponent* const pRigid = new RigidBodyComponent(false);
        AddComponent(pRigid);

        //Geometry
        physx::PxConvexMesh* const pGeometry = ContentManager::Load<physx::PxConvexMesh>(L"Resources/Meshes/Fruit/Fruit.ovpc");
        std::shared_ptr<physx::PxGeometry> pSharedGeom{ new physx::PxConvexMeshGeometry(pGeometry, physx::PxMeshScale(0.1f)) };
        physx::PxMaterial* const pMat = pPhysX->createMaterial(0.2f, 0.1f, 0.4f);
        AddComponent(new ColliderComponent(pSharedGeom, *pMat, physx::PxTransform::createIdentity()));
    }

    //Trigger
    {
        std::shared_ptr<physx::PxGeometry> pSharedGeom{ new physx::PxSphereGeometry(4.f) };
        physx::PxMaterial* const pMat = pPhysX->createMaterial(0.2f, 0.1f, 0.4f);
        ColliderComponent* const pCC = new ColliderComponent(pSharedGeom, *pMat, physx::PxTransform(0.f, 3.f, 0.f));
        pCC->EnableTrigger(true);
        AddComponent(pCC);

        //Bind callback
        SetOnTriggerCallBack(std::bind(&FruitItem::TouchTrigger, this, std::placeholders::_1, std::placeholders::_2, std::placeholders::_3));
    }
}

FruitItem::~FruitItem()
{
    if (--m_InstanceCounter == 0)
    {
        GetScene()->GetGameContext().pMaterialManager->RemoveMaterial(m_MaterialID);
        m_pMaterial = nullptr;
    }
}

void FruitItem::Initialize(const GameContext& gameContext)
{
    //If no material, initialise
    if (!m_pMaterial)
    {
        //Material
        m_pMaterial = new PropMaterial();
        m_pMaterial->SetDiffuseTexture(L"./Resources/Textures/Fruit/Fruit_Diffuse.png");
        m_pMaterial->SetLightWarpTexture(L"./Resources/Textures/Player/LightWarp.png");
        m_pMaterial->SetLightDirection(gameContext.pShadowMapper->GetLightDirection());
        gameContext.pMaterialManager->AddMaterial(m_pMaterial, m_MaterialID);
    }

    //Set material on model
    m_pModel->SetMaterial(m_MaterialID);
}

void FruitItem::PostInitialize(const GameContext& gameContext)
{
    UNREFERENCED_PARAMETER(gameContext);
    GetComponent<RigidBodyComponent>()->GetPxRigidBody()->setMass(2.f);
}

void FruitItem::Update(const GameContext& gameContext)
{
    UNREFERENCED_PARAMETER(gameContext);

    //TouchTrigger has been triggered
    if (m_Touched)
    {
        Collect();
    }
}

void FruitItem::Draw(const GameContext& gameContext)
{
    //Drawing done by another component
    UNREFERENCED_PARAMETER(gameContext);
}

void FruitItem::TouchTrigger(GameObject* pTrigger, GameObject* pOther, GameObject::TriggerAction triggerAction)
{
    //Will be taken care of on next frame
    if (pTrigger && pOther == m_pPlayer && triggerAction == TriggerAction::ENTER)
    {
        m_Touched = true;
    }
}

void FruitItem::Collect()
{
    const GameContext& gameContext = GetScene()->GetGameContext();

    //Matrices
    const DirectX::XMFLOAT4X4 world = GetTransform()->GetWorld();
    const DirectX::XMFLOAT4X4 view = gameContext.pCamera->GetView();
    const DirectX::XMFLOAT4X4 projection = gameContext.pCamera->GetProjection();
    const DirectX::XMVECTOR pos = DirectX::XMVectorSet(0.f, 2.0f, 0.f, 1.f);

    //Get screen pos
    const GameSettings::WindowSettings windowSettings = OverlordGame::GetGameSettings().Window;
    DirectX::XMFLOAT3 screenPos;
    DirectX::XMStoreFloat3(&screenPos, DirectX::XMVector3Project(pos, 0.f, 0.f, (float)windowSettings.Width, (float)windowSettings.Height, 0.f, 1.f,
        DirectX::XMLoadFloat4x4(&projection), DirectX::XMLoadFloat4x4(&view), DirectX::XMLoadFloat4x4(&world)));

    //Add fruit, effect will play out from the pos where the fruit previously existed
    m_pPlayer->AddFruit(1, screenPos);

    //Remove from scene
    GetScene()->MarkChildForDelete(this);
}
