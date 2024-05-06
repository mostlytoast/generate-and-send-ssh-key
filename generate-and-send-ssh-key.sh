#!/bin/bash

# these are the defaults for the commandline-options
KEYSIZE=4096
PASSPHRASE=
FILENAME=~/.ssh/id_test
KEYTYPE=rsa
HOST=host
USER=${USER}
CONFIG_FILE="/Users/thomassimon/.ssh/config"  # Variable for config file path
# use "-p <port>" if the ssh-server is listening on a different port
SSH_OPTS="-o PubkeyAuthentication=no"
NICKNAME=""
#
# NO MORE CONFIG SETTING BELOW THIS LINE
#

function usage() {
	echo "Specify some parameters, valid ones are:"

    echo "  -u (--user)       <username>, default: ${USER}"
    echo "  -f (--file)       <file>,     default: ${FILENAME}"
    echo "  -h (--host)       <hostname>, default: ${HOST}"
	echo "  -n (--nick)       <nickname>, default: none"

    echo "  -p (--port)       <port>,     default: <default ssh port>"
    echo "  -k (--keysize)    <size>,     default: ${KEYSIZE}"
    echo "  -t (--keytype)    <type>,     default: ${KEYTYPE}, typical values are 'rsa' or 'ed25519'"

    echo "  -P (--passphrase) <key-passphrase>, default: ${PASSPHRASE}"

    exit 2
}

if [[ $# < 1 ]];then
	usage
fi

while [[ $# > 0 ]]
do
	key="$1"
	shift
	case $key in
		-u*|--user)
			USER="$1"
			shift
			;;
		-f*|--file)
			FILENAME="$1"
			shift
			;;
		-h*|--host)
			HOST="$1"
			shift
			;;
		-n*|--nick)
			NICKNAME="$1"
			shift
			;;
		-p*|--port)
			SSH_OPTS="${SSH_OPTS} -p $1"
			shift
			;;
		-k*|--keysize)
			KEYSIZE="$1"
			shift
			;;
		-t*|--keytype)
			KEYTYPE="$1"
			shift
			;;
		-P*|--passphrase)
			PASSPHRASE="$1"
			shift
			;;
		*)
			# unknown option
			usage "unknown parameter: $key, "
			;;
	esac
done

echo
echo "Transferring key from ${FILENAME} to ${USER}@${HOST} using options '${SSH_OPTS}', keysize ${KEYSIZE} and keytype: ${KEYTYPE}"
echo
echo "Press ENTER to continue or CTRL-C to abort"
read

# check that we have all necessary parts
SSH_KEYGEN=`which ssh-keygen`
SSH=`which ssh`
SSH_COPY_ID=`which ssh-copy-id`

if [ -z "${SSH_KEYGEN}" ];then
    echo Could not find the 'ssh-keygen' executable
    exit 1
fi
if [ -z "${SSH}" ];then
    echo Could not find the 'ssh' executable
    exit 1
fi

echo
# perform the actual work
if [ -f "${FILENAME}" ];then
    echo Using existing key
else
    echo Creating a new key using ${SSH-KEYGEN}
    ${SSH_KEYGEN} -t $KEYTYPE -b $KEYSIZE  -f "${FILENAME}" -N "${PASSPHRASE}"
    RET=$?
    if [ ${RET} -ne 0 ];then
        echo ssh-keygen failed: ${RET}
        exit 1
    fi
fi

if [ ! -f "${FILENAME}.pub" ];then
    echo Did not find the expected public key at ${FILENAME}.pub
    exit 1
fi

echo
echo Having key-information
ssh-keygen -l -f "${FILENAME}"

echo
echo Adjust permissions of generated key-files locally
chmod 0600 "${FILENAME}" "${FILENAME}.pub"
RET=$?
if [ ${RET} -ne 0 ];then
    echo chmod failed: ${RET}
    exit 1
fi

echo
echo Copying the key to the remote machine ${USER}@${HOST}, this usually will ask for the password
if [ -z "${SSH_COPY_ID}" ];then
    echo Could not find the 'ssh-copy-id' executable, using manual copy instead
    cat "${FILENAME}.pub" | ssh ${SSH_OPTS} ${USER}@${HOST} 'cat >> ~/.ssh/authorized_keys'
else
    ${SSH_COPY_ID} ${SSH_OPTS} -i ${FILENAME}.pub ${USER}@${HOST}
    RET=$?
    if [ ${RET} -ne 0 ];then
      echo Executing ssh-copy-id via ${SSH_COPY_ID} failed, trying to manually copy the key-file instead
      cat "${FILENAME}.pub" | ssh ${SSH_OPTS} ${USER}@${HOST} 'cat >> ~/.ssh/authorized_keys'
    fi
fi

in=$?
if [ ${RET} -ne 0 ];then
    echo ssh-copy-id failed: ${RET}
    exit 1
fi

echo
echo Adjusting permissions to avoid errors in ssh-daemon, this may ask once more for the password
${SSH} ${SSH_OPTS} ${USER}@${HOST} "chmod go-w ~ && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
RET=$?
if [ ${RET} -ne 0 ];then
    echo ssh-chmod failed: ${RET}
    exit 1
fi
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macOS detected. adding to keychain"
	ssh-add "--apple-use-keychain" ${FILENAME}
fi

RET=$?
if [ ${RET} -ne 0 ];then
    echo ssh-add failed: ${RET}
    exit 1
fi
if [ ! -z "$VARIABLE" ]; then
	TEXT="\nHost ${HOST}\n  UseKeychain yes\n  AddKeysToAgent yes\n  IdentityFile ~/.ssh/${FILENAME}"
	# Check if the text already exists in the file
	if grep -qF "${TEXT}" "${CONFIG_FILE}"; then
		echo "Text already exists in file."
	else
		# Append the text to the file
		echo -e "${TEXT}" >> "${CONFIG_FILE}"
		echo "Text appended to ${CONFIG_FILE}."
		RET=$?
		if [ ${RET} -ne 0 ];then
			echo appending to ${CONFIG_FILE} failed: ${RET}
			exit 1
		fi
	fi
fi


# Cut out PubKeyAuth=no here as it should work without it now
echo
echo Setup finished, now try to run ${SSH} `echo ${SSH_OPTS} | sed -e 's/-o PubkeyAuthentication=no//g'` -i "${FILENAME}" ${USER}@${HOST}

echo
echo If it still does not work, you can try the following steps:
echo "- Check if ~/.ssh/config has some custom configuration for this host"
echo "- Make sure the type of key is supported, e.g. 'dsa' is deprecated and might be disabled"
echo "- Try running ssh with '-v' and look for clues in the resulting output"
