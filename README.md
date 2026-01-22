# GCP Serverless Web Application with Terraform

This repository provides a Terraform configuration to deploy a serverless web application on Google Cloud Platform (GCP).
It sets up a static frontend hosted on Google Cloud Storage (GCS) and a dynamic API backend using Cloud Functions and API Gateway. The entire infrastructure is managed as code using Terraform.

## Architecture

The following diagram illustrates the infrastructure architecture:

```mermaid
graph TD
    subgraph User Request Flow
        User[<i class="fa fa-user"></i> User] -->|HTTPS| DNS[Cloud DNS]
    end

    subgraph Frontend
        DNS -->|A Record| LB[Cloud Load Balancing / CDN]
        LB -->|Backend| GCS[Cloud Storage Bucket<br/>(Static Website)]
    end

    subgraph Backend
        LB -->|Backend| APIGW[API Gateway]
        APIGW -->|Invokes| GCF[Cloud Function<br/>(Python API)]
    end

    subgraph Security
        LB -- Attaches --> Armor[Cloud Armor<br/>(WAF Policy)]
        LB -- Uses --> SSL[Google-managed SSL Certificate]
    end

    style User fill:#d1e7dd,stroke:#333,stroke-width:2px
    style DNS fill:#cff4fc,stroke:#333,stroke-width:2px
    style LB fill:#fff3cd,stroke:#333,stroke-width:2px
    style GCS fill:#f8d7da,stroke:#333,stroke-width:2px
    style APIGW fill:#cfe2ff,stroke:#333,stroke-width:2px
    style GCF fill:#e2d1f9,stroke:#333,stroke-width:2px
    style Armor fill:#f8d7da,stroke:#333,stroke-width:2px
    style SSL fill:#d1e7dd,stroke:#333,stroke-width:2px
```

### Key Components

*   **Frontend**:
    *   **Google Cloud Storage (GCS)**: Hosts the static website content (HTML, CSS, JavaScript).
    *   **Cloud Load Balancing & CDN**: Provides a single global entry point with a static IP, caches content, and terminates SSL.
    *   **Cloud Armor**: A Web Application Firewall (WAF) to protect the application from common web attacks and control access (e.g., allow traffic only from specific regions).

*   **Backend**:
    *   **Cloud Functions (2nd gen)**: A serverless function written in Python that runs your backend API logic.
    *   **API Gateway**: Exposes the Cloud Function as a managed, secure, and scalable API. It uses an OpenAPI specification to define the API structure.

*   **Networking & DNS**:
    *   **Cloud DNS**: Manages the domain's DNS records.
    *   **Google-managed SSL Certificate**: Provides free, auto-renewing SSL certificates for the custom domain.

*   **IaC & State Management**:
    *   **Terraform**: Manages the entire cloud infrastructure as code.
    *   **GCS Backend**: Stores the Terraform state file (`.tfstate`) remotely in a GCS bucket for collaboration and state locking.

## Deployment Steps

Follow these steps to deploy the infrastructure.

### 1. Prerequisites

*   Install [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) and authenticate:
    ```sh
    gcloud auth login
    gcloud auth application-default login
    gcloud config set project YOUR_PROJECT_ID
    ```
*   Install [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) (version >= 1.0).
*   Create a GCS bucket to store the Terraform state file. This must be done manually before running Terraform.
    ```sh
    gsutil mb gs://your-terraform-state-bucket-name
    ```
*   Update `backend.tf` to point to your newly created bucket.

    ```hcl
    # backend.tf
    terraform {
      backend "gcs" {
        bucket  = "your-terraform-state-bucket-name" # <-- UPDATE THIS
        prefix  = "terraform/state"
      }
    }
    ```

### 2. Configuration

Create a `terraform.tfvars` file in the root of the project to specify your environment-specific variables.

```hcl
# terraform.tfvars

project_id  = "your-gcp-project-id"
region      = "asia-northeast1"
domain_name = "your-domain.com"
bucket_name = "your-unique-frontend-bucket-name"
```

### 3. Execution

1.  **Initialize Terraform**:
    Downloads the necessary providers and initializes the backend.
    ```sh
    terraform init
    ```

2.  **Apply Configuration**:
    Creates the resources on GCP. Review the plan and type `yes` to approve.
    ```sh
    terraform apply
    ```

After the apply is complete, Terraform will output the DNS name servers, CDN IP address, and other relevant URLs. You will need to update your domain's registrar to point to the name servers provided by Cloud DNS.

## Terraform Variables

The following variables are used in this project:

| Name          | Description                                  | Type   | Default             | Required |
|---------------|----------------------------------------------|--------|---------------------|:--------:|
| `project_id`  | The GCP project ID to deploy resources to.   | `string` | -                   |   Yes    |
| `region`      | The GCP region to deploy resources to.       | `string` | `asia-northeast1`   |    No    |
| `domain_name` | The main domain name for the application.    | `string` | `example.com`       |    No    |
| `bucket_name` | The name for the GCS bucket.                 | `string` | `sample-gcs-bucket-name` | No    |

## Terraform Outputs

The following outputs are generated after applying the configuration:

| Name                 | Description                                  |
|----------------------|----------------------------------------------|
| `api_gateway_url`    | The URL of the API Gateway.                  |
| `cloud_function_url` | The trigger URL of the Cloud Function.       |
| `cdn_ip_address`     | The public IP address of the CDN Load Balancer. |
| `dns_name_servers`   | The name servers for the Cloud DNS zone.     |