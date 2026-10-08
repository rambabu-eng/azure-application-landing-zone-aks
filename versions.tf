terraform {
  required_version = ">= 1.11, < 2.0"

  backend "azurerm" {}

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}