#!/bin/bash
# Convert Info-ZIP Zip's "nothing to do" status (12) to "success" (0)
# Based on an answer by Alexander L. Belikoff
# http://stackoverflow.com/a/19258421/2738262

zip "$@"
status=$?
if [[ status -eq 12 ]]; then
    exit 0
fi
exit $status

