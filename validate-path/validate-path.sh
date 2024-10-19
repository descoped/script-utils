#!/usr/bin/env bash

echo $PATH | tr ':' '\n' | while read p; do if [ -z "$p" ]; then echo "Empty (::) path exists"; elif [ -e "$p" ]; then echo "$p exists"; else echo "$p does not exist"; fi; done
