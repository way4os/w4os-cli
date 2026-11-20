# OpenSimulator in a container: suggestions

> **Not supported yet.** No image is published, and the way to run OpenSimulator in a container is still being worked out: what
> follows are suggestions from the tests done so far, to try at your own risk. Use the packages (`kickstart.sh`, `apt install
> opensim-kit`) for a grid that has to stay up.

## The two ways tried

- **A whole machine in a container** (the closest to a server): `./kickstart.sh --podman` makes a persistent Podman container
  with systemd, then installs the packages inside it as on a server. `--connection NAME` uses another machine's Podman,
  `--image IMAGE` another base (Ubuntu 26.04 by default).
- **One service per container**, the way containers are usually run: the packages in an image of your own, the instances started
  by its entrypoint, the database in another container. This is the way the notes below are about.

## A database apart

OpenSimulator needs a MySQL or MariaDB: in another container, or on the host.

```bash
podman network create opensim
podman run -d --name db --network opensim -e MARIADB_ROOT_PASSWORD=<root password> docker.io/library/mariadb:11
```

The host of the database is then the name of its container (`db`), and the administrator account is the one `opensim setup`
asks for what it has to create.

## Ports

`opensim ports --publish`, run where the config is, gives the `-p` options for exactly the ports the instances use: the public
ports, the regions in UDP (the viewers send to them, with the number they are given, so it must be the same outside), the
private and console ports to the local machine only (`--private-address=` to change it). A simulator in a container reaches a
Robust elsewhere, and a Robust in a container serves simulators elsewhere, only when their ports are published to them.

```bash
podman exec opensim opensim ports --publish
```

## Volumes

- `/etc/opensim`, `/var/lib/opensim` and `/var/log/opensim` as volumes; the cache (`/var/cache/opensim`) can be a tmpfs.
- On a host with SELinux (Fedora, RHEL, the machine of Podman on a Mac), add `:z` to the volumes: without it, a container made
  again with the same volumes cannot read what the previous one wrote, and the instances stop with "Permission denied".
- The instances run as the account `opensim`: a folder of the host shared with the container is given to its ID.

## Stopping

A region takes a while to stop cleanly: give the container time (`--stop-timeout 120`), and have its entrypoint stop the
instances on TERM (`opensim stop now`).

## Locked down

A container protects the host from OpenSimulator, which runs scripts written by its users; it does not replace the settings of
OpenSimulator that keep those scripts away from your internal network. Options worth trying:

```bash
--read-only --tmpfs /tmp --tmpfs /var/cache/opensim:rw,mode=1777 \
--cap-drop ALL --security-opt no-new-privileges --pids-limit 600 --memory 2g
```

## Known limits

- Starting or stopping one instance of a container that holds several: one service per container for now, restarted with it.
- The public address of the regions: their external host name is the one the container sees, not the one of the host.
- No compose file and no published image yet.
