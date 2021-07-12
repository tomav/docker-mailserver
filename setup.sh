#! /bin/bash

# version   v0.3.0 stable
# executed  manually / via Make
# task      wrapper for various setup scripts

SCRIPT='setup.sh'

WHITE="\e[37m"
RED="\e[31m"
PURPLE="\e[35m"
YELLOW="\e[93m"
ORANGE="\e[38;5;214m"
CYAN="\e[96m"
BLUE="\e[34m"
LBLUE="\e[94m"
BOLD="\e[1m"
RESET="\e[0m"

set -euEo pipefail
trap '__log_err "${FUNCNAME[0]:-?}" "${BASH_COMMAND:-?}" "${LINENO:-?}" "${?:-?}"' ERR

function __log_err
{
  printf "\n--- ${BOLD}${RED}UNCHECKED ERROR${RESET}\n%s\n%s\n%s\n%s\n\n" \
    "  - script    = ${SCRIPT:-${0}}" \
    "  - function  = ${1} / ${2}" \
    "  - line      = ${3}" \
    "  - exit code = ${4}" >&2

  printf "Make sure you use a version of this script that matches
the version / tag of docker-mailserver. Please read the
'Get the tools' section in the README on GitHub careful-
ly and use ./setup.sh help and read the VERSION section.\n" >&2
}

function _get_absolute_script_directory
{
  if [[ "$(uname)" == "Darwin" ]]
  then
    readlink() {
      greadlink "${@:+$@}" # Requires coreutils
    }
  fi
  if dirname "$(readlink -f "${0}")" &>/dev/null
  then
    DIR="$(dirname "$(readlink -f "${0}")")"
  elif realpath -e -L "${0}" &>/dev/null
  then
    DIR="$(realpath -e -L "${0}")"
    DIR="${DIR%/setup.sh}"
  fi
}

DIR="$(pwd)"
_get_absolute_script_directory

CRI=
CONFIG_PATH=
CONTAINER_NAME=
DEFAULT_CONFIG_PATH="${DIR}/config"
IMAGE_NAME=
INFO=
USE_CONTAINER=false
USE_TTY=
USE_SELINUX=
VOLUME=
WISHED_CONFIG_PATH=

function _check_root
{
  if [[ ${EUID} -ne 0 ]]
  then
    echo "Curently docker-mailserver doesn't support podman's rootless mode, please run this script as root user."
    exit 1
  fi
}

function _update_config_path
{
  if [[ -n ${CONTAINER_NAME} ]]
  then
    VOLUME=$(${CRI} inspect "${CONTAINER_NAME}" \
      --format="{{range .Mounts}}{{ println .Source .Destination}}{{end}}" | \
      grep "/tmp/docker-mailserver$" 2>/dev/null)
  fi

  if [[ -n ${VOLUME} ]]
  then
    CONFIG_PATH=$(echo "${VOLUME}" | awk '{print $1}')
  fi
}

function _inspect
{
  if _docker_image_exists "${IMAGE_NAME}"
  then
    echo "Image: ${IMAGE_NAME}"
  else
    echo "Image: '${IMAGE_NAME}' can’t be found."
  fi

  if [[ -n ${CONTAINER_NAME} ]]
  then
    echo "Container: ${CONTAINER_NAME}"
    echo "Config mount: ${CONFIG_PATH}"
  else
    echo "Container: Not running, please start docker-mailserver."
  fi
}

