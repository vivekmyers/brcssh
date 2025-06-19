### Installation

Run the following command to install the BRC SSH wrapper script:

```
bash -c "$(curl https://raw.githubusercontent.com/vivekmyers/brcssh/master/install_brcssh.sh)"
```

This will modify your `.bashrc`/`.zshrc` to wrap `ssh` and related commands (`scp`, `sftp`, `rsync`)
with a script that queries and injects your BRC credentials when needed.

The installer will prompt you for your authentication token and password, see
<https://docs-research-it.berkeley.edu/services/high-performance-computing/user-guide/using-authy/>
for details on how to obtain these.


### Dependencies

Requires `python`, `perl`, and Tcl `expect`

On Linux, install `expect` with conda:
```
conda install expect
```

MacOS should have `expect` pre-installed, but if not, you can install it with Homebrew:
```
brew install expect
```

