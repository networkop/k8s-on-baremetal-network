# Config Reconciler 

This application is designed to reconcile network configurations for Cumulus Linux and SONiC. It is distributed as a docker container and controller by a single bash script which also serves as the entrypoint. This bash script monitors a number of pre-defined source directories that are supposed to be mounted externally (as volume mounts), copies all files found from those directories into pre-defined destination directories and triggers a config reload. Destination directories are host mounts so that the copied configuration files can survive container restart and are persistent across reboots. The entrypoint script performs the following sequence of actions:

1. Check what source directories have been mounted and save a list of them in a `WATCH_DIR` variable.
2. On the first run, synchronize all files between all source and destination directories and triggers a config reload.
3. Using `inotify`, establishe a watch loop on each present source directory and triggers a config reload every time it detects an update.

Currently, the script understands 3 types of network configurations:

1. FRR and interface configurations that are managed by `frr` and `ifupdown2` respectively.
2. SONiC's `config_db.json`.
3. Cumulus's NVUE yaml file.

The script utilizes multiple different ways to trigger the config reload:

* It uses `ifupdown2` as a package installed in a container and assumes that this container is running in the host OS network namespace.
* It uses `/usr/lib/frr/frr-reload.py` to reload the configuration of the frr service and assumes that the container is running in the host OS PID namespace.
* For SONiC it uses SSH to connect to `localhost` and issues a `config reload -y` command from inside the SSH shell.
* For NVUE it mounts the `nvue.sock` file and uses `curl` (REST API) to replace the current configuration of a device.