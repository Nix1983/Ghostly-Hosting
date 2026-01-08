#!/bin/bash
set -e

install_git() {
  echo -e "\n \e[1mInstalling Git (for deployments)...\e[0m"
  if ! command -v git >/dev/null 2>&1; then
    if apt-get install -y git git-core git-man >/dev/null 2>&1; then
      echo " Git installed."
    else
      echo -e " \e[31mFailed to install Git.\e[0m"
      exit 1
    fi
  else
    echo " Git is already installed."
  fi

  #  Validate Git installation
  if ! command -v git >/dev/null 2>&1; then
    #  Fallback: manually link if git exists but is not in PATH
    if [[ -x /usr/lib/git-core/git && ! -x /usr/bin/git ]]; then
      ln -sf /usr/lib/git-core/git /usr/bin/git
    fi
  fi

  #  Still no Git – hard abort
  if ! command -v git >/dev/null 2>&1; then
    echo -e " \e[31mGit binary not found after installation – aborting.\e[0m"
    exit 1
  fi

  echo " Git binary verified: $(command -v git)"
}

remove_git() {
  apt-get purge -y git git-core git-man git-all git-doc >/dev/null 2>&1

  rm -f /usr/bin/git /usr/local/bin/git /snap/bin/git
  rm -rf /etc/gitconfig /usr/share/doc/git* /usr/share/man/man1/git* /var/lib/snapd/snap/git*

  echo -e " Removed Git and all related files."
}