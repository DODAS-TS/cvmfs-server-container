#!/bin/bash

# This file is subject to the terms and conditions defined by
# the LICENSE.md file and was developed by
# Gabriele Gaetano Fronzé, Sara Vallero and Stefano Lusso from
# INFN sezione Torino (IT).
# For abuse reports and other communications write to 
# <gabriele.fronze at to.infn.it>

export CVMFS_SERVER_GIT_URL=https://github.com/gabrielefronze/cvmfs-server-container.git
export CVMFS_SERVER_LOCAL_GIT_REPO=~/cvmfs-server-container
export CVMFS_CONTAINER_BASE_IMAGE_NAME=slidspitfire/cvmfs
export CVMFS_STRATUM_CONTAINER="dummy"
export DEFAULT_HOST_CVMFS_ROOT_DIR=/local/cvmfs-docker
export CVMFS_LOG_DIR=/var/log/cvmfs-server-container

if [[ ! -d "$CVMFS_LOG_DIR" ]]; then
    mkdir -p "$CVMFS_LOG_DIR"
fi

function prompt_stratum_selection {
    if [[ "$CVMFS_STRATUM_CONTAINER"=="dummy" ]]; then
        if [[ $(docker ps | grep -c "cvmfs-stratum0") == 1 ]]; then
            if [[ $(docker ps | grep -c "cvmfs-stratum1") == 1 ]]; then
                read -p "Both stratum0 and stratum1 are running. Please enter [0/1]: " strindex

                case "$strindex" in
                0)
                    CVMFS_STRATUM_CONTAINER="cvmfs-stratum0"
                    ;;
                1)
                    CVMFS_STRATUM_CONTAINER="cvmfs-stratum1"
                    ;;
                *)
                    echo "FATAL: Unsupported option. Please use [0/1]"
                    exit 1
                    ;;
                esac
            else
                CVMFS_STRATUM_CONTAINER="cvmfs-stratum0"
            fi
        elif [[ $(docker ps | grep -c "cvmfs-stratum1") == 1 ]]; then
            CVMFS_STRATUM_CONTAINER="cvmfs-stratum1"
        else
            echo "FATAL: No cvmfs container found. Please run it or manually set the CVMFS_STRATUM_CONTAINER environment variable."
            exit 1
        fi

        echo "Running next operation on $CVMFS_STRATUM_CONTAINER."
    fi
}

