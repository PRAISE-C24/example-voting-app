# Example Voting App: DevOps Edition

A fork of [dockersamples/example-voting-app](https://github.com/dockersamples/example-voting-app) that takes the sample app from `docker compose up` to a tested, scanned, containerized, cloud-deployed service on AWS EKS, built and delivered by GitHub Actions pipelines that authenticate to AWS with OIDC (no stored AWS keys).

The app itself is unchanged in purpose: a **vote** web app (Python/Flask), a **result** web app (Node.js), a **worker** (.NET), **Redis** and **PostgreSQL**. Everything around it is what this fork adds.

## What changed

| Area | Original | This fork |
|---|---|---|
| Containers | Floating tags, runs as root, port 80, dev tooling in images | Supported base versions (Python 3.13, Node 24, .NET 10), pinned by digest, non-root users, port 8000, `pip` and `npm` removed from runtime images, a `.dockerignore` per service |
| Tests | PhantomJS test on abandoned tooling | `socket.io-client` integration test: casts a vote and waits for it to appear in the results |
| CI | Upstream workflows pushing to the maintainers' registries | One workflow, run only when app code changes: integration test, build, Trivy scan, push to GHCR tagged with the commit SHA |
| Infrastructure | None | Terraform: EKS cluster in the default VPC, state in S3 with native locking, explicit cluster access entries |
| Deployment | Static Kubernetes manifests | Helm chart, public access through AWS ALBs, rehearsed rollback, automatic rollback when a pipeline deploy fails |
| Pipelines | None | Separate GitHub Actions for infrastructure and app delivery, AWS access through OIDC roles, an approval gate on every apply, destroy and deploy |

## Architecture

```
Internet ── ALB ── vote pods ──► Redis ◄── worker ──► PostgreSQL ◄── result pods ── ALB ── Internet
```

How changes reach the cluster:

```
app code (vote/, result/, worker/) ──► CI: test, build, scan, push image ──► app-deploy ─┐
Helm chart (charts/) ─────────────────────────────────────────────────────► app-deploy ─┼─► approval ─► Helm ─► EKS
manual button ────────────────────────────────────────────────────────────► app-deploy ─┘

infra/eks change ──► infra: fmt, validate, plan (read-only)
manual button ──► infra-deploy or infra-destroy ──► approval ──► Terraform scripts ──► EKS
```

## Repository layout

```
.github/workflows/
  ci.yml              CI: test, build, scan, push (app changes only)
  infra.yml           Terraform format check, validate and plan for infra/eks (read-only)
  infra-deploy.yml    Manual: create the cluster (approval required)
  infra-destroy.yml   Manual: destroy the cluster, then verify nothing is left (typed confirmation and approval)
  app-deploy.yml      Deploy the Helm chart after CI, on chart changes, or manually (approval required)
charts/voting-app/    Helm chart (one chart, one values file)
infra/eks/            Terraform for the EKS cluster (terraform.tfvars.example lists the inputs)
infra/github-oidc/    Terraform for GitHub's OIDC provider and the pipelines' AWS roles (applied once, separate state)
scripts/              bootstrap-state, deploy, destroy, verify-destroyed (used by you and by the pipelines)
vote/  result/  worker/      The three services, each with a hardened Dockerfile
result/tests/                Integration test
docker-compose.yml           Local development
```

## Prerequisites

Docker, Terraform 1.10 or later, AWS CLI v2 with credentials for your own AWS account, `kubectl` and Helm. The pipelines run on GitHub-hosted runners and need nothing installed locally.

## Run locally

```bash
docker compose up --build
```

- Vote: <http://localhost:8080>
- Result: <http://localhost:8081>

Run the integration test:

```bash
docker compose -f result/docker-compose.test.yml up --build --exit-code-from sut
```

## CI

`.github/workflows/ci.yml` runs only when a change touches the app, since that is what it tests and packages:

- Pushes to `main` that change `vote/**`, `result/**` or `worker/**`
- Pull requests into `main` that change the same paths, or `ci.yml` itself (so a change to CI is tested on its pull request without rebuilding images when it merges)

Changes to infrastructure, the Helm chart or other workflows do not start CI. When it runs:

1. Run the integration test.
2. Build each image (`vote`, `result`, `worker`).
3. Scan it with Trivy. The job fails on fixable HIGH or CRITICAL findings.
4. On pushes to `main`, push to GitHub Container Registry as
   `ghcr.io/<owner>/voting-app-<service>:<commit-sha>`.

Nothing is pushed unless the scan passes. Third-party actions are pinned to commit SHAs, and Dependabot keeps them current.

## Pipelines

| Workflow | Starts when | What it does | Approval |
|---|---|---|---|
| `ci` | App code changes (see above) | Test, build, scan, push images | None |
| `infra` | A pull request or push to `main` changes `infra/eks/**` | Format check, validate and plan using the read-only role. Plan totals appear in the run summary. It never applies. | None, read-only |
| `infra-deploy` | Manual, on `main` | Runs `scripts/deploy.sh` with the apply role to create the cluster | `production` environment |
| `infra-destroy` | Manual, on `main`, and you must type `destroy` | Removes the app and waits for its load balancers to be deleted, runs `scripts/destroy.sh`, then a `verify` job runs `scripts/verify-destroyed.sh` with the read-only role (up to three tries, 90 seconds apart) | `production` environment |
| `app-deploy` | CI succeeds on `main`, a push to `main` changes `charts/**`, or manual (optional commit SHA) | Skips cleanly if the cluster does not exist. Otherwise installs the AWS Load Balancer Controller, runs `helm upgrade --install --wait`, rolls back if the upgrade fails, and prints the ALB URLs in the run summary. | `app-production` environment |

Pull requests never deploy, and workflow-only changes never deploy anything. Approval means a required reviewer clicks **Approve** on the environment before the job starts. Rejecting or cancelling a run before approval changes nothing in AWS.

### AWS access through OIDC

GitHub proves each run's identity to AWS with a short-lived token, so no AWS keys are stored in the repository. The roles are created by `infra/github-oidc/`, which has its own state, so destroying the cluster never removes the pipelines' access.

| Role | Permissions | Who can assume it |
|---|---|---|
| `gha-terraform-plan` | Read-only AWS access and the Terraform state bucket | Pull request runs and runs on `main` without an environment |
| `gha-terraform-apply` | `AdministratorAccess` | Only jobs running in the `production` environment |
| `gha-app-deploy` | `eks:DescribeCluster` only | Only jobs running in the `app-production` environment |

The trust policy is the control: a branch push or a fork cannot assume the apply or deploy roles. Access inside the cluster comes from EKS access entries (your admin user, the apply role and the deploy role), so it does not depend on who created the cluster.

### Which image versions does `app-deploy` use?

| Situation | Images used |
|---|---|
| CI just finished, or you typed a commit SHA | That exact commit's images, with that commit's chart |
| Chart-only push, or a manual run with the box blank, and the app is already running | The versions already running (`helm upgrade --reset-then-reuse-values`) |
| Chart-only push, or a manual run with the box blank, and nothing is running | The newest commit where CI succeeded on `main` |

The run summary says which case applied. To redeploy or roll back to a known-good build, run `app-deploy` manually with a full commit SHA that CI built.

## Infrastructure

The cluster is built with Terraform in `infra/eks/`, using the default VPC and a managed node group. State lives in an S3 bucket with versioning and encryption. Cluster-admin access is granted explicitly through EKS access entries.

From your own machine:

```bash
./scripts/bootstrap-state.sh     # once per AWS account: creates the state bucket
./scripts/deploy.sh              # fmt, init, validate, plan, then asks before applying
aws eks update-kubeconfig --region us-east-1 --name example-voting-app
```

Local runs need the inputs listed in `infra/eks/terraform.tfvars.example`. Copy it to `terraform.tfvars` (git-ignored) or export the matching `TF_VAR_` variables. In GitHub Actions the same values come from repository variables.

The scripts behave the same in both places. When `CI=true` they skip their interactive prompts, because approval happens at the GitHub environment instead. `scripts/destroy.sh` shows the account, region and cluster, removes the app and waits for its load balancers to be deleted, refuses to continue while any Kubernetes load balancers still exist, shows the destroy plan, and (locally) requires you to type the cluster name. `scripts/verify-destroyed.sh` checks that nothing is left behind, and fails if it cannot read the Terraform state.

## Deploy with Helm

The pipeline does this for you (see `app-deploy` above). To do it by hand, install the AWS Load Balancer Controller once, then the app:

```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --version <chart-version> \
  --set clusterName=example-voting-app \
  --set region=us-east-1 \
  --set vpcId=$(terraform -chdir=infra/eks output -raw vpc_id) \
  --wait

helm upgrade --install voting-app charts/voting-app \
  -n voting --create-namespace --wait --timeout 10m

kubectl -n voting get ingress
```

`RELEASE` (the name Helm gives the installed app) and `NAMESPACE` (the named section of the cluster the app lives in) are set at the top of `app-deploy.yml`. Keep them the same as the names you use in the commands here (`voting-app` and `voting`), or the pipeline and your manual commands will manage two separate copies of the app.

Each app gets its own ALB. Open the `ADDRESS` of each Ingress over plain `http://` on port 80. A new load balancer can take a minute or two to answer.

Images are referenced by commit SHA. To deploy a newer build by hand, wait for CI to pass, then:

```bash
helm upgrade voting-app charts/voting-app -n voting \
  --set image.tag=<full-commit-sha> --wait --timeout 5m
```

## Bad release and rollback

Ship a release that cannot start, watch the old pods keep serving traffic, then recover:

```bash
# Point vote at an image tag that does not exist
helm upgrade voting-app charts/voting-app -n voting \
  --set vote.tag=does-not-exist --wait --timeout 2m      # fails, release marked "failed"

helm history voting-app -n voting                        # find the last good revision
helm rollback voting-app <last-good-revision> -n voting --wait
```

The new pod sits in `ImagePullBackOff`, the existing pods stay ready, and the public site keeps answering with HTTP 200 throughout. After the rollback, `helm history` shows a new revision marked `Rollback to <n>`.

The `app-deploy` pipeline does the same recovery on its own: if `helm upgrade --wait` fails, the next step runs `helm rollback` and the run still ends red so you notice. A release that starts but behaves wrongly is not caught automatically. Roll it back by hand, or redeploy a known-good SHA.

## Tear down

Order matters, because Kubernetes creates the load balancers and Terraform does not know about them. The destroy flow handles this for you: it uninstalls the app, waits for the load balancers to be deleted, and only then destroys the cluster. Run it from GitHub (**Actions → infra-destroy**, type `destroy`, approve; the verify job runs afterwards) or from your machine:

```bash
./scripts/destroy.sh
./scripts/verify-destroyed.sh
```

If you ever need to do it by hand, remove the app first and wait for the load balancers to disappear:

```bash
helm uninstall voting-app -n voting
# wait until no load balancers remain:
aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[].LoadBalancerName' --output text
```

Keep the load balancer controller running until the load balancers are gone, because it is what deletes them. Destroying the cluster removes the controller afterwards.

## Run it in your own account

1. Fork the repo and let CI publish images to your own GHCR namespace.
2. In `charts/voting-app/values.yaml`, set `image.registry` to `ghcr.io/<your-lowercase-username>` and `image.tag` to a commit SHA whose images exist. Make the three packages public so the cluster can pull them.
3. Run `./scripts/bootstrap-state.sh` so you get your own state bucket and your own `backend.hcl` (git-ignored). Never reuse someone else's state.
4. Create the pipelines' AWS roles once, using your own admin credentials. Give `infra/github-oidc/` its own `backend.hcl` (same bucket, key `github-oidc/terraform.tfstate`), then:
   ```bash
   cd infra/github-oidc
   terraform init -backend-config=backend.hcl
   terraform apply -var region=us-east-1 -var state_bucket=<your-state-bucket>
   terraform output
   ```
   Set `github_repo_sub` in `infra/github-oidc/main.tf` to your repository's identity. Depending on how a repository was created, the token's subject is either `repo:OWNER/REPO` or includes numeric IDs, as in `repo:OWNER@OWNER_ID/REPO@REPO_ID`. `gh api repos/OWNER/REPO --jq '.owner.id, .id'` shows the IDs. If a workflow fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity", compare the token's `sub` claim with the trust policy.
5. In the repository settings, create two environments, each with yourself as a required reviewer and deployments limited to `main`: `production` (infrastructure apply and destroy) and `app-production` (app deploys).
6. Add these repository **variables** (not secrets) under Settings → Secrets and variables → Actions:

   | Variable | Value |
   |---|---|
   | `AWS_REGION` | Your region, for example `us-east-1` |
   | `TF_STATE_BUCKET` | Your Terraform state bucket |
   | `AWS_PLAN_ROLE_ARN` | `plan_role_arn` from the Terraform output |
   | `AWS_APPLY_ROLE_ARN` | `apply_role_arn` from the Terraform output |
   | `AWS_DEPLOY_ROLE_ARN` | `deploy_role_arn` from the Terraform output |
   | `ADMIN_USER_ARN` | The IAM user that should get `kubectl` access to the cluster |

7. Run **infra-deploy**, approve it, then run **app-deploy** with the commit box blank.

## Cost and safety

- An EKS cluster, its nodes and the load balancers bill by the hour. Destroy the environment when you finish, and set an AWS Budget alert.
- Every apply, destroy and app deploy waits for an approval click. A destroy also needs the typed word `destroy`.
- The pipelines hold no AWS keys. Roles are assumed with short-lived OIDC tokens, and the trust policies limit who can assume each role.
- State files can contain secrets and are never committed. `backend.hcl`, `terraform.tfvars`, `*.tfstate*`, `*.tfplan` and `.terraform/` are git-ignored. Role ARNs are not secrets, but they contain your AWS account number, which is why they live in repository variables and an ignored file rather than in committed code.

## Known limitations

- Plain HTTP only. HTTPS needs a domain name and a certificate.
- The upstream app hardcodes the database credentials (`postgres`/`postgres`), so they appear in `values.yaml`.
- PostgreSQL and Redis use `emptyDir` volumes, so votes are lost if those pods restart.
- The two apps use separate ALBs because there is no domain for host-based routing.
- The apply role has `AdministratorAccess`, and the deploy role has cluster-admin inside the cluster. Both are protected by their trust policies and approval gates rather than by narrow permissions.
- The deploy and destroy scripts plan again when they run, so an approval covers the action, not one specific saved plan. Review the plan on the pull request first.
- The cluster is deliberately temporary. Pushes that arrive while it is destroyed skip the deploy with a notice.

## Roadmap

- Terraform security scanning (tfsec or Checkov) in the pull request plan.
- Narrower permissions for the apply and deploy roles.
- Scheduled drift detection, and separate AWS accounts for development and production.
- Stretch: one shared ALB with hostnames and HTTPS, remote GitOps with Argo CD, autoscaling.

## Credits

The voting app is by [Docker Samples](https://github.com/dockersamples/example-voting-app).
