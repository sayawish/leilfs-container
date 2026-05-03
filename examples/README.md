# Example Clusters

These examples are intended for CI and development testing only.

- They use images from the local Harbor registry.
- They use a dedicated external Docker `ipvlan` network with a reserved cluster floating IP.
- The master gets its own static IP plus an additional floating IP inside the Compose network.
- Other services resolve `sfsmaster` to that floating IP.
- The chunkservers create volatile test disks inside the containers unless you add your own mounts.
- After changing image entrypoints or Dockerfiles in this repository, rebuild and republish the Harbor images before using these examples.

Each example directory contains:

- `docker-compose.yml`
- `start.sh`
- `stop.sh`

## Shared Environment Variables

All `start.sh` scripts accept the following environment variables:

- `REGISTRY`
  - Default: `saywish-mini-al:443`
- `PROJECT`
  - Default: `leilfs`
- `LEILFS_TAG`
  - Default: `ubuntu-24.04-leilfs-5.9.0-1-main`
- `MASTER_HOST`
  - Default: `sfsmaster`
- `LEILFS_SUBNET`
  - Example: `172.31.0.0/24`
- `LEILFS_GATEWAY`
  - Example: `172.31.0.1`
- `FLOATING_IP`
  - Example: `172.31.0.10`
- `MASTER1_IP`
  - Example: `172.31.0.11`
- `CLUSTER_NETWORK_NAME`
  - Example: `leilfs-minimal-net`
- `PARENT_INTERFACE`
  - Example: `enp3s0`
  - If omitted, the start script tries to detect the default route interface automatically
- `CGI_EXTERNAL_PORT_BASE`
  - Default: `29425`
  - Used by `minimal/start.sh` as the first host port to try for the CGI service
  - In `10/start.sh`, the default starting point is `29435`

## Examples

- `minimal`
  - One container for each service: `master`, `metalogger`, `cgi`, `chunkserver`, `client`
  - Defaults to `1` volatile disk for the chunkserver
  - Uses subnet `172.31.0.0/24`, master IP `172.31.0.11`, floating IP `172.31.0.10`
- `10`
  - Scaled CI topology
  - Defaults to `10` separate metalogger containers, `1` cgi container, `10` separate chunkserver containers, and `10` separate client containers
  - Each chunkserver gets `10` volatile test disks
  - Uses subnet `172.32.0.0/24`, master IP `172.32.0.11`, floating IP `172.32.0.10`

## Current VIP Model

The `start.sh` scripts:

1. create the external `ipvlan` network if it does not exist
2. start the master first
3. attach the configured floating IP to the master container
4. start the rest of the services

This gives every container a stable `sfsmaster -> FLOATING_IP` mapping while keeping Docker out of SaunaFS failover logic.

The `minimal/start.sh` script also finds the first available CGI host port starting from `CGI_EXTERNAL_PORT_BASE` and prints a short cluster summary after startup.

The examples follow a single-CGI rule: each Compose cluster starts at most one CGI container.

This is manual VIP ownership, not automatic failover. If you later run multiple masters and want the floating IP to move automatically between them, you will need an additional failover mechanism such as `keepalived` or a dedicated VIP management script.
