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

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.100.0.0/20"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.101.0.0/20"
  }
}

resource "google_compute_subnetwork" "subnet2" {
  for_each      = local.envs
  name          = "eab-${each.key}-${var.region2}-subnet-2"
  ip_cidr_range = each.value.subnet2_cidr
  region        = var.region2
  project       = google_project.infra.project_id
  network       = google_compute_network.vpc[each.key].self_link

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.102.0.0/20"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.103.0.0/20"
  }
}

# Router + NAT + egress firewall per environment (development, nonproduction, production)
locals {
  router_pairs = { for pair in setproduct(keys(local.envs), [var.region1, var.region2]) : "${pair[0]}-${pair[1]}" => { env = pair[0], region = pair[1] } }
}

resource "google_compute_router" "env_router" {
  for_each = local.router_pairs
  name     = "eab-${each.value.env}-router-${each.value.region}"
  region   = each.value.region
  network  = google_compute_network.vpc[each.value.env].self_link
  project  = google_project.infra.project_id
}

resource "google_compute_router_nat" "env_nat" {
  for_each = local.router_pairs
  name     = "eab-${each.value.env}-nat-${each.value.region}"
  router   = google_compute_router.env_router[each.key].name
  region   = google_compute_router.env_router[each.key].region
  project  = google_project.infra.project_id

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  min_ports_per_vm                   = 128
}

resource "google_compute_firewall" "env_allow_egress_internet" {
  for_each = local.envs
  name     = "eab-${each.key}-allow-egress-internet"
  network  = google_compute_network.vpc[each.key].name
  project  = google_project.infra.project_id

  direction          = "EGRESS"
  priority           = 1000
  destination_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
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