function _usage
{
  # shellcheck disable=SC2059
  printf "${PURPLE}SETUP${RED}(${YELLOW}1${RED})

${ORANGE}NAME${RESET}
    ${SCRIPT:-${0}} - docker-mailserver administration script

${ORANGE}SYNOPSIS${RESET}
    ./${SCRIPT:-${0}} [ OPTIONS${RED}...${RESET} ] COMMAND [ help ${RED}|${RESET} ARGUMENTS${RED}...${RESET} ]

    COMMAND ${RED}:=${RESET} { email ${RED}|${RESET} alias ${RED}|${RESET} quota ${RED}|${RESET} config ${RED}|${RESET} relay ${RED}|${RESET} debug } SUBCOMMAND

${ORANGE}DESCRIPTION${RESET}
    This is the main administration script that you use for all interactions with your
    mail server. Setup, configuration and much more is done with this script.

    Please note that the script executes most of the commands inside the container itself.
    If the image was not found, this script will pull the ${WHITE}:latest${RESET} tag of
    ${WHITE}mailserver/docker-mailserver${RESET}. This tag refers to the latest release,
    see the tagging convention in the README under
    ${BLUE}https://github.com/docker-mailserver/docker-mailserver/blob/master/README.md${RESET}

    You will be able to see detailed information about the script you're invoking and
    its arguments by appending ${WHITE}help${RESET} after your command. Currently, this
    does not work with all scripts.

${ORANGE}VERSION${RESET}
    The current version of this script is backwards compatible with versions of
    ${WHITE}docker-mailserver${RESET} ${BOLD}after${RESET} ${BLUE}8.0.1${RESET}. In case that there is not a more recent release,
    this script is currently only working with the ${WHITE}:edge${RESET} tag.

    You can download the script for your release by substituting TAG from the
    following URL, where TAG looks like 'vX.X.X':
    https://raw.githubusercontent.com/docker-mailserver/docker-mailserver/TAG/setup.sh

${ORANGE}OPTIONS${RESET}
    ${LBLUE}Config path, container or image adjustments${RESET}
        -i IMAGE_NAME
            Provides the name of the docker-mailserver image. The default value is
            ${WHITE}docker.io/mailserver/docker-mailserver:latest${RESET}

        -c CONTAINER_NAME
            Provides the name of the running container.

        -p PATH
            Provides the config folder path. The default is
            ${WHITE}${DIR}/config/${RESET}

    ${LBLUE}SELinux${RESET}
        -z
            Allows container access to the bind mount content that is shared among
            multiple containers on a SELinux-enabled host.

        -Z
            Allows container access to the bind mount content that is private and
            unshared with other containers on a SELinux-enabled host.

${RED}[${ORANGE}SUB${RED}]${ORANGE}COMMANDS${RESET}
    ${LBLUE}COMMAND${RESET} email ${RED}:=${RESET}
        ${0} email ${CYAN}add${RESET} [ OPTIONS${RED}...${RESET} ] <EMAIL ADDRESS> [<PASSWORD>]
        ${0} email ${CYAN}update${RESET} [ OPTIONS${RED}...${RESET} ] <EMAIL ADDRESS> [<PASSWORD>] [ <OLD CRYPTOKEY PASSWORD>${RED}...${RESET} ]
        ${0} email ${CYAN}del${RESET} [ OPTIONS${RED}...${RESET} ] <EMAIL ADDRESS> [ <EMAIL ADDRESS>${RED}...${RESET} ]
        ${0} email ${CYAN}restrict${RESET} <add${RED}|${RESET}del${RED}|${RESET}list> <send${RED}|${RESET}receive> [<EMAIL ADDRESS>]
        ${0} email ${CYAN}list${RESET}

    ${LBLUE}COMMAND${RESET} alias ${RED}:=${RESET}
        ${0} alias ${CYAN}add${RESET} <EMAIL ADDRESS> <RECIPIENT>
        ${0} alias ${CYAN}del${RESET} <EMAIL ADDRESS> <RECIPIENT>
        ${0} alias ${CYAN}list${RESET}

    ${LBLUE}COMMAND${RESET} quota ${RED}:=${RESET}
        ${0} quota ${CYAN}set${RESET} <EMAIL ADDRESS> [<QUOTA>]
        ${0} quota ${CYAN}del${RESET} <EMAIL ADDRESS>

    ${LBLUE}COMMAND${RESET} config ${RED}:=${RESET}
        ${0} config ${CYAN}dkim${RESET} [ ARGUMENTS${RED}...${RESET} ]

    ${LBLUE}COMMAND${RESET} relay ${RED}:=${RESET}
        ${0} relay ${CYAN}add-domain${RESET} <DOMAIN> <HOST> [<PORT>]
        ${0} relay ${CYAN}add-auth${RESET} <DOMAIN> <USERNAME> [<PASSWORD>]
        ${0} relay ${CYAN}exclude-domain${RESET} <DOMAIN>

    ${LBLUE}COMMAND${RESET} debug ${RED}:=${RESET}
        ${0} debug ${CYAN}fetchmail${RESET}
        ${0} debug ${CYAN}fail2ban${RESET} [unban <IP>]
        ${0} debug ${CYAN}show-mail-logs${RESET}
        ${0} debug ${CYAN}inspect${RESET}
        ${0} debug ${CYAN}login${RESET} <COMMANDS>

${ORANGE}EXAMPLES${RESET}
    ${WHITE}./setup.sh email add test@domain.tld${RESET}
        Add the email account ${WHITE}test@domain.tld${RESET}. You will be prompted
        to input a password afterwards since no password was supplied.

    ${WHITE}./setup.sh config dkim keysize 2048 domain 'whoami.com,whoareyou.org'${RESET}
        Creates keys of length 2048 but in an LDAP setup where domains are not known to
        Postfix by default, so you need to provide them yourself in a comma-separated list.

    ${WHITE}./setup.sh config dkim help${RESET}
        This will provide you with a detailed explanation on how to use the ${WHITE}
        config dkim${RESET} command, showing what arguments can be passed and what they do.

${ORANGE}EXIT STATUS${RESET}
    Exit status is 0 if the command was successful. If there was an unexpected error, an error
    message is shown describing the error. In case of an error, the script will exit with exit
    status 1.

"
}

function _docker_image_exists
{
  ${CRI} history -q "${1}" &>/dev/null
  return ${?}
}

function _docker_image
{
  if ${USE_CONTAINER}
  then
    # reuse existing container specified on command line
    _docker_container "${@:+$@}"
  else
    # start temporary container with specified image
    if ! _docker_image_exists "${IMAGE_NAME}"
    then
      echo "Image '${IMAGE_NAME}' not found. Pulling ..."
      ${CRI} pull "${IMAGE_NAME}"
    fi

    ${CRI} run --rm \
      -v "${CONFIG_PATH}:/tmp/docker-mailserver${USE_SELINUX}" \
      "${USE_TTY}" "${IMAGE_NAME}" "${@:+$@}"
  fi
}

