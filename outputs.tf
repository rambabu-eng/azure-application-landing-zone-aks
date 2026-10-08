output "resource_group_id" {
  value = module.resource_group.resource_id
}

output "spoke_vnet_id" {
  value = module.spoke_vnet.resource_id
}

output "spoke_vnet_name" {
  value = module.spoke_vnet.name
}

output "subnets" {
  value = module.spoke_vnet.subnets
}