function cvmfs_server_container {
    MODE=$1

    case "$MODE" in
    # Clone the remote git repo locally
    get)
        if [[ ! -d "$CVMFS_SERVER_LOCAL_GIT_REPO"/.git ]]; then
            echo "Cloning git repo from $CVMFS_SERVER_GIT_URL in $CVMFS_SERVER_LOCAL_GIT_REPO... "
            mkdir -p "$CVMFS_SERVER_LOCAL_GIT_REPO"
            git clone "$CVMFS_SERVER_GIT_URL" "$CVMFS_SERVER_LOCAL_GIT_REPO"
        else
            echo "Pulling git repo from $CVMFS_SERVER_GIT_URL in $CVMFS_SERVER_LOCAL_GIT_REPO... "
            git --git-dir="$CVMFS_SERVER_LOCAL_GIT_REPO"/.git --work-tree="$CVMFS_SERVER_LOCAL_GIT_REPO" pull
            source "$CVMFS_SERVER_LOCAL_GIT_REPO"/$(basename $BASH_SOURCE)
        fi
        echo "done"
        ;;
    # Option to build the base container image
    build)  
        rm -f "$CVMFS_LOG_DIR"/build.log

        REQ="$2"
        
        case "$REQ" in
        0|1)
            echo -n "Building base cvmfs-server image... "
            docker build -t slidspitfire/cvmfs-server-base "$CVMFS_SERVER_LOCAL_GIT_REPO"/cvmfs-server-base >> "$CVMFS_LOG_DIR"/build.log
            echo "done"

            echo -n "Building cvmfs stratum$REQ base image with name $CVMFS_CONTAINER_BASE_IMAGE_NAME-stratum$REQ-base... "
            docker build -t "$CVMFS_CONTAINER_BASE_IMAGE_NAME"-stratum"$REQ"-base "$CVMFS_SERVER_LOCAL_GIT_REPO"/cvmfs-stratum"$REQ" >> "$CVMFS_LOG_DIR"/build.log
            echo "done"
        ;;
        pub)
            echo -n "Building base cvmfs-server image... "
            docker build -t slidspitfire/cvmfs-server-base "$CVMFS_SERVER_LOCAL_GIT_REPO"/cvmfs-server-base >> "$CVMFS_LOG_DIR"/build.log
            echo "done"

            echo -n "Building cvmfs publisher base image with name cvmfs-publisher... "
            docker build -t "$CVMFS_CONTAINER_BASE_IMAGE_NAME"-publisher "$CVMFS_SERVER_LOCAL_GIT_REPO"/cvmfs-publisher >> "$CVMFS_LOG_DIR"/build.log
            echo "done"
        ;;
        client)
            echo -n "Building cvmfs client image with name cvmfs-client... "
            docker build -t "$CVMFS_CONTAINER_BASE_IMAGE_NAME"-client "$CVMFS_SERVER_LOCAL_GIT_REPO"/cvmfs-client >> "$CVMFS_LOG_DIR"/build.log
            echo "done"
        ;;
        squid)
            echo -n "Building frontier-squid image with name cvmfs-frontier-squid... "
            docker build -t "$CVMFS_CONTAINER_BASE_IMAGE_NAME"-frontier-squid "$CVMFS_SERVER_LOCAL_GIT_REPO"/proxy-frontier >> "$CVMFS_LOG_DIR"/build.log
            echo "done"
        ;;
        *)
            echo "FATAL: provided option $2 not recognized. Please select [0/1/pub/client]."
            exit 1
        ;;
        esac

        unset REQ

        ln -sf "$CVMFS_LOG_DIR"/build.log "$CVMFS_LOG_DIR"/last-operation.log
        ;;

    # Option to execute the base image
    run)    
        rm -f "$CVMFS_LOG_DIR"/run.log

        REQ=""
        TEST=False
        HOST_CVMFS_DATA_DIR=""

        if [[ "$2" == "--test" ]]; then
            REQ="$3"
            HOST_CVMFS_DATA_DIR=${4:-"$DEFAULT_HOST_CVMFS_ROOT_DIR"/"$CVMFS_STRATUM_CONTAINER"}
            TEST=True
        else
            REQ="$2"
            HOST_CVMFS_DATA_DIR=${3:-"$DEFAULT_HOST_CVMFS_ROOT_DIR"/"$CVMFS_STRATUM_CONTAINER"}
            TEST=False
        fi
        
        case "$REQ" in
        0|1)
            STRATUM="$REQ"

            CVMFS_STRATUM_CONTAINER=cvmfs-stratum"$STRATUM"

            IMAGE_NAME="$CVMFS_CONTAINER_BASE_IMAGE_NAME"-stratum"$STRATUM"-base

            echo "Running cvmfs stratum$STRATUM docker container as $CVMFS_STRATUM_CONTAINER with:"
            echo -e "\t- Host cvmfs dir = $HOST_CVMFS_DATA_DIR"
            sh "$CVMFS_SERVER_LOCAL_GIT_REPO"/cvmfs-stratum"$STRATUM"/Dockerrun-args.sh "$HOST_CVMFS_DATA_DIR" "$IMAGE_NAME" "$TEST" >> "$CVMFS_LOG_DIR"/run.log
            echo "done"

            unset CVMFS_STRATUM_CONTAINER
            unset IMAGE_NAME
            unset HOST_CVMFS_DATA_DIR
            unset STRATUM
        ;;
        pub)
            CVMFS_STRATUM_CONTAINER=cvmfs-publisher

            IMAGE_NAME="$CVMFS_CONTAINER_BASE_IMAGE_NAME"-publisher

            echo "Running cvmfs publisher docker container as $CVMFS_STRATUM_CONTAINER with:"
            echo -e "\t- Host cvmfs dir = $HOST_CVMFS_DATA_DIR"
            sh "$CVMFS_SERVER_LOCAL_GIT_REPO"/cvmfs-publisher/Dockerrun-args.sh "$HOST_CVMFS_DATA_DIR" "$IMAGE_NAME" >> "$CVMFS_LOG_DIR"/run.log
            echo "done"

            unset CVMFS_STRATUM_CONTAINER
            unset IMAGE_NAME
            unset HOST_CVMFS_DATA_DIR
        ;;
        client)
            echo "Running cvmfs client docker container as cvmfs-client... "
            sh "$CVMFS_SERVER_LOCAL_GIT_REPO"/cvmfs-client/Dockerrun.sh >> "$CVMFS_LOG_DIR"/run.log
            echo "done"
        ;;
        squid)
            echo "Running frontier-squid docker container as cvmfs-squid... "
            sh "$CVMFS_SERVER_LOCAL_GIT_REPO"/proxy-frontier/Dockerrun.sh >> "$CVMFS_LOG_DIR"/run.log
            echo "done"
        ;;
        *)
            echo "FATAL: provided option $2 not recognized. Please select [0/1/pub/client]."
            exit 1
        ;;
        esac

        unset REQ

        ln -sf "$CVMFS_LOG_DIR"/run.log "$CVMFS_LOG_DIR"/last-operation.log
        ;;

    # Option to switch the endpoint of CVMFS commands if both containers running locally on the same host
    switch-str)
        if [[ ! $CVMFS_STRATUM_CONTAINER=="dummy" ]]; then
            if [[ $CVMFS_STRATUM_CONTAINER=="cvmfs-stratum0" ]]; then
                echo "Switching to stratum1... done"
                CVMFS_STRATUM_CONTAINER=="cvmfs-stratum1"
            elif [[ $CVMFS_STRATUM_CONTAINER=="cvmfs-stratum1" ]]; then
                echo "Switching to stratum0... done"
                CVMFS_STRATUM_CONTAINER=="cvmfs-stratum0"
            else
                echo "FATAL: env variable CVMFS_STRATUM_CONTAINER=$CVMFS_STRATUM_CONTAINER does not refer to any runnign container."
                echo "       Please manually export the name of the CVMFS cotnainer via 'export CVMFS_STRATUM_CONTAINER=<container-name>'."
                exit 1
            fi
        else
            echo "FATAL: no running CVMFS stratum containers."
            exit 1
        fi
        ;;

    # Option to initialize the required repo[s] using the internal script and committing the new image on top of the existing
    mkfs)
        rm -f "$CVMFS_LOG_DIR"/initrepo.log

        prompt_stratum_selection

        REQUIRED_REPOS="${@: -1}"
        OPTIONS="${@:2:$#-1}"

        if [[ -z "$OPTIONS" ]] || [[ ! $(echo "$OPTIONS" | grep -q "\-o root") ]]; then
            OPTIONS="-o root ""$OPTIONS"
        fi

        if [[ -z "$REQUIRED_REPOS" ]]; then
            echo "FATAL: no repository name provided."
            exit 1
        else
            REPO_NAME_ARRAY=$(echo $REQUIRED_REPOS | tr "," "\n")
            REQUIRED_REPOS_SUFFIX=$(echo $REQUIRED_REPOS | sed 's/\,/-/')

            for REPO_NAME in $REPO_NAME_ARRAY
            do
                echo -n "Initializing $REPO_NAME repository in $CVMFS_STRATUM_CONTAINER container with options: $OPTIONS ... "
                docker exec -ti "$CVMFS_STRATUM_CONTAINER" cvmfs_server mkfs -o root "$REPO_NAME" >> "$CVMFS_LOG_DIR"/initrepo.log
                docker exec -ti "$CVMFS_STRATUM_CONTAINER" cvmfs_server check "$REPO_NAME" >> "$CVMFS_LOG_DIR"/initrepo.log
                echo "done"
            done

            unset REPO_NAME_ARRAY
            unset REQUIRED_REPOS_SUFFIX
            unset REPO_NAME

            ln -sf "$CVMFS_LOG_DIR"/initrepo.log "$CVMFS_LOG_DIR"/last-operation.log
        fi

        unset OPTIONS
        unset REQUIRED_REPOS
        ;;
    
    # Option to recover the required repo[s] using the internal script
    mount)
        rm -f "$CVMFS_LOG_DIR"/recover.log

        prompt_stratum_selection

        if [[ "$2" == "-a" || -z "$2" ]]; then
            HOST_CVMFS_DATA_DIR=${3:-"$DEFAULT_HOST_CVMFS_ROOT_DIR"/"$CVMFS_STRATUM_CONTAINER"}

            REPO_NAME_ARRAY=$(ls $HOST_CVMFS_DATA_DIR/srv-cvmfs/ | tr " " "\n" | sed "/info/d")

            for REPO_NAME in $REPO_NAME_ARRAY
            do
                echo -n "Recovering $REPO_NAME repository in $CVMFS_STRATUM_CONTAINER container... "
                docker exec -ti "$CVMFS_STRATUM_CONTAINER" sh /etc/cvmfs-scripts/restore-repo.sh "$REPO_NAME" >> "$CVMFS_LOG_DIR"/recover.log
                echo "done"
            done

            unset HOST_CVMFS_DATA_DIR
            unset REPO_NAME_ARRAY
        else
            REQUIRED_REPOS="$2"
            REPO_NAME_ARRAY=$(echo $REQUIRED_REPOS | tr "," "\n")
            REQUIRED_REPOS_SUFFIX=$(echo $REQUIRED_REPOS | sed 's/\,/-/')

            for REPO_NAME in $REPO_NAME_ARRAY
            do
                echo -n "Recovering $REPO_NAME repository in $CVMFS_STRATUM_CONTAINER container... "
                docker exec -ti "$CVMFS_STRATUM_CONTAINER" sh /etc/cvmfs-scripts/restore-repo.sh "$REPO_NAME" >> "$CVMFS_LOG_DIR"/recover.log
                echo "done"
            done

            unset REPO_NAME_ARRAY
            unset REQUIRED_REPOS_SUFFIX
            unset REPO_NAME
            unset REQUIRED_REPOS
        fi
        
        ln -sf "$CVMFS_LOG_DIR"/recover.log "$CVMFS_LOG_DIR"/last-operation.log
        ;;

    # Help option
    help)
        prompt_stratum_selection
        echo "CernVM-FS Container Server Tool\n"
        echo
        echo "Usage: cvmfs_server_container COMMAND [options] <parameters>\n"
        echo
        echo "Supported commands:\n"
        echo
        echo "  get             Clone the git repo locally"
        echo "  build           [0/1]"
        echo "                  Build the stratum[0/1] container image"
        echo "  run             [0/1]"
        echo "                  Runs the stratum[0/1] container as cvmfs-stratum[0/1]."
        echo "  switch-str      Allows to switch between redirecting commands to "
        echo "                  stratum0 or stratum1, if deployed on the same host."
        echo "  mkfs            [-o owner=root] [-w stratum0 url] [-u upstream storage]"
        echo "                  [-m replicable] [-f union filesystem type] [-s S3 config file]"
        echo "                  [-g disable auto tags] [-G Set timespan for auto tags]"
        echo "                  [-a hash algorithm (default: SHA-1)]"
        echo "                  [-z enable garbage collection] [-v volatile content]"
        echo "                  [-Z compression algorithm (default: zlib)]"
        echo "                  [-k path to existing keychain] [-p no apache config]"
        echo "                  [-R require masterkeycard key ]"
        echo "                  [-V VOMS authorization] [-X (external data)]"
        echo "                  <fully qualified repository name>,"
        echo "                  [fully qualified repository name],..."
        echo "                  Configures the running container"
        echo "                  to host the provided comma-separed repo or list"
        echo "                  of repos always setting root as owner."
        echo "  mount           [-a]"
        echo "                  Mounts all the repositories found in"
        echo "                  the host root path, automatically recovering"
        echo "                  from crashes and shutdowns."
        echo "  mount           <fully qualified repository name>,"
        echo "                  [fully qualified repository name],..."
        echo "                  Mounts the specified repo or list of repos,"
        echo "                  automatically recovering them from crashes,"
        echo "                  container prunes and shutdowns."
        docker exec -ti "$CVMFS_STRATUM_CONTAINER" cvmfs_server help | awk 'NR>5'| awk '!/^NOTE:/' | awk '!/^  mount/' | awk '!/^                  Mount/' | sed '/add-replica/,$!d'
        ;;
    
    # Option to forward commands to cvmfs_server software running inside the container
    *)  
        prompt_stratum_selection

        CVMFS_REPO_NAME="$2"

        docker exec -ti "$CVMFS_STRATUM_CONTAINER" cvmfs_server "$@"

        if [[ "$1" == "transaction" ]]; then
            mount -o remount,rw overlay_"$CVMFS_REPO_NAME"
        fi

        if [[ "$1" == "publish" ]]; then
            mount -o remount,ro overlay_"$CVMFS_REPO_NAME"
        fi

        unset CVMFS_REPO_NAME
        ;;

    esac

    unset MODE
}
