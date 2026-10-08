variable "location" {
  description = "Azure region for the Application Landing Zone."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the Application Landing Zone network."
  type        = string
}

variable "vnet_name" {
  description = "Spoke virtual network name."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the Application Landing Zone spoke VNet."
  type        = set(string)
}