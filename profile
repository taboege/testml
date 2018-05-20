#! bash

ok=true
error() { echo "$*"; ok=false; }
need() { type "$1" &>/dev/null || error "+ $2"; }

need bash 'Bash is required'
need node 'NodeJS is required'
need testml-compiler 'testml-compiler is required
Try: npm install -g testml-compiler'

if $ok; then
  [[ -d testml ]] ||
    git clone -b master git@github.com:testml-lang/testml

  if [[ -z $TESTML_ROOT ]]; then
    source testml/.rc
    export PATH="$PWD/bin:$PATH"
  fi

  echo "Everything looks good. Try: 'testml --help'"
else
  echo
  echo "Fix these issues and try again"
fi
