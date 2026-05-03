# Harbor Usage On `saywish-mini-al`

This document describes the exact steps needed to trust the Harbor registry running at:

```text
https://saywish-mini-al
```

and to build and push LeilFS container images from this repository.

## Preconditions

- Harbor is already installed and reachable at `https://saywish-mini-al`
- A Harbor project named `leilfs` exists
- You have a Harbor user account, for example `admin`
- The Harbor server was configured with a locally generated CA and TLS certificate

## 1. Copy The Harbor CA Certificate To Your Client Machine

On the client machine that will run Docker or Podman, copy the CA certificate from the Harbor server:

```bash
scp root@saywish-mini-al:/root/harbor-certs/ca.crt /tmp/saywish-mini-al-ca.crt
```

If direct root SSH access is disabled, copy the file using another allowed account or first move the CA certificate to a readable location on the server.

## 2. Trust The Harbor CA In Docker

Install the CA certificate for Docker:

```bash
sudo mkdir -p /etc/docker/certs.d/saywish-mini-al
sudo cp /tmp/saywish-mini-al-ca.crt /etc/docker/certs.d/saywish-mini-al/ca.crt
sudo systemctl restart docker
```

The directory name must exactly match the registry hostname:

```text
/etc/docker/certs.d/saywish-mini-al/
```

## 3. Trust The Harbor CA In The System Certificate Store

This allows tools such as `curl` and browsers to trust the registry certificate too:

```bash
sudo cp /tmp/saywish-mini-al-ca.crt /usr/local/share/ca-certificates/saywish-mini-al-harbor-ca.crt
sudo update-ca-certificates
```

## 4. Trust The Harbor CA In Podman

If you also use Podman on the client machine:

```bash
sudo mkdir -p /etc/containers/certs.d/saywish-mini-al
sudo cp /tmp/saywish-mini-al-ca.crt /etc/containers/certs.d/saywish-mini-al/ca.crt
```

## 5. Log In To Harbor

Test Docker login:

```bash
docker login saywish-mini-al:443
```

You should be prompted for your Harbor username and password.

If login fails with `x509: certificate signed by unknown authority`, the CA certificate was not installed in the correct place or Docker was not restarted.

## 6. Build And Push Images From This Repository

This repository includes a helper script:

[`publish.sh`](/home/aneutrino/git/leilfs-container/publish.sh)

It builds the base image and all component images, then pushes them into Harbor.

The script validates the LeilFS version against the public package repository at `repo.leil.io`. If `--saunafs-version` is omitted, it will fetch the available versions for the selected Ubuntu release and ask you to choose one interactively.

Example:

```bash
docker login saywish-mini-al:443
./publish.sh --saunafs-version 5.8.0-1 --distro 24.04 --registry saywish-mini-al:443 --project leilfs
```

Interactive example:

```bash
./publish.sh --distro 24.04 --registry saywish-mini-al:443 --project leilfs
```

For Docker image references, always use `saywish-mini-al:443`, not just `saywish-mini-al`. A bare hostname without `.` or `:` is interpreted by Docker as Docker Hub, not as a private registry.

## 7. Resulting Harbor Image Names

The Harbor layout is:

```text
registry/project/repository:tag
```

Examples:

```text
saywish-mini-al:443/leilfs/saunafs-base:ubuntu-24.04
saywish-mini-al:443/leilfs/saunafs-master:ubuntu-24.04-leilfs-5.8.0-1-main
saywish-mini-al:443/leilfs/saunafs-client:ubuntu-24.04-leilfs-5.8.0-1-main
```

The repository name stays stable per service, and the tag contains:

- Ubuntu version
- LeilFS version
- Git branch

## 8. Branch Override

By default, `publish.sh` uses the current git branch name in the image tag.

If you want to override it:

```bash
./publish.sh --saunafs-version 5.8.0-1 --distro 24.04 --registry saywish-mini-al:443 --project leilfs --branch master
```

## 9. Supported Ubuntu Versions

At the moment, this repository supports only:

- `22.04`
- `24.04`

Ubuntu `26.04` is not yet supported by the current base Dockerfile and publish script.

## 10. Notes

- Use the CA certificate `ca.crt`, not the server certificate `saywish-mini-al.crt`
- The Harbor registry is using the bare hostname `saywish-mini-al`
- Harbor already includes its own frontend `nginx`, so no extra reverse proxy is required for this setup
