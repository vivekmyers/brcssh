#!/bin/bash

# Author: Vivek Myers
# This script installs a custom ssh wrapper that uses Google Authenticator to automatically get BRC ssh codes


read -r -d '' SSHLIB_SCRIPT << 'EOFF'
read -r -d '' GOOGLE_AUTH_SCRIPT << EOF
import hmac, base64, struct, hashlib, time, json, os

def get_hotp_token(secret, intervals_no):
    """This is where the magic happens."""
    key = base64.b32decode(normalize(secret), True) # True is to fold lower into uppercase
    msg = struct.pack(">Q", intervals_no)
    h = bytearray(hmac.new(key, msg, hashlib.sha1).digest())
    o = h[19] & 15
    h = str((struct.unpack(">I", h[o:o+4])[0] & 0x7fffffff) % 1000000)
    return prefix0(h)


def get_totp_token(secret):
    """The TOTP token is just a HOTP token seeded with every 30 seconds."""
    return get_hotp_token(secret, intervals_no=int(time.time())//30)


def normalize(key):
    """Normalizes secret by removing spaces and padding with = to a multiple of 8"""
    k2 = key.strip().replace(' ','')
    # k2 = k2.upper()   # skipped b/c b32decode has a foldcase argument
    if len(k2)%8 != 0:
        k2 += '='*(8-len(k2)%8)
    return k2


def prefix0(h):
    """Prefixes code with leading zeros if missing."""
    if len(h) < 6:
        h = '0'*(6-len(h)) + h
    return h

def main(label):
    secrets = json.load(open(os.environ['GOOGLE_AUTH_SECRETS']))
    pin, qr_code = secrets[label]
    key = get_totp_token(qr_code)
    return '{}{}'.format(pin, key)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--label',
                        type=str,
                        default='savio')
    args = parser.parse_args()

    key = main(args.label)
    print(key)
EOF


read -r -d '' SSH_EXPECT_SCRIPT << 'EOF'
set timeout 15
log_user 0
set cmd [lrange $argv 0 end]
set tmp [exec mktemp -u]

eval exec mkfifo $tmp
exec sh -c "cat $tmp 1>&2; rm $tmp" &

if { [catch { system {test -t 0} } error] } {
    spawn sh -c "cat | ( \"\$@\" ) 2>$tmp" sshlib {*}$cmd
    set piped 1
    set timeout 5
} else {
    spawn sh -c "\"$@\" 2>$tmp" sshlib {*}$cmd
    set piped 0
}



trap {
    set rows [stty rows]
    set cols [stty columns]
    stty rows $rows columns $cols < $spawn_out(slave,name)
} WINCH

expect {
    -nocase "*.brc.berkeley.edu* password: " {
        set password [exec python -c "$env(GOOGLE_AUTH_SCRIPT)"]
        send "$password\r"
        expect "*\n"
        exp_continue
    }
    -nocase "password: " {
        send_user -- "$expect_out(buffer)"
        interact "\r" {
            send -- "\r"
            exp_continue
        }
    }
    -re ".*\[?\] " {
        send_user -- "$expect_out(buffer)"
        set timeout -1
        interact "\r" {
            send -- "\r"
            exp_continue
        }
    }
    "*\n" {
        send_user -- "$expect_out(buffer)"
    }
    eof {
        send_user -- "$expect_out(buffer)"
    }
}

catch { 
    if { $piped } {
        while {[gets stdin line] != -1} {
                send "$line\r"
                expect -re "(.*\n)"
        }
        send_user -- "$expect_out(buffer)"
        send "\004"
        expect eof
    } else {
        interact
    }
} error

catch wait result
exit [lindex $result 3]

EOF

function ssh_wrapper {
    if command -v expect &> /dev/null; then
        ( export GOOGLE_AUTH_SCRIPT
          expect <(printf "%s" "$SSH_EXPECT_SCRIPT") "$@" )
    else
        command "$@"
    fi
}

function ssh { ssh_wrapper ssh "$@"; }
function scp { ssh_wrapper scp "$@"; }
function sftp { ssh_wrapper sftp "$@"; }
function rsync { ssh_wrapper rsync "$@"; }

export GOOGLE_AUTH_SECRETS=$HOME/.local/etc/secrets.json
EOFF


if [ -z "$BASH" ] || [ -z "$BASH_VERSION" ] || [ -o posix ]; then
  echo "Error: This script must be run in bash"
  exit 1
fi

which expect &> /dev/null || {
    echo 'Could not find `expect` in $PATH. Please install Tcl expect and try again.'
    exit 1
}

which python &> /dev/null || {
    echo 'Could not find `python` in $PATH. Please install Python and try again.'
    exit 1
}

which perl &> /dev/null || {
    echo 'Could not find `perl` in $PATH. Please install Perl and try again.'
    exit 1
}


if [[ -e "$HOME/.local/etc/secrets.json" ]]; then
    echo "Found existing authentication token in $HOME/.local/etc/secrets.json"
    read -p "Do you want to overwrite it? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        SKIP=1
    else
        read pass token <<< "$(perl -e '
            local $/; $_ = <>; print join " ", m{
                "savio" \s* : \s* \[
                    \s* (\d+) \s* , \s* "([^"]+)" \s*
                \]
            }sx
        ' "$HOME/.local/etc/secrets.json")"
    fi
fi

if [[ -z "$SKIP" ]]; then
    read -p "Enter your authentication token: " -i "$token" -e token
    read -p "Enter your password (4 digit): " -i "$pass" -e pass

    read -r -d '' SECRET_JSON << EOF
{
    "savio": [$pass, "$token"]
}
EOF

    mkdir -p "$HOME/.local/etc" &&
    printf "%s\n" "$SECRET_JSON" > "$HOME/.local/etc/secrets.json" &&
    echo "Saved authentication token to $HOME/.local/etc/secrets.json"
fi &&

mkdir -p "$HOME/.local/lib" &&
printf "%s\n" "$SSHLIB_SCRIPT" > "$HOME/.local/lib/sshlib.sh" &&
echo "Saved sshlib.sh to $HOME/.local/lib/sshlib.sh" &&


initcmd="source $HOME/.local/lib/sshlib.sh" &&

if grep -qF "$initcmd" "$HOME/.bashrc"; then
    echo "Found \`$initcmd\` in $HOME/.bashrc, skipping addition"
else
    echo "$initcmd" >> "$HOME/.bashrc" &&
    echo "Added \`$initcmd\` to $HOME/.bashrc"
fi

if [[ "$SHELL" == *zsh ]]; then
    if grep -qF "$initcmd" "$HOME/.zshrc"; then
        echo "Found \`$initcmd\` in $HOME/.zshrc, skipping addition"
    else
        echo "$initcmd" >> "$HOME/.zshrc" &&
        echo "Added \`$initcmd\` to $HOME/.zshrc"
    fi
fi