function _docker_container
{
  if [[ -n ${CONTAINER_NAME} ]]
  then
    ${CRI} exec "${USE_TTY}" "${CONTAINER_NAME}" "${@:+$@}"
  else
    echo "The mailserver is not running!"
    exit 1
  fi
}

function _main
{
  if command -v docker &>/dev/null
  then
    CRI=docker
  elif command -v podman &>/dev/null
  then
    CRI=podman
    _check_root
  else
    echo "No supported Container Runtime Interface detected."
    exit 10
  fi

  INFO=$(${CRI} ps --no-trunc --format "{{.Image}};{{.Names}}" --filter \
    label=org.opencontainers.image.title="docker-mailserver" | tail -1)

  IMAGE_NAME=${INFO%;*}
  CONTAINER_NAME=${INFO#*;}

  if [[ -z ${IMAGE_NAME} ]]
  then
    IMAGE_NAME=${NAME:-docker.io/mailserver/docker-mailserver:latest}
  fi

  if test -t 0
  then
    USE_TTY="-ti"
  else
    # GitHub Actions will fail (or really anything else
    #   lacking an interactive tty) if we don't set a
    #   value here; "-t" alone works for these cases.
    USE_TTY="-t"
  fi

  local OPTIND
  while getopts ":c:i:p:hzZ" OPT
  do
    case ${OPT} in
      i ) IMAGE_NAME="${OPTARG}" ;;
      z ) USE_SELINUX=":z"     ;;
      Z ) USE_SELINUX=":Z"     ;;
      c )
        # container specified, connect to running instance
        CONTAINER_NAME="${OPTARG}"
        USE_CONTAINER=true
        ;;

      p )
        case "${OPTARG}" in
          /* ) WISHED_CONFIG_PATH="${OPTARG}"         ;;
          *  ) WISHED_CONFIG_PATH="${DIR}/${OPTARG}" ;;
        esac

        if [[ ! -d ${WISHED_CONFIG_PATH} ]]
        then
          echo "Directory doesn't exist"
          _usage
          exit 40
        fi
        ;;

      * )
        echo "Invalid option: -${OPT}" >&2
        ;;

    esac
  done

  shift $(( OPTIND - 1 ))

  if [[ -z ${WISHED_CONFIG_PATH} ]]
  then
    # no wished config path
    _update_config_path

    if [[ -z ${CONFIG_PATH} ]]
    then
      CONFIG_PATH=${DEFAULT_CONFIG_PATH}
    fi
  else
    CONFIG_PATH=${WISHED_CONFIG_PATH}
  fi


  case ${1:-} in

    email )
      case ${2:-} in
        add      ) shift 2 ; _docker_container addmailuser "${@:+$@}" ;;
        update   ) shift 2 ; _docker_container updatemailuser "${@:+$@}" ;;
        del      ) shift 2 ; _docker_container delmailuser "${@:+$@}" ;;
        restrict ) shift 2 ; _docker_container restrict-access "${@:+$@}" ;;
        list     ) _docker_container listmailuser ;;
        *        ) _usage ;;
      esac
      ;;

    alias )
      case ${2:-} in
        add      ) shift 2 ; _docker_image addalias "${1}" "${2}" ;;
        del      ) shift 2 ; _docker_image delalias "${1}" "${2}" ;;
        list     ) shift 2 ; _docker_image listalias ;;
        *        ) _usage ;;
      esac
      ;;

    quota )
      case ${2:-} in
        set      ) shift 2 ; _docker_image setquota "${@:+$@}" ;;
        del      ) shift 2 ; _docker_image delquota "${@:+$@}" ;;
        *        ) _usage ;;
      esac
      ;;

    config )
      case ${2:-} in
        dkim     ) shift 2 ; _docker_image open-dkim "${@:+$@}" ;;
        *        ) _usage ;;
      esac
      ;;

    relay )
      case ${2:-} in
        add-domain     ) shift 2 ; _docker_image addrelayhost "${@:+$@}" ;;
        add-auth       ) shift 2 ; _docker_image addsaslpassword "${@:+$@}" ;;
        exclude-domain ) shift 2 ; _docker_image excluderelaydomain "${@:+$@}" ;;
        *              ) _usage ;;
      esac
      ;;

    debug )
      case ${2:-} in
        fetchmail      ) _docker_image debug-fetchmail ;;
        fail2ban       ) shift 2 ; _docker_container fail2ban "${@:+$@}" ;;
        show-mail-logs ) _docker_container cat /var/log/mail/mail.log ;;
        inspect        ) _inspect ;;
        login          )
          shift 2
          if [[ -z ${1:-} ]]
          then
            _docker_container /bin/bash
          else
            _docker_container /bin/bash -c "${@:+$@}"
          fi
          ;;
        * ) _usage ; exit 1 ;;
      esac
      ;;

    help ) _usage ;;
    *    ) _usage ; exit 1 ;;
  esac
}

_main "${@:+$@}"
