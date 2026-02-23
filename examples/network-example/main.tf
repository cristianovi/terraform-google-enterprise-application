terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
}

variable "org_id" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "billing_account" {
  type = string
}

variable "region1" {
  type    = string
  default = "us-central1"
}

variable "region2" {
  type    = string
  default = "us-west1"
}

locals {
  envs = {
    development = {
      subnet1_cidr = "10.10.0.0/20"
      subnet2_cidr = "10.20.0.0/20"
    }
    nonproduction = {
      subnet1_cidr = "10.30.0.0/20"
      subnet2_cidr = "10.40.0.0/20"
    }
    production = {
      subnet1_cidr = "10.50.0.0/20"
      subnet2_cidr = "10.60.0.0/20"
    }
  }
}

resource "google_project" "infra" {
  project_id      = "eab-net-infra"
  name            = "EAB Infra"
  folder_id       = var.folder_id
  billing_account = var.billing_account
}

resource "google_compute_network" "vpc" {
  for_each                = local.envs
  name                    = "eab-${each.key}-vpc"
  project                 = google_project.infra.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet1" {
  for_each      = local.envs
  name          = "eab-${each.key}-${var.region1}-subnet-1"
  ip_cidr_range = each.value.subnet1_cidr
  region        = var.region1
  project       = google_project.infra.project_id
  network       = google_compute_network.vpc[each.key].self_link
}

resource "google_compute_subnetwork" "subnet2" {
  for_each      = local.envs
  name          = "eab-${each.key}-${var.region2}-subnet-2"
  ip_cidr_range = each.value.subnet2_cidr
  region        = var.region2
  project       = google_project.infra.project_id
  network       = google_compute_network.vpc[each.key].self_link
}

output "global_tfvars_snippet" {
  value = {
    common_folder_id = "folders/${var.folder_id}"
    project_id       = google_project.infra.project_id

    envs = {
      development = {
        billing_account    = var.billing_account
        folder_id          = "folders/${var.folder_id}"
        network_project_id = google_project.infra.project_id
        network_self_link  = google_compute_network.vpc["development"].self_link
        org_id             = var.org_id
        subnets_self_links = [
          google_compute_subnetwork.subnet1["development"].self_link,
          google_compute_subnetwork.subnet2["development"].self_link,
        ]
      }
      nonproduction = {
        billing_account    = var.billing_account
        folder_id          = "folders/${var.folder_id}"
        network_project_id = google_project.infra.project_id
        network_self_link  = google_compute_network.vpc["nonproduction"].self_link
        org_id             = var.org_id
        subnets_self_links = [
          google_compute_subnetwork.subnet1["nonproduction"].self_link,
          google_compute_subnetwork.subnet2["nonproduction"].self_link,
        ]
      }
      production = {
        billing_account    = var.billing_account
        folder_id          = "folders/${var.folder_id}"
        network_project_id = google_project.infra.project_id
        network_self_link  = google_compute_network.vpc["production"].self_link
        org_id             = var.org_id
        subnets_self_links = [
          google_compute_subnetwork.subnet1["production"].self_link,
          google_compute_subnetwork.subnet2["production"].self_link,
        ]
      }
    }
  }
}