#!/bin/bash

#set -x

INTFS_SRC=/tmp/intfs/
INTFS_DST=/etc/network/interfaces.d
INTFS_APPLY=restart_ifupdown

FRR_SRC=/tmp/frr/
FRR_DST=/etc/frr
FRR_APPLY=restart_frr

SONIC_SRC=/tmp/sonic/
SONIC_DST=/etc/sonic
SONIC_APPLY=restart_sonic

NVUE_SRC=/tmp/nvue/
NVUE_DST=/etc/nvue.d
NVUE_APPLY=restart_nvue

declare -A mapping=( 
  [$INTFS_SRC]=$INTFS_DST:$INTFS_APPLY 
  [$FRR_SRC]=$FRR_DST:$FRR_APPLY
  [$SONIC_SRC]=$SONIC_DST:$SONIC_APPLY
  [$NVUE_SRC]=$NVUE_DST:$NVUE_APPLY
)



restart_ifupdown() {
  mkdir -p /run/network # this is where ifupdown2 stores its lock
  ifreload -a -f || true  
}

restart_frr() {
  if [ ! -S /run/frr/watchfrr.vty ]; then
    echo "ERROR: watchfrr socket file not found"
    return 42
  fi

  rc=$(/usr/lib/frr/frr-reload.py --reload $FRR_DST/frr.conf)
  if [ $? -ne 0 ]; then
    echo "ERROR: failed to frr-reload: ${rc}"
    return 42
  fi
}

restart_sonic() {
  sshpass -p 'YourPaSsWoRd' ssh -oStrictHostKeyChecking=no admin@localhost 'sudo config reload -y'
}

restart_nvue() {
  if [ ! -S /var/run/nvue/nvue.sock ]; then
    echo "ERROR: nvue socket file not found"
    return 42
  fi

  if [ ! -f $NVUE_DST/nvue.yaml ]; then
    echo "ERROR: nvue yaml file not found"
    return 42
  fi

  yq eval -o=j '.[].set' $NVUE_DST/nvue.yaml > $NVUE_DST/nvue.json
  if [ $? -ne 0 ]; then
    echo "ERROR: error converting nvue.yaml to json"
    return 42
  fi

  echo "replacing nvue configuration"
  
  echo "creating nvue revision"
  response=$(curl -s --unix-socket /var/run/nvue/nvue.sock --request POST localhost/nvue_v1/revision)
  if [ $? -ne 0 ]; then
    echo "ERROR: invalid response from nvue: ${response}"
    return 42
  fi

  changeset=$(echo $response | jq -r 'keys | .[]')
  if [ -z "$changeset" ]; then
    echo "ERROR: could not extract changeset ID from: ${response}"
    return 42
  fi

  date=$(echo $changeset | cut -d'/' -f3)
  if [ -z "$date" ]; then
    echo "ERROR: could not extract date from: ${changeset}"
    return 42
  fi

  echo "cleanup revision $changeset" 
  response=$(curl -s --unix-socket /var/run/nvue/nvue.sock --request DELETE localhost/nvue_v1/?rev=${changeset})
  if [ $? -ne 0 ]; then
    echo "ERROR: invalid response from nvue: ${response}"
    return 42
  fi

  echo "patching revision $changeset" 
  response=$(curl -s --unix-socket /var/run/nvue/nvue.sock -H 'Content-Type: application/json' -d @$NVUE_DST/nvue.json --request PATCH localhost/nvue_v1/?rev=${changeset})
  if [ $? -ne 0 ]; then
    echo "ERROR: invalid response from nvue: ${response}"
    return 42
  fi

  echo "applying revision $changeset" 
  response=$(curl -s --unix-socket /var/run/nvue/nvue.sock -H 'Content-Type: application/json' -d '{"state": "apply", "auto-prompt": {"ays": "ays_yes"}}' --request PATCH localhost/nvue_v1/revision/changeset%2Froot%2F${date})
  if [ $? -ne 0 ]; then
    echo "ERROR: invalid response from nvue: ${response}"
    return 42
  fi

}

sync_dir() {
  if [ $# -ne 1 ]; then
    echo "sync expects a single argument"
    return 
  fi

  src=$1
  value="${mapping[$1]}"
  dst=$(echo $value | cut -d ':' -f1)
  cmd=$(echo $value | cut -d ':' -f2)

  if [ ! -e "$dst" ]; then
    mkdir -p $dst
  fi

  echo "syncing all files for ${src} to ${dst} and running ${cmd}"
  for file in "$src"*; do
    echo "copying $file"
    cp $file $dst/
  done

  eval $cmd 
  if [ $? -ne 0 ]; then
    echo "ERROR: configuration apply failed"
  else
    echo "configuration applied"
  fi
}

watch_dir() {
  if [ $# -ne 1 ]; then
    echo "watch expects a single argument"
    return 
  fi

  echo "Entering watch loop for $1"
  inotifywait -m --event MOVED_TO --format "%w" $1 | while read NAME
  do
    echo "change detected to directory ${NAME}"
    sync_dir $NAME &
  done
}

WATCH_DIR=""
if [ -d "$INTFS_SRC" ]; then
  WATCH_DIR="$WATCH_DIR $INTFS_SRC"
fi
if [ -d "$FRR_SRC" ]; then
  WATCH_DIR="$WATCH_DIR $FRR_SRC"
fi  
if [ -d "$SONIC_SRC" ]; then
  WATCH_DIR="$WATCH_DIR $SONIC_SRC"
fi  
if [ -d "$NVUE_SRC" ]; then
  WATCH_DIR="$WATCH_DIR $NVUE_SRC"
fi  

for name in $WATCH_DIR; do
  sync_dir ${name}
  watch_dir ${name} &
done

# blocking on background `inotifywait -m` processes
wait 

