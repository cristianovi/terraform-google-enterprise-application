## Network Example for EAB Deployer

This example shows how to use Terraform to create the **network and infra project** required to run the Enterprise Application Blueprint (EAB) `eab-deployer` helper.

It is intended to be run **before** `eab-deployer`. After applying this example, you will have:

- A single **infra / network / CI-CD project** (created by the `google_project.infra` resource).
- One **VPC per logical environment** (`development`, `nonproduction`, `production`) in that same project.
- Two **subnets per environment**, in two different regions.
- A ready-to-use **`global_tfvars_snippet` output** that you can copy into the `global.tfvars` file used by `eab-deployer`.

### What this Terraform configuration creates

The `main.tf` file does the following:

- **Provider and inputs**
  - Uses the `google` provider (version `~> 5.0`).
  - Expects the following variables:
    - `org_id`: GCP organization ID (string).
    - `folder_id`: numeric folder ID where projects will be created (string).
    - `billing_account`: billing account ID used to attach billing to projects.
    - `region1`: first region for subnets (default `us-central1`).
    - `region2`: second region for subnets (default `us-west1`).

- **Local environments definition**
  - Defines three environments: `development`, `nonproduction`, and `production`.
  - For each environment, defines two non-overlapping CIDR ranges used for subnets:
    - `subnet1_cidr`
    - `subnet2_cidr`

- **Projects**
  - Creates a single **infra / network project**:
    - The project ID is defined in the `google_project.infra` resource (for example, `eab-net-infra`).
    - This project is used later as the **CI-CD / pipelines project** (`project_id` in `global.tfvars`) and also as the **network project** for all environments.

- **Networks and subnets**
  - For each environment:
    - Creates a **VPC** named `eab-<env>-vpc` with `auto_create_subnetworks = false`, in the infra project.
    - Creates two **subnets** in that project:
      - Subnet 1 in `region1` with the `subnet1_cidr` range.
      - Subnet 2 in `region2` with the `subnet2_cidr` range.

- **Output for `global.tfvars`**
  - Exposes a single `output` called `global_tfvars_snippet` that contains:
    - `common_folder_id`: formatted as `folders/<folder_id>`.
    - `project_id`: the ID of the infra project (to be used as `project_id` in `global.tfvars`).
    - `envs`: a structure with entries for `development`, `nonproduction`, and `production`, where each entry includes:
      - `billing_account`
      - `folder_id`
      - `network_project_id` (the same infra project ID for all environments).
      - `network_self_link`
      - `org_id`
      - `subnets_self_links`: list of two subnet self links (regions `region1` and `region2`).

This output is structured to match the expectations of the `global.tfvars.example` used by `helpers/eab-deployer`.

### How to use this example

1. **Configure authentication**
   - Make sure you have authenticated with Application Default Credentials:

     ```bash
     gcloud auth application-default login
     ```

2. **Create a `terraform.tfvars` file**
   - Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in the required values:

     ```hcl
     org_id          = "YOUR_ORG_ID"
     folder_id       = "YOUR_FOLDER_ID"
     billing_account = "YOUR_BILLING_ACCOUNT_ID"

     region1 = "us-central1"
     region2 = "us-west1"
     ```

3. **Initialize and apply**

   ```bash
   terraform init
   terraform apply
   ```

4. **Copy the `global_tfvars_snippet`**
   - After a successful apply, Terraform will print the `global_tfvars_snippet` output.
   - Copy the `envs`, `common_folder_id`, and `project_id` values into your `global.tfvars` file used by `helpers/eab-deployer`.

5. **Use this project as quota project and enable required APIs**
   - You can use the same project created by this example (the one referenced by `project_id` in the output) as the **billing quota project** and **seed project** for `eab-deployer`:

     ```bash
     gcloud config set billing/quota_project YOUR_INFRA_PROJECT_ID
     ```

   - Enable the **Service Usage API** first (this is required before enabling other services):

     ```bash
     gcloud services enable serviceusage.googleapis.com --project YOUR_INFRA_PROJECT_ID
     ```

   - Then enable the core APIs required by the `eab-deployer` README:

     ```bash
     gcloud services enable \
       cloudresourcemanager.googleapis.com \
       iamcredentials.googleapis.com \
       cloudbuild.googleapis.com \
       securitycenter.googleapis.com \
       accesscontextmanager.googleapis.com \
       --project YOUR_INFRA_PROJECT_ID
     ```

   - Depending on how much of the Enterprise Application Blueprint you plan to deploy, you might also need to enable the additional APIs listed in `1-bootstrap/README.md` (for example: `compute.googleapis.com`, `container.googleapis.com`, `gkehub.googleapis.com`, `secretmanager.googleapis.com`, etc.).

6. **Create a Cloud Build worker pool and update `workerpool_id`**
   - The `global.tfvars` file used by `eab-deployer` requires a `workerpool_id` that points to a Cloud Build worker pool in the infra project.
   - Create a worker pool in the same project and region you want to use for CI/CD, for example:

     ```bash
     gcloud beta builds worker-pools create eab-net-infra-pool \
       --project=YOUR_INFRA_PROJECT_ID \
       --region=us-central1
     ```

   - Then set the `workerpool_id` in `global.tfvars` to match the created pool:

     ```hcl
     workerpool_id = "projects/YOUR_INFRA_PROJECT_ID/locations/us-central1/workerPools/eab-net-infra-pool"
     ```

7. **Run `eab-deployer`**
   - With the `global.tfvars` file updated, you can run:

     ```bash
     eab-deployer -tfvars_file /path/to/global.tfvars
     ```

   - The helper will then use the projects, VPCs, and subnets created by this example as the network foundation for the Enterprise Application Blueprint.

