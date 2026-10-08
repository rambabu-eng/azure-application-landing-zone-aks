data "azurerm_client_config" "current" {}

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name     = var.resource_group_name
  location = var.location
}

module "nsg_aks_nodes" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  name                = "nsg-aks-nodes-australiaeast"
  resource_group_name = module.resource_group.name
  location            = var.location
}

module "nsg_private_endpoints" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  name                = "nsg-private-endpoints-australiaeast"
  resource_group_name = module.resource_group.name
  location            = var.location
}

module "nsg_ingress" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  name                = "nsg-ingress-australiaeast"
  resource_group_name = module.resource_group.name
  location            = var.location
}

module "nsg_management" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  name                = "nsg-management-australiaeast"
  resource_group_name = module.resource_group.name
  location            = var.location
}

module "spoke_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  name          = var.vnet_name
  location      = var.location
  parent_id     = module.resource_group.resource_id
  address_space = var.vnet_address_space

  subnets = {
    aks_nodes = {
      name             = "snet-aks-nodes"
      address_prefixes = ["10.10.0.0/20"]

      network_security_group = {
        id = module.nsg_aks_nodes.resource_id
      }
    }

    private_endpoints = {
      name             = "snet-private-endpoints"
      address_prefixes = ["10.10.16.0/24"]

      network_security_group = {
        id = module.nsg_private_endpoints.resource_id
      }
    }

    ingress = {
      name             = "snet-ingress"
      address_prefixes = ["10.10.17.0/24"]

      network_security_group = {
        id = module.nsg_ingress.resource_id
      }
    }

    management = {
      name             = "snet-management"
      address_prefixes = ["10.10.18.0/24"]

      network_security_group = {
        id = module.nsg_management.resource_id
      }
    }
  }
}

module "hub_spoke_peering" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm//modules/peering"
  version = "0.22.2"

  name                      = "peer-spoke-to-hub"
  parent_id                 = module.spoke_vnet.resource_id
  remote_virtual_network_id = "/subscriptions/a54948ad-1f2f-4234-9807-1c1760cac9c7/resourceGroups/rg-hub-australiaeast/providers/Microsoft.Network/virtualNetworks/vnet-hub-australiaeast"

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false

  create_reverse_peering               = true
  reverse_name                         = "peer-hub-to-spoke"
  reverse_allow_virtual_network_access = true
  reverse_allow_forwarded_traffic      = false
  reverse_allow_gateway_transit        = false
  reverse_use_remote_gateways          = false
}

module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.8.3"

  name      = "aks-app-australiaeast-001"
  location  = var.location
  parent_id = module.resource_group.resource_id

  dns_prefix         = "aksappae001"
  kubernetes_version = "1.36.4"

  addon_profile_azure_policy = {
    enabled = true
  }

  api_server_access_profile = {
    enable_private_cluster = true
    private_dns_zone       = "system"
  }

  oidc_issuer_profile = {
    enabled = true
  }

  security_profile = {
    workload_identity = {
      enabled = true
    }
  }

  managed_identities = {
    system_assigned = true
  }

  sku = {
    name = "Base"
    tier = "Free"
  }

  network_profile = {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_dataplane   = "cilium"
    network_policy      = "cilium"

    outbound_type     = "loadBalancer"
    load_balancer_sku = "standard"

    load_balancer_profile = {
      managed_outbound_ips = {
        count = 1
      }
    }

    service_cidr   = "10.20.0.0/16"
    dns_service_ip = "10.20.0.10"
  }

  default_agent_pool = {
    count_of       = 2
    vm_size        = "Standard_D4as_v7"
    vnet_subnet_id = module.spoke_vnet.subnets["aks_nodes"].resource_id
  }
}

module "acr" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.8.0"

  name                = "acrappae001rkb"
  resource_group_name = module.resource_group.name
  location            = var.location

  sku = "Basic"

  admin_enabled                 = false
  public_network_access_enabled = true
  zone_redundancy_enabled       = false

  role_assignments = {
    aks_kubelet_acr_pull = {
      role_definition_id_or_name = "AcrPull"
      principal_id               = "719f1988-cf32-4988-bf09-af914e2c4d1d"
      principal_type             = "ServicePrincipal"
    }
  }
}

module "workload_identity" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.2"

  name                = "uami-aks-workload-australiaeast-001"
  resource_group_name = module.resource_group.name
  location            = var.location

  federated_identity_credentials = {
    aks_platform_demo = {
      name     = "fic-aks-platform-demo"
      issuer   = module.aks.oidc_issuer_profile_issuer_url
      subject  = "system:serviceaccount:default:aks-platform-demo-sa"
      audience = ["api://AzureADTokenExchange"]
    }
  }
}

resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = module.resource_group.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name                  = "link-keyvault-spoke"
  resource_group_name   = module.resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = module.spoke_vnet.resource_id

  registration_enabled = false
}

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  name                = "kv-aks-app-ae-001"
  location            = var.location
  resource_group_name = module.resource_group.name

  tenant_id = data.azurerm_client_config.current.tenant_id

  sku_name                      = "standard"
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7

  private_endpoints = {
    primary = {
      name                          = "pep-kv-aks-app-ae-001"
      subnet_resource_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.keyvault.id]
    }
  }

  role_assignments = {
    workload_identity_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = module.workload_identity.principal_id
      principal_type             = "ServicePrincipal"
    }


  }
